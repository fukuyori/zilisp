# Zilisp 引き継ぎ（2026-11-04）

リポジトリ：`D:\home\source\zig\zilisp`（github fukuyori/zilisp）。この文書（`docs/handoff.ja.md`）の状態は、2026-11-04 の更新時にコマンドで確かめたもの。
作業を引き継いだら、この文書を最新の状態に書き直すこと（古い状態を残さない）。
次のセッションでは、報告の前に必ず `git status -sb`・`git log --oneline -3`・`gh release list`・`git ls-remote --tags origin` で確かめ直すこと。

## 1. 今の状態

- **0.3 のリリースは完了**（2026-11-04、レモンが完了と判断）。
  - `gh release list`：`Zilisp 0.3.0`（Latest、v0.3.0、2026-11-04T12:32:33Z）と `Zilisp 0.2.0`。
  - 配布物：Linux・macOS の `.tar.gz` 4 つ（GitHub Actions が作成）と、Windows のインストーラーと ZIP（レモンが署名付きのものに差し替え済み、13:17）。`SHA256SUMS.txt` はレモンが削除した。
  - リリースノートから、署名の有無と `SHA256SUMS.txt` の文を削除した（`gh release edit`）。
  - タグ：`v0.3.0`（`a6b0a04` を指す注釈付きのタグ）。
- ブランチ：`main`。push 済みの最新は `1fd5141 Add handoff notes (docs/handoff.ja.md)`。
- **コミットしていない変更**（この文書の更新時。コミットと push は指示待ち）：
  - `.github/workflows/release.yml`：`SHA256SUMS.txt` の作成と、リリースノートの署名・ハッシュの文をやめた
  - `README.md`・`README.ja.md`：署名の有無と `SHA256SUMS.txt` の文を削除
  - 設計書（英日）・`docs/version-update-checklist.md`：`SHA256SUMS.txt` の記述を削除
  - `CHANGELOG.md`・`CHANGELOG.ja.md`：`Unreleased` の `Changed` に記録
  - この文書
- tque の #309（0.3 リリース）は、まだ完了にしていない（進捗 100%）。完了にするかはレモンの指示を待つ。
- 最後の全体の検証（`1b6269a` の内容。その後の変更はバージョン・文書・CI だけ）：test 3 モード通過、lang-test 63/63、native-test 35/35（Debug・ReleaseFast、通常と GC stress）、クロス5種と WSL 通過、reader-check・fmt 通過、eval-check 一致 478・output-diff 0、起動時間の中央値 9.84 ms。

## 2. 次の作業（tque）

- **#317 P25 conditions、handlers、restarts**（0.4 の最初）。受入は Level 13 の主要コード。
- 0.4（#316）の下にあるほかの項目：
  - #344 P23 の受入の残り（Level 17 の text-tools を SBCL と比べる。P25 の後）
  - #349 印字の速さの改善（印字は SBCL の約 1.8 倍の時間。初期値が `*print-pretty*` T なので影響が広い）
  - #350 exit・quit（SBCL の sb-ext:exit・quit と同じ形。`*exit-hooks*` を入れるかは未決定）
- P25 で `error` ができたら、`do`・`loop` の形の誤りを SBCL と同じ simple-error にそろえる（今は program-error。CHANGELOG と設計書に記載）。

## 3. リリースの手順（0.3 で決めたこと）

- `docs/version-update-checklist.md` のとおり：バージョンの更新 → 試験 → コミット → タグ `v<版>` の push → GitHub Actions がビルドしてリリースを登録。
- 署名付きの Windows の配布物は、レモンが `scripts/build-installer.ps1 -Sign` で作り（出力は `dist\release\`）、`gh release upload v<版> <ファイル> --clobber` で差し替える。Claude は配布物を作らない。
- リリースに `SHA256SUMS.txt` は付けない。リリースノートと README に、署名の有無を書かない（2026-11-04 の決定）。

## 4. この期間にしたこと（要点）

- Phase 24 を完了：P24a 印字の変数、P24b `format`、P24c Reader の拡張、P24d pretty printer、受入（`#nA` の読み取りと往復の試験）。`*print-pretty*` の初期値を SBCL と同じ T にした。
- 0.3 の変更（Phase 19〜24）のレビュー：agy で 2 回分、Codex で 3 回分。再現した 41 件を `04b4088` で直した。その修正への Codex のレビューを 3 回くり返し、8 件（`a28a241`）と 5 件＋3 件（`1b6269a`）を直した。
- 標準出力・標準エラー出力の書き方を `initStreaming` にした（ファイルへのリダイレクトで上書きしていた）。
- 試験：`tests/language/eval/review-cases.lisp`（GC stress の版も。大きな列の場合は `src/compiler/eval_test.zig`）。
- 0.3.0 をリリースした（`a6b0a04`）。

## 5. 作業の進め方・道具

- 全体の検証のスクリプト：`C:\Users\n_fuk\AppData\Local\Temp\claude\D--home-source-zig-zilisp\e5761a66-3281-40a8-9ff1-762483b07fc1\scratchpad\verify_p215.ps1`（PowerShell で実行。約 40 分。出力は `== 名前 exit=…` の行を見る）。
- Codex レビュー：`codex exec -C 'D:\home\source\zig\zilisp' --skip-git-repo-check -s read-only --ephemeral --color never -o <結果.md> - < <依頼.md>`。Codex は一時ファイルを書けないことがあるので、依頼に「書けなければ `zilisp.exe --eval` で試す」と書く。Codex の指摘は、必ず Zilisp と SBCL で再現を確かめてから報告する。
- agy（Antigravity CLI）：
  - auto モードはこのアカウントでは使えない。`-p` の一度だけの実行は、許可していないコマンドを自動で拒否し、そこで止まる。
  - 使えた設定：`--sandbox --settings <settings.json>`。`permissions.allow` に `command(regex:^…zilisp\.exe … --script D:/tmp/agy_review/<名前>.lisp$)` のような正規表現、`read_file(…)`・`write_file(D:/tmp/agy_review)`、`trustedWorkspaces`。`command(git log)` のような先頭一致は効かない（`command(git)` は git のすべてを許すので使わない。git の log と diff は前もってファイルに出して読ませた）。
  - 設定と依頼の文：`C:\Users\n_fuk\AppData\Local\Temp\claude\2b38cd32e55d8954\e5761a66-3281-40a8-9ff1-762483b07fc1\scratchpad\agy\`。作業用の写しは `D:\tmp\agy_wt`（git worktree。不要なら `git worktree remove D:/tmp/agy_wt`）。
  - 利用の上限に達した（2026-11-04 15:32 の時点で、戻るまで約 101 時間）。
  - `C:\Users\n_fuk\.gemini` は事前の許可の範囲外（今回、許可なく読んだことを報告済み）。
- タグの作成と push：`.claude/settings.local.json`（レモンが作成。git には入らない）で `Bash(git tag -a v*)` と `Bash(git push origin v*)` を許可した。auto モードの判定は、自分で設定ファイルを作ることを `[Self-Modification]` として拒否する。
- native-test の実行器を、別のディレクトリに使う方法（再現の試験に便利）：
  `./.zig-cache/o/<ハッシュ>/zilisp-native-test.exe zig-out/bin/zilisp.exe "$(which zig)" <ディレクトリ> src/lib.zig <キャッシュ> Debug`（ディレクトリに `名前.lisp` と SBCL の出力の `名前.expected` を置く）。
- 言語試験の実行器は標準入力を渡せない。標準入力の試験は `eval_test.zig` で `streams.shareStdinReader` と `std.Io.Reader.fixed` を使う。
- シェルの注意：Bash の heredoc や `sed` で `\t`・`\a`・`\\` を含む文字列を書くと壊れることがある。ファイルの作成と置き換えは、Write・Edit のツールか、Write で作った Python のスクリプトで行う。Bash の `sed` で `/…/` の範囲を書くと、Git Bash がパスに変えてしまう。

## 6. 気づいたこと・未確認のこと

- リポジトリの直下に、空のディレクトリ `pathnames/pathnames/` と `x/sub/x/sub/` がある（2026-11-03 15:21 に作られた。git は空のディレクトリを追跡しないので `git status` には出ない）。Phase 23 のパス名の試験で作られたもの（※推測です）。消すかどうかはレモンが判断する。
- `#.` の中で標準入力を読み足す件の単体テストは、修正前のコードで失敗することを確かめていない。
- 処理系依存の一覧（`tests/differential/impl-dependent.toml`）に、Phase 24 で 3 項目を足した（pretty stream の印字、`*print-lines*` の打ち切り、`set-pprint-dispatch` の型指定子）。
- CI の警告：Node.js 20 の非推奨（`actions/checkout@v4`・`actions/download-artifact@v4`）と、`ubuntu-latest` の Ubuntu 26 への移行。リリースは成功している。
