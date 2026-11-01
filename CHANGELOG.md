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
