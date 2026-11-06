# Zilisp 引き継ぎ（2026-11-06）

リポジトリ：`D:\home\source\zig\zilisp`（github fukuyori/zilisp）。この文書（`docs/handoff.ja.md`）の状態は、2026-11-06 の更新時にコマンドで確かめたもの。
作業を引き継いだら、この文書を最新の状態に書き直すこと（古い状態を残さない）。
次のセッションでは、報告の前に必ず `git status -sb`・`git log --oneline -3`・`gh release list`・`git ls-remote --tags origin`・`tque ls` で確かめ直すこと。

## 1. 今の状態

- リリース：この文書には書かない。`gh release list` と `git ls-remote --tags origin` で確かめること。
- ブランチ：`main`。コードの最新のコミットは `7ab89c7`（試験の追加）。この文書の更新は、それに続くコミット（文書だけ）。
- tque：#309（0.3 リリース）と #317（P25）は完了。#317 は 2026-11-06 にレモンの指示で完了にした。今は 0.4（#316）の途中。
- 全体の検証（`verify_p215.ps1`）が最後に通ったのは `b9949a1`（2026-11-06）：test 3 モード、lang-test 65/65、native-test 36/36（Debug・ReleaseFast、通常と GC stress）、クロス 5 種、WSL の試験 125 passed・1 skipped・0 failed、reader-check・fmt、eval-check 一致 513・output-diff 1（Level 13 L455 のファイルのエラーの文面。処理系依存）・zilisp-error 79、起動時間の中央値 12.86 ms（ReleaseFast。最小 11.80 ms）。
  - `7ab89c7` は試験だけを足したコミット。2026-11-06 に lang-test 65/65、native-test 36/36（Debug・ReleaseFast、通常と GC stress）が通過（test Debug・fmt も通過）。`conditions.lisp` は SBCL・Zilisp の通常実行・GC stress で一致。ほかの項目（クロス・WSL・eval-check・起動時間）は、コードが同じ `b9949a1` の結果。
  - **未確認**：WSL の 1 skipped が前から同じ試験か。
  - 起動時間は測るたびに 12.8〜13.5 ms ほど揺れる。設計書の値 13.55 ms は、`3edff0f` を `d3dd091` と交互に 41 回ずつ測った中央値。

## 2. P25（condition・handler・restart）のまとめ

- 内容：condition・handler・restart、`typep`、型の分岐と `check-type`・`assert`、関数としての `eval`、`do`・`do*`・`psetq` の形の誤りを simple-error に。受入（Level 13 の主要コード）は、L455（処理系依存）と L704（未実装の `get-universal-time`。#378）以外 SBCL 2.6.7 と同じ出力。
- コミット：`5214e36`（本体）・`d6c0d6e`・`f1b6ab8`・`25c48bb`・`d3dd091`・`3edff0f`・`01ce1bd`・`5c1d02a`・`59fa8ac`・`b9949a1`（Codex のレビュー 3〜14 回目の指摘）・`7ab89c7`（15 回目の提案の試験）。
- Codex のレビューは 15 回。15 回目（`b9949a1` に対して）で指摘がなくなった。依頼と結果は `C:\Users\n_fuk\AppData\Local\Temp\claude\2b38cd32e55d8954\9f49964b-3593-43ef-814e-feeb4feff29d\scratchpad\codex\`（`request.md`〜`request16.md`、`result1.md`〜`result16.md`）。修正ごとの内容は設計書（英日）の Phase 25 の節と CHANGELOG（英日）にある。
- 決めたこと：
  - 2026-11-05：condition は専用の `record` で表し P27 で CLOS にまとめる／標準の condition の report は SBCL の英語の文面／Zig で見つけたエラーは `th.signal` の場所ですぐ handler を呼ぶ／REPL は restart の一覧の表示まで。
  - 2026-11-05：`zilisp:unimplemented` は `error` の下位にしない（`serious-condition` の下位。`ignore-errors` に飲み込まれない）。CL の未実装の関数・変数も handler には `zilisp:unimplemented` として通知する（`src/runtime/thread.zig` の callSignalHook）。
  - 2026-11-06：subtypep や空かどうかの判定が要る `complex` の引数（`(and string symbol)`・`(complex nil)`・`(cons (integer 3 1) t)` など）は `zilisp:unimplemented`（SBCL は NIL）。
  - 2026-11-06：`assert` の場所（places）の値を尋ねない制限は、デバッガのフェーズで直す（下の §3）。
  - 2026-11-06：名前で restart を探すとき SBCL より多く後ろの `:test-function` を呼ぶのは、仕様違反ではない（処理系の差）。CLHS の `find-restart` の Notes に `(find-restart identifier) == (find identifier (compute-restarts) :key :restart-name)` とあり、`restart-bind` の `:test-function` には呼ぶ時期・回数の定めがない（原文を確認）。
- 意図した SBCL との違い：形は正しいがまだ判定できない型は `zilisp:unimplemented`。and・or・not・cons の部分の型は判定に使うときだけ確かめる。抜けた `restart-case` の restart をオブジェクトで呼ぶと control-error（SBCL 2.6.7 は memory fault になるので、その例は `eval_test.zig` で確かめる）。スタックの溢れは handler に通知しない（`th.stackExhausted`。handler を動かす予備の領域がない）。
- 実装の要点：handler・restart のスタックは特殊変数 `zl-sys::*handler-clusters*`・`*restart-clusters*` の動的束縛。Zig の `th.signal` は handler・restart があるときだけ `zl-sys::%signal-zig-error`（boot.lisp）を呼ぶ。Lisp の部分は boot.lisp の末尾（空でない行は全体で 1934）。
- Zig から Lisp を呼んだ後（`th.call`）は、主値だけを使うところで `th.mv_count = 1` にすること（13・14 回目の指摘。印字・`format`・`satisfies`・`eval`・reader で値が漏れていた）。正常に戻ったときだけ戻し、`Value.unwind` の経路は変えない（`throw` の多値を保つ試験が `conditions.lisp` にある）。

## 3. 次の作業（tque）

- **デバッガ（#351。#317 が完了したので着手できる）**：要件は `docs/debugger-requirements.ja.md`（英語版 `debugger-requirements.md`。v1.1、`b615282`）。外部のツール（GUI を含む）とエージェントとの連携を同じ重みで優先し、REPL のデバッガは後。0.4 に入れるのは段階 1（#356：中核の基本、`break`・`*break-on-signals*`、JSON の出力、MCP の最小）。調査の記録は `C:\Users\n_fuk\AppData\Local\Temp\claude\2b38cd32e55d8954\9f49964b-3593-43ef-814e-feeb4feff29d\scratchpad\dbg\survey\`。
  - 次にするのは要件の文書の v1.2（英日）。段階 1 に `assert` の場所の問い合わせを加える：`y-or-n-p`・`yes-or-no-p`（いまは未定義）を足し、`continue` の restart の `:interactive` で場所ごとに SBCL と同じ「The old value of X is 1.」「Do you want to supply a new value?  (y or n)」を出す（CLHS は `continue` の前に場所を変える機会を求める）。`*break-on-signals*`（Codex P25 1 回目 #7）も段階 1。
- 0.4（#316）の下のほかの項目：
  - #318 P26 defstruct（受入 Level 19）。#317 が完了したので着手できる。
  - #344 P23 の受入の残り（Level 17 の text-tools を SBCL と比べる）。着手できる。
  - #349 印字の速さの改善（印字は SBCL の約 1.8 倍の時間）。
  - #350 exit・quit（`*exit-hooks*` を入れるかは未決定）。
  - #377 印字の中の再帰でスタックが溢れるとプロセスが落ちる（重大度は高）。report の中で自分の condition を `~A` で印字する・`~/名前/` の中で同じ `~/名前/` を使う・`pprint-logical-block` の再帰・pprint-dispatch の関数の中で同じ型を印字すると、終了コード -1073741819 と `Stack overflow (no address available)` で落ちる（ふつうの関数の再帰は storage-condition になる）。Zig の関数を挟んだ入れ子の上限（`max_native_depth = 1000`。`src/runtime/thread.zig`）に届く前に Zig のスタックが溢れると推測される（※推測です。zilisp.exe のスタックの大きさは未確認）。直し方の案：生成した実行ファイルと同じ残りのスタックの検査（`src/native/rt.zig` の `stack_limit`）を `th.call` にも入れる。直す前にスタックの大きさと 1 段の使用量を測る。
  - #378 `get-universal-time`・`get-decoded-time`・`decode-universal-time`・`encode-universal-time`（どれも未定義。P25 の受入の Level 13 L704）。`get-internal-real-time` も未定義（#378 には入れていない）。
  - #379 `type-of`・`subtypep`・`deftype`（`deftype` は呼ぶと `zilisp:unimplemented`）。
  - #380 `*print-pretty*` が NIL のとき、リストの中の condition を `#<型 {アドレス}>` と書く（SBCL と違う）。

## 4. リリースの手順（0.3 で決めたこと）

- `docs/version-update-checklist.md` のとおり：バージョンの更新 → 試験 → コミット → タグ `v<版>` の push → GitHub Actions がビルドしてリリースを登録。
- 署名付きの Windows の配布物は、レモンが `scripts/build-installer.ps1 -Sign` で作り（出力は `dist\release\`）、`gh release upload v<版> <ファイル> --clobber` で差し替える。Claude は配布物を作らない。
- リリースに `SHA256SUMS.txt` は付けない。リリースノートと README に、署名の有無を書かない（2026-11-04 の決定）。

## 5. 作業の進め方・道具

- 作業の流れ（P25 で続けたもの）：Codex のレビュー（読み取り専用）→ 指摘ごとに Zilisp と SBCL 2.6.7 で再現 → 直し方の案と報告 →「直して」で修正 →「コミット、プッシュして」でコミット →「全体の検証とcodexのレビューを進めて」で次の回。
- 全体の検証のスクリプト：`C:\Users\n_fuk\AppData\Local\Temp\claude\D--home-source-zig-zilisp\e5761a66-3281-40a8-9ff1-762483b07fc1\scratchpad\verify_p215.ps1`（PowerShell でバックグラウンドで実行。約 70 分。出力は最後にまとめて出る。要約は `Select-String '^== |passed|failed|eval-check:|startup|error:'`）。走っている間は作業ツリーのソースと試験を変えない（`zig-out` も作り直される）。変えるときは git worktree（例 `D:/tmp/zl_fixNN`）で作業し、検証が終わってから写す。
  - worktree で PowerShell の `Set-Location` を使っても、`[IO.File]::WriteAllText` などの .NET の関数の相対パスは元のディレクトリを指す（2026-11-06 に、メインのリポジトリのファイルに書いてしまい、すぐ戻した）。.NET の関数には絶対パスを渡す。
- Codex レビュー：`Get-Content <依頼.md> -Raw | codex exec -C 'D:\home\source\zig\zilisp' --skip-git-repo-check -s read-only --ephemeral --color never -o <結果.md> - *> <ログ>`。Codex には `zig-out` ではなく、コピーした実行ファイル（`...\scratchpad\codex\bin\zilisp.exe`）を使わせる（検証が `zig-out` を作り直すため。コミットの前のソースなら `zig build -p <scratchpad の別の場所>` で作ってコピーする）。依頼には「書けなければ `zilisp.exe --eval` で試す」と、直さないと決めたものの一覧を書く。Codex の指摘は、必ず Zilisp と SBCL で再現を確かめてから報告する。
- 期待値の作り方：`sbcl --script <ファイル> 2>$null` の標準出力だけを、改行を LF にして BOM なしの UTF-8 で書く。`tests/language/eval/` の `.lisp` と `.expected` は `tests/language/gc-stress/` にも写す。比べるときは空白を正規化（`-replace '\s+',' '`）して、SBCL・Zilisp・`--gc-stress` の 3 つを比べる。
- コミットのメッセージは scratchpad のファイル（BOM なしの UTF-8、改行は LF）に書いて `git commit -F <ファイル>` で渡す（PowerShell の here-string を `-F -` に流すと失敗した）。
- agy（Antigravity CLI）：
  - auto モードはこのアカウントでは使えない。`-p` の一度だけの実行は、許可していないコマンドを自動で拒否し、そこで止まる。
  - 使えた設定：`--sandbox --settings <settings.json>`。`permissions.allow` に `command(regex:^…zilisp\.exe … --script D:/tmp/agy_review/<名前>.lisp$)` のような正規表現、`read_file(…)`・`write_file(D:/tmp/agy_review)`、`trustedWorkspaces`。`command(git log)` のような先頭一致は効かない（`command(git)` は git のすべてを許すので使わない）。
  - 設定と依頼の文：`C:\Users\n_fuk\AppData\Local\Temp\claude\2b38cd32e55d8954\e5761a66-3281-40a8-9ff1-762483b07fc1\scratchpad\agy\`。作業用の写しは `D:\tmp\agy_wt`（git worktree。不要なら `git worktree remove D:/tmp/agy_wt`）。
  - 2026-11-04 15:32 の時点で利用の上限に達していた（戻るまで約 101 時間。今使えるかは未確認）。
  - `C:\Users\n_fuk\.gemini` は事前の許可の範囲外。
- タグの作成と push：`.claude/settings.local.json`（レモンが作成。git には入らない）で `Bash(git tag -a v*)` と `Bash(git push origin v*)` を許可した。auto モードの判定は、自分で設定ファイルを作ることを `[Self-Modification]` として拒否する。
- native-test の実行器を、別のディレクトリに使う方法（再現の試験に便利）：
  `./.zig-cache/o/<ハッシュ>/zilisp-native-test.exe zig-out/bin/zilisp.exe "$(which zig)" <ディレクトリ> src/lib.zig <キャッシュ> Debug`（ディレクトリに `名前.lisp` と SBCL の出力の `名前.expected` を置く）。
- 言語試験の実行器は標準入力を渡せない。標準入力の試験は `eval_test.zig` で `streams.shareStdinReader` と `std.Io.Reader.fixed` を使う。
- 教材の1章のブロックを SBCL と比べる簡易のスクリプト：`C:\Users\n_fuk\AppData\Local\Temp\claude\2b38cd32e55d8954\9f49964b-3593-43ef-814e-feeb4feff29d\scratchpad\cmp.sh 開始番号 終了番号`（番号は `.work/samples/index.tsv`。Level 13 は 453〜485）。
- シェルの注意：Bash の heredoc や `sed` で `\t`・`\a`・`\\` を含む文字列を書くと壊れることがある。`grep -c $'\r'` は Git Bash では行数を返すことがあり、改行コードの確認に使えない（Python で数える）。Bash の `sed` で `/…/` の範囲を書くと、Git Bash がパスに変えてしまう。`git diff --name-only` は日本語のファイル名を引用符と 8 進数で出すので、ファイル名を使うときは `git -c core.quotepath=false`。

## 6. 気づいたこと・未確認のこと

- リポジトリの直下に、空のディレクトリ `pathnames/pathnames/` と `x/sub/x/sub/` がある（2026-11-06 にも存在を確認。git は空のディレクトリを追跡しないので `git status` には出ない）。Phase 23 のパス名の試験で作られたもの（※推測です）。消すかどうかはレモンが判断する。
- `#.` の中で標準入力を読み足す件の単体テストは、修正前のコードで失敗することを確かめていない。
- 処理系依存の一覧（`tests/differential/impl-dependent.toml`）に、Phase 24 で 3 項目、Phase 25 で 5 項目（condition の内部の型、report の文面、トップレベルの restart、リストの中の condition の印字、スタックの溢れ）を足した。
- CI の警告：Node.js 20 の非推奨（`actions/checkout@v4`・`actions/download-artifact@v4`）と、`ubuntu-latest` の Ubuntu 26 への移行（2026-11 時点。今の状態は未確認）。
