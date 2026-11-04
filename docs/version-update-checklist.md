# バージョン更新チェックリスト

Zilisp のバージョン、または使用する Zig のバージョンを変更するときに更新するファイルの一覧です。

## 1. Zilisp のバージョンを変更するとき

| ファイル | 更新する箇所 |
|---|---|
| `build.zig.zon` | `.version` |
| `src/version.zig` | `version`（`build.zig.zon` と同じ値にする） |
| `CHANGELOG.md`（英語）・`CHANGELOG.ja.md`（日本語） | 新しいバージョンの見出しと変更点（両方に同じ内容を書く） |
| `docs/Zilisp_詳細設計書_v0.2.md`・`docs/Zilisp_Detailed_Design_v0.2.md`、`docs/zig-std-usage.ja.md`・`docs/zig-std-usage.md` | 変更するときは、日本語版と英語版の両方を同じ変更で更新する（2026-11-02 決定） |
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
   リリースの同じ名前のファイルを差し替える（`gh release upload v<バージョン> <ファイル> --clobber`）。

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
| `docs/zig-std-usage.ja.md` | 照合をやり直し、結果と日付を更新する |
| `docs/Zilisp_詳細設計書_v*.md` | §1.1 の Zig のバージョン |
| `docs/Zilisp_企画・基本設計書_v*.md` | Zig のバージョンに触れている箇所 |

確認：`zig build test`、`zig build bench`、`scripts/build-release.ps1` がすべて成功すること。

## 4. Unicode の版を変更するとき

文字の種類と大文字・小文字の表（Phase 21.5。詳細設計 §11.2）は、比べる SBCL と同じ版の UCD から作る。

| ファイル | 更新する箇所 |
|---|---|
| `data/unicode/UnicodeData.txt`・`data/unicode/SpecialCasing.txt` | 新しい版の UCD のファイル（unicode.org の `Public/<版>/ucd/`）。比べる SBCL の `tools-for-build/` のものと同じであることを確かめる |
| `data/unicode/LICENSE.txt` | unicode.org の `license.txt` が変わっていれば更新する |
| `tools/gen_unicode/main.zig` | 出力の `unicode_version` |
| `src/unicode/tables.zig` | `zig build gen-unicode` で作り直す（手で編集しない） |
| `src/unicode/testdata/sbcl-<版>-chars.txt` | 比べる SBCL で `sbcl --script tools/gen_unicode/sbcl-chars.lisp` を実行して作り直す（ファイル名を変えたら `src/unicode/unicode.zig` の試験も） |
| `tests/language/eval/unicode.expected`・`tests/differential/impl-dependent.toml` | 結果が変わった箇所 |
| `README.md`・`README.ja.md`、`CHANGELOG.md`・`CHANGELOG.ja.md`、詳細設計（英日） | Unicode の版 |

確認：`zig build test`（表が UCD と同じか、全符号位置で SBCL と同じか）、`zig build lang-test`、`zig build native-test`。
