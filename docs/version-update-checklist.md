# バージョン更新チェックリスト

Zilisp のバージョン、または使用する Zig のバージョンを変更するときに更新するファイルの一覧です。

## 1. Zilisp のバージョンを変更するとき

| ファイル | 更新する箇所 |
|---|---|
| `build.zig.zon` | `.version` |
| `src/version.zig` | `version`（`build.zig.zon` と同じ値にする） |
| `CHANGELOG.md` | 新しいバージョンの見出しと変更点 |
| `installer/zilisp.iss` | `AppVersion`（Phase 38 でファイルを作成した後） |

確認：`zig build test` と `zig-out/bin/zilisp --version` の表示が新しいバージョンになっていること。

## 2. 内部形式を変更したとき（該当する場合のみ）

| 変更の内容 | 更新する箇所 |
|---|---|
| `.zfasl` の形式、Core IR、バイトコード | `.zfasl` の `format_version`（詳細設計 §7.3・§14.1） |
| `Value`・`Thread` の配置、ランタイムの関数表、定数表の形式 | ABI の版番号（詳細設計 §6.2） |

## 3. Zig のバージョンを変更するとき

更新は専用の作業単位で行う（詳細設計 §1.1）。

| ファイル | 更新する箇所 |
|---|---|
| `build.zig.zon` | `.minimum_zig_version` |
| `scripts/build-release.ps1` | 要求する Zig のバージョンの検査 |
| `docs/zig-std-usage.md` | 照合をやり直し、結果と日付を更新する |
| `docs/Zilisp_詳細設計書_v*.md` | §1.1 の Zig のバージョン |
| `docs/Zilisp_企画・基本設計書_v*.md` | Zig のバージョンに触れている箇所 |

確認：`zig build test`、`zig build bench`、`scripts/build-release.ps1` がすべて成功すること。
