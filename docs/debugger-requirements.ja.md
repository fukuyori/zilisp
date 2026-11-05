# Zilisp デバッガの要件

[English](debugger-requirements.md)

| 項目 | 内容 |
|---|---|
| 版 | 1.1（2026-11-05。1.0 への Codex のレビュー 17 件を反映） |
| tque | #351（D1 調査・D2 制約・D3 比較・D4 決定。D5 で設計書に反映して段階 1 を実装する） |
| 上位文書 | `docs/Zilisp_企画・基本設計書_v0.3.md` §9、`docs/Zilisp_詳細設計書_v0.2.md` §9.4 |

## 1. 目的

1. 学ぶ人が、REPL で SBCL と同じ流れでデバッグできる（教材 Level 13・14 の説明のとおりに操作できる）。
2. 外部のデバッグツール（GUI を含む）から、Zilisp のプログラムをデバッグできる。
3. エージェント（Claude Code・Codex など）が、Zilisp のプログラムをデバッグできる。
4. 1〜3 は同じ仕組み（デバッガの中核）の上に作る。どの層で何ができるかは §3.8 の対応表に定める。

**優先順位**（2026-11-05、レモンの決定）：目的 2 と目的 3 を同じ重みで優先し、目的 1 は後にする。作りやすいエージェント向け（目的 3）から作る（§5）。

## 2. 前提と制約

- handler と `invoke-debugger` は、巻き戻す前（エラーの場所）で動く（Phase 25）。デバッガもエラーの場所で、巻き戻さずに動かせる。
- ただし、受け止められなかったエラーのうち、Zig で見つけたもの（`car` の型の誤りなど）は `invoke-debugger` を通らない（`zl-sys::%signal-zig-error` が `*debugger-hook*` を直接呼び、受け止められなければ Zig の側でトップレベルへ戻る）。デバッガの入口は C1 で一つにする。
- VM の `run` は、`Value.unwind` を受けると cleanup を実行し、フレームと束縛を戻す。止まった状態を保つには、巻き戻す前の場所で要求を処理する必要がある（C15）。
- VM の命令の実行の途中には、要求を受けたり時間を確かめたりする場所がない（C16 で加える）。
- VM のフレームは closure・ip・base を持つ。必須の引数の値は読める。`Frame.ip` は、そのフレームが別の関数を呼んでいる間の「次の命令の位置」で、今の位置とは限らない。局所変数の名前・有効範囲・置き場所（局所の枠・捕捉の枠・セル）と、ip とソースの位置の対応はない（コンパイラに足す。C4）。
- `eval` はフレームの環境を受け取らない（C5 で加える）。
- ネイティブコードはフレームを記録しない。Zig には C の `#line` に当たるものがない（提案 ziglang/zig#1833 は 2026-04-21 に not planned で閉じた）。
- 単一スレッド。ソケットはまだない（Phase 31）。CLOS はまだない（Phase 27〜29）。
- 標準のストリーム `*query-io*`・`*debug-io*`・`*terminal-io*` は、今は標準入出力につながる（C17 で、通信と分ける）。
- 起動時間は 12.72 ms（2026-11-05、`5214e36` の内容。20 ms を超えたら2段階ビルドを前倒しにする決まり。詳細設計 §11.2）。

## 3. 機能の要件

### 3.1 デバッガの中核（すべての層が使う）

| 番号 | 要件 |
|---|---|
| C1 | **止まる契機と入口**：止まるのは次の場合だけ。(a) 受け止められなかった error（`error`・`cerror`、Zig で見つけたエラー）、(b) `invoke-debugger` の直接の呼び出し、(c) `break`、(d) `*break-on-signals*` に合う condition の通知の前、(e) breakpoint、(f) step。受け止められなかった `signal` は止まらずに NIL を返し、`warn` は警告を書いて続ける（CLHS）。(a)〜(f) はすべて、ユーザーの `*debugger-hook*` とは別の、中核の一つの入口を通る。(a)・(b) では、先に `*debugger-hook*` を（それを NIL に束縛して）呼ぶ（CLHS `invoke-debugger`）。(c) の `break` は `*debugger-hook*` を NIL に束縛してから入口を呼ぶ（CLHS `break`）。起動の途中（標準ライブラリを読み込む間）とスタックの溢れ（`th.stackExhausted`）では止まらず、今と同じくトップレベルへ戻る |
| C2 | **止まったときの情報**：止まった理由（C1 の (a)〜(f)）、condition（型・report）、使える restart（番号・名前・report）、止まった場所 |
| C3 | **フレームの一覧**：関数の名前、引数の値、ソースの位置（ファイル・行・列。分かるとき）。標準ライブラリの内部のフレームを隠せる。一番上のフレームの位置は止まった命令、それより下は呼び出しの命令の位置 |
| C4 | **フレームの変数**：引数と局所変数の名前と値。コンパイラは、変数ごとに名前・有効範囲（ip の区間）・置き場所（局所の枠・捕捉の枠・セル）を残す。同じ名前の変数は有効範囲で区別する。値の中を見られる（inspect）。得られない値（debug が低い、範囲外、最適化で消えた）は「得られない」と示す |
| C5 | **フレームでの評価**：そのフレームの局所変数を使える式の評価。動的環境（特殊変数・`*package*`）は止まった時点のもの。局所変数への `setq` は元のフレームに効く（局所の枠・セルに書く）。多値を返す。評価の中のエラーは入れ子の停止（C7）になる。局所関数（`flet`・`labels`）が見えるかは debug の段階で決め、文書に書く |
| C6 | **restart の選択**：番号・名前で選ぶ。引数は要求に含めて渡せる。`:interactive` を持つ restart で引数がなければ、REPL では対話で尋ね、通信の層（MCP・DAP・一括）では「引数が要る」として断る（勝手に読まない）。restart の関数が普通に戻ったら（非局所脱出しなかったら）、その値を結果として返し、止まったままにする（CLHS `invoke-restart`） |
| C7 | **抜け方と入れ子**：1 段抜ける（abort）、トップへ戻る、入れ子の停止（深さを示す）。抜けるときは `unwind-protect` の cleanup を一度だけ実行する |
| C8 | **step**：into・over・out・continue・stop。デバッグ用にコンパイルしたコードだけ（SBCL・Allegro と同じ。CLHS は step の範囲を処理系定義とする） |
| C9 | **breakpoint**：関数の入口、ソースの行。条件付き（任意。条件は Lisp の式なので評価の権限が要る。P2） |
| C10 | **フレームから値を返す**（return）、**フレームのやり直し**（restart-frame）。任意 |
| C11 | `trace`・`untrace`（CLHS） |
| C12 | `describe`・`inspect`・`apropos`・`documentation`（CLHS。教材 Level 14 §2）。`describe-object` は CLOS の後 |
| C13 | **表示の上限**：デバッガが作る表示（値の印字・report・一覧）に、深さ・項目の数・文字列の長さ・応答の全体のバイト数・report を作る時間の上限を設ける。既定の値は実装の段階で決めて文書に書き、要求で変えられる。省いた項目は、数が分かれば数を、分からなければ「省いた」ことを示す |
| C14 | **デバッグ情報の量**：`(declare (optimize (debug n)))`・`declaim`。debug の段階ごとに、残す情報（C3〜C5・C8・C9 で使えるもの）を定めて文書に書く |
| C15 | **止まった状態**：セッションの状態は「実行中」「停止中」「終了」。止まったときは巻き戻さず、止まった場所（中核の入口の中）で次の要求を待つ（入れ子の要求の処理）。止まっている間に受け付ける要求（情報・評価・restart・抜ける・再開）と、受け付けない要求を定める。評価の要求の「応答」と、評価の「完了」を分ける：評価の途中で止まったら、応答は「停止中」と停止の情報を返し、評価は止まったまま残る |
| C16 | **実行中の割り込み**：VM の安全な地点（関数の呼び出しと、ループの後ろ向きの分岐）で、割り込みの印と時間の上限を確かめる。通信の層は、安全な地点で待たずに入力を確かめる（頻度は間引く）。割り込み（pause）と時間の超過は「止まる」（C15。続きを再開できる）。取り消し（cancel）は、その要求を abort で終える。Zig のプリミティブの実行中・入力待ち・GC・cleanup の間は、次の安全な地点まで遅れる（遅れの最大の目安を文書に書く） |
| C17 | **入出力の分離**：通信の層（MCP・DAP・一括）を使うとき、通信は標準入出力を使い、Lisp のプログラムの入出力とは分ける。プログラムの `*standard-input*` は空（または要求で渡した内容）、`*standard-output*`・`*error-output*`・`*trace-output*`・`*terminal-io*`・`*query-io*`・`*debug-io*` は横取りして要求の結果で返す。プログラムが通信の入力を読むことはない |
| C18 | **識別子と寿命**：セッション・停止（停止ごとの世代の番号）・フレーム・restart・inspect の対象に識別子を付ける。フレームと restart の識別子は、その停止の間だけ有効。inspect の対象は、停止が終わるか明示的に放すまで GC から守る。古い識別子・ほかの停止の識別子は、理由を示して断る。通信が切れたら、止まっていた評価を abort（cleanup を実行）してセッションを終える |

### 3.2 REPL のデバッガ（目的 1）

- R1：SBCL 2.6.7 の形を基本にする（入るときの表示、`0]` の形のプロンプトと入れ子、restart の番号と名前、`UP`・`DOWN`・`FRAME`・`BACKTRACE`・`LIST-LOCALS`・`PRINT`・`SOURCE`・`STEP`・`NEXT`・`OUT`・`RETURN`・`TOPLEVEL`・`HELP`、それ以外は評価）。ほかの処理系に多いキーワードの形（`:b`・`:c n`・`:a` など）も別名として受け付ける。最終的なコマンドの一覧は、この層を作る段階で決める。使えるコマンドは中核の段階による（§5）。
- R2：入力は `*debug-io*`（REPL と同じ標準入力を共有する）。
- R3：対話のデバッガは VM で実行するときだけ（ネイティブのプログラムは N1 のとおりエラーの報告まで。§6.5）。`--script`・ファイルの実行の既定は、今と同じく対話しない（報告・restart の一覧・呼び出しの履歴を書き、終了コード 1。SBCL の `--script` と同じ）。オプションでデバッガに入れる（CLISP の `-on-error debug` と同じ考え。オプションの名前はこの層を作る段階で決める）。

### 3.3 対話しない実行と、機械が読める出力（目的 3）

- B1：受け止められなかった condition を JSON で出すオプション（名前は仮に `--error-format=json`）。止まった理由・型・report・restart の一覧・呼び出しの履歴（関数・引数・位置。局所変数は段階 2 から。段階 1 では「得られない」）を、1 行に 1 件の JSON で書く（rustc の `--error-format=json` と同じ形）。一方向の報告で、対話の操作は含まない。
- B2：一括のデバッガ（名前は仮に `zilisp debug --batch`）：止まったら、渡したコマンドを順に実行し、結果を JSON Lines で書く（gdb の `-batch`、lldb の `--batch`、pdb の `-c` と同じ考え）。
- B3：デバッガが作る表示は、同じ停止の状態に対して毎回同じ（アドレス・時刻を出さない。プログラム自身が書く出力は対象外）。量の上限は C13。エラーには、次に使えるコマンドを示す。

### 3.4 Debug Adapter Protocol（目的 2。GUI のエディタ）

- D1：標準入出力の DAP のアダプタ（名前は仮に `zilisp --dap`）。対応の目標は VS Code・Visual Studio・Zed・Eclipse・Emacs・Neovim・IntelliJ（LSP4IJ）。接続を試験したものは別に記録する（P4）。
- D2：初期化の順序：`initialize`（capabilities を返す）→ `launch` → `initialized` イベント → `setBreakpoints`・`setFunctionBreakpoints`・`setExceptionBreakpoints` → `configurationDone`。capabilities には、対応するもの（`supportsConfigurationDoneRequest`・`supportsExceptionInfoRequest`・`supportsFunctionBreakpoints`・例外のフィルタなど）を正しく示す。`attach` はこの層を作る段階で決める。
- D3：最小の要求とイベント：上の初期化の要求、`disconnect`・`threads`（1 つ）・`stackTrace`・`scopes`・`variables`・`continue`・`next`・`stepIn`・`stepOut`・`pause`・`evaluate`・`exceptionInfo`、イベント `initialized`・`stopped`・`output`・`terminated`・`exited`。breakpoint は、置けたか（verified）を返す。行と列は 1 から数え、パスは絶対パス。
- D4：condition は `stopped`（reason `exception`）と `exceptionInfo` で知らせる。restart の選択は DAP の標準にないので、Zilisp の拡張の要求を定める（`evaluate` で代わりにすると評価の権限が要るので、拡張の要求を正とする）。
- D5：VS Code などでの起動の設定（拡張）が別に要る。どこで作るかは、この層を作る段階で決める。

### 3.5 Swank（目的 2。SLIME。教材 Level 14 §8）

- S1：SLIME の Swank の backend（`swank/zilisp.lisp` 相当）。通信の形は `nil`（単一スレッド。評価の実行中は SLIME からの割り込みを受けられない）。
- S2：先行条件：TCP のソケット（Phase 31）、CLOS（Phase 27〜29）、Gray streams（CLOS の上に別に作る）、`defstruct` の `:include`（Phase 26）、中核の C4・C5・C8（段階 2・3）。
- S3：SLIME のデバッガ（sldb）の操作（backtrace・フレームの変数・フレームでの評価・restart・step）が中核で動く。
- S4：SLY（Slynk）と Lem（micros）は Swank とは別のサーバなので、別の要件として後で決める。

### 3.6 MCP のサーバ（目的 3）

- M1：標準入出力の MCP のサーバ（名前は仮に `zilisp --mcp`）。Claude Code（`claude mcp add`）と Codex（`config.toml`）に登録できる。
- M2：ツール（段階ごと）：
  - M2a（段階 1）：セッションの開始・終了、ファイルの読み込み・式の評価、止まったときの情報（C2）、呼び出しの履歴（関数と引数）、restart の一覧と選択（引数を渡せる）、abort・トップへ戻る、pause、出力の取得、`trace`・`untrace`
  - M2b（段階 2）：フレームの変数、フレームでの評価、inspect、macroexpand
  - M2c（段階 3）：breakpoint、step
  - 止まる操作は、止まった理由・位置・スタックの上位・（段階 2 から）変数を 1 回の応答で返す。
- M3：結果は `structuredContent` と、同じ内容のテキストで返す。量の上限は C13（既定は Claude Code の既定の上限 25,000 トークンより十分小さい値）。1 回の呼び出しは、Codex の既定の 60 秒より短い時間の上限（C16）で止めて、「停止中」として応答する。cancel は C16 のとおり。
- M4：入出力は C17 のとおり（標準出力は MCP の通信だけ）。
- M5：3.3 と同じ内部の API と、同じ JSON の形を使う。

### 3.7 ネイティブコード

- N1：エラーの報告で、Lisp の関数の名前と位置を出す（フレームの記録か対応表）。対話のデバッガは対象にしない（§6.5）。
- N2：gdb・lldb・Visual Studio で Lisp のソースの位置を見ることは、今は範囲に入れない（必要になったら、生成する Zig の行と Lisp の位置の表と、DAP の中継で行う）。

### 3.8 中核と各層の対応

○：専用の操作がある、△：一部（括弧の中）、×：ない（範囲外）、―：その層には当てはまらない。段階は §5。

| 中核 | REPL（R） | JSON の出力（B1） | 一括（B2） | MCP（M） | DAP（D） | Swank（S） |
|---|---|---|---|---|---|---|
| C1 止まる契機 | ○ | △（受け止められなかった error だけ） | ○ | ○ | ○ | ○ |
| C2 止まったときの情報 | ○ | ○ | ○ | ○ | ○（exceptionInfo） | ○ |
| C3 フレームの一覧 | ○ | ○ | ○ | ○ | ○ | ○ |
| C4 フレームの変数 | ○ | ○（段階 2） | ○ | ○（M2b） | ○ | ○ |
| C5 フレームでの評価 | ○ | ― | ○ | ○（M2b） | ○（evaluate） | ○ |
| C6 restart | ○ | △（一覧だけ） | ○ | ○ | ○（拡張の要求） | ○ |
| C7 抜け方と入れ子 | ○ | ― | ○ | ○ | △（disconnect・拡張） | ○ |
| C8 step | ○ | ― | ○ | ○（M2c） | ○ | ○ |
| C9 breakpoint | ○ | ― | ○ | ○（M2c） | ○ | ○ |
| C10 return・restart-frame | ○ | ― | ○ | × | △（restartFrame） | ○ |
| C11 trace | ○ | ― | ○ | ○ | × | ○ |
| C12 describe・inspect | ○ | ― | ○ | ○（M2b） | △（variables の展開） | ○ |
| C16 割り込み | ○（キーボードの割り込み。要検討） | ― | △（時間の上限） | ○ | ○（pause） | ×（S1） |

## 4. 非機能の要件

- P1：**速さと起動時間**：デバッガを使わない実行（既定）で、基準のコミット（段階を始める直前のコミット）と比べて、起動時間（ReleaseFast・x86_64-windows、`zilisp --eval nil` を 31 回の中央値。全体の検証のスクリプトと同じ方法）の増加を 0.5 ms 以下、`zig build bench` の各項目の低下を 3% 以下にする（許容の値は目安で、段階を始めるときに見直す）。C16 の安全な地点の確かめの費用もこれに含める。デバッガの Lisp の部分を必要なときに読み込む場合は、初めて止まるまでの時間と、読み込みに失敗したときの動作も測って記録する。MCP・DAP の起動の時間も記録する。
- P2：**安全**（エージェント・外部のツールから使うとき）：
  - 権限の段階：「参照だけ」「実行の制御」「評価」。操作ごとの必要な権限を表にする（実装の段階で文書にする）。Lisp のコードを動かす操作はすべて「評価」の権限が要る：式の評価・フレームでの評価・ファイルの読み込み・macroexpand（マクロの関数を動かす）・条件付きの breakpoint・`:interactive` の restart・`trace` の条件。
  - 権限の判定は、読み取り（Reader）とマクロの展開の前に行う。「参照だけ」の権限での読み取りは `*read-eval*` を偽にし、ユーザー定義の reader macro を使わない。
  - 「参照だけ」の権限での表示は、ユーザーのコード（condition の report・印字の関数）を呼ばない安全な形（型とスロットの値）にする。
  - 評価の権限は、起動時の明示的なフラグ（例 `--allow-eval`）がなければ得られない。評価の権限は OS の資源（ファイル・プロセス・ネットワーク）の制限ではない（その制限はないことを文書に書く）。
  - 読み込めるファイルのパスを制限できる。
  - 1 回の評価の時間・確保・出力の上限と、割り込み（C16）。
  - 監査のログ：実行した操作と結果の要約。秘密らしい値（環境変数など）は既定で隠す。
  - 将来 HTTP・TCP にするときは、127.0.0.1 だけで待ち、トークンと Origin を確かめる。
- P3：**標準**：`invoke-debugger`・`*debugger-hook*`・`break`・`*break-on-signals*`・`step`・`trace`・`untrace`・`describe`・`inspect` は CLHS のとおり。処理系定義のところ（コマンド・表示・step の範囲・debug の段階）は文書に書く。
- P4：**試験と受入**（段階ごとに、その段階の範囲で）：
  - 正しさ：C1 の各契機で止まる（止まらない場合も含む）、止まった場所での評価、restart の選択（引数あり・`:interactive`・普通に戻る restart）、入れ子の停止、`unwind-protect` の cleanup が一度だけ、abort・トップへ戻る。
  - 停止の状態：止まっている間の別の要求、古い識別子・ほかの停止の識別子、不正な要求、通信が切れたとき。
  - 割り込み：無限ループ・入力待ちへの pause と時間の超過、その後もセッションを使えること。
  - 入出力：通信に Lisp の出力が混ざらないこと、プログラムが通信の入力を読まないこと。
  - 安全：評価の権限がないときに、読み込み・macroexpand・`#.`・条件付きの breakpoint・`:interactive` で Lisp のコードが動かないこと。
  - 変数（段階 2 から）：捕捉された変数・同じ名前の変数・多値・得られない値・GC の後の inspect。
  - 層の間の一致：同じ停止に対して、各層（§3.8 の対応表の範囲）が同じ情報を返すこと。
  - SBCL との比較：文面の一致（入るときの文面・restart の report・`assert` の流れ）と、CL の意味の一致（どの restart が使えるか、評価の結果）を分けて比べる。
  - DAP：対応の目標のエディタのうち、接続を試験したものを記録する。

## 5. 段階（2026-11-05 の決定：0.4 に入れるのは段階 1）

| 段階 | 内容 | 先行条件 | 版 |
|---|---|---|---|
| 1 | 中核の基本（C1（(a)〜(d)）・C2・C3（関数と引数。位置は分かるところまで）・C6・C7・C11・C13・C15・C16・C17・C18）、`break`・`*break-on-signals*`（Phase 25 の Codex のレビュー 1 回目 #7）、JSON の出力（B1。局所変数は「得られない」）、MCP（M1・M2a・M3〜M5） | Phase 25。VM の安全な地点（C16）、入出力の分離（C17） | 0.4 |
| 2 | 局所変数とソースの位置（C3 の位置・C4・C5・C14。コンパイラのデバッグ情報）、一括のデバッガ（B2・B3）、MCP（M2b）、B1 の局所変数 | 段階 1 | 0.5 |
| 3 | breakpoint と step（C1 の (e)・(f)、C8・C9・C10）、DAP（D1〜D5）、MCP（M2c） | 段階 2 | 0.5 |
| 4 | Swank（S1〜S3）、`describe`・`inspect` の全体（C12） | 段階 2・3、CLOS（Phase 27〜29）、Gray streams、ソケット（Phase 31）、`defstruct :include`（Phase 26） | 0.5 |
| 5 | ネイティブ（N1） | Phase 36 | 0.7 |
| 後 | REPL のデバッガ（R1〜R3）。使えるコマンドは、その時点の中核の段階による | 中核（段階 1 以降） | 段階 1 以降 |

段階 2 以降の版は目安で、各段階に入る前に見直す。

## 6. 決定の記録（2026-11-05、レモン）

1. 目的 2 と 3 を同じ重みで優先し、目的 1 は後。
2. REPL の操作は SBCL の形を基本にし、キーワードの形を別名として受け付ける（最終的な一覧はその層を作る段階で決める）。
3. 対話しない実行の既定は対話しない。オプションでデバッガに入れる。
4. step と行の breakpoint は範囲に入れる（段階 3）。
5. ネイティブはエラーの報告の名前と位置（N1）まで。gdb などとの連携（N2）は今は範囲外。
6. 0.4 に入れるのは段階 1。
7. この要件は docs に英日で置く。

## 7. 調査の要点と出典（2026-11-05）

### 7.1 処理系のデバッガ

- 調べた処理系（SBCL・CCL・ECL・CLISP・LispWorks・Allegro）は、どれも入れ子の REPL（深さを示す）で、入るときに report と番号付きの restart を出し、デバッガのコマンドでない入力は式として評価する。コマンドの形は、CCL・ECL・CLISP・LispWorks・Allegro はキーワード（`:b`・`:c n` など）、SBCL はキーワードでない名前（`BACKTRACE`・`UP` など）。
- 1 段抜ける・トップへ戻る・番号で restart を選ぶ・呼び出しの履歴・フレームの移動・局所変数・フレームから値を返す は、調べた処理系のほぼすべてにある。
- 局所変数とソースの位置はコンパイラが残す情報による（Allegro の debug 3、CCL の `*save-local-symbols*`・`*record-pc-mapping*`、LispWorks の `*source-level-debugging*`）。ECL・CLISP はバイトコードのフレームの方が情報が多い。
- LispWorks には公式のリモートのデバッグの機能（TCP）がある（形式は文書になっていない）。ほかの処理系に同じような公式の機能があるかは、調べた範囲では見つからなかった（未確認）。
- SBCL 2.6.7 のコマンドの一覧は、手元の SBCL で `sb-debug::*debug-commands*` と `sb-debug::*debug-help-string*` を印字して確かめた（2026-11-05）。Windows の SBCL は、パイプで渡したデバッガのコマンドを読まなかったので、コマンドを実際に打った結果は確かめていない（未確認）。
- 出典：https://ccl.clozure.com/docs/ccl.html 、https://ecl.common-lisp.dev/static/manual/The-interpreter.html 、https://clisp.sourceforge.io/impnotes/repl.html 、https://www.lispworks.com/documentation/lw80/lw/lw-debugger-ug.htm 、https://franz.com/support/documentation/current/doc/debugging.htm 、CLHS（https://www.lispworks.com/documentation/HyperSpec/Body/f_invoke.htm ・f_break.htm・v_break_.htm・f_signal.htm・f_invo_1.htm・m_step.htm・m_tracec.htm）

### 7.2 外部のツール

- Swank：6 桁の 16 進の長さと S 式。TCP。通信の形 `nil` なら単一スレッドで動く。Swank 本体は CLOS（`defgeneric`・`defclass`）と Gray streams を使う。backend にはフレーム・変数・評価・step の関数が要る。SLIME のほかに、Swank を使うクライアントとして Vlime、IntelliJ の SLT（実験的）がある。SLY は Slynk、Lem は micros（どちらも Swank から分かれたサーバ）を使う。https://github.com/slime/slime 、https://slime.common-lisp.dev/doc/html/Communication-style.html 、https://github.com/joaotavora/sly 、https://github.com/lem-project/micros
- DAP：`Content-Length` のヘッダと JSON。標準入出力で 1 つのセッション。`initialized` イベントで設定の要求を始め、capabilities のない機能は使われない。restart の選択は標準にない。Common Lisp のコードをデバッグする DAP のアダプタは見つからなかった。VS Code の Alive は SBCL だけ。https://microsoft.github.io/debug-adapter-protocol/overview.html 、https://microsoft.github.io/debug-adapter-protocol/implementors/tools/ 、https://github.com/nobody-famous/alive
- Lisp の GUI のデバッガ（LispWorks・Allegro・CCL の IDE）は各処理系の専用品。McCLIM のデバッガは Swank を使う。
- Zig の `#line`：https://github.com/ziglang/zig/issues/1833 （2026-04-21 に not planned）。同じ issue の議論で、Zig に出力する言語 Zebra が行のコメントと DAP の中継で元の位置に戻すことが紹介されている（Zebra の実装そのものは未確認）。

### 7.3 エージェント

- MCP：標準入出力（JSON-RPC）と Streamable HTTP。結果は `structuredContent` とテキスト。取り消しは要求の識別子に対する通知で、完了と行き違うことがある。Claude Code（出力の上限は既定 25,000 トークン）と Codex（呼び出しの既定の時間は 60 秒）。https://modelcontextprotocol.io/specification/2025-06-18/basic/transports 、https://modelcontextprotocol.io/specification/2025-06-18/basic/utilities/cancellation 、https://code.claude.com/docs/en/mcp 、https://learn.chatgpt.com/docs/extend/mcp?surface=cli
- 既存のデバッグ用の MCP サーバ：mcp-debugger・go-delve の mcp-dap-server（DAP を包む）、cl-mcp（SBCL。restart を選ぶ操作は見つからなかった）。https://github.com/debugmcpdev/mcp-debugger 、https://github.com/go-delve/mcp-dap-server 、https://github.com/cxxxr/lisp-mcp-server
- エージェント向けの道具の作り方：出力を小さく、ページングと切り詰め、意味のある名前、直し方を示すエラー。https://www.anthropic.com/engineering/writing-tools-for-agents
- 安全：https://modelcontextprotocol.io/specification/2025-06-18/basic/security_best_practices

## 8. 改訂の履歴

| 版 | 日付 | 内容 |
|---|---|---|
| 1.0 | 2026-11-05 | 初版 |
| 1.1 | 2026-11-05 | 1.0 への Codex のレビュー（17 件）を反映：止まる契機と一つの入口（C1）、止まった状態・割り込み・入出力の分離・識別子（C15〜C18）、局所変数とフレームでの評価の詳細（C4・C5）、restart の引数と普通に戻る restart（C6）、表示の上限（C13）、段階の依存の修正（§5）、MCP のツールの段階分け（M2a〜M2c）、DAP の初期化と capabilities（D2・D3）、Swank と SLY・Lem の区別（S4）、対話のデバッガは VM だけ（R3）、中核と層の対応表（§3.8）、安全（P2）と試験（P4）と性能（P1）の具体化、調査の要点の言い過ぎの修正（§7） |
