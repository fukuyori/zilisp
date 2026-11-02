# バージョン更新チェックリスト

Zilisp のバージョン、または使用する Zig のバージョンを変更するときに更新するファイルの一覧です。

## 1. Zilisp のバージョンを変更するとき

| ファイル | 更新する箇所 |
|---|---|
| `build.zig.zon` | `.version` |
| `src/version.zig` | `version`（`build.zig.zon` と同じ値にする） |
| `CHANGELOG.md`（英語）・`CHANGELOG.ja.md`（日本語） | 新しいバージョンの見出しと変更点（両方に同じ内容を書く） |
| `README.md`・`README.ja.md` | 「Status」・「状況」の版と、実装した機能の一覧（機能が増えたとき） |
| `installer/zilisp.iss` | 更新しない（`scripts/build-installer.ps1` が `build.zig.zon` の `.version` を読んで `AppVersion` として渡す。`src/version.zig` と違えば停止する） |

確認：`zig build test` と `zig-out/bin/zilisp --version` の表示が新しいバージョンになっていること。

リリースの手順（タグ・配布物）
1. 上の表のファイルを更新し、`CHANGELOG.md`・`CHANGELOG.ja.md` の `Unreleased` の内容を新しいバージョンの見出しに移す。
2. 試験（`zig build test`、`lang-test`、`native-test`）を実行してコミットする。
3. タグ（`v<バージョン>`）を作って push する。GitHub Actions（`.github/workflows/release.yml`）が、タグと
   `build.zig.zon`・`src/version.zig`・`CHANGELOG.md`・`CHANGELOG.ja.md` の見出しの一致を確かめ、3つの OS で試験してから、
   各ターゲットをビルドしてリリースを登録する（配布物は署名なし。リリースノートは、両方の変更履歴の該当バージョンの節）。
4. 署名付きの Windows の配布物が必要なときは、利用者が `scripts/build-installer.ps1 -Sign` で作成し（Claude は作成しない）、
   リリースの同じ名前のファイルを差し替える（`gh release upload v<バージョン> <ファイル> --clobber`。SHA256SUMS.txt も作り直す）。

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
