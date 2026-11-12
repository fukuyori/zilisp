# Zilisp 引き継ぎ（2026-11-12）

リポジトリ：`/home/fuk/source/zig/zilisp`（github fukuyori/zilisp）。2026-11-12にLinux環境で状態を確認した。Windows環境の以前の検証結果には、その日付を残してある。
作業を引き継いだら、この文書を最新の状態に書き直すこと（古い状態を残さない）。
次のセッションでは、報告の前に必ず `git status -sb`・`git log --oneline -3`・`gh release list`・`git ls-remote --tags origin`・`tque ls` で確かめ直すこと。

## 1. 今の状態

- リリース：この文書には書かない。`gh release list` と `git ls-remote --tags origin` で確かめること。
- ブランチ：`main`。この更新にP28の実装・試験・レビュー対応と文書更新を含む。直前のコミットは `878edf9`（P27）。現在のコミットと作業ツリーは `git log --oneline -3` と `git status -sb` で確認する。
- **P28（#320）は受け入れ完了**。primaryメソッド、多重・EQLディスパッチ、引数優先順位、次メソッド、メソッド管理、総称アクセサ、print-objectを追加。#536（全クラスの一意なstamp）はCLIで完了。範囲・結果は `docs/clos-phase28-plan.ja.md`、レビュー原文と対応は `docs/clos-phase28-claude-review.md`・`docs/clos-phase28-claude-review.ja.md`。
  - Claude Codeは初回5件・限定再確認1件。キーワード・印字・アクセサの事前検査・inlineメソッドの再宣言を修正。深い再帰で中間フレームを多く使う資源上限は #541に分離（40段成功、600段storage-condition。SBCLは600段成功）。スタック安全上限は維持した。
  - 最終検証：単体Debug・ReleaseSafe・ReleaseFast成功、言語83/83、ネイティブReleaseFast全45/45、Debug新規3/3（通常・GC stress）、クロス5種、fmt成功。全45件のネイティブDebug再実行とWindows/macOS実行は未実施。レビュー修正前に停止した試行は算入していない。
  - 教材955件は一致558・both-error 362・出力差1・Zilispのみエラー34。保存済みの比較との差13件はすべて一致への改善（P27も含む累積差、SBCLの版も異なる）。結果は `compatibility/eval-check-sbcl-2.6.10-p28.tsv`。Readerは1079/23/5/0で以前と同じ。eval-checkの生成MarkdownはSBCL 2.6.7と固定表示するが、今回の実行は2.6.10.168。
  - 教材をcanonical commitから復元し `.work/samples` を再生成した。Level 21-Aの基本5ブロックを連続実行する `clos-level21.lisp` がSBCLと一致。修飾子・初期化フック・再定義はP29、with-slotsはP30。次は #321（P29）。
- **P27の受け入れ範囲は完了**。tque CLIで #319を完了にした（2026-11-12）。#317（P25）・#318（P26）・#378（時刻）・#380（conditionの印字）も完了。P27完了時の0.4（#316）の表示進捗は43%だった。現在値はtque CLIで確認する。
- P27の検証（Linux、Zig 0.17.1）：単体試験Debug・ReleaseSafe・ReleaseFast、lang-test 75/75、クロス5種が成功。ネイティブ全体は28本成功・13本コンパイル失敗の後、失敗分とCLOSの14本を固定ソースで再実行してすべて成功し、全41ケースをカバーした（通常・GC stress）。最終配置のCLOS試験はVM・ネイティブで個別確認済み。詳細と再試験の理由は `docs/clos-phase27-plan.ja.md`。教材の `.work/samples` がなく、reader-check・eval-checkは今回は未実施。Windows・macOSはクロスビルドのみ。
  - Claude Codeのレビュー6件を修正した。記録は `docs/clos-phase27-claude-review.ja.md`。修正後は単体Debug、言語77/77、影響するネイティブ4/4（通常・GC stress）、最後のRuntime再初期化修正はP27限定試験とclos-reviewのVM通常・GC stressで確認した。全42ネイティブケースの再実行はしていない。
- 以前のWindows環境での全体検証（`verify_p215.ps1`）が最後に通ったのは `6d2cde7`（2026-11-11）。以下はP27より前の結果。
  - 結果：test 3 モード、lang-test 73/73、native-test 40/40（Debug・ReleaseFast、通常と GC stress）、クロス 5 種、WSL の試験 126 passed・1 skipped・0 failed、reader-check・fmt、eval-check 一致 545・both-error 362・output-diff 1（Level 13 L455 のファイルのエラーの文面。処理系依存）・zilisp-error 47、起動時間の中央値 13.91 ms（ReleaseFast。最小 13.09 ms）。
  - 所要時間は 1,119 秒（約 19 分。ほかのビルドや試験と並行しないとき）。
  - reader-check の数（`zig build reader-check -- .work/samples`）：both-ok 1079、both-error 23、zilisp-only-error 5、sbcl-only-error 0。
- **未確認**：macOS での時刻の関数の動作（クロスビルドが通ることだけ）、夏時間のある地域の動作、WSL の 1 skipped が前から同じ試験か（2026-11-06 から）。起動時間の中央値が `996b98d` の 13.44 ms から 13.91 ms になったのが、測定のばらつきか変更の影響か。

## 2. P26（defstruct）と時刻の関数のまとめ

### 決めたこと

- 2026-11-10 のレモンの決定（「推奨で進めて」）：構造体は専用のオブジェクト（`ObjKind.structure`。スロットを直接並べる）／範囲は設計書 §10.5 の項目と周辺の標準機能（`#S`・`copy-structure`・`equalp`・`typep`）で、`(:type list)`・`(:type vector)`・`:named`・`:initial-offset` は `zilisp:unimplemented`／スロットの `:type` は構築子と `setf` で検査する／#378（時刻）を P26 の前に入れる。
- 2026-11-11 のレモンの決定（案 A。Codex 8 回目）：reader が型を確かめるのは、reader が `#S` で作った構造体だけ。reader macro が作った・書き換えた構造体の型は reader macro の責任。
- 2026-11-11 のレモンの決定（Codex 10 回目・15 回目）：次は直さず、処理系依存の一覧に書く。
  - reader macro が、reader の作った構造体に後から `#n#` を `setf` する形（案 A の範囲）。
  - ラベルの中の大きな `#S`（4,096 個より多くのオブジェクト）の型のエラーの通知が、ラベルの終わりまで遅れること。
  - コンマをふつうのリストで表すので、内部のシンボルを直接書いたリスト（`` `(a . (zl-sys::unquote-splicing b)) ``）がコンマと同じに扱われること（`comma-as-list`。SBCL と同じにする作業は tque #533）。
- Codex のレビューは 15 回目で区切った（2026-11-11、レモンと確認）。15 回目の後は処理系のコードを変えていないので、16 回目は依頼していない。11 回目からの指摘は reader の一般の動作（`#S` の後の文字、リストの閉じ括弧、ドット、コンマ）で、Phase 26 の本体（構築子・アクセサ・印字・型・時刻）には 10 回目から指摘が出ていない。

### 内容と場所

- 内容：設計書（英日）の §10.5 と「Phase 26 の実装」の節（Codex の各回の指摘と修正もここにある）、CHANGELOG（英日）の Unreleased。
- 実装の場所：`src/primitives/structures.zig`・`src/primitives/time.zig`（新規）、`src/lisp/boot.lisp` の末尾（時刻、defstruct の順）、`object.zig`・`gc.zig`・`types.zig`（`recordTypep`・`slotCheckable`）・`equalp.zig`・`hashtables.zig`・`streams.zig`（`hasLispPrinted`・`inLispPrinter`）・`pprint.zig`・`printer.zig`・`reader.zig`・`value_builder.zig`（`structure`・`labelFinish`・`isSplicing`）・`functions.zig`（`fboundp` の `(setf 名前)`）。
- 受入（Level 19）：`defstruct` で止まっていた 10 ブロックはすべて SBCL 2.6.7 と同じ出力。教材の `defstruct` の 31 ブロックと `get-universal-time` の 1 ブロックが一致になった。
- 試験：言語試験は `defstruct.lisp`（基本）・`defstruct-read.lisp`（`#S` の読み取り、`#n#`、Codex 10〜14 回目で足した reader の例）・`defstruct-review.lisp`（レビューで足した例）・`time.lisp`。SBCL と違えた動作（別名、`comma-as-list` など）は、期待値が SBCL の出力である言語試験には置かず、`src/compiler/eval_test.zig` の最後の test に置いた。
- README（英日）：タグ `v0.3.0` より後のコミットで作った condition・構造体・時刻の 3 行を、「0.3.0 の後に実装したもの（0.4 に入る予定）」の見出しの下に置いた（2026-11-11、レモンの指示。CHANGELOG の「Unreleased」と同じ分け方）。
- コミット：P26 と時刻は `7cb07fe`。Codex の修正は 1 回目から順に `14c8a75`・`6c6110e`・`8473f4d`・`54ac755`（`defstruct.lisp` を 3 つに分ける変更も）・`f29570a`・`d7f1866`・`6f1ab7e`・`14a9210`（案 A）・`cdf4946`・`7610a8b`・`b46ea09`・`28af74f`・`5ef5884`・`b13505d`、15 回目の対応（文書と単体試験だけ）は `6d2cde7`。試験の実行器の並列化は `ffea1fb`（native-test）と `996b98d`（lang-test・eval-check）。
- Codex の依頼と結果：`C:\Users\n_fuk\AppData\Local\Temp\claude\2b38cd32e55d8954\d4a5fc96-8737-44b4-9d02-2040df687ef5\scratchpad\codex\` の `request1.md`〜`request15.md`・`result1.md`〜`result15.md`。再現のスクリプトは、その 1 つ上のフォルダの `r1.lisp`〜`r25.lisp`。

### 実装の要点（次に触るときに要ること）

- クラスの記述は、シンボルの属性 `zl-sys::%class` の simple-vector `#(名前 CPL include スロット 標準の構築子 printer 読み取り用の構築子)`。スロットは `(名前 initform 型 read-only アクセサ)`。
- `:include` は、展開のときに元の構造体のクラスの記述を読む。そのため `defstruct` は `eval-when` でコンパイル時にもクラスを登録する。ネイティブでコンパイルするファイルでは、`:include` する構造体をトップレベルで定義する。構造体のリテラル `#S(…)` は、ネイティブでコンパイルするファイルには書けない。
- 構造体・condition を中に含むリスト・ベクタは、`*print-pretty*` が NIL でも pretty printer の経路で書く（`streams.hasLispPrinted`）。Lisp の印字の関数の中からの印字（`streams.inLispPrinter`）も同じ。
- `#n=` と `#S`（`value_builder.zig`）：
  - `#n=` の仮の値は car が unbound の cons（`labelDefine`）。
  - 解決していない `#n=` のラベルがあれば（`hasPendingLabel`）、型を検査しない読み取り用の構築子で作る。できた構造体の中に仮の値がなければ（`containsPlaceholderLimited`。4,096 個より多くのオブジェクトを通ったら「分からない」）その場で `zl-sys::%check-structure-slots` で確かめ、あるか分からなければ、ラベルの表の 1 つの項目 `(unbound . 構造体のリスト)` に検査待ちとして置く。ラベルがなければ標準の構築子（型を検査する）。
  - 構築子を呼ぶ間は、ストリームの位置・`th.read_builder`・`b.bq_depth` を設定する（initform の recursive な `read` のため）。
  - `labelFinish`：返ったオブジェクトと検査待ちの構造体の中の仮の値を置き換え、別名（`#1=(#2=#1#)` の `#2`）の項目を解決した値にし、仮の値がなくなった検査待ちの構造体を確かめる。
- reader（`reader.zig`。Codex 11〜14 回目で変えた、リスト全体が通る場所）：
  - `readItem(close)`：空白の後の文字が `close` そのものなら、マクロ文字の関数を呼ばずに「終わり」を返す。`readList`（ドットの後も）・`readVector`・`readDelimitedList` が使う。`readObj` は `readItem(null)`。
  - `#S` のすぐ後は `(` でなければならない。本体は backquote の深さ 0 で `readList` で読む。
  - 読み飛ばしの中（`*read-suppress*`・`#+` / `#-`）では、単独のドットをふつうのトークンとして読む。機能式が合った `#+` / `#-` は、続くオブジェクトをその場で 1 つ読んで返す。
  - backquote の中のドットのすぐ後の `,@`・`,.` は、閉じ括弧まで読んでから、読んだオブジェクトを Builder の `isSplicing` で見て reader-error にする（`tools/reader_check` の NullBuilder は `isSplicing` を持たないので検査しない）。
- `tests/language/gc-stress/` に試験を足すときは、`名前.args`（`--gc-stress --script`）も置く（ないと別の引数で実行されて失敗する）。

### 意図した SBCL との違い

`tests/differential/impl-dependent.toml` にある（2026-11-11 の時点で、全体は 50 項目、`since = "Phase 26"` は 11 項目。CLHS の節は原文で確かめていない）。Phase 26 で足した主なもの：

- 初期値のない `&aux` のスロットは NIL。type-error の expected-type は書いた型のまま。構造体のリテラルはコンパイルできない。`:include` の裸のシンボルの書き換えは受け付ける。
- その土地の時刻の求め方（Windows 以外は `/etc/localtime`。環境変数 `TZ` は見ない）。
- 入れ子のラベルで互いを指す型のある `#S` は、解決した後の値が型に合えば読める。reader macro が別の場所に保存した構造体の中の `#n#` も置き換えて型を確かめる。reader macro が複製して元だけを書き換えた構造体の型は確かめない（`sharp-s-copied-by-reader-macro`）。
- 未解決のラベルの中の別名は解決した値になる（`sharp-equal-alias-of-pending-label`）。大きな `#S` の型のエラーの通知の遅れ（`sharp-s-large-in-pending-label`）。コンマの表し方（`comma-as-list`）。
- エラーの handler の中の recursive な `read` が外側のラベルを参照できない（`recursive-read-in-handler`。Phase 25 からの制限で、`#.` の中のエラーでも同じ。handler には読み取りの途中の状態を引き継がない：`thread.zig` の `callSignalHook`。tque には未登録）。
- reader macro が持ち出した仮の値そのものを、利用者のコードが構造体以外の場所に入れた場合は、置き換わらずに残る（読んだ結果の外はたどれない。SBCL も内部の印が残る）。

## 3. 次の作業（tque）

- P28（#320）とstampの#536はtque CLIで完了にした。**次は #321（P29：メソッド結合・初期化フック・再定義）**。P27（#319）は完了。
  - P27ではrack方式を採用した。比較計測・受け入れ範囲・実装・検証結果は `docs/clos-phase27-plan.ja.md`（英語版 `docs/clos-phase27-plan.md`）。実装は `src/primitives/clos.zig` と `src/lisp/clos.lisp`。
  - #536（P28の子）は完了：組み込み・condition・構造体も一意な正のstampを持つ。古いrackの更新はP29。#541は中間フレーム削減の独立した改善。
  - #534・#535（P29の子）：上位クラスの前方参照、`(setf find-class)` によるクラス名の登録・解除。
- 0.4（#316）の下のほかの項目：
  - #344 P23 の受入の残り（Level 17 の text-tools を SBCL と比べる）。着手できる。
  - #349 印字の速さの改善（印字は SBCL の約 1.8 倍の時間）。
  - #350 exit・quit（`*exit-hooks*` を入れるかは未決定）。
  - #351 デバッガ：要件は `docs/debugger-requirements.ja.md`（英語版 `debugger-requirements.md`。v1.1、`b615282`）。外部のツール（GUI を含む）とエージェントとの連携を同じ重みで優先し、REPL のデバッガは後。0.4 に入れるのは段階 1（#356：中核の基本、`break`・`*break-on-signals*`、JSON の出力、MCP の最小）。調査の記録は `C:\Users\n_fuk\AppData\Local\Temp\claude\2b38cd32e55d8954\9f49964b-3593-43ef-814e-feeb4feff29d\scratchpad\dbg\survey\`。
    - 次にするのは要件の文書の v1.2（英日）。段階 1 に `assert` の場所の問い合わせを加える：`y-or-n-p`・`yes-or-no-p`（いまは未定義）を足し、`continue` の restart の `:interactive` で場所ごとに SBCL と同じ「The old value of X is 1.」「Do you want to supply a new value?  (y or n)」を出す（CLHS は `continue` の前に場所を変える機会を求める）。`*break-on-signals*`（Codex P25 1 回目 #7）も段階 1。
- 関連する残作業：
  - #377 印字の中の再帰でスタックが溢れるとプロセスが落ちる（重大度は高）。report の中で自分の condition を `~A` で印字する・`~/名前/` の中で同じ `~/名前/` を使う・`pprint-logical-block` の再帰・pprint-dispatch の関数の中で同じ型を印字すると、終了コード -1073741819 と `Stack overflow (no address available)` で落ちる（ふつうの関数の再帰は storage-condition になる）。`*print-circle*` なしで循環リストを印字しても落ちる（2026-11-11 に `(print (read-from-string "#1=(#2=#1# #2#)"))` で起きた）。構造体の `:print-function` の中で自分を印字する場合と、自分を指す構造体の `equalp` も同じ種類と推測される（※推測です。試していない）。Zig の関数を挟んだ入れ子の上限（`max_native_depth = 1000`。`src/runtime/thread.zig`）に届く前に Zig のスタックが溢れると推測される（※推測です。zilisp.exe のスタックの大きさは未確認）。直し方の案：生成した実行ファイルと同じ残りのスタックの検査（`src/native/rt.zig` の `stack_limit`）を `th.call` にも入れる。直す前にスタックの大きさと 1 段の使用量を測る。
  - #379 `type-of`・`subtypep`・`deftype`（`deftype` は呼ぶと `zilisp:unimplemented`）。
  - #533 backquote のコンマを専用のオブジェクトで表す（Codex P26 15 回目。backquote の展開・印字・ネイティブの定数の読み込みに及ぶ見込みで、範囲は未調査。設計の検討から始める）。
- **見つけた違い（tque には未登録。登録するかはレモンの判断）**：
  - `*print-pretty*` が NIL のとき、type-error を `princ` すると `The value   1 is not of type   STRING` と空白が余分に入る（SBCL 2.6.7 は空白 1 つ。report の `~2@T` の扱いと推測される。※推測です。Phase 26 の変更の前から同じ）。
  - condition を `*print-level*` の限界の深さで印字すると形が違う（`*print-level*` 2 の `((condition))`：SBCL は pretty で `((#))`、pretty でないと `((#<TYPE-ERROR #>))`。Zilisp はどちらも `((#<TYPE-ERROR expected-type: STRING datum: #>))`。Phase 25 の範囲。再現は `r6.lisp`）。
  - エラーの handler の中の recursive な `read` が外側のラベルを参照できない（§2 の `recursive-read-in-handler`）。
  - `(:type list)`・`(:type vector)`・`:named`・`:initial-offset` の `defstruct`、`get-internal-real-time`・`get-internal-run-time`・`internal-time-units-per-second`・`sleep`（どれも未実装）。

## 4. リリースの手順（0.3 で決めたこと）

- `docs/version-update-checklist.md` のとおり：バージョンの更新 → 試験 → コミット → タグ `v<版>` の push → GitHub Actions がビルドしてリリースを登録。
- 署名付きの Windows の配布物は、レモンが `scripts/build-installer.ps1 -Sign` で作り（出力は `dist\release\`）、`gh release upload v<版> <ファイル> --clobber` で差し替える。Claude は配布物を作らない。
- リリースに `SHA256SUMS.txt` は付けない。リリースノートと README に、署名の有無を書かない（2026-11-04 の決定）。

## 5. 作業の進め方・道具

- 開発の進め方（P25・P26 の反復レビューを受けた改善）：
  1. Phase の開始時に、実装する範囲・受け入れ条件・重要な相互作用（循環参照、エラー経路、既存機能との組み合わせなど）・対象外を短く決める。新しい表し方や設計上の選択肢がある場合は、案と推奨を示して決定を受ける。
  2. 実装と受け入れ試験をそろえてから、Phase の範囲と差分を指定した読み取り専用レビューを依頼する。レビュー依頼では、見つかった指摘を重大度・再現例・根拠とともに一括で報告するよう求め、対象外の既存動作を調べる場合は別項目に分けてもらう。
  3. 指摘は Zilisp と利用可能なSBCL（この環境は2.6.10.168）で再現を確かめ、既存2.6.7の期待値は版の違いだけで上書きせず、関連する修正と試験をまとめて行う。誤った入力を拒む修正では、拒むべき入力だけでなく「拒んではいけない形」も SBCL で確かめて試験に入れる（P26 の 13〜15 回目で、追加した検査が正しい入力まで拒む問題が続いた）。
  4. 再レビューは通常1回とし、修正箇所とその回帰に絞る。未解決の受け入れ条件、重大な正しさの問題、または試験失敗がある場合は、解消するまで追加レビューを行う。対象外の指摘や合意済みの制限は別タスクまたは処理系依存の項目に記録し、それだけを理由に現在の Phase を広げない。
  5. ソースを変更していないコミットにはレビューを依頼しない。関連する修正をまとめた後に fmt・`zig build test`・lang-test・native-test（Debug）・reader-check・eval-check を実行し、Phase の受け入れ時に ReleaseSafe・ReleaseFast・クロス・WSL を含む全体検証を行う。各 Phase のレビュー回数と、着手から受け入れまでの日数も記録し、見積もりを更新する。重いネイティブ全体試験はレビュー修正をまとめてから固定ソースで実施し、試験中にソースを変えない。範囲を絞って実施した場合はモード・対象・未実施範囲を明記する。
  - `native-test` は実行中もケースごとにランタイムをコンパイルする。検証対象のソースは終了まで固定し、並行して修正する場合は別のworktreeを使う。P27では実行中に編集したため13本がコンパイル段階で失敗し、失敗分の再実行が必要になった。
- 新しい Phase の始め方（P26）：教材の使い方・設計書・既存のコードを調べ、決めること（表し方・範囲など）を案と推奨つきで短く示してから、受け入れ条件と対象外を決めて実装する。
- 全体の検証のスクリプト：`C:\Users\n_fuk\AppData\Local\Temp\claude\D--home-source-zig-zilisp\e5761a66-3281-40a8-9ff1-762483b07fc1\scratchpad\verify_p215.ps1`（PowerShell でバックグラウンドで実行。約 19 分（native-test を並列にする前は約 70 分、lang-test・eval-check を並列にする前は 22〜28 分）。出力は最後にまとめて出る。要約は `Select-String '^== |passed|failed|eval-check:|startup|error:'`）。走っている間は作業ツリーのソースと試験を変えない（`zig-out` も作り直される）。変えるときは git worktree（例 `D:/tmp/zl_fixNN`）で作業し、検証が終わってから写す。
  - worktree で PowerShell の `Set-Location` を使っても、`[IO.File]::WriteAllText` などの .NET の関数の相対パスは元のディレクトリを指す（2026-11-06 に、メインのリポジトリのファイルに書いてしまい、すぐ戻した）。.NET の関数には絶対パスを渡す。
  - lang-test と eval-check も並列に実行する（2026-11-11 から。`tools/lang_test/main.zig`・`tools/eval_check/main.zig`。環境変数 `ZILISP_LANG_TEST_JOBS`（既定は論理プロセッサの数で 1〜16）・`ZILISP_EVAL_CHECK_JOBS`（既定は半分で 1〜8））。lang-test は、同じ名前の試験（eval と gc-stress は同じ `.zig-cache/lang-tmp/<名前>/` にファイルを書く）を 1 つの組にして順に実行し、組どうしを並列にする。lang-test は約 280 秒から 49 秒（順次なら 244 秒）、eval-check は約 160 秒から 28 秒。eval-check の結果（545・362・1・47）と `compatibility/` のファイルは変わらない。
  - 言語試験の時間のほとんどは gc-stress（確保のたびに GC。Debug で通常の実行は全部で 6 秒、gc-stress は長いもので 1 ファイル 40 秒）。生きているデータが多い例を足すと、後ろの例がすべて遅くなる（`defstruct-read.lisp` の 200×200 の例で 156 秒になっていた。30×30 にして 40 秒）。
  - 試験を 1 つずつ手で実行するときは、リポジトリの直下から実行する（試験のディレクトリを作業ディレクトリにすると、試験が `.zig-cache/lang-tmp/` をそこに作り、実行器がその中の `.lisp` を試験として拾って失敗する。2026-11-11 に起こして消した）。
  - native-test は試験を並列に実行する（2026-11-11 から。`tools/native_test/main.zig`。並列の数は環境変数 `ZILISP_NATIVE_TEST_JOBS`、既定は論理プロセッサの数の半分で 1〜8。結果はすべて終わってから名前の順に出る）。38 ファイルの Debug は、順に実行すると約 37 分、8 並列で約 7 分（この機械は 8 コア 16 スレッド）。
- Codex レビュー：`Get-Content <依頼.md> -Raw | codex exec -C 'D:\home\source\zig\zilisp' --skip-git-repo-check -s read-only --ephemeral --color never -o <結果.md> - *> <ログ>`。Codex には `zig-out` ではなく、コピーした実行ファイル（`...\scratchpad\codex\bin\zilisp.exe`）を使わせる（検証が `zig-out` を作り直すため。コミットの前のソースなら `zig build -p <scratchpad の別の場所>` で作ってコピーする）。依頼には「書けなければ `zilisp.exe --eval` で試す」と、直さないと決めたものの一覧を書く。Codex の指摘は、必ず Zilisp と SBCL で再現を確かめてから報告する。P25 の依頼と結果は `C:\Users\n_fuk\AppData\Local\Temp\claude\2b38cd32e55d8954\9f49964b-3593-43ef-814e-feeb4feff29d\scratchpad\codex\`。
- 期待値の作り方：`sbcl --script <ファイル> 2>$null` の標準出力だけを、改行を LF にして BOM なしの UTF-8 で書く。`tests/language/eval/` の `.lisp` と `.expected` は `tests/language/gc-stress/` にも写す（`.args` も置く）。比べるときは、SBCL・Zilisp・`--gc-stress` の 3 つを比べる。
- このLinux環境のSBCLソースは `/home/fuk/source/lisp/sbcl`（読むだけ）。ソースと実行ファイルの版、および既存の2.6.7基準との比較結果は§6に記録した。以前のWindows環境では `D:\home\source\lisp\sbcl` を参照していた。
- 文書の追記：設計書・CHANGELOG・この文書への追記は、scratchpad に Python のスクリプトを Write のツールで書いて実行した（置き換える文字列が 1 回だけ現れることを `assert` で確かめ、改行コードを元のファイルに合わせる。例：`...\scratchpad\doc14.py`）。言語試験への追記は `append.py 追加分のファイル 目印`。
- tque：題名は 200 文字まで（超えると `InvalidInput`）。`tque add <題名> [--parent ID] [--dep ID]`、`tque done <ID>`、`tque ls --root 316`。
- コミットのメッセージは scratchpad のファイル（BOM なしの UTF-8、改行は LF）に書いて `git commit -F <ファイル>` で渡す（PowerShell の here-string を `-F -` に流すと失敗した）。
- agy（Antigravity CLI）：
  - auto モードはこのアカウントでは使えない。`-p` の一度だけの実行は、許可していないコマンドを自動で拒否し、そこで止まる。
  - 使えた設定：`--sandbox --settings <settings.json>`。`permissions.allow` に `command(regex:^…zilisp\.exe … --script D:/tmp/agy_review/<名前>.lisp$)` のような正規表現、`read_file(…)`・`write_file(D:/tmp/agy_review)`、`trustedWorkspaces`。`command(git log)` のような先頭一致は効かない（`command(git)` は git のすべてを許すので使わない）。
  - 設定と依頼の文：`C:\Users\n_fuk\AppData\Local\Temp\claude\2b38cd32e55d8954\e5761a66-3281-40a8-9ff1-762483b07fc1\scratchpad\agy\`。作業用の写しは `D:\tmp\agy_wt`（git worktree。2026-11-11 にも `git worktree list` にある。不要なら `git worktree remove D:/tmp/agy_wt`）。
  - 2026-11-04 15:32 の時点で利用の上限に達していた（今使えるかは未確認）。
  - `C:\Users\n_fuk\.gemini` は事前の許可の範囲外。
- タグの作成と push：`.claude/settings.local.json`（レモンが作成。git には入らない）で `Bash(git tag -a v*)` と `Bash(git push origin v*)` を許可した。auto モードの判定は、自分で設定ファイルを作ることを `[Self-Modification]` として拒否する。
- native-test の実行器を、別のディレクトリに使う方法（再現の試験に便利）：
  PowerShell で `Get-ChildItem .zig-cache\o -Recurse -Filter zilisp-native-test.exe` の新しいものを探し、`<実行器> zig-out\bin\zilisp.exe (Get-Command zig).Source <ディレクトリ> src\lib.zig <キャッシュ> Debug`（ディレクトリに `名前.lisp` と SBCL の出力の `名前.expected` を置く）。
- 言語試験の実行器は標準入力を渡せない。標準入力の試験は `eval_test.zig` で `streams.shareStdinReader` と `std.Io.Reader.fixed` を使う。`eval_test.zig` の `evalText` はスレッドなしで読むので、`#S` と `#.` は `read-from-string` を通して試す。
- 教材の1章のブロックを SBCL と比べる簡易のスクリプト：`C:\Users\n_fuk\AppData\Local\Temp\claude\2b38cd32e55d8954\9f49964b-3593-43ef-814e-feeb4feff29d\scratchpad\cmp.sh 開始番号 終了番号`（番号は `.work/samples/index.tsv`。Level 13 は 453〜485）。
- シェルの注意：
  - Bash の heredoc は、`<<'EOF'` と引用していても、本文に引用符やバックスラッシュが多いと壊れる（「unexpected EOF」で失敗する、`\\` が `\` になる。2026-11-10 に Lisp・Zig・設計書の文で起きた）。そういう文は Write・Edit のツールで書く。
  - Bash の `sed` で `\t`・`\a`・`\\` を含む文字列を書くと壊れることがある。`grep -c $'\r'` は Git Bash では行数を返すことがあり、改行コードの確認に使えない（Python で数える）。Bash の `sed` で `/…/` の範囲を書くと、Git Bash がパスに変えてしまう。`git diff --name-only` は日本語のファイル名を引用符と 8 進数で出すので、ファイル名を使うときは `git -c core.quotepath=false`。
  - Bash で `cd` した後は、作業ディレクトリが変わったままになることがある。絶対パスを使う。

## 6. 気づいたこと・未確認のこと

- SBCL の版による動作差（2026-11-12 に確認）：この環境の `/usr/local/bin/sbcl` は `SBCL 2.6.10.168-29d0bbc7f`。ソースは `/home/fuk/source/lisp/sbcl`（`sbcl-2.6.10-168-g29d0bbc7f`、commit `29d0bbc7fc949ba7ede32740d45bf9881049692f`）。`tests/language/eval/*.lisp` 40 本を一時コピー上で `sbcl --script` により実行し、2.6.7 から作った `.expected` と照合したところ、38 本は一致し、`unicode.lisp` と `conditions.lisp` に差があった。期待値と互換性記録は変更していない。
  - `unicode.lisp`：Unicode 15.0.0 基準の期待値に対し、2.6.10 では `ǅ` の行が `(453 NIL T T T)`・`(NIL NIL NIL 453)` から `(452 T T T T)`・`(T T T 454)` に変わり、印字も `ǅ` から `|ǅ|` になった。SBCL 2.6.10 のソースには Unicode 18.0.0 への更新がある。現在の差は `tests/differential/impl-dependent.toml` の `char-case-titlecase`・`reader-symbol-normalization` と関係する。
  - `conditions.lisp`：2.6.10 では定数の `x = 3` を `check-type` で検査する例で、コンパイラが挿入した型検査の `SIMPLE-TYPE-ERROR` が出る。106行目のhandler-caseの例は `Value of X in X is 3, not a STRING.` を出力し、109行目からのstore-valueによる回復例では終了コード1で途中終了する。一方、`x` を `(read-from-string "3")` から取得する動的な例は、同じ2.6.10でも従来の `The value of X is 3, which is not of type STRING.` を出す。一般のcheck-typeの文面が一律に変わったという意味ではない。ソース履歴には `c48b71254`（`check-type` 展開の変更）がある。
  - 以上は2.6.7基準の試験40本での照合であり、SBCL 全体の網羅比較ではない。既存の基準値は維持し、2.6.10 の結果は追加の比較対象として扱う。
- リポジトリの直下に、空のディレクトリ `pathnames/pathnames/` と `x/sub/x/sub/` がある（2026-11-06 に存在を確認。2026-11-11 にも `pathnames`・`x` があることを確認。git は空のディレクトリを追跡しないので `git status` には出ない）。Phase 23 のパス名の試験で作られたもの（※推測です）。消すかどうかはレモンが判断する。
- `#.` の中で標準入力を読み足す件の単体テストは、修正前のコードで失敗することを確かめていない。
- 処理系依存の一覧（`tests/differential/impl-dependent.toml`）に、Phase 24 で 3 項目、Phase 25 で 5 項目、Phase 26 で 12 項目を足し（うち 1 項目は Phase 25 からの制限）、Phase 25 の「リストの中の condition の印字」を外した。2026-11-11 の時点で全体は 50 項目。
- WSL の単体テストの 1 skipped が前から同じ試験かは未確認（2026-11-06 から）。
- CI の警告：Node.js 20 の非推奨（`actions/checkout@v4`・`actions/download-artifact@v4`）と、`ubuntu-latest` の Ubuntu 26 への移行（2026-11 時点。今の状態は未確認）。
