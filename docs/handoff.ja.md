# Zilisp 引き継ぎ（2026-11-11）

リポジトリ：`D:\home\source\zig\zilisp`（github fukuyori/zilisp）。この文書（`docs/handoff.ja.md`）の状態は、2026-11-11 の更新時にコマンドで確かめたもの。
作業を引き継いだら、この文書を最新の状態に書き直すこと（古い状態を残さない）。
次のセッションでは、報告の前に必ず `git status -sb`・`git log --oneline -3`・`gh release list`・`git ls-remote --tags origin`・`tque ls` で確かめ直すこと。

## 1. 今の状態

- リリース：この文書には書かない。`gh release list` と `git ls-remote --tags origin` で確かめること。
- ブランチ：`main`。Phase 26（defstruct）と時刻の関数（#378）のコミットは `7cb07fe`、Codex のレビューの修正は 1 回目 `14c8a75`・2 回目 `6c6110e`、native-test を並列にする実行器の変更は `ffea1fb`（ここまで push 済み）。**3 回目の 2 件の修正は、この文書と同じコミットに入れる**（2026-11-11 の時点では作業ツリーにあり、コミットしていない。`git status -sb` と `git log --oneline -3` で確かめること）。
- tque：#317（P25）は完了。#318（P26）・#378（時刻）・#380（リストの中の condition の印字）は、実装は済んでいるが、tque では未完了のまま（完了にするのはレモンの指示を受けてから）。今は 0.4（#316）の途中。
- 全体の検証（`verify_p215.ps1`）が最後に通ったのは `ffea1fb`（2026-11-11。`7cb07fe`・`14c8a75` でも通った）：test 3 モード、lang-test 69/69、native-test 38/38（Debug・ReleaseFast、通常と GC stress）、クロス 5 種、WSL の試験 126 passed・1 skipped・0 failed、reader-check・fmt、eval-check 一致 545・output-diff 1（Level 13 L455 のファイルのエラーの文面。処理系依存）・zilisp-error 47。所要時間は 1,311 秒（約 22 分。native-test を並列にする前は 65〜74 分）。
  - Codex の 3 回目の修正の後に確かめたのは、fmt、test Debug、lang-test 69/69、`defstruct.lisp` の SBCL・VM・GC stress での一致、native-test Debug 38/38 まで。**未確認**：修正の後の native-test の ReleaseFast、eval-check、クロス、WSL。
  - Linux 版を WSL（Asia/Tokyo）で実行して `time.lisp`・`defstruct.lisp` が期待値と一致することは、`7cb07fe` と同じソースで確かめた。**未確認**：macOS での時刻の関数の動作（クロスビルドが通ることだけ）、夏時間のある地域の動作、WSL の 1 skipped が前から同じ試験か。
  - 起動時間（ReleaseFast。`4833203`（Phase 26 の前）と交互に 41 回ずつ測った中央値）：2026-11-10 は 13.40 ms → 14.06 ms（`7cb07fe` と同じソース）、2026-11-11 は 14.06 ms → 15.04 ms（3 回目の修正の後）。検証のスクリプトの中の値（`ffea1fb` で 16.84 ms）は、ほかのコンパイルが同時に走っていたときのもの。

## 2. P26（defstruct）と時刻の関数のまとめ

- 2026-11-10 のレモンの決定（「推奨で進めて」）：構造体は専用のオブジェクト（`ObjKind.structure`。スロットを直接並べる）／範囲は設計書 §10.5 の項目と周辺の標準機能（`#S`・`copy-structure`・`equalp`・`typep`）で、`(:type list)`・`(:type vector)`・`:named`・`:initial-offset` は `zilisp:unimplemented`／スロットの `:type` は構築子と `setf` で検査する／#378（時刻）を P26 の前に入れる。
- 内容：設計書（英日）の §10.5 と「Phase 26 の実装」の節、CHANGELOG（英日）の Unreleased。
- 実装の場所：`src/primitives/structures.zig`・`src/primitives/time.zig`（新規）、`src/lisp/boot.lisp` の末尾（時刻、defstruct の順）、`object.zig`・`gc.zig`・`types.zig`（`recordTypep`・`slotCheckable`）・`equalp.zig`・`hashtables.zig`・`streams.zig`（`hasLispPrinted`）・`pprint.zig`・`printer.zig`・`reader.zig`・`value_builder.zig`（`structure`）・`functions.zig`（`fboundp` の `(setf 名前)`）。
- 受入（Level 19）：`defstruct` で止まっていた 10 ブロックはすべて SBCL 2.6.7 と同じ出力。教材の `defstruct` の 31 ブロックと `get-universal-time` の 1 ブロックが一致になった。
- 意図した SBCL との違い（`tests/differential/impl-dependent.toml` に 4 項目を足した。CLHS の節は原文で確かめていない）：初期値のない `&aux` のスロットは NIL、type-error の expected-type は書いた型のまま、構造体のリテラルはコンパイルできない、その土地の時刻の求め方（Windows 以外は `/etc/localtime`。環境変数 `TZ` は見ない）。
- 実装の要点：
  - `:include` は、展開のときに元の構造体のクラスの記述（シンボルの属性 `zl-sys::%class`）を読む。そのため `defstruct` は `eval-when` でコンパイル時にもクラスを登録する。ネイティブでコンパイルするファイルでは、`:include` する構造体をトップレベルで定義する（言語試験 `defstruct.lisp` の `animal`・`dog`・`pf` は、そのためにトップレベルに置いた）。
  - 構造体・condition を中に含むリスト・ベクタは、`*print-pretty*` が NIL でも pretty printer の経路で書く（`streams.hasLispPrinted`）。これで #380 の `prin1` の形は SBCL と同じになった（`condition-print-in-list` の項目を処理系依存の一覧から外した）。
  - `tests/language/gc-stress/` に試験を足すときは、`名前.args`（`--gc-stress --script`）も置く（ないと別の引数で実行されて失敗する）。
- README（英日）の「0.3.0 で実装したもの」の一覧に、構造体と時刻の行を足した（condition の行と同じ場所）。0.3.0 のリリースには入っていない機能なので、見出しを分けるかはレモンの判断待ち。
- Codex のレビュー（P26）：1 回目（`7cb07fe` に対して）は 5 件。どれも Zilisp と SBCL 2.6.7 で再現し、直した（`#n#` で自分を指す `#S`、BOA の supplied-p の変数と同じ名前のスロット、`:include` で型を書き換えたときの元の型、`decode-universal-time` の time-zone が秒にして整数にならない場合、オプションの余分な引数と重なり。内容は設計書の「Codex のレビューの修正（Phase 26、1回目）」）。依頼と結果は `C:\Users\n_fuk\AppData\Local\Temp\claude\2b38cd32e55d8954\d4a5fc96-8737-44b4-9d02-2040df687ef5\scratchpad\codex\`（`request1.md`・`result1.md`、再現の `r1.lisp`・`r2.lisp`）。
  - 2 回目（`14c8a75` に対して）は 6 件。どれも再現し、直した（スロットの値のリストの中の `#n#` の型の検査、`:include` の `(x)` の初期値、pretty でない印字の深さと共有の状態、`(:conc-name "")`、`(:print-function nil)`、`:include` の同じスロットの重なり。内容は設計書の「Codex のレビューの修正（Phase 26、2回目）」。`request2.md`・`result2.md`、再現の `r3.lisp`・`r4.lisp`）。
  - `#n=` の仮の値は car が unbound の cons（`value_builder.zig` の `labelDefine`）。`#S` の値の中に仮の値があれば（`containsPlaceholder`）、`th.skip_slot_type_check` を立てて構築子を呼び、構造体をラベルの表に `(unbound . 構造体)` として置く。`labelFinish` が、中に仮の値がなくなった構造体を `zl-sys::%check-structure-slots` で確かめる。
  - pretty でない印字で、Lisp の印字の関数の中からの印字（`th.pp_level` が 1 以上か `th.pp_circle` がある：`streams.inLispPrinter`）は、pretty printer の経路で書く。
  - 3 回目（`6c6110e` に対して）は 2 件。どれも再現し、直した（循環する `#S` を読んでいる間に initform が作る別の構造体・`setf`・入れ子の読み取りの型の検査が省略される、pretty でない印字で構造体の中の多次元の文字の配列を 1 段深く書く。内容は設計書の「Codex のレビューの修正（Phase 26、3回目）」。`request3.md`・`result3.md`、再現の `r5.lisp`）。`th.skip_slot_type_check` が立っている間も、`sysCheckSlotType` は値の中に仮の値がある検査だけを省略する。
  - SBCL 2.6.7 と意図して違えた 2 点（`impl-dependent.toml`）：入れ子のラベルで互いを指す型のある `#S` は、解決した後の値が型に合えば読める（SBCL は type-error）。`:include` の裸のシンボルの書き換えは受け付ける（SBCL はエラー）。

## 3. 次の作業（tque）

- **P26 の仕上げ**：レモンの指示を受けて、3 回目の修正のコミット、全体の検証（`verify_p215.ps1`）、Codex のレビューの 4 回目（§5 の流れ。指摘がなくなるまで）。その後で #318・#378・#380 を完了にするかを確かめる。
- **見つけた違い（tque には未登録）**：`*print-pretty*` が NIL のとき、type-error を `princ` すると `The value   1 is not of type   STRING` と空白が余分に入る（SBCL 2.6.7 は空白 1 つ。report の `~2@T` の扱いと推測される。※推測です。Phase 26 の変更の前から同じ）。condition を `*print-level*` の限界の深さで印字すると形が違う（`*print-level*` 2 の `((condition))`：SBCL は pretty で `((#))`、pretty でないと `((#<TYPE-ERROR #>))`。Zilisp はどちらも `((#<TYPE-ERROR expected-type: STRING datum: #>))`。Phase 25 の範囲。再現は `r6.lisp`）。
- **デバッガ（#351）**：要件は `docs/debugger-requirements.ja.md`（英語版 `debugger-requirements.md`。v1.1、`b615282`）。外部のツール（GUI を含む）とエージェントとの連携を同じ重みで優先し、REPL のデバッガは後。0.4 に入れるのは段階 1（#356：中核の基本、`break`・`*break-on-signals*`、JSON の出力、MCP の最小）。調査の記録は `C:\Users\n_fuk\AppData\Local\Temp\claude\2b38cd32e55d8954\9f49964b-3593-43ef-814e-feeb4feff29d\scratchpad\dbg\survey\`。
  - 次にするのは要件の文書の v1.2（英日）。段階 1 に `assert` の場所の問い合わせを加える：`y-or-n-p`・`yes-or-no-p`（いまは未定義）を足し、`continue` の restart の `:interactive` で場所ごとに SBCL と同じ「The old value of X is 1.」「Do you want to supply a new value?  (y or n)」を出す（CLHS は `continue` の前に場所を変える機会を求める）。`*break-on-signals*`（Codex P25 1 回目 #7）も段階 1。
- 0.4（#316）の下のほかの項目：
  - #319 P27 CLOS の class・instance・slot（#318 の後）。condition の `record` と構造体を CLOS のクラスにまとめるのもここ。
  - #344 P23 の受入の残り（Level 17 の text-tools を SBCL と比べる）。着手できる。
  - #349 印字の速さの改善（印字は SBCL の約 1.8 倍の時間）。
  - #350 exit・quit（`*exit-hooks*` を入れるかは未決定）。
  - #377 印字の中の再帰でスタックが溢れるとプロセスが落ちる（重大度は高）。report の中で自分の condition を `~A` で印字する・`~/名前/` の中で同じ `~/名前/` を使う・`pprint-logical-block` の再帰・pprint-dispatch の関数の中で同じ型を印字すると、終了コード -1073741819 と `Stack overflow (no address available)` で落ちる（ふつうの関数の再帰は storage-condition になる）。構造体の `:print-function` の中で自分を印字する場合と、自分を指す構造体の `equalp` も同じ種類と推測される（※推測です。試していない）。Zig の関数を挟んだ入れ子の上限（`max_native_depth = 1000`。`src/runtime/thread.zig`）に届く前に Zig のスタックが溢れると推測される（※推測です。zilisp.exe のスタックの大きさは未確認）。直し方の案：生成した実行ファイルと同じ残りのスタックの検査（`src/native/rt.zig` の `stack_limit`）を `th.call` にも入れる。直す前にスタックの大きさと 1 段の使用量を測る。
  - #379 `type-of`・`subtypep`・`deftype`（`deftype` は呼ぶと `zilisp:unimplemented`）。
  - `(:type list)`・`(:type vector)`・`:named`・`:initial-offset` の `defstruct`、`get-internal-real-time`・`get-internal-run-time`・`internal-time-units-per-second`・`sleep`（どれも未実装。tque には未登録）。

## 4. リリースの手順（0.3 で決めたこと）

- `docs/version-update-checklist.md` のとおり：バージョンの更新 → 試験 → コミット → タグ `v<版>` の push → GitHub Actions がビルドしてリリースを登録。
- 署名付きの Windows の配布物は、レモンが `scripts/build-installer.ps1 -Sign` で作り（出力は `dist\release\`）、`gh release upload v<版> <ファイル> --clobber` で差し替える。Claude は配布物を作らない。
- リリースに `SHA256SUMS.txt` は付けない。リリースノートと README に、署名の有無を書かない（2026-11-04 の決定）。

## 5. 作業の進め方・道具

- 作業の流れ（P25 で続けたもの）：Codex のレビュー（読み取り専用）→ 指摘ごとに Zilisp と SBCL 2.6.7 で再現 → 直し方の案と報告 →「直して」で修正 →「コミット、プッシュして」でコミット →「全体の検証とcodexのレビューを進めて」で次の回。
- 新しい Phase の始め方（P26）：教材の使い方・設計書・既存のコードを調べ、決めること（表し方・範囲など）を案と推奨つきで短く示してから、決定を受けて実装する。
- 全体の検証のスクリプト：`C:\Users\n_fuk\AppData\Local\Temp\claude\D--home-source-zig-zilisp\e5761a66-3281-40a8-9ff1-762483b07fc1\scratchpad\verify_p215.ps1`（PowerShell でバックグラウンドで実行。約 22 分（native-test を並列にする前は約 70 分）。出力は最後にまとめて出る。要約は `Select-String '^== |passed|failed|eval-check:|startup|error:'`）。走っている間は作業ツリーのソースと試験を変えない（`zig-out` も作り直される）。変えるときは git worktree（例 `D:/tmp/zl_fixNN`）で作業し、検証が終わってから写す。
  - worktree で PowerShell の `Set-Location` を使っても、`[IO.File]::WriteAllText` などの .NET の関数の相対パスは元のディレクトリを指す（2026-11-06 に、メインのリポジトリのファイルに書いてしまい、すぐ戻した）。.NET の関数には絶対パスを渡す。
  - native-test は試験を並列に実行する（2026-11-11 から。`tools/native_test/main.zig`。並列の数は環境変数 `ZILISP_NATIVE_TEST_JOBS`、既定は論理プロセッサの数の半分で 1〜8。結果はすべて終わってから名前の順に出る）。38 ファイルの Debug は、順に実行すると約 37 分、8 並列で約 7 分（この機械は 8 コア 16 スレッド）。
- Codex レビュー：`Get-Content <依頼.md> -Raw | codex exec -C 'D:\home\source\zig\zilisp' --skip-git-repo-check -s read-only --ephemeral --color never -o <結果.md> - *> <ログ>`。Codex には `zig-out` ではなく、コピーした実行ファイル（`...\scratchpad\codex\bin\zilisp.exe`）を使わせる（検証が `zig-out` を作り直すため。コミットの前のソースなら `zig build -p <scratchpad の別の場所>` で作ってコピーする）。依頼には「書けなければ `zilisp.exe --eval` で試す」と、直さないと決めたものの一覧を書く。Codex の指摘は、必ず Zilisp と SBCL で再現を確かめてから報告する。P25 の依頼と結果は `C:\Users\n_fuk\AppData\Local\Temp\claude\2b38cd32e55d8954\9f49964b-3593-43ef-814e-feeb4feff29d\scratchpad\codex\`。
- 期待値の作り方：`sbcl --script <ファイル> 2>$null` の標準出力だけを、改行を LF にして BOM なしの UTF-8 で書く。`tests/language/eval/` の `.lisp` と `.expected` は `tests/language/gc-stress/` にも写す（`.args` も置く）。比べるときは、SBCL・Zilisp・`--gc-stress` の 3 つを比べる。
- SBCL のソースは `D:\home\source\lisp\sbcl` にある（2026-11-10 にレモンが教えた。`git describe` は `sbcl-2.6.10-151-g5974545c3` で、比較に使う実行ファイルの 2.6.7 より新しい。読むだけ）。印字の形（`src/code/target-defstruct.lisp`）や時刻（`src/code/time.lisp`・`src/runtime/time.c`）の確認に使った。
- コミットのメッセージは scratchpad のファイル（BOM なしの UTF-8、改行は LF）に書いて `git commit -F <ファイル>` で渡す（PowerShell の here-string を `-F -` に流すと失敗した）。
- agy（Antigravity CLI）：
  - auto モードはこのアカウントでは使えない。`-p` の一度だけの実行は、許可していないコマンドを自動で拒否し、そこで止まる。
  - 使えた設定：`--sandbox --settings <settings.json>`。`permissions.allow` に `command(regex:^…zilisp\.exe … --script D:/tmp/agy_review/<名前>.lisp$)` のような正規表現、`read_file(…)`・`write_file(D:/tmp/agy_review)`、`trustedWorkspaces`。`command(git log)` のような先頭一致は効かない（`command(git)` は git のすべてを許すので使わない）。
  - 設定と依頼の文：`C:\Users\n_fuk\AppData\Local\Temp\claude\2b38cd32e55d8954\e5761a66-3281-40a8-9ff1-762483b07fc1\scratchpad\agy\`。作業用の写しは `D:\tmp\agy_wt`（git worktree。2026-11-10 にも `git worktree list` にある。不要なら `git worktree remove D:/tmp/agy_wt`）。
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

- リポジトリの直下に、空のディレクトリ `pathnames/pathnames/` と `x/sub/x/sub/` がある（2026-11-06 に存在を確認。2026-11-10 にも `pathnames`・`x` があることを確認。git は空のディレクトリを追跡しないので `git status` には出ない）。Phase 23 のパス名の試験で作られたもの（※推測です）。消すかどうかはレモンが判断する。
- `#.` の中で標準入力を読み足す件の単体テストは、修正前のコードで失敗することを確かめていない。
- 処理系依存の一覧（`tests/differential/impl-dependent.toml`）に、Phase 24 で 3 項目、Phase 25 で 5 項目、Phase 26 で 6 項目を足し、Phase 25 の「リストの中の condition の印字」を外した。
- WSL の単体テストの 1 skipped が前から同じ試験かは未確認（2026-11-06 から）。
- CI の警告：Node.js 20 の非推奨（`actions/checkout@v4`・`actions/download-artifact@v4`）と、`ubuntu-latest` の Ubuntu 26 への移行（2026-11 時点。今の状態は未確認）。
