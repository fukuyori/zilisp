# Changelog

## Unreleased

### Added
- 企画・基本設計書（v0.3）と詳細設計書（v0.2）
- MIT ライセンス
- Phase 01：`build.zig` / `build.zig.zon`（Zig 0.17.0）、CLI の骨組み（`--version` / `--help`）、
  ベンチマークの実行器（`zig build bench`、`scripts/run-bench.ps1`）、
  リリースビルドのスクリプト（`scripts/build-release.ps1`）、
  バージョン更新チェックリスト、Zig 0.17.0 の std・言語機能の照合結果（`docs/zig-std-usage.md`）
- Phase 02：言語試験の実行器（`zig build lang-test`）、教材のコードブロックの抽出（`zig build extract-samples`）、
  SBCL による読み込みだけの分類（`tools/classify_samples/classify.lisp`）、
  `scripts/curriculum-inventory.ps1`、`compatibility/curriculum-inventory.md`、`compatibility/manifest.toml`（初期版）
- Phase 03：Reader の基本（`src/reader/`）。空白、コメント（`;`・`#| |#` の入れ子）、整数・比・浮動小数
  （`*read-base*`・`*read-default-float-format*`・指数の記号）、シンボル（エスケープ、パッケージ修飾、
  大文字への変換）、位置情報（行・列）。値を作る処理は Builder として差し替え可能（Value との接続は Phase 05）。
  SBCL との処理系依存の違いを `tests/differential/impl-dependent.toml` に記録
- Phase 04：Reader のマクロ文字。quote、文字列、リスト（ドット対）、`#'`、`#(`（`#n(` を含む）、`#\`（標準・準標準の名前、`U+XXXX`）、
  `#:`、`#b #o #x #nR`、backquote（`zl-sys:quasiquote` など）、`#+` / `#-`（`*read-suppress*`、`*features*`）。
  `#P #S #C #A #. #= ##` は後の Phase まで明示的な reader-error。
  教材のブロックを Zilisp の Reader で読み SBCL と比べる道具（`zig build reader-check`）
- Phase 05：8 バイトの Value（`enum(u64)`、下位ビットのタグ。`src/values/`）、オブジェクトの形（シンボル 64 バイト、
  cons 16 バイト、文字列、単純ベクタ、double-float、パッケージ）、仮のヒープ（Phase 06 で置き換え）、
  パッケージと intern（CL・CL-USER・KEYWORD・ZILISP・ZILISP-SYSTEM。CL の 978 シンボルは SBCL から生成：
  `tools/gen_cl_symbols/gen.lisp`）、Reader を Value につなぐ Builder、印字（prin1 相当。SBCL 2.6.7 と同じ形）、
  `zilisp --read FILE`、言語試験 `tests/language/reader/`（SBCL の出力と一致）、NIL の表現 A/B/C の計測（A を採用）
