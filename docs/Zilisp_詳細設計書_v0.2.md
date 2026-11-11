# Zilisp 詳細設計書

[English](Zilisp_Detailed_Design_v0.2.md)

**Version 0.2 / 2026-11-01**

| 項目 | 内容 |
|---|---|
| 上位文書 | `docs/Zilisp_企画・基本設計書_v0.3.md`（以下「基本設計」） |
| 対象範囲 | 基本設計 §19「最初に決めるべき詳細設計事項」の12項目、およびそれに付随するモジュール構成・エラーモデル・ネイティブバックエンド・ビルドスクリプト |
| 優先順位 | **実行速度が最上位**（基本設計 §17）。標準の意味論は前提条件であり、速度と引き換えにしない |
| 準拠範囲 | 基本設計のとおり（実用的な互換サブセット。実装済み機能は標準に忠実）（D-0） |
| ライセンス | MIT（D-6）。著作権表示は fukuyori |
| 状態 | §17 の決定事項 D-0〜D-10 をすべて反映した版 |

| 版 | 日付 | 改訂内容 |
|---|---|---|
| 0.1 | 2026-11-01 | 初版ドラフト |
| 0.2 | 2026-11-01 | 速度最優先に変更。D-0〜D-10 を決定し反映（Value 8バイト化、ページ単位のヒープ、保守的スタック走査、ネイティブバックエンドを主経路化、§7A 新設） |
| 0.2（追記） | 2026-11-01 | SBCL のソースと Web 情報による確認結果を反映（§2.2、§2.5、§3.1、§3.4、§7A.6、§15.1）。単一実行ファイルの条件を §16.3 に追加。参考資料を §20 に追加 |
| 0.2（追記33） | 2026-11-10 | Phase 26：`defstruct`（§9.1・§10.5・§11.2。構造体の専用のオブジェクト、クラスの記述、`defstruct` マクロの展開、スロットの `:type` の検査、`#S(…)` の印字と読み取り、`equalp`、リストの中の condition・構造体の印字の経路）と、時刻の関数（§11.2。`get-universal-time`・`decode-universal-time`・`encode-universal-time`・`get-decoded-time`） |
| 0.2（追記32） | 2026-11-05 | Phase 25：condition・handler・restart（§6.6・§7 の命令の表・§9・§11.2。condition と restart の `record`、特殊変数で表す handler と restart のスタック、Zig で見つけたエラーの handler への通知、SBCL と同じ report の文面、`typep`、型の分岐と `check-type`・`assert`、`eval` の関数） |
| 0.2（追記31） | 2026-11-04 | Phase 24（P24d）：pretty printer（§11.2。pretty stream、`pprint-logical-block` などの pretty printing の関数、`*print-pprint-dispatch*` の表と標準の印字、`format` の `~<…~:>`・`~_`・`~I`・`~:T`、`*print-pretty*` の初期値 T、`#nA` の読み取りと往復の受入） |
| 0.2（追記30） | 2026-11-03 | Phase 24（P24c）：Reader の拡張（§11.2。readtable のオブジェクト、ユーザー定義の reader macro、`#.`、`#n=`／`#n#`、読み取りと印字の `readtable-case`、`*read-base*` などの読み取りの変数、`with-standard-io-syntax`） |
| 0.2（追記29） | 2026-11-03 | Phase 24（P24b）：pretty printer 以外のすべての指示子の `format`（§11.2。SBCL と同じ字句解析と指示子の意味、`~F ~E ~G ~$` のための `flonum-to-string` の移植、`formatter`、`~T` のためのストリームの桁） |
| 0.2（追記28） | 2026-11-03 | Phase 24（P24a）：印字の変数（§11.2。`*print-base*`・`*print-case*`・`*print-circle*`・`*print-readably*` など、`write` のすべてのキーワード、`print-not-readable`） |
| 0.2（追記27） | 2026-11-03 | Phase 23：ストリームとパス名（§2.4、§11.2。標準のストリーム、ファイル・文字列のストリーム、#P、ファイルの操作、GC による閉じ忘れたストリームの後始末） |
| 0.2（追記26） | 2026-11-03 | Phase 22：パッケージ（§8.2。`*package*`、パッケージの関数、defpackage・in-package、名前の衝突、load、ネイティブの定数の修飾）。シャドウイングシンボルの持ち方の変更 |
| 0.2（追記25） | 2026-11-03 | Phase 21.6：ハッシュ表を SBCL 2.6.7 の並べ方に置き換え（§2.6。maphash の順序、枠の数の決め方、flat の表）。GC の走査しない配列 `raw_vector`（§2.4） |
| 0.2（追記24） | 2026-11-03 | Phase 21.5：Unicode 15.0.0 の文字の種類と大文字・小文字（§11.2。表の生成器と、全符号位置での SBCL 2.6.7 との比較）。§2.6 の equalp の大文字・小文字 |
| 0.2（追記23） | 2026-11-03 | 調査と決定：ハッシュ表のエントリの並べ方の比較と、SBCL の方式への置き換え（§2.6。Phase 21.6）、Unicode 15.0.0 への対応（§11.2。Phase 21.5）、フェーズごとの起動時間と対策の基準（§11.2） |
| 0.2（追記22） | 2026-11-02 | Phase 21：一般の配列（多次元・fill-pointer・adjustable。§2.4）、`equalp` と `equalp` のハッシュ表（§2.6）、文字・文字列・列・リスト・集合の関数（§11.2） |
| 0.2（追記21） | 2026-11-02 | Phase 20：数の階層の実装（bignum・比、浮動小数との混在、整数の割り算、累乗・平方根・初等関数、ビット演算。§2.4）。複素数は後の Phase |
| 0.2（追記20） | 2026-11-02 | Phase 19：tagbody・go の実装（§6.4）、反復のマクロ・loop・写像と畳み込み・format の最小版と、反復の教材で使う関数（§11.2） |
| 0.2（追記19） | 2026-11-02 | §5.2 の `define-symbol-macro` などの時期の記述（Phase 30 に移したことに合わせる）と、§6.4 の `ControlEntry` のネイティブの再開の説明（Phase 18 の実装に合わせる）を直した。英語版（`docs/Zilisp_Detailed_Design_v0.2.md`）を作成。以後、本書を変更するときは英語版も同じ変更で更新する。`docs/zig-std-usage.md` は英語版になり、日本語版は `docs/zig-std-usage.ja.md` |
| 0.2（追記18） | 2026-11-02 | 0.2.0 のリリースの準備：インストーラーのスクリプト（§18.1・§18.2）、GitHub Actions による試験とリリース（§18.4）、Linux・macOS のスタックの先頭（§3.4） |
| 0.2（追記17） | 2026-11-02 | Codex・agy のレビュー（Phase 18）を反映：暗黙の block は本体だけを囲む（defmacro のコンパイル時の定義にも付ける）、処理途中の脱出のスタックの大きさの不変条件、cleanup の間のエラーの内容の退避、検証器による制御スタックの検査、方式2の試作の修正（浮動小数の制御の状態の保存、直接呼び出し）と再計測（§6.4・§7.4） |
| 0.2（追記16） | 2026-11-02 | Phase 18：block・return-from・catch・throw・unwind-protect の実装（制御スタック、Transfer、cleanup の中の脱出、VM の再開、ネイティブのラベル付きブロック）、defun・flet・labels・defmacro の暗黙の block、非局所脱出の方式2の試作と計測（方式1を継続。§6.4・§7.4） |
| 0.2（追記15） | 2026-11-02 | Phase 17：多値の実装（ValueMode、VM の命令、関数の本体の多値の位置、REPL の印字）と、&optional・&rest・&key・&aux の実装（§5.5・§6.2・§6.3） |
| 0.2（追記14） | 2026-11-02 | Phase 16：setf と場所の展開、eval でのトップレベルのフォームの順の処理、eval-when、ハッシュ表と1次元の配列の最小版（§2.6・§5.2） |
| 0.2（追記13） | 2026-11-02 | Phase 15：マクロ展開器、defmacro、分解束縛、backquote の展開、Lisp で書く標準ライブラリの読み込み（§5.2・§11.2） |
| 0.2（追記12） | 2026-11-02 | Phase 14：動的束縛の実装（束縛のスタック、VM の命令、エラーで抜けるときの復元、special 宣言の表し方、defvar・defparameter のコンパイル時の宣言。§6.5） |
| 0.2（追記11） | 2026-11-02 | Phase 13：教材のブロックの実行と SBCL との比較（`zig build eval-check`。§13.1）、エラーの報告の呼び出しの履歴（§9.4） |
| 0.2（追記10） | 2026-11-02 | Phase 12：IR の検証器、ネイティブバックエンドの最小実装（§7A.8）、VM とネイティブの一致の試験（`zig build native-test`）、VM とネイティブの速度と、`Value.unwind` の検査の費用の計測（§6.4・§7A.8） |
| 0.2（追記9） | 2026-11-02 | VM の命令の分岐をラベル付き `switch` と `continue` に確定（計測の結果。§7.1）。`defun` の展開（§5.2） |
| 0.2（追記8） | 2026-11-02 | Phase 08 の実装に合わせて、condition ができるまでのエラーの扱い（§6.6）、`call-arguments-limit` の解釈（§7.3）、Phase 08 で実装した命令とフレームの形（§7.4）、CLI の動作（§19）を追記 |
| 0.2（追記7） | 2026-11-02 | Phase 07 の実装に対する Codex のレビュー（10件）を受けて、レジスタの退避の方法と走査の下端を確定（§3.4）。実装側では §3.5 の規則（Zig のヒープに Lisp の値を置くなら明示的なルートに登録する）への違反を修正 |
| 0.2（追記6） | 2026-11-01 | Phase 01 の照合結果（`docs/zig-std-usage.ja.md`）を受けて、Value を `enum(u64)` で定義（§2.1）、戻り値の規約を案 A に変更（主値だけをレジスタで返し、個数は `th.mv_count`、非局所脱出・エラーは特別な即値 `Value.unwind` と `th.fault`。§2.2・§6.1〜§6.4・§6.6・§7A.2）、汎用の入口を `callconv(.c)` に（§6.2） |
| 0.2（追記5） | 2026-11-01 | agy（Antigravity）によるレビューの指摘15件を反映（本文では「agy #番号」）。closure を作り直さず code にネイティブの入口を設定（§2.4・§6.2・§7A.6）、cleanup の前の動的環境の巻き戻し（§6.4）、派生したポインタの規則（§3.4）、動的環境を深さで戻す方式に統一（§6.4）、`call-next-method` の引数と `:after` の扱い（§10.3）、トップレベルフォームの再帰的な処理（§4.1・§16.1）、`setf` 関数と高速入口をシンボルの欄に（§6.2・§8.1）、Phase 12〜34 は `.zfasl` を介さない（§5.1・§15.2）、自己再帰のループ化と `musttail` の型の制約（§6.2・§7A.3）、まとめてコンパイル・プロセス数の上限・キャッシュの掃除（§7A.6）、CL 関数の直接呼び出し（§5.2）、`equalp` のハッシュ（§2.6）、`defconstant`（§8.1・§16.1）、`unintern`・シャドウイング（§8.2）、`&environment`・`define-symbol-macro` の時期（§5.2） |
| 0.2（追記4） | 2026-11-01 | Codex によるレビューの指摘（24件。#25 は CLHS で確認のうえ不採用、#5 は一部のみ採用）を反映。`eql` のハッシュ（§2.6）、GC の資源回収と確保量（§3.1・§3.2）、保守的走査の「生存の契約」（§3.4）、FFI の貸し出し（§3.6）、単一スレッドの制約（§6.1）、共有ライブラリとの ABI（§6.2）、多値の退避（§6.3）、`unwind-protect` と入れ子の脱出（§6.4）、未束縛の特殊変数（§6.5・§7.4）、引数の個数の符号化（§7.3）、バイトコードの検証（§7.4・§14.1）、末尾呼び出しの条件（§7A.3）、バックグラウンドのジョブ・`compile`・キャッシュ（§7A.6）、Reader の `#+`・`#.`（§8.5・§12）、クラスの再定義の標準手順（§10.2）、標準メソッド結合（§10.3）、キャッシュの失効（§10.4）、混在経路の試験と GC の再判断（§13）、`.zfasl` のロード順序（§14.1）、起動時の状態復元の範囲（§15.3） |
| 0.2（追記3） | 2026-11-01 | SICL・Janet・Carp の調査結果を反映。クラスの番号（stamp）によるディスパッチとキャッシュの失効（§10.2、§10.4）、rack によるインスタンスの表現（§2.4、§10.2）、判別用コードの生成（§10.4）、Zig の識別子とソース位置の対応づけ（§7A.5）、起動時間の対策（§11.3、§15.3）、参考資料（§20） |
| 0.2（追記2） | 2026-11-01 | ECL・Clasp・Gambit・Emacs の調査結果を反映。NIL の C 案（§2.2）、主値と個数を返す呼び出し規約（§6.2）、非局所脱出の方式の比較計測（§6.4）、末尾呼び出しの代替手段（§7A.3）、D-10 を④バックグラウンドのネイティブ化に変更（§5.1、§7.1、§7A.6、§17）、生成コードの関数の大きさの規則（§7A.7）、ansi-test の両方式での実行（§13.1）、参考資料（§20） |

> **記述上の約束**
> - 「確定」は本書で決めた設計事項、「要検証」は Zig 0.17.0 等の実物で確認が必要な事項、「要調査」は外部の調査が必要な事項を示す。
> - Zig 標準ライブラリと Zig 言語機能の名前は、本書執筆時点で実物と照合していない。名前を挙げている箇所はすべて **要検証** とし、Phase 01 で照合する（§1.3）。
> - 性能の効果についての記述は、計測前の推測である。
> - 本書に記載のコマンド・API・ファイル名は計画であり、実装済みを意味しない。

---

## 目次

1. Zig版・対象アーキテクチャ・標準ライブラリの使用範囲
2. Value 表現とヒープオブジェクトヘッダ
3. ヒープと GC：ページ管理、ルート、FFI handle
4. ソース位置情報
5. コンパイラ・パイプラインと Core IR
6. 実行時の共通基盤：呼び出し規約、多値、非局所脱出、動的束縛
7. バイトコード VM
7A. ネイティブバックエンドと REPL のネイティブ化
8. 名前空間・パッケージ・intern テーブル
9. Condition / restart の実行時構造
10. CLOS：クラス表、標準メソッド結合、キャッシュ失効
11. ブートストラップ順序と標準ライブラリのロード
12. 教材サンプルの A〜E 分類と依存関数一覧（手順）
13. SBCL との差分試験・性能計測
14. コンパイル済みモジュール形式（`.zfasl`）
15. 実行ファイルの生成（`zilisp build`）
16. `compile-file` と `zilisp build` の違い、マルチOS配布条件
17. 決定事項
18. 処理系自身のビルド・リリーススクリプト
19. Phase 01〜08 の実装単位への分解
20. 参考資料

---

## 1. Zig版・対象アーキテクチャ・標準ライブラリの使用範囲

### 1.1 Zig のバージョン（確定）

- **Zig 0.17.0** に固定する（2026-11-01 時点で開発環境の `zig version` が 0.17.0 であることを確認した）。
- `build.zig.zon` の `minimum_zig_version` に `0.17.0` を記載する。
- Zig の更新は、更新専用の作業単位で実施する。手順は `docs/version-update-checklist.md` に記す（§18.3）。

### 1.2 対象ターゲット

| 区分 | ターゲット（Zig 表記、要検証） | 位置づけ |
|---|---|---|
| 一次 | `x86_64-windows` | 開発機。全テスト・ベンチマークを毎回実行 |
| 一次 | `x86_64-linux`（musl 静的リンクを第一案） | CI/WSL で実行 |
| 一次 | `aarch64-macos` | 実機試験はリリース前に実施 |
| 二次 | `x86_64-macos`、`aarch64-linux`、`aarch64-windows` | クロスビルドの成否のみ報告。実機動作は別記 |

対象はすべて64ビットとする（§2 の Value 表現の前提）。「クロスコンパイルが成功した」ことと「実機で動作した」ことは、常に区別して報告する。

### 1.3 Zig 標準ライブラリ・言語機能の使用範囲

| 用途 | 使用する予定の機能（名前はすべて要検証） | 方針 |
|---|---|---|
| メモリ | ページアロケータ、汎用アロケータ、ArenaAllocator | ヒープのページ確保（OS から大きな単位で取得）と、コンパイラの一時領域にのみ使う |
| 集合 | ハッシュマップ、ArrayList 相当 | Zig 側の非GC管理データにのみ使う |
| 多倍長整数 | `std.math.big.int` の limb 演算 | limb 配列は管理ヒープに置き、演算だけを借りる |
| ハッシュ | Wyhash 等の非暗号ハッシュ、CRC32 | sxhash、intern、`.zfasl` のチェックサム |
| 算術 | `@addWithOverflow` 等の溢れ検出付き演算 | fixnum の高速経路（§2.2） |
| ディスパッチ | ラベル付き `switch` と `continue`（スレッデッドコード相当の分岐） | VM の命令分岐（§7） |
| 末尾呼び出し | `@call(.always_tail, …)` | ネイティブコードの末尾呼び出し（§7A） |
| レジスタの退避 | インラインアセンブリ、またはそれに代わる方法 | 保守的スタック走査の前にレジスタをスタックに退避する（§3.4） |
| ファイル・プロセス | ファイル・ディレクトリ・環境変数・自身の実行ファイルパス・子プロセス | `src/platform/` からのみ呼ぶ |
| I/O | std の I/O・Writer/Reader 系インターフェース | 0.15 以降で大きな変更があったため、`src/platform/io.zig` で吸収する |
| 文字コード | UTF-8 / UTF-16 変換 | Windows API 境界でのみ使う |

**規則**：`std` への依存は `src/platform/` と `src/support/` に集め、上位層は Zilisp の自前インターフェースだけを参照する。

**Phase 01 の検証項目**：上表の各機能について、0.17.0 に実在すること、シグネチャ、使用例を `docs/zig-std-usage.ja.md` に記録する。存在しない機能があれば本書を改訂する。

---

## 2. Value 表現とヒープオブジェクトヘッダ（D-9）

### 2.1 方針

- `Value` は **8バイト（64ビット）の1語**とし、**下位3ビットに型タグ**を置く。ヒープのオブジェクトは8バイト境界（cons は16バイト境界）に配置するので、ポインタの下位3ビットは常に 0 であり、タグに使える。
- `Value` のビット操作は `src/values/` の中だけで行う。他の層はメソッド（`isCons()`、`asFixnum()`、`Value.fromFixnum()` など）経由でのみ扱う。
- **Zig での定義は `enum(u64)`（非網羅の enum）とする**（2026-11-01 確定）。Zig 0.17.0 の既定の呼び出し規約では、`enum(u64)` の値はレジスタで返されるが、8バイトの `extern struct` はメモリ経由で返される（`docs/zig-std-usage.ja.md` §3 で、x86_64-windows・x86_64-linux・aarch64-macos のアセンブリを確認）。

```zig
pub const Value = enum(u64) {
    _,
    // 特別な即値は定数として定義する（例：pub const nil: Value = …;）
};
```
- fixnum の範囲は 62 ビット（`most-positive-fixnum` = 2^61−1、`most-negative-fixnum` = −2^61）とする。

### 2.2 タグの割り当て（確定）

```text
 63                                              3 2 1 0
┌───────────────────────────────────────────────┬─┬─┬─┐
│ 符号付き整数（62ビット）                          │x│0│0│  fixnum      （下位2ビットが 00。bit2 は値の一部）
│ cons のアドレス                                 │0│0│1│  cons
│ ヘッダ付きオブジェクトのアドレス                    │0│1│1│  other
│ 関数オブジェクトのアドレス                         │1│0│1│  function
│ 即値                                           │1│1│1│  immediate（下位8ビットで種類を分ける）
└───────────────────────────────────────────────┴─┴─┴─┘
  010 と 110 は予約
```

**即値（下位3ビットが 111）の内訳**（下位8ビットで区別する）

| 種類 | 上位ビットの内容 |
|---|---|
| `nil` | なし（固定の1語） |
| `unbound` | なし。Lisp 側には決して出さない |
| `unwind` | なし。**関数の戻り値として、非局所脱出・エラーが進行中であることを表す**（§6.2）。Lisp 側には決して出さない |
| `character` | bit 8〜28 にコードポイント（21ビット） |
| `single_float` | bit 32〜63 に f32 のビット列 |
| `forward_marker` 等 | 内部用（予約） |

| 決定事項 | 内容 | 理由 |
|---|---|---|
| fixnum の演算 | タグを付けたまま加減算する（下位 `00` 同士の和は `00`）。溢れは `@addWithOverflow` で検出し、bignum に切り替える | 加算1命令と溢れ検査で済む |
| 型の検査 | 下位3ビット（即値は下位8ビット）の比較だけで行う | 分岐が1つで済む |
| NIL | 固定の即値。`symbol-name` 等ではランタイムが持つ NIL シンボルの実体に読み替える（**2026-11-02 確定**。下の比較の計測結果による） | `null` の判定が定数1つとの比較で済む |
| T | 通常のシンボル（`other`） | 特別扱いを最小にする |
| single-float | 即値 | CL の既定の浮動小数（`*read-default-float-format*` の既定値は `single-float`）をヒープに確保しない |
| double-float | ヒープに確保する（`other`、ObjKind `double_float`） | 64ビットの語に収まらないため。ネイティブコードでは型推論でボックス化を避ける（§7A.3） |
| function タグ | `funcall` / `apply` の型検査を、ヘッダを読まずに行う | 呼び出しは最も頻度が高い操作の一つ |
| 文字 | 0〜#x10FFFF。`char-code-limit` = #x110000 | Unicode を前提とする |

**NIL の表現の比較（Phase 05 で計測して決める）**

| 方式 | 内容 | `car` / `cdr` の速さ | 備考 |
|---|---|---|---|
| A：即値（現在の暫定案） | NIL は固定の即値 | リストに `car` を適用するとき、「cons か」「NIL か」の2つの判定が要る | 実装が単純 |
| B：cons と symbol を兼ねる（SBCL の方式） | NIL を、cons のタグでも symbol としても読める特別な配置のオブジェクトにする。NIL の car と cdr の位置に NIL 自身を置く | 「リストのタグか」の判定1つで、NIL にもそのまま `car` を適用できる | SBCL の `src/compiler/generic/early-objdef.lisp` 20〜22行目で確認した（「NIL is both a cons and a symbol (at the same address)」）。cons タグと other タグのオフセットの関係に制約がかかる |

| C：list のタグを持つ固定の値（ECL の方式） | NIL を、cons のタグを持つ固定のアドレス値にする（ECL では `ECL_NIL` = 1。`src/h/object.h` 289行目）。`car`・`cdr` の前に NIL かどうかを比較する | 「list のタグか」の判定1つで「リストか」が分かる。`car` の前に NIL との比較が1つ要る | B より単純で、`listp` の判定は B と同じ速さ |

速度最優先のため、**Phase 05 で A・B・C を同じベンチマークで計測し、最も速いものを採用する**（R5）。

**計測結果（2026-11-02、Phase 05）**：`tests/bench/nil_repr.zig`（`zig build bench -- nil-repr`）を x86_64-windows・ReleaseFast で5回実行した中央値（1回あたりの ns）。

| 表現 | length（1000要素のリストをたどる） | safe-cadr（長さ0〜3のリストに `(car (cdr x))`） |
|---|---|---|
| A：即値 | 1.005 | 0.694 |
| B：cons と symbol を兼ねる | 1.006 | 0.709 |
| C：cons のタグを持つ固定の値 | 1.002 | 0.689 |

3つの差は3%以内で、同じ表現の計測のばらつき（最小と最大で2〜3%）と同程度だった。意味のある差がないため、**実装が最も単純な A を採用する**（B は NIL を cons と symbol の両方として配置する必要があり、C は A と判定の数が同じ）。この計測は単独の小さな処理によるものなので、Phase 12 以降のネイティブコードのベンチマークで差が現れた場合は見直す。

**SBCL（x86-64）との比較**：SBCL は下位4ビットをタグに使い、fixnum は下位1ビットが 0（63ビット）である（`early-objdef.lisp` 37〜69行目、および SBCL 2.6.7 で `most-positive-fixnum` = 2^62−1 を確認）。Zilisp は fixnum を62ビットとするため、範囲は SBCL より1ビット狭い。

### 2.3 ヒープオブジェクトヘッダ（cons 以外）

```zig
pub const ObjHeader = packed struct(u64) {
    kind: ObjKind,   // u8
    flags: u8,       // 種別ごとのフラグ（finalize 必要、pinned など）
    aux: u16,        // 種別ごとの小さな値
    len: u32,        // 長さ・要素数など
};                   // 8 バイト
```

- **マークビットはヘッダに置かない**（ページ外のビット表に置く。§3.2）。
- 全オブジェクトをつなぐリストは持たない。

### 2.4 ObjKind 一覧（初版）

| ObjKind | タグ | 主な内容 | 対応する CL 型 |
|---|---|---|---|
| （cons） | cons | **ヘッダなし**。car（8）＋ cdr（8）＝16バイト | `cons` |
| `symbol` | other | name、package、value、function、plist、flags | `symbol`（NIL 実体を含む） |
| `string` | other | 長さ、幅（u8/u32）、別確保バッファ | `simple-string`（`character` 要素） |
| `simple_vector` | other | Value を本体内に直接配置 | `simple-vector` |
| `byte_vector` | other | u8 を本体内に直接配置 | `(simple-array (unsigned-byte 8) (*))` |
| `double_vector` | other | f64 を本体内に直接配置 | `(simple-array double-float (*))` |
| `fixnum_vector` | other | i64 を本体内に直接配置 | `(simple-array fixnum (*))` |
| `bit_vector` | other | ビット列 | `simple-bit-vector` |
| `array` | other | 次元、fill-pointer、adjustable、displaced 先、実データ | 単純でない配列・多次元配列 |
| `double_float` | other | f64 | `double-float` |
| `bignum` | other | 符号、limb 列 | `bignum` |
| `ratio` | other | 分子・分母（約分済み、分母は正） | `ratio` |
| `complex` | other | 実部・虚部 | `complex` |
| `hash_table` | other | 比較関数、キーと値の配列、バケットの表と鎖、ハッシュ値の配列（Phase 21.6。§2.6） | `hash-table` |
| `raw_vector` | other | u32 か u64 を本体内に直接配置（GC は中を走査しない。Phase 21.6） | （内部：ハッシュ表のバケットの表・鎖・ハッシュ値） |
| `package` | other | §8 | `package` |
| `code` | other | バイトコード、定数表、ラムダリスト記述子、行番号表、**ネイティブの入口**（ネイティブ化が済んでいれば。§7A.6） | （内部。同じ lambda から作った closure すべてが共有する） |
| `closure` | function | 入口アドレス、code、捕捉値の配列（並べ方は VM とネイティブで共通。§7A.6） | `function` |
| `native_function` | function | 入口アドレス、名前、ラムダリスト記述子 | `function`（ネイティブコード・プリミティブ） |
| `value_cell` | other | Value 1つ | （内部：捕捉され、かつ代入される変数の箱） |
| `instance` | other | class、rack へのポインタ（§10.2） | `standard-object`、condition |
| `rack` | other | 番号（stamp）、layout、スロットの値の並び | （内部：インスタンスのスロットの本体） |
| `structure` | other | layout、スロット配列 | `structure-object` |
| `class` / `layout` | other | §10 | `class` / （内部） |
| `generic_function` | function | §10 | `generic-function` |
| `method` | other | §10 | `method` |
| `stream` | other | 種別、Lisp の値（ref）、Zig の側の状態（OS ハンドル・入出力のバッファ・エンコーディング。Phase 23） | `stream` |
| `pathname` | other | host、device、directory、name、type、version（Phase 23） | `pathname` |
| `environment` | other | コンパイラの環境（動的エクステントのみ有効） | `&environment` の値 |
| `foreign_pointer` | other | アドレス、所有フラグ | （拡張） |
| `random_state` / `readtable` | other | | `random-state` / `readtable` |

- マクロ専用の ObjKind は設けない。マクロ関数は関数オブジェクトで表し、シンボルの関数セルに「マクロ」フラグを付けて区別する。
- condition は condition-class の `instance` とする（§9）。
- 要素型を特殊化した配列（`double_vector`、`fixnum_vector`）は、値をボックス化せずに並べる。数値計算の速度のために 1.0 から用意する。

**Phase 20 の実装（数の階層）**
- **bignum**：limb（usize）を、ヘッダの直後に下位から並べる（`object.Bignum`。header.len が limb の数、header.aux が 1 なら負）。値は変わらない（演算はいつも新しい bignum を作る）ので、別のバッファも finalize も要らない。**fixnum の範囲に収まる値は、必ず fixnum にする**（`Runtime.makeInteger`）。このため、整数が fixnum か bignum かは値だけで決まり、`eql` は bignum どうしを値で比べればよい。
- **比**：分子と分母の Value を持つ（`object.Ratio`）。いつも約分し、分母は 2 以上（分母が 1 なら整数にする）。
- 多倍長の演算は `std.math.big.int.Managed` を借りる。途中の値は Zig のヒープ（gpa）に置き、結果だけを Lisp のヒープに作る。fixnum どうしの加減乗算は i128 で計算し、収まらなければ bignum にする（VM・ネイティブの高速経路は、溢れたときにこの処理へ回す）。
- **混在の規則**（CLHS 12.1.4）：整数と比どうしの演算は正確。浮動小数が混ざれば浮動小数（double-float が混ざれば double-float、そうでなければ single-float）。比較は正確（浮動小数を正確な有理数に直して比べる。fixnum は高速経路）。
- **有理数から浮動小数への変換**：分子・分母が仮数のビット数に収まれば、浮動小数の割り算1回（丸めは1回で正しい）。そうでなければ、64 ビット以上の商を求め、余りがあれば最下位のビットを立ててから（sticky）丸めるので、丸めは1回で正しい。浮動小数から有理数への変換（`rational`）は正確。
- **関数**：`floor`・`ceiling`・`truncate`・`round`（商と余りの2つの値。round は半分なら偶数）、`mod`・`rem`、`gcd`・`lcm`、`numerator`・`denominator`、`rational`・`float`、`expt`（正確な数の整数乗は正確。指数が比・浮動小数なら浮動小数）、`sqrt`・`isqrt`、`exp`・`log`・`sin`・`cos`・`tan`・`asin`・`acos`・`atan`、`logand`・`logior`・`logxor`・`lognot`・`ash`・`integer-length`・`logcount`（2の補数の意味）、型の述語（`integerp`・`rationalp`・`floatp`・`realp`・`complexp`）。Reader は fixnum を超える整数と比（`1/2`、`#x…`、`#b-101/11`）を読み、印字は10進で書く（`*print-base*` は Phase 24）。
- **複素数は未実装**（2026-11-02 決定。後の Phase で実装する）：結果が複素数になる演算（負の数の `sqrt`・`log`、負の底の分数乗、範囲外の `asin`・`acos`）は明示的なエラー。`complexp` はいつも NIL。
- **SBCL 2.6.7 との違い**：fixnum は 62 ビット（SBCL は 63 ビット。`most-positive-fixnum` が違う）。超越関数は Zig の実装（`@exp` など）を使うので、double-float で最後の 1 ビットが違うことがある（例：`(exp 1d0)` は SBCL が `2.718281828459045d0`、Zilisp が `2.7182818284590455d0`。どちらも誤差は 1 ulp 未満。※CLHS には超越関数の浮動小数の結果の精度の規定がないと推測されます。原文での確認はしていません）。`tests/differential/impl-dependent.toml` に記録した。
- 試験：SBCL 2.6.7 の結果と比べる192通り（GC stress でも実行。ネイティブでも実行：`number-cases.lisp`）、fixnum の境界、読み・印字の往復、`eql`・ハッシュ表、エラーの種類。言語試験 `numbers.lisp`（と gc-stress 版）。

**Phase 21 の実装（一般の配列）**
- **表し方**：1次元で fill-pointer がなく adjustable でない配列は、今までどおり simple-vector（要素の型 T）か文字列（要素の型 character）。それ以外（多次元・fill-pointer あり・adjustable）は `array` オブジェクト（`object.Array`）：header.len は次元の数、header.flags は adjustable と fill-pointer の印、続いて fill-pointer、data（要素を行優先で並べた simple-vector か文字列）、次元の大きさ。GC は data だけを印付けする。
- **要素の型**：T と文字（シンボルの `character`・`base-char`・`standard-char`）。ほかの型は、`(or character integer)` などの複合の型指定もすべて T に格上げする（CLHS 15.1.2.1。T はどの要素も入れられるので、正しい格上げ）。数の特化ベクタは上記のとおり 1.0 から。
- **fill-pointer のあるベクタは adjustable**（`adjustable-array-p` が T。`vector-push-extend` でいつでも大きくできる。SBCL 2.6.7 と同じ）。`vector-push-extend` で大きくするとき、増やす数の既定は今の大きさ（0 なら 1）。指定があればその数。`adjust-array` は、adjustable な配列はその配列を書き換えて返し、そうでなければ新しい配列を返す。新旧の両方の次元に収まる添字の要素を引き継ぐ。
- `adjust-array` に NIL でない `:fill-pointer` を指定できるのは、fill-pointer のある配列だけ（そうでなければ `type-error`。SBCL 2.6.7 は `simple-type-error`、0次元の配列なら `simple-error`）。
- **displaced な配列は未実装**（明示的なエラー）。
- **関数**：`make-array`（次元のリスト、`:element-type`・`:initial-element`・次元の数だけ入れ子の `:initial-contents`・`:adjustable`・`:fill-pointer`）、添字がいくつでもよい `aref` と `(setf aref)`、`row-major-aref`、`array-dimensions`・`array-dimension`・`array-rank`・`array-total-size`・`array-row-major-index`・`array-in-bounds-p`・`array-element-type`・`array-has-fill-pointer-p`・`adjustable-array-p`、`fill-pointer`（と setf）、`vector-push`・`vector-push-extend`・`vector-pop`・`adjust-array`、`stringp`・`simple-string-p`。`length`・`copy-seq`・`elt`・列の関数・`equal`・`equal` のハッシュ値・印字は、単純でないベクタの有効な部分（fill-pointer まで）を使う。単純でない文字列も文字列として扱う（`stringp`・`equal`・文字列の関数）。
- **印字**（SBCL 2.6.7 と同じ）：1次元はベクタ・文字列と同じ形（有効な部分だけ）。多次元は `#2A((1 2) (3 4))`、0次元は `#0A7`。

### 2.5 文字列

- 型は `(simple-array character (*))`。内部的には幅1バイト（コード ≤ #xFF）と幅4バイトの2通りの表現を持つ。幅1の文字列に #xFF を超える文字を `setf` した時点で、バッファだけを幅4に再確保する（オブジェクトは移動しない）。
- `base-char` はコード < 128 の文字とする。SBCL も Unicode 対応版では同じ境界である（確認済み：`src/compiler/generic/early-vm.lisp` 121行目 `base-char-code-limit #-sb-unicode 256 #+sb-unicode 128`。SBCL 2.6.7 で `sb-int:base-char-code-limit` = 128、`(typep (code-char 200) 'base-char)` = NIL）。
- UTF-8 への変換は、ストリームと FFI の境界でのみ行う。

### 2.6 ハッシュテーブル

**Phase 16 の最小版**（`src/primitives/hashtables.zig`）：比較は `eq`・`eql`・`equal`（`equalp` は Phase 21 で加えた。下記）。項目は simple-vector に (キー 値) の組で並べる開番地法（線形探査。容量は 2 の冪。使用率 3/4 を超えたら作り直す）。空きの枠はキーが unbound、削除した枠は墓標のシンボル。非移動型の GC なので、`eq`・`eql` のハッシュ値にアドレスを使う。`equal` のハッシュ値は、cons は深さ 4 まで、文字列は中身から作る。`gethash` は2つ目の値（あったかどうか）も多値レジスタに置く。弱いハッシュ表は未実装。

- **`eq` のハッシュ**：非移動型 GC なので、アドレス（即値は語そのもの）を使える。
- **`eql` のハッシュ**（レビュー #4）：アドレスは使えない。`eql` は、型が同じで値が等しい数（bignum・ratio・double-float・complex）と文字を等しいとみなすため（例：`(eql (expt 2 100) (expt 2 100))` は T、`eq` は NIL。SBCL 2.6.7 で確認）。数と文字は値からハッシュを計算し、それ以外のオブジェクトはアドレスを使う。
- **`equal` と `equalp` のハッシュは別の関数にする**（agy #12）。
  - `equal` 用：CLHS `sxhash` と整合させる（`equal` な2つのオブジェクトは同じ値になる）。
  - `equalp` 用：`equalp` で等しいものが同じ値になるようにする。具体的には、**数は数値として等しければ同じ値**（`1`・`1.0f0`・`1.0d0`・`#c(1.0 0.0)` など。`equalp` は数を `=` で比べるため）、**文字は大文字小文字を区別しない**（`char-equal`）、**文字列と文字のベクタは同じ計算方法**（`"abc"` と `#(#\A #\b #\c)` は `equalp`）、配列・構造体・ハッシュ表は要素を再帰的に使う。`sxhash` は `equal` 用であり、`equalp` 用には使えない（CLHS `equalp`、`sxhash`）。
  - キーとして使っている間にオブジェクトを変更した場合の結果は未定義である（CLHS 18.1.2）。
- **エントリの並べ方**（レビュー #21）：挿入順のエントリ配列とオープンアドレス方式のインデックス表で構成する案を初期案とする。CLHS は `maphash` の順序を規定しておらず、差分試験は順序を並べ替えて比べる（§13.1）ため、挿入順を保つ必要はない。**Phase 21 で、挿入順を保たない方式と、検索・挿入・削除・走査の速さとメモリ使用量を比べ、速い方を採用する。**
- `:weakness` 引数は 1.0 では未対応とし、指定された場合はエラーにする。

**Phase 21 の実装（`equalp`）**
- `equalp`（`src/primitives/equalp.zig`）：文字は `char-equal`、数は `=`、cons は再帰的に、配列は次元が同じで要素がすべて `equalp`（ベクタは有効な部分を比べるので、文字列と文字のベクタも `equalp` になりうる）、ハッシュ表は比較の種類と項目の数が同じで、一方の各キーがもう一方にあり値が `equalp`。それ以外は `eq`。大文字・小文字は `char-downcase` の値でそろえる（`char-equal` と同じ。Phase 21.5 から Unicode 15.0.0 に従う。それまでは ASCII の文字だけ）。
- **`equalp` のハッシュ表**：数のハッシュ値は、正しく丸めた double-float の値から求める（`=` で等しい数は同じ double-float に丸まるので、同じハッシュ値になる。`-0.0` と `0.0` はそろえる）。文字は大文字・小文字をそろえる。ベクタは長さと先頭の 16 個までの要素（深さを制限）、多次元の配列は全体の大きさ、ハッシュ表は項目の数、cons は深さ 4 まで。
- `equal` のハッシュ値と `equal` は、単純でない文字列も中身で扱う。`sxhash` は `equal` のハッシュ値を負でない fixnum で返す。
- **エントリの並べ方の比較（2026-11-03）**：リポジトリの外に、4つの方式を Zig で書いて比べた（ReleaseFast、x86_64-windows、3回の最小値。キーは `eql` の表の fixnum と、`equal` の表の文字列。文字列は中身が同じ別のオブジェクトで引く。メモリは malloc で確保し、GC のヒープではない）。OA はいまの表（キーと値を交互に並べた開番地法と墓標。ハッシュ値は持たない）、OAH は OA にハッシュ値の配列を加えたもの、CH は SBCL の方式（キーと値の配列、バケットの表、`next` の鎖、空き枠の一覧。ハッシュ値は `equal` 系の表だけが持つ）、DI は初期案（挿入順の密な配列と開番地法の添字の表。Python の dict と同じ）。結果（1回あたりの ns）：
  - 1,000件以下の表：あるキーを引く時間は、どの方式もほぼ同じ（fixnum で 1.5〜2.1 ns）。CH は、削除と挿入の繰り返し（17 ns。OA は 31 ns：墓標が溜まり、同じ大きさの作り直しが繰り返される）、走査（1件 0.2 ns。OA は 0.3〜0.7 ns）、ないキーを引くことが速く、容量も小さい（1件 25 バイト。OA は 33 バイト）。
  - 文字列のキー：CH は、表の作成が OA の約1/3、削除と挿入の繰り返しが約1/2の時間（ハッシュ値を持つので、計算し直しと中身の比較が減る）。
  - 10万件以上の fixnum の表：あるキーを引くのは OA が約1.6倍速い（10万件で 5.6 対 9.1 ns、100万件で 21.5 対 35.8 ns。CH はバケットの表とエントリの2回のメモリの読み込みが要るためと推測されます）。ほかの操作は CH が速い。
  - DI は CH とほぼ同じか少し遅く、容量は CH より大きい。
- **決定**：Phase 21.6（tque #343。Phase 21.5 の後、Phase 22 の前）で CH（SBCL の方式）に置き換える。最初に、GC のヒープに走査しない u32 の配列（バケットの表と鎖）を置けるかを確かめる。10万件を超える fixnum の表で、あるキーを引くのが遅くなることは許容する。

**Phase 21.6 の実装（ハッシュ表の並べ方）**
- **並べ方**（`src/values/object.zig` の `HashTable`、`src/primitives/hashtables.zig`）：キーと値の simple-vector（枠 i のキーが 2i、値が 2i+1。枠 0 は使わない。空きの枠はキーが unbound）、バケットの表と `next` の鎖を 1 つにまとめた u32 の配列（確保の回数を減らすため。バケットの数は `header.len`）、`equal`・`equalp` の表だけが持つ u64 のハッシュ値の配列。件数、使った枠の最大の番号（hwm）、空き枠の一覧の先頭、枠の数を持つ。墓標（`ZILISP-SYSTEM::%TOMBSTONE`）はなくした。
- **GC の走査しない配列**：オブジェクトの種類 `raw_vector` を加えた（`header.len` は要素の数、`header.aux` は要素のバイト数 4 か 8）。GC は中を走査しない。Lisp からは見えない（印字は `#<object …>`）。
- **探す**：ハッシュ値でバケットを決め、鎖をたどる。`equal`・`equalp` の表は、比べる前に保存したハッシュ値を照合する（中身の比較を減らす）。表を作り直すときもハッシュ値を計算し直さない。
- **削除**：鎖から外し、空き枠の一覧に積む（後に削除した枠から再利用する）。
- **順序は SBCL 2.6.7 と同じ**：`maphash` と `loop` の `being the hash-keys`（`%hash-pairs`）は、枠の番号の順にたどる。削除がなければ入れた順になる。このため、枠の数の決め方と枠の再利用も SBCL に合わせた（`target-hash-table.lisp` の `%recompute-ht-vector-sizes`・`grow-hash-table`・`define-puthash/flat`）：
  - 初めの枠の数は `:size`（7 未満なら 7。省略すると 7）。
  - 小さい `eq`・`eql` の表（`:size` が `eq` は 32 以下、`eql` は 16 以下）は flat の表として始める。flat の表は、削除した枠を空き枠の一覧に積まず、挿入では空いている枠のうち番号のいちばん大きいものを使う（SBCL の flat の表は線形に探す形だが、Zilisp は flat の表でも鎖を使って探す）。`:size` を省いた flat の表の枠の数は 8。
  - 枠が埋まったら大きくする。新しい数は 1.5 倍（少なくとも 1 増やす）で、2 の冪のバケット数に対する割合が 0.9 を超えれば 0.85、0.55 未満なら 0.65 にする。flat の表は、バケット数が上限以下なら枠の数をバケット数にして flat のまま、超えたら flat でない表にする。
  - `:rehash-size` を指定した表は、その値で大きくする（整数ならその数だけ増やし、浮動小数ならその倍率。割合の調整は既定の 1.5 のときだけ）。型は SBCL と同じく `(or (integer 1 *) (float (1.0) *))` で、合わなければ type-error（Codex のレビュー P21.6 #3）。
  - `:rehash-threshold` は型（0〜1 の実数）を検査し、1/16 より小さければ 1/16 にする。使うのは、`:size` を省いた flat の表の初めの枠の数（大きさ / threshold から決めるバケット数）だけ。SBCL 2.6.7 の threshold を指定した表の続け方は、ソースから読める規則と合わず、順序が違うことがある（`tests/differential/impl-dependent.toml` の `hash-table-rehash-threshold-order`）。
  - 枠の数の上限は 2^28（キーと値の配列、バケットの表と鎖の長さがヘッダの u32 に収まる大きさ）。超えて大きくするときは storage-condition（Codex のレビュー P21.6 #1）。flat の印は、作り直しが成功してから外す（#2）。
  - `clrhash` は使った枠の番号を 0 に戻す。消すのは使った枠とバケットの表だけ（鎖は挿入のときに書き直す。#4）。
- **確認**：入れた順、大きくした後、削除の後の挿入（flat の表・flat でない表、`eq` の 32 件・`eql` の 16 件の境目、`:size` が 0〜100）、`clrhash` の後、`maphash` の中の `remhash`・`setf`、`loop` の順序、ハッシュ表どうしの `equalp` を、SBCL 2.6.7 と比べてすべて同じ（言語試験 `hash-tables.lisp`。GC stress の版も）。
- **速さ**（ReleaseFast、x86_64-windows、起動の時間を除いた 7 回の中央値。置き換える前の `42fd447` と比べた比）：fixnum のキー 20 万件の挿入と検索 1.02、文字列のキー 5 万件 0.92、1,000 件の表での削除と挿入 30 万回 0.56、8 件の表を 3 万個作る 1.02、10 万件の `maphash` 0.76、文字列のキーでの削除と挿入 0.81。
- 結果：教材のブロックの一致は 421（前と同じ。出力の違い 0）。起動時間は 8.74 ms。

---

## 3. ヒープと GC：ページ管理、ルート、FFI handle（D-8・D-9）

### 3.1 ヒープの構成

```text
ヒープ ＝ OS から大きな単位で取得した領域を、固定サイズのページに分割したもの
 ├─ cons ページ      ：16バイト単位で敷き詰める
 ├─ サイズ別ページ    ：16, 32, 48, 64, 96, 128, …バイトのオブジェクトを種類ごとのページに置く
 └─ 大きいオブジェクト ：専用のページ列（ページ境界にそろえる）
ページ表（ヒープの外）
 └─ ページごとに：格納サイズ、マークビット表（16バイトごとに1ビット）、使用中ビット表、空きの先頭
```

- ページの大きさは、計測して決める（初期案 32 KiB。大きさを変えた比較の計測は P39 で行う）。参考：SBCL の x86-64 版も 32768 バイトである（`src/compiler/x86-64/parms.lisp` 33行目 `gencgc-page-bytes`）。
- **確保**：サイズクラスごとに「現在のページ」を持ち、その中の空き（空きビット表から作った連続領域）を前から取り出す。空きが連続している間は、ポインタを進めるだけで確保できる。
- **GC の契機**：前回の GC 以降の確保バイト数が閾値を超えたとき。閾値は max(8 MiB, 前回の生存バイト数 × 2) の初期案とし、計測して調整する。**確保バイト数には、オブジェクトが別に確保して所有するバッファ（文字列のバッファ、ハッシュ表の配列、bignum の limb など）の増減も含める**（レビュー #18。小さなヘッダが大きなバッファを持つ場合に、GC が起こらずメモリが増え続けることを防ぐ）。
- GC が起こり得るのは、管理ヒープからの確保の時点だけである。

### 3.2 マークとスイープ

- マークは明示的なマークスタックで行う（深いリストでも Zig のスタックが溢れないようにする）。
- マークビットはページ表のビット表に記録する。cons にはヘッダがないので、オブジェクトの中には何も書き込まない。
- **遅延スイープ**：GC の時点ではマークだけを行い、ページの掃除（使用中ビットとマークビットの比較）は、そのサイズクラスで次に確保するときに行う。停止時間を短くするためである。
  - **次の GC を始める前に、掃除の終わっていないページをすべて掃除する**（レビュー #18）。マークビットを次の GC で使い回せるようにし、前回の GC の結果と混ざらないようにするためである。
- **内部資源を持つオブジェクト**（文字列バッファ、ハッシュ表の配列、bignum の limb、ファイルストリームの OS ハンドル、所有フラグ付きの foreign_pointer）は、ページとは別の「finalize 待ちの一覧」に登録する（レビュー #18）。マークが終わった時点でこの一覧だけを走査し、マークされていないものの資源をその場で解放する。ページの掃除を遅らせても、資源の解放は GC のたびに行われる。
- 利用者が定義する finalizer と弱参照は 1.0 では未対応とする。閉じ忘れたファイルストリームは、上記の手順で GC のたびに閉じ、デバッグオプションが有効なら警告を出す。

### 3.3 ルートの種類と走査方式

| ルート | 走査方式 |
|---|---|
| ヒープ内のオブジェクト同士の参照 | **正確**（ObjKind ごとのレイアウトに従う） |
| VM の値スタック・フレーム・多値レジスタ | 正確 |
| 動的束縛スタック・制御スタック・handler／restart スタック | 正確 |
| 全パッケージ、クラス表、総称関数のキャッシュ | 正確 |
| FFI handle 表、明示的に登録したルート（§3.5）、C に貸し出し中のオブジェクトの一覧（§3.6） | 正確 |
| 処理途中の非局所脱出の状態（§6.4 の `Transfer` の値と保存した多値） | 正確 |
| **ネイティブのスタック**（Zig のランタイムとネイティブコードのフレーム） | **保守的** |
| **CPU のレジスタ** | **保守的**（GC の開始時に callee-saved レジスタの値を読み出して走査する。§3.4 手順1） |

### 3.4 保守的走査の手順

1. GC を開始する関数（`gc.scanStack`）で、callee-saved レジスタの値をインラインアセンブリで読み出し、各値を下の 2 と同じ方法で判定する（Phase 07 で確定）。
   - x86_64：`rbx` `rbp` `rdi` `rsi` `r12`〜`r15`（`rdi`・`rsi` は Windows で callee-saved）。Windows ではさらに `xmm6`〜`xmm15` の下位 64 ビット。
   - aarch64：`x19`〜`x29` と `d8`〜`d15`。
   - レジスタを出力に指定する書き方（`"={rbx}"`）で読む。メモリを指す書き方（`0(%[r])`）は Zig の x86_64 用コード生成器で使えない。フレームポインタ（`rbp`・`x29`）は指定できないので `mov` 命令で読む（`docs/zig-std-usage.ja.md` §2）。
2. スレッドのスタックの先頭（起動時に記録した位置）から**現在のスタックポインタ**（インラインアセンブリで読む。ローカル変数の位置は使わない）までの各語について、次の判定を行う。
   1. タグを外したアドレスが、ヒープの範囲に入っているか。
   2. ページ表を引き、そのページのサイズクラスから、オブジェクトの先頭を計算する（`先頭 = ページ先頭 + ⌊(addr − ページ先頭) / サイズ⌋ × サイズ`。大きいオブジェクトはページ列の先頭）。**オブジェクトの途中を指すポインタも、そのオブジェクトへの参照とみなす。**
   3. 使用中ビットが立っていれば、マークする。
3. ヒープ内の走査は正確に行うので、保守的に扱うのはスタックとレジスタから直接指されているオブジェクトだけである。

**スタックの上端の決め方（Phase 07 で確定）**
- Windows：スレッドの情報（TEB）の `NtTib.StackBase` を使う（`std.os.windows.teb()`）。
- Windows 以外：`main` の先頭で記録した `@frameAddress()` を使う（`runtime.main_stack_top`）。`main` 自身は Lisp の値を持たず、Lisp の値はすべてそれより下（呼び出し先）のフレームにある。
- **Lisp の値を持つ関数自身の `@frameAddress()` は、上端に使ってはならない。** 最適化ありのビルドでは、その関数のローカル変数が `@frameAddress()` より高いアドレスに置かれることがあり、走査の範囲から外れて回収されてしまう（Phase 07 の試験で、ReleaseSafe・ReleaseFast で確認した）。試験では、上端を記録する外側の関数と、値を扱う内側の関数（`@call(.never_inline, …)`）を分ける。
- 試験で「回収されたこと」を確かめるために持つアドレスは、ビットを反転して持つ。そのままの値で持つと、保守的な走査がポインタと見なして回収されない。

- **この方式による利点**：ネイティブコードと Zig のランタイムは、ローカル変数に保持した Lisp 値を GC に登録する必要がない。シャドウスタックの費用（値の登録・解除）がかからない。ただし、次の「生存の契約」を守ることが条件である。
- **この方式の欠点**：整数がたまたまヒープのアドレスに見える場合に、不要なオブジェクトが残ることがある。GC 統計で監視する。
- **非移動型であることが前提**：保守的に参照されたオブジェクトは移動できない。移動型にする場合は、保守的に参照されたオブジェクトだけを固定する方式（mostly-copying）とする（基本設計 §5.2）。
- **コンパイラ最適化との関係**：ネイティブコードの最適化で、オブジェクトを指すポインタがスタックからもレジスタからも消える場合があり得る（ポインタを加工した値だけが残る場合など）。途中を指すポインタを参照とみなしても、オブジェクトの範囲を指すアドレスそのものが残らない場合は防げない。**ストレステストに通ることは、別の最適化結果でも安全であることの保証にはならない**（レビュー #1）。

**生存の契約（レビュー #1）**

保守的走査が正しく働くために、ネイティブコードとランタイムの Zig コードは次を守る。

1. **GC が起こり得る呼び出し**（管理ヒープからの確保、Lisp 関数の呼び出し、GC を起こし得るランタイム関数）**をまたいで後で使う Lisp 値は、`Value` の形（タグ付きの語）のまま保持する。** オブジェクトの中のフィールドを指すポインタや、配列の終端を指すポインタだけを残して、元の `Value` を捨てるコードを書かない（ランタイムの Zig コード）・生成しない（ネイティブバックエンド）。
2. ネイティブバックエンドは、GC が起こり得る呼び出しの後で使う `Value` を、その呼び出しの後まで生きている変数として生成する。最適化で消されないことを保証するため、値を最適化の境界の外に出す手段（Zig の `std.mem.doNotOptimizeAway` に相当するもの。手段は要検証）を、**GC が起こり得る呼び出しの後、その値（およびその値から取り出したポインタ）を最後に使った地点の直後**に置く（agy #3。呼び出しの前に置いても、呼び出しの後で使われなければ、呼び出しの時点で値を保持するスロットが再利用され得るため）。
2a. **派生したポインタの規則**（agy #3）：`Value` から取り出したポインタ（オブジェクトのフィールドへのポインタ、**別に確保したバッファ**へのポインタ・スライス：文字列の中身、ハッシュ表の配列、bignum の limb など）は、**GC が起こり得る呼び出しをまたいで保持しない**。呼び出しの後で必要なら、`Value` から取り出し直す。
   - 理由：別に確保したバッファはヒープのページの外にあるため、バッファへのポインタがスタックに残っていても、持ち主のオブジェクトはマークされない。持ち主が回収されると、§3.2 の手順でバッファも解放され、解放済みの領域を使うことになる。
   - Zig のコンパイラから見ると、派生したポインタを使うことは元の `Value` を使うことにはならない。このため、契約 1・2 だけでは足りず、この規則が必要になる。
3. ページの範囲の判定では、オブジェクトの末尾の直後を指すアドレスを、そのオブジェクトへの参照とはみなさない（次のオブジェクトと区別できないため）。契約 1 により、そのようなアドレスだけが残るコードは作らない。
4. 契約は、規則の文書化だけでなく、次の検証で確かめる：ReleaseFast・インライン展開・リンク時最適化（LTO）を有効にした生成コードでの `--gc-stress`、Windows・Linux・macOS の各 ABI での実行、ランタイムの Zig コードのレビュー観点への追加。
5. 契約を満たせないことが計測や検証で分かった場合は、該当する場所だけで明示的なルート（§3.5）を使う。
6. Phase 07 と Phase 12 で、この方式（保守的走査と契約）と、シャドウスタックによる正確なルート管理の速さを計測して比べる（agy #3）。
- **SBCL との比較**：SBCL の x86-64 版も、スタックとレジスタを保守的に走査し、参照先を固定する（確認済み：`src/runtime/gencgc.c` 1335〜1341行目。SBCL 2.6.7 で機能 `:c-stack-is-control-stack` が有効であり、`genesis.lisp` 3163行目の条件により `GENCGC_IS_PRECISE` が 0 になる）。ただし SBCL は、オブジェクトの途中を指すポインタを、コードオブジェクト以外では参照とみなさない。SBCL は自前のコンパイラで生成するコードの形を制御できるが、Zilisp は Zig と LLVM が生成するコードを制御できないため、途中を指すポインタも参照とみなす。

### 3.5 明示的なルート登録 API

ネイティブのスタック以外の場所（Zig のヒープ上の構造体、static 変数など）に Lisp 値を保持する場合だけ、明示的に登録する。

```zig
// Zig のヒープ上の構造体に Lisp 値を保持する場合
const h = try rt.roots.register(value);  // GC 中も h.get() は有効
defer rt.roots.unregister(h);
```

**規則（コードレビューの観点）**
1. ローカル変数・引数に保持した Lisp 値は、§3.4 の「生存の契約」を守る限り登録不要（保守的走査の対象）。
2. Zig のヒープ上の構造体・static 変数・C ライブラリに渡す構造体に保持する Lisp 値は、必ず登録する。
3. C 側へは、Lisp オブジェクトのアドレスではなく、FFI handle を渡す（§3.6）。

### 3.6 FFI handle

- C 側へは **handle** を渡す。handle 表はルートの一部であり、`(zilisp-ffi:free-handle h)` を呼ぶまで対象を保持する。
  - handle は「表の番号」と「世代番号」の組とし、解放済みの handle や、番号が再利用された後の古い handle を使った場合はエラーにする（レビュー #12）。
- **C へのバッファの貸し出し**（レビュー #12）
  - 貸し出しは `(zilisp-ffi:with-borrowed-buffer (ptr obj) …)` の形で、範囲を限って行う。貸し出し中のオブジェクトは「貸し出し中の一覧」（ルートの一部。§3.3）に登録し、参照カウントで管理する。
  - **貸し出し中は、バッファを作り直す操作を禁止する。** 例：幅1の文字列に #xFF を超える文字を `setf` する（§2.5）、adjustable な配列の大きさを変える。禁止された操作を行うと、エラーを通知する。
  - C 側でバッファを長く保持する必要がある場合は、管理ヒープの外に複製したバッファを渡す（複製は呼び出し側で明示的に解放する）。
- FFI の詳細設計（コールバックでの再入、別スレッドからの呼び出し：§6.1 の注意を参照）は Phase 31 で `docs/ffi.md` として別に作成する。

### 3.7 診断

- `--gc-stress`：確保のたびに GC を実行する。
- poison（デバッグビルド）：掃除した領域を 0xAA で埋める。
- 統計：GC 回数、停止時間（ns）、確保バイト数、生存バイト数、保守的走査で見つかった参照の数。`(zilisp:gc-statistics)` と `--gc-stats` で表示する。

---

## 4. ソース位置情報

### 4.1 データ構造（確定）

```zig
pub const SourceLoc = extern struct {
    file: u32,   // Runtime.source_files の添字。0 は「不明」
    line: u32,   // 1 起点
    col: u32,    // 1 起点（文字単位）
};
```

- Reader は、読み取った cons の同一性（アドレス）をキーにした `SourceMap` に位置を記録する。アトムには位置を付けない。
- `SourceMap` は、**Reader が `read` 1回で読み取った最上位のフォーム**の処理（§16.1 のトップレベル処理による分割を含む）が終わった時点で破棄する（agy #6）。コンパイル結果には、位置の表だけを残す（VM：pc → SourceLoc、ネイティブ：§7A.5）。
- マクロ展開で新しく作られた cons には位置がない。コンパイラは「位置を持つ、最も近い外側のフォーム」の位置を継承する。
- REPL からの入力には `file = <repl>` を割り当て、入力の通し番号を行番号の代わりに使う。

### 4.2 利用箇所

- コンパイル時の警告・エラー：`file:line:col: warning: ...` の形式。
- 実行時の backtrace：VM のフレームは pc から、ネイティブのフレームは関数名と位置の表から引く。
- `.zfasl` には位置の表とファイル名表を保存する（§14）。

---

## 5. コンパイラ・パイプラインと Core IR

### 5.1 パイプライン（D-1・D-7・D-10）

```text
フォーム（Value）
  │ macroexpand（ローカル/グローバルのマクロ、symbol-macro）
  ▼
Resolver：名前解決、special 宣言、captured / assigned の計算
  ▼
Core IR（ArenaAllocator 上。トップレベルフォーム1つごとに破棄）
  │ 型推論、宣言（type・optimize・inline）の反映、定数畳み込み
  ▼
  ├─▶ Native backend（主経路）：IR → Zig ソース → LLVM（zilisp build と標準ライブラリのビルドに使う。入力は**メモリ上の Core IR**。Phase 35 以降は `.zfasl` に保存した Core IR も入力にできる：agy #8）
  ├─▶ Background native（Phase 39）：IR → Zig ソース → 別プロセスの Zig で共有ライブラリ → 読み込んで入口を置き換え（REPL・eval・load。§7A.6）
  └─▶ Bytecode backend：IR → バイトコード（REPL・eval・load ですぐに実行する経路。Zig がない環境ではこの経路だけを使う）
```

- **評価器（AST/IR インタプリタ）は作らない**（D-1）。`eval` も必ずコンパイルしてから実行する。
- 3つのバックエンドは同じ Core IR を入力とし、§6 の共通基盤（呼び出し規約・制御スタック・動的束縛）の上で動く。互いの関数を呼び合える。
- 意味論の一致は、全言語試験を VM とネイティブの両方で実行して確認する。

### 5.2 Core IR ノード（初版）

```zig
pub const Node = union(enum) {
    constant: Value,
    lex_ref: *Var,                 lex_set: struct { v: *Var, value: *Node },
    special_ref: Value,            special_set: struct { sym: Value, value: *Node },
    global_fn: Value,              local_fn: *FnBinding,
    call: struct { callee: *Node, args: []*Node },
    call_global: struct { sym: Value, args: []*Node, same_file: ?*LambdaInfo },
    prim: struct { op: PrimOp, args: []*Node },
    if_: struct { cond: *Node, then: *Node, else_: *Node },
    progn: []*Node,
    let_: struct { bindings: []Binding, body: *Node },
    lambda: *LambdaInfo,
    labels: struct { fns: []*FnBinding, body: *Node },
    block: struct { b: *BlockInfo, body: *Node },
    return_from: struct { b: *BlockInfo, value: *Node },
    tagbody: struct { t: *TagbodyInfo, segments: []Segment },
    go: struct { t: *TagbodyInfo, index: u32 },
    catch_: struct { tag: *Node, body: *Node },
    throw: struct { tag: *Node, value: *Node },
    unwind_protect: struct { protected: *Node, cleanup: *Node },
    mv_call: struct { callee: *Node, args: []*Node },
    mv_prog1: struct { first: *Node, rest: *Node },
    progv: struct { syms: *Node, vals: *Node, body: *Node },
    load_time_value: struct { form: Value, read_only: bool },
    the: struct { type: TypeId, value: *Node },
};
// すべてのノードは、推論した型 `ty: TypeId` と SourceLoc を持つ
```

- `defun` は、Zig で書いたブートストラップ用のマクロ（§11.1 の 6）として Resolver が直接展開する（Phase 10）。`(defun 名前 ラムダリスト 本体…)` は `(zl-sys::%defun '名前 (lambda ラムダリスト 本体…))` になり、lambda には関数の名前を付ける（印字は `#<FUNCTION 名前>`。SBCL 2.6.7 と同じ）。本体を `(block 名前 …)` で囲む処理は、`block` を実装する Phase 18 で加える。COMMON-LISP パッケージのシンボルの関数の定義は `package-error` にする（CLHS 11.1.2.1.2。SBCL ではパッケージのロックのエラー）。マクロ展開器（Phase 15）ができた後も、`defun` はこの形に展開する。
- `flet`・`labels`（Phase 11）：Resolver の範囲に関数の名前空間の束縛（名前と、関数の値を入れる名前の見えない局所変数）を持つ。`flet` は `(let ((f (lambda …)) …) 本体)`、`labels` は `(let ((f nil) …) (setq f (lambda …)) … 本体)` と同じ IR にする。`labels` で互いに（または自分を）参照する関数の変数は、捕捉され代入されるので value_cell に入る。局所関数は大域の関数・マクロより優先する（CLHS 3.1.2.1.2.3）。COMMON-LISP パッケージのシンボルと特殊演算子の名前は局所関数にできない（SBCL 2.6.7 と同じく `program-error`）。関数の本体を `(block 名前 …)` で囲む処理は Phase 18 で加える。
- **マクロ展開**（Phase 15）：Resolver は、フォームの先頭がマクロのシンボルなら、マクロ関数を `(フォーム 環境)` で呼んで展開し、その結果を解決する（局所関数はマクロより優先する。特殊演算子はマクロより先に判定する）。トップレベルのフォームの展開結果もトップレベル（CLHS 3.2.3.1）。展開の結果と、Resolver が作るフォームは Pins に積む（§5.4）。Phase 15 では、環境の引数は常に NIL（大域の環境）。
- **defmacro**：`(zl-sys::%defmacro '名前 (lambda (#:whole #:env) (let ((#:args (cdr #:whole))) (let* (分解の束縛…) 本体…))))` にする。トップレベルの `defmacro` は、コンパイルの時点でも定義する（同じファイルの後のフォーム・ネイティブバックエンドの生成でも展開できるように）。マクロ関数の印字は `#<FUNCTION (:MACRO 名前) {…}>`。
- **分解束縛**（`defmacro`・`destructuring-bind` のラムダリスト。CLHS 3.4.4・3.4.5）：必須・`&optional`（既定値・供給の変数）・`&rest`・`&body`・ドット対の末尾・`&key`（`((:k v) …)`、`&allow-other-keys`、`:allow-other-keys t`）・`&aux`・`&whole`・`&environment`・入れ子のラムダリストを、`let*` の束縛の並びにする。引数の数の誤り・奇数個のキーワード引数・知らないキーワードは `program-error`。
- **backquote**：`zl-sys:quasiquote` を、`list`・`list*`・`append`・`(apply #'vector …)` の呼び出しにする（CLHS 2.4.6）。unquote を含まない部分は `quote` にする（共有してよい：CLHS 2.4.6）。`,.` は `,@` と同じく、壊さずにつなぐ。入れ子の backquote は深さを数えて扱う。
- **Phase 15 で実装しなかったもの**（§5.2 の当初の予定から外した。Phase 30 で行う：tque #341）：`macrolet`、`symbol-macrolet`、`define-symbol-macro`、環境のオブジェクト（`&environment` の値。今は NIL）、`compiler-macro`。教材のブロックで使っているものは0件（Phase 15 の時点）。
- **setf**（Phase 16）：`src/lisp/boot.lisp` に Lisp で書く。場所の展開は CLHS 5.1.1.2 の5つの要素（一時変数・値の式・格納変数・格納フォーム・読み出しフォーム）で表し、多値ができる Phase 17 まではリストで返す（`zl-sys::%setf-expansion`。`get-setf-expansion`・`define-setf-expander` は Phase 17）。展開の順序は、場所の展開関数（`defsetf` で定義し、シンボルの属性 `zl-sys::setf-expander` に置く）→ マクロの展開 → setf 関数（`(funcall #'(setf 名前) 値 引数…)`）。`incf`・`decf`・`push`・`pop` も同じ展開の上に作る（場所の部分のフォームは1回だけ、左から順に評価する：CLHS 5.1.2）。`(defun (setf 名前) …)` はシンボルの `setf_function` の欄に置き、`#'(setf 名前)` は VM の命令 `LOAD_SETF_FUNCTION` で読む。
- **eval でのトップレベルのフォームの処理**（Phase 16）：VM の `eval` は、トップレベルの `progn`・マクロの展開結果・`eval-when`（`:execute`）の中のフォームを、1つずつコンパイルして実行する（SBCL 2.6.7 の eval と同じ。`(progn (defsetf f g) (setf (f x) 1))` の2つ目は、1つ目を実行した後で展開される）。
- **eval-when**（Phase 16）：eval の意味（VM）では `:execute` だけを見る。compile-file の意味（ネイティブバックエンド）では、トップレベルなら `:compile-toplevel` で本体をその場で評価し、`:load-toplevel` で本体をトップレベルの `progn` として扱う（CLHS 3.2.3.1）。`defsetf` は `(eval-when (:compile-toplevel :load-toplevel :execute) …)` に展開する。
- `let*` は、変数1つの `let_` を入れ子にして表す（Phase 09）。各初期値は、それより前の変数が見える範囲で解決する。`let` と違い、同じ名前の変数を2回束縛してよい（後の束縛が前を隠す。SBCL 2.6.7 で確認）。`let`・`let*` の変数の局所変数の番号は、本体を抜けた後で再利用する（closure は作った時点の値か value_cell を捕捉するので、番号の再利用の影響を受けない）。
- `Var` は `captured` と `assigned` を持つ。両方が真の変数だけを `value_cell` に入れる（assignment conversion）。
- `Var` と `Node` は推論した型（`TypeId`：fixnum、double-float、cons、simple-vector、`t` など）を持つ。ネイティブバックエンドは型に応じてボックス化と型検査を省く（§7A.3）。
- `BlockInfo` / `TagbodyInfo` は `nonlocal`（内側のクロージャから脱出される）を持つ。偽の場合はジャンプにする。
- CL の 25 個の特殊演算子は Resolver が直接解釈する。
- `prim`（インライン化）の対象は CL パッケージの関数に限り、`flet` / `labels` で局所的に隠されていない場合だけ行う（CL パッケージの関数の再定義は未定義の動作：CLHS 11.1.2.1.2）。
- **CL パッケージの関数の直接呼び出し**（agy #11）：インライン化しない CL パッケージの関数（`format`、`mapcar`、`sort` など）も、同じ理由で、関数セルを経由せずにネイティブの入口を直接呼ぶ（`flet` / `labels` で局所的に隠されている場合を除く）。
- **`&environment` と `define-symbol-macro`**（agy #15）：`defmacro` の `&whole` は Phase 15 で実装した。`&environment` の値（§2.4 の `environment` オブジェクト。今は NIL）、`define-symbol-macro`（シンボルのフラグ `global_symbol_macro`）と `symbol-macrolet` は、当初は Phase 15 の予定だったが、Phase 30 で行う（上の「Phase 15 で実装しなかったもの」。tque #341）。
- `call_global.same_file`：同じファイル内で定義された関数の呼び出し。`notinline` が宣言されていなければ、ネイティブバックエンドは直接呼び出しにしてよい（CLHS 3.2.2.3 が許す範囲）。

### 5.3 宣言と安全性

| 宣言 | 扱い |
|---|---|
| `(declare (type …))` / `the` | `safety` ≥ 1 では検査してから型を信用する。`safety` 0 では検査せずに信用する |
| `(optimize (speed n) (safety n) (debug n))` | 既定は `speed 1 safety 1 debug 1`。`safety 0` では引数の個数・型の検査を省く |
| `inline` / `notinline` | 尊重する |
| `dynamic-extent` | 1.0 では、ネイティブバックエンドで closure と `&rest` リストのスタック確保に使う（実装は後期） |

**`safety` ≥ 1 では、型の誤りは必ず `type-error` などの condition になる**（基本設計 §3.1：黙って別の値を返さない）。

### 5.4 コンパイル時の GC 安全性

マクロ展開の結果やトップレベルフォームは、コンパイラの作業用構造体（Zig のヒープ上）に保持するため、§3.5 の API で登録する。IR が保持する定数は、登録したフォームから到達できる状態を保つ。

### 5.5 ValueMode

コンパイラは式ごとに、結果の受け取り方 `ValueMode = single | multiple | discard` を指定してコードを生成する。

**Phase 17 の実装**
- 関数の本体の最後の式は multiple の位置。multiple の位置では、関数の呼び出しは呼んだ関数が書いた個数をそのまま使い、`values` は個数を書き、`if`・`progn`・`let`・`multiple-value-bind`・`multiple-value-prog1` は中の式に multiple を伝える。それ以外の単値の式は、個数を 1 にする（VM の命令 `SINGLE`。ネイティブでは `th.mv_count = 1`）。プリミティブの入口は、本体を呼ぶ前に個数を 1 にする（多値を返すプリミティブは本体で書き直す。Zig の関数から関数を呼ぶプリミティブは、戻る前に個数を 1 に戻す）。
- VM の命令：`VALUES n`、`SINGLE`、`MV_LIST`（全部の値のリスト）、`MV_PUSH_N n`（値を n 個積む）、`MV_RESTORE`（リストを多値に戻す）。`multiple-value-prog1` は最初のフォームの値をリストに退避して戻す。`multiple-value-call` は `(apply f (append (multiple-value-list …) …))` にする（確保を伴う。速さが問題になれば専用の命令にする）。
- REPL は、すべての値を1行ずつ印字する（`(values)` なら何も印字しない。SBCL 2.6.7 と同じ）。
- **&optional・&rest・&key・&aux**：必須の引数より後ろの引数を、VM（ネイティブでは生成したコード）が名前のない引数のリストにまとめ、そのリストを分解束縛（§5.2、Phase 15 と同じ仕組み）で変数に束縛する。省略可能な引数を省いた呼び出しではリストは NIL なので確保しない。キーワード引数を渡す呼び出しは、呼び出しのたびにリストを作る（速さの改善は後の Phase。§7A.3 の高速入口と一緒に検討する）。

---

## 6. 実行時の共通基盤：呼び出し規約、多値、非局所脱出、動的束縛

VM とネイティブコードは、この章の構造を共有する。

### 6.1 スレッドの状態

```zig
pub const Thread = struct {
    mv: [MV_LIMIT]Value,         // 多値レジスタ（MV_LIMIT = 1024）。mv[0] は使わない（主値は戻り値）
    mv_count: u32,               // 直前に返った値の個数（§6.2）
    fault: Fault,                // 戻り値が Value.unwind のときの理由（§6.6）
    bindings: []Binding,         // 動的束縛（shallow binding）
    control: []ControlEntry,     // block / tagbody / catch / unwind-protect
    handlers: []HandlerCluster,
    restarts: []RestartEntry,
    unwinds: []Transfer,         // 処理途中の非局所脱出のスタック（§6.4。入れ子の脱出に対応するためスタックにする）
    stack_base: usize,           // 保守的走査の開始位置
    vm: Vm,                      // VM の値スタック・フレーム（§7）
};
```

1.0 は単一スレッドとする。`Thread` を構造体にしておくのは、将来のマルチスレッド化に備えるためである。

**単一スレッドであることによる制約（レビュー #19）**
- C ライブラリからのコールバックで、**同じスレッドから** Lisp に再入する場合は、再入の入口で多値レジスタの内容を退避し、戻るときに復元する。コールバックから C のフレームを越えて Lisp の非局所脱出を行うことは禁止し、境界で `control-error` に変換する（C のフレームの後始末を飛ばさないため）。
- **別のスレッドから**のコールバック（外部ライブラリが作ったスレッドなど）は、1.0 では拒否する（エラーを返す、または処理系を停止する）。詳細は `docs/ffi.md`（Phase 31）で定める。

### 6.2 呼び出し規約（確定）

すべての関数オブジェクト（`closure`、`native_function`、`generic_function`）は、先頭に**入口アドレス**を持つ。

```zig
// 汎用の入口（すべての関数オブジェクトで同じ型）
pub const Entry = *const fn (th: *Thread, self: Value, args: [*]const Value, nargs: u32) callconv(.c) Value;
// 高速入口（引数の個数が固定。同じコンパイル単位の中で使う。例：2引数）
//   fn (th: *Thread, a: Value, b: Value) Value
```

**戻り値の規約（案 A。2026-11-01 確定。Phase 12 で計測して確認する）**

- **戻り値は主値の `Value`（`enum(u64)`）だけ**とし、レジスタで返す。値が0個のときの主値は NIL とする。
- **値の個数は `th.mv_count` に書く。** 2番目以降の値は `th.mv[1..]` に書く。
  - 個数を正しく保つため、**関数は戻るたびに `th.mv_count` を書く**（単値を返す場合は 1 を書く）。ただし、戻り値が末尾位置の関数呼び出しの戻り値そのものである場合は、呼び出し先が書いた個数をそのまま使えるので書かない。
  - 呼び出し側は、多値が必要な場所（`multiple-value-bind` など。§5.5 の `multiple` モード）でだけ `th.mv_count` と `th.mv` を読む。単値の場所では戻り値だけを使う。
- **非局所脱出とエラーは、特別な即値 `Value.unwind`（§2.2）を返して表す。** 理由は `th.fault`（§6.6）に置く。呼び出し側は、呼び出しのたびに戻り値が `Value.unwind` かを比べ（レジスタと定数の比較1回）、そうであれば自分も `Value.unwind` を返す（§6.4）。
- **この規約にした理由**：Zig 0.17.0 では、`Error!Ret`、エラーを含む型、16バイトの構造体は、x86_64-windows・x86_64-linux・aarch64-macos のどれでもメモリ経由で返される。`callconv(.c)` の16バイトの構造体は Linux・macOS ではレジスタで返るが、開発の一次ターゲットの Windows ではメモリ経由になる。`enum(u64)` の値だけが、3つのターゲットすべてでレジスタで返る（`docs/zig-std-usage.ja.md` §3）。
- 参考：Clasp は主値と個数をレジスタで返している（`include/clasp/core/lispCallingConvention.h` 36〜46行目）。Zilisp の規約は、個数を `Thread` の欄に書く分だけ、戻るたびにメモリへの書き込みが1回増える。この費用は Phase 12 で計測する。

**呼び出し規約の種類**

- **汎用の入口は `callconv(.c)` とする。** VM の closure、ネイティブコード、別にコンパイルした共有ライブラリ（§7A.6）の関数が、同じ型の入口を持てるようにするためである。C の呼び出し規約では、`u64` の戻り値は3つのターゲットすべてでレジスタ（`rax` / `x0`）で返る。
- **高速入口は Zig の既定の呼び出し規約**とし、同じコンパイル単位の中（同じファイル内の直接呼び出し、インライン展開）でだけ使う。
- 汎用の入口を `callconv(.c)` にする費用（Windows x64 の呼び出しで確保する32バイトの領域など）は、Phase 12 で既定の呼び出し規約と比べて計測する。

**別にコンパイルした共有ライブラリとの境界**（レビュー #11）
1. 境界を通る関数は、上記の `callconv(.c)` の汎用の入口と、初期化の入口だけにする。引数と戻り値は、`Value`（`u64`）・ポインタ・整数だけである。
2. `Value`・`Thread` の配置、ランタイムの関数表の並び、定数表の形式に**ABI の版番号**を付ける。共有ライブラリの初期化の入口は、最初に版番号を照合し、一致しなければ読み込みを拒否する（VM のまま実行する）。
3. 共有ライブラリの中の高速入口は、その共有ライブラリの中でだけ使う。
- **VM の closure** の入口は、VM の実行ループを開始するトランポリンである。トランポリンは、呼ばれるたびに closure の code にネイティブの入口があるかを調べ、あればそちらを呼ぶ（§7A.6、agy #1）。VM の中から VM の closure を呼ぶ場合は、トランポリンを経由せず、同じ実行ループの中でフレームを積む（このときも code のネイティブの入口を調べる）。
- **受け取った引数の扱い**（agy #9）：汎用の入口は、関数の最初で `args[0..nargs]` をローカル変数（必要なら `&rest` のリスト）に写し、その後は `args` を参照しない。`args` が指す領域（呼び出し元の領域や、末尾呼び出し用の引数領域：§7A.3）が後の呼び出しで上書きされても安全にするためである。
- **ネイティブコード**は、関数ごとに Zig の関数として生成し、その入口アドレスを関数オブジェクトに置く。引数の個数が固定の関数には、引数を配列にせずレジスタで受け取る**高速入口**も生成する（同じファイル内の直接呼び出しと、インラインキャッシュから使う）。
- グローバル関数の呼び出しは、シンボルの関数セルを毎回参照する（再定義を即座に反映する）。ネイティブコードでは、関数セルの参照と入口の呼び出しを1つの間接呼び出しにまとめる。
- **シンボルの高速入口**（agy #11。SBCL の FDEFN に相当する考え方）：シンボルに、引数の個数が固定の呼び出し用の**高速入口**の欄を持たせる（§8.1）。関数を定義・再定義するたびに、この欄を更新する。関数が未定義の場合、VM の関数の場合、引数の個数が合わない場合は、欄に**汎用の処理へ戻るトランポリン**を入れておく。これにより、呼び出し側はキャッシュの判定をせずに、1回の間接呼び出しで高速入口を呼べる。§7A.3 のインラインキャッシュより速いかを Phase 12 で計測し、速い方を採用する。
- 引数の解析（必須・`&optional`・`&rest`・`&key`）の規則は CLHS 3.4.1 に従う。個数の誤り、奇数個のキーワード引数、未知のキーワードは `program-error` を通知する。同じキーワードが重複した場合は、最も左を使う。

### 6.3 多値

- 主値は戻り値、個数は `th.mv_count`、2番目以降の値は `th.mv[1..]` に置く（§6.2）。
- `th.mv` は、次に多値を返す関数の呼び出しで上書きされる。**値を返した後に別の関数を呼ぶ処理**（`multiple-value-prog1`、`unwind-protect` の cleanup、`handler` の呼び出しなど）は、全値をスタックまたは `Transfer`（§6.4）に退避し、終わった後で復元する。
- `multiple-value-prog1`：最初のフォームの全値を退避し、残りのフォームを評価した後で復元する。
- `multiple-value-call`：各引数フォームの全値を順に連結して、関数に渡す。

### 6.4 非局所脱出

**制御スタックのエントリ**

```zig
pub const ControlEntry = struct {
    kind: enum { block, tagbody, catch_tag, unwind_protect, native_frame },
    token: Value,          // block/tagbody の識別子、または catch タグ
    binding_depth: u32,
    handler_depth: u32,
    restart_depth: u32,
    resume: Resume,        // VM：フレーム番号・sp・ip。ネイティブ：使わない（Value.unwind を受け取ったコードが脱出先かを確かめる。Phase 18 の実装）
};
```

**処理途中の脱出の状態**（レビュー #3）

```zig
pub const Transfer = struct {
    target: u32,              // 脱出先の制御スタックのエントリ番号
    values: []Value,          // 脱出で運ぶ全値（主値を含む。多値レジスタからコピーしたもの）
    tag_index: u32,           // go の場合のタグの番号
};
```

- `Transfer` は `th.unwinds` に**スタックとして**積む。値は GC のルートとして正確に走査する（§3.3）。

**方式（VM とネイティブで共通）**

- 非局所脱出（`return-from`・`go`・`throw` で、脱出先が別のフレームにある場合）は、脱出先のエントリを決め、運ぶ全値をコピーした `Transfer` を `th.unwinds` に積み、`th.fault = .unwind` として、**特別な値 `Value.unwind` を返して**関数を順に抜ける（§6.2）。
- ネイティブコードの `block`・`tagbody`・`catch` は、エントリを積んだうえで、本体の呼び出しが `Value.unwind` を返したときに「`th.fault` が `.unwind` で、`th.unwinds` の先頭の脱出先が自分か」を調べる。自分であれば `Transfer` を取り除いて値を受け取り、処理を続ける。自分でなければ `Value.unwind` をそのまま返す。

**`unwind-protect`**（レビュー #2・#3）

cleanup は、保護されたフォームから**どのように抜けた場合でも**実行する。

| 抜け方 | 手順 |
|---|---|
| 正常に終わった | 保護されたフォームの**全値**を退避する → cleanup を実行する → 全値を復元して返す |
| 別のフレームへの非局所脱出（`Value.unwind` が返った） | cleanup を実行する（`th.unwinds` の先頭の `Transfer` と `th.fault` は退避して残す）→ `Value.unwind` を返し直して脱出を続ける |
| 同じ関数の中のジャンプ（`return-from`・`go`）で、cleanup の範囲を横切る | ジャンプの前に、横切るすべての cleanup を内側から順に実行し、横切る動的束縛を解除する（下記） |

- **cleanup を実行する時点の動的環境**（agy #2。CLHS 5.2「Transfer of Control to an Exit Point」）：cleanup は、その `unwind-protect` に入った時点の動的環境で実行する。このため、どの抜け方の場合も、cleanup を実行する**直前に**、保護されたフォームの内側で作られた動的束縛・handler・restart・catch タグを、その `unwind_protect` エントリに記録した深さ（`binding_depth`・`handler_depth`・`restart_depth`）まで戻す。`unwind-protect` より外側（脱出先との間）の束縛などは、cleanup の実行中も有効のまま残す。脱出が複数の `unwind-protect` を通る場合は、内側から順に「深さを戻す → cleanup を実行する」を繰り返す。
- **cleanup の中で起きた脱出**
  - cleanup の中で起きて、**cleanup の中で受け止められる**脱出（cleanup の中の `catch`・`block` が脱出先のもの）は、新しい `Transfer` として積まれ、受け止めた時点で取り除かれる。外側の進行中の脱出（下の `Transfer`）は**取り消されない**。cleanup が終われば、外側の脱出が続く。
  - cleanup の中で起きて、**cleanup の外に出る**脱出だけが、進行中の外側の脱出を置き換える。この場合、外側の `Transfer` を取り除いてから、新しい `Transfer` で脱出を続ける。
  - この区別は、脱出先のエントリ番号と、cleanup を実行している `unwind_protect` エントリの番号を比べて行う。
- cleanup の中では関数の呼び出しで `th.mv` が上書きされるため、運ぶ値は必ず `Transfer` または退避領域から取り出す（§6.3）。
- 根拠：CLHS の `unwind-protect`、`throw`、`multiple-value-prog1` の各定義と、5.2「Transfer of Control to an Exit Point」。

**同じ関数の中のジャンプ**（`nonlocal = false`）

- ネイティブでは通常の分岐、VM ではジャンプにする。エラーを返す費用はかからない。
- ただし、ジャンプが `unwind-protect`・動的束縛・`handler-bind`・`restart-bind` の範囲を**横切る**場合は、コンパイラがその場所に、横切る cleanup の呼び出し、束縛の解除（`UNBIND_TO`）、handler・restart のスタックの深さの復元を生成する。これらの範囲を横切らないジャンプだけが、単純な分岐になる。
- VM の実行ループは、`native_frame` 境界を越える脱出を受け取った場合に `Value.unwind` を返して抜ける。この仕組みで、VM → ネイティブ → VM のように入れ子になった呼び出しの間でも、脱出と cleanup が正しく行われる。
- 脱出先が見つからない場合（block の動的エクステントが終わっている場合など）は `control-error` を通知する。

**Phase 18 の実装**
- `Thread` の制御スタック `control`（`ControlEntry`：種類、token、動的束縛の深さ、VM の再開の位置。既定 65536 要素）と、処理途中の脱出のスタック `unwinds`（`Transfer`：脱出先のエントリの番号、主値・個数・2つ目以降の値のリスト、cleanup で止まっている深さ `cleanup_at`、エラーの理由の退避）。どちらも GC のルート。
- block の token は、block に入るたびに作る fixnum（`th.next_token`）。脱出は制御スタックを上から探し、見つからなければ `control-error`（動的エクステントの終わった block、対応する catch のない throw）。値の個数が 1 なら確保しない。
- **Resolver**：`return-from` は、同じ lambda の中で unwind-protect（保護したフォーム・cleanup）の範囲を横切らなければ**ジャンプ**、そうでなければ**実行時の脱出**（block に `needs_entry` を付け、token の局所変数を捕捉させる）。エントリの要らない block は何も生成しない。token の局所変数の番号は、lambda の本体を解決した後で、使っている番号の後ろに割り当てる。`defun`（`(setf 名前)` なら 名前）・`flet`・`labels`・`defmacro` の本体は、名前の block で囲む。`return` は標準ライブラリのマクロ。
- **ジャンプで抜ける return-from**：横切る動的束縛を、いちばん外側の束縛の前の深さまで戻し（`UNBIND_TO`）、横切るエントリ（catch、エントリのある block）を取り除き（`CONTROL_POP n`）、途中の値を捨てて（`SLIDE n`）、block の出口へジャンプする。
- **VM**：命令 `BLOCK_ENTER i rel`・`CATCH_ENTER rel`・`UWP_ENTER rel`（エントリを積む。rel は脱出したときに再開する位置）、`CONTROL_POP n`、`UWP_SAVE`・`UWP_END`、`RETURN_FROM_NL`・`THROW`（この後には進まない）、`SLIDE n`。`vm.run` は、実行ループが `Value.unwind` で抜けてきたら、自分が積んだエントリを上から調べ、unwind-protect なら cleanup の先頭から、脱出先の block・catch ならその出口から、フレーム・値スタック・動的束縛をエントリの記録に戻して実行を続ける（`resumeAfterUnwind`）。自分のエントリがなくなれば `Value.unwind` を返す（ネイティブのコードや外側の `vm.run` が続きを処理する）。検証器は、エントリを積む命令の rel を「脱出したときの深さ（block・catch は値1つ、unwind-protect は値と印の2つを積んだ深さ）」で調べる。さらに、命令の位置ごとに、その関数が積んだエントリの並びと実行中の cleanup を求め、どの経路でも同じ位置では同じ並びであること、`CONTROL_POP` は block・catch のエントリだけを、`UWP_SAVE` は unwind-protect のエントリを取り除くこと、`UWP_END` は cleanup の中でだけ使うこと、`RETURN` ではエントリも cleanup も残っていないことを確かめる（Codex・agy のレビュー P18）。実行時にも、`CONTROL_POP` の数と、`UWP_END` で続ける脱出がこの cleanup のものであること（記録の `cleanup_at` が今の深さと同じ）を確かめ、違えば内部の誤りにする。
- **ネイティブ**：エントリのある block・catch・unwind-protect の本体は Zig のラベル付きブロックにし、本体の中で `Value.unwind` を受け取ったら（関数から返る代わりに）そのブロックを抜ける。block・catch の後で `N.land` が自分が脱出先かを確かめる。ジャンプで抜ける return-from は `if (true) break :bN 値;`（後ろのコードもそのまま生成できる形）。
- **暗黙の block の範囲**（Codex・agy のレビュー P18）：暗黙の block は本体（宣言の後ろ）だけを囲み、ラムダリストの初期値の式（`&optional`・`&key`・`&aux`）は囲まない（CLHS flet「The body forms (but not the lambda list)」）。`defmacro` は、コンパイル時の定義（トップレベル）と実行時の定義の両方で、展開関数の本体に同じ block を付ける。
- **処理途中の脱出のスタックの大きさ**（Codex のレビュー P18 #1）：エラーで cleanup に入るたびに記録が1つ増える（cleanup の中で再びエラーが起きて、入れ子の cleanup に入る場合など。制御スタックは増えない）。このため `unwinds` の大きさを制御スタック + 1 とし、エントリを積むときに「制御スタックの深さ + 記録の数」が制御スタックの大きさを超えないかを確かめる（超えたら `storage-condition`）。cleanup に入るときはエントリを1つ取り除いてから記録を1つ積むので和は増えず、増えるのは脱出を始めるときの1つだけなので、記録は溢れない。
- **エラーの内容の退避**（Codex のレビュー P18 #4）：エラーで cleanup に入るとき、エラーの理由に加えて内容（`th.err`）と呼び出しの履歴も退避し（`th.saved_errors`。GC のルート）、cleanup の後で戻す。cleanup の中で起きて受け止められたエラーが内容を上書きしても、元のエラーを報告する。
- **unwind-protect**：保護したフォームを抜けると、エントリを取り除いて値を退避する（`uwpSave`。値が1つなら fixnum 1、2つ以上なら全部の値のリスト。脱出・エラーの途中なら印 -1 で、動的束縛をエントリの深さまで戻し、進行中の脱出を止めるか、エラーの理由を Transfer に退避する）。cleanup の後の `uwpEnd` が、値を戻すか、止めていた脱出・エラーを続ける。エラーで抜けるときも cleanup を実行する（SBCL 2.6.7 の `--script` と同じ出力）。
- **cleanup の中の脱出**：新しい脱出を始めるときと、エラーで cleanup に入るとき、`cleanup_at` が脱出先（エラーでは今の深さ）より深い、止まっている脱出を取り消す（その cleanup の外へ出るため）。cleanup の中で受け止められる脱出は、止まっている脱出を取り消さない。エラーでトップレベルまで戻ったときは、残った記録を消す（`clearError`）。
- 試験：SBCL 2.6.7 の結果と比べる63通り（GC stress でも実行。毎回、制御スタック・脱出の記録・動的束縛が空に戻ることも確かめる）、エラーと cleanup の組み合わせ、言語試験 `exits.lisp`・`exit-cases.lisp`（63通りをネイティブでも実行）・`error-cleanup.lisp`。

**Phase 19 の実装（tagbody・go）**
- **Resolver**：tagbody の引数を、タグ（シンボルと整数。bignum を含み、eql で比べる）とフォーム（複合フォーム）に分ける。それ以外のアトムと、同じタグの重複は program-error（SBCL 2.6.7 と同じ）。go は return-from と同じ規則で、同じ lambda の中で unwind-protect を横切らなければジャンプ、そうでなければ実行時の脱出（tagbody に `needs_entry` を付ける）。値は NIL。
- **制御スタック**：エントリの種類 `tagbody` を加えた。go の実行時の脱出が運ぶ値はタグの番号（fixnum）。block と違い、**脱出先として着地してもエントリを取り除かない**（tagbody の中で続けるため。`landTransfer`）。普通に抜けるときに取り除く。
- **VM**：命令 `TAGBODY_ENTER i rel`（識別子を局所変数 i に置いてエントリを積む。rel は着地したときの再開の位置）と `GO_NL`（[識別子 タグの番号]。この後には進まない）。着地したら、タグの番号を局所変数に置き、番号を比べてタグの位置へ分岐する（タグの数に比例する。実行時の go はまれなため）。同じ関数の中の go は、途中の値を捨て（`POP`）、横切る動的束縛を戻し、横切るエントリを取り除いてジャンプする（後ろへのジャンプを含む）。検証器は、tagbody のエントリを「着地した後も残る」種類として扱う。
- **ネイティブ**：tagbody を Zig のラベル付き switch にする（0 番の分岐は最初のタグの前、k+1 番の分岐はタグ k の後ろ）。同じ関数の中の go は `if (true) continue :s番号 k+1;`。実行時の脱出先なら、switch をループで囲み、`Value.unwind` を受け取ったら `N.land` で着地して、タグの分岐から switch に入り直す。
- 試験：SBCL 2.6.7 の結果と比べる tagbody・go の24通り（後述の反復のマクロ・loop と合わせて139通り。GC stress でも実行。ネイティブでも実行：`iteration-cases.lisp`）。

**動的環境を戻す方式の統一**（agy #4）

動的束縛・handler・restart の解除は、Zig の `defer` / `errdefer` には頼らず、**すべて `Thread` のスタックの深さで戻す方式に統一する**（VM の `UNBIND_TO` と同じ考え方。ランタイムの関数 `th.unwindTo(depths)`）。

- 正常に抜けるとき：生成コードが、範囲の終わりで `th.unwindTo(入る前の深さ)` を呼ぶ。
- 非局所脱出のとき：脱出先（`block`・`tagbody`・`catch`）と各 `unwind-protect` が、制御スタックのエントリに記録した深さまで戻す（上記）。
- この方式なら、Zig のエラーで伝える方式と、`setjmp`/`longjmp` に相当する方式（下記の比較）のどちらを採用しても、解除の手順は変わらない。
- Zig の `defer` / `errdefer` は、Lisp の動的環境とは関係のない、ランタイム内部の資源（一時的に確保した Zig のメモリなど）の後始末にだけ使う。`setjmp`/`longjmp` に相当する方式を採用する場合は、それらの資源も制御スタックに登録して解放する。

**戻り値で伝える方式を選んだ理由**：`setjmp`/`longjmp` を使わずに、すべての関数を通常の戻りで抜けるため、Zig のランタイムの後始末が確実に実行される。通常の実行では、検査は戻り値（レジスタ）と定数の比較1回と分岐1つで済む。※分岐の費用は小さいと推測されますが、計測して確認します。

**他の処理系の方式と、計測による確認（R3）**

| 処理系 | 方式 | 根拠 |
|---|---|---|
| ECL | `setjmp`/`longjmp`（バイトコードと C の両方） | `src/h/stacks.h` 282〜296行目 `ecl_frs_push`、`src/c/stacks.d` 759〜771行目 `ecl_unwind` |
| Clasp | 通常は `setjmp`/`longjmp`。協調しない C++ のフレームがあるときだけ C++ の例外。C++ の例外は「setjmp/longjmp の数千倍遅い」と記録されている | `src/lisp/kernel/cleavir/unwind-notes.md` 10〜16、46、88行目 |
| Zilisp | 特別な戻り値 `Value.unwind` で1段ずつ返す（例外表を使わない。呼び出しのたびに比較と分岐が1つ入る） | 本節 |

Zilisp の方式は、脱出しない通常の呼び出しにも分岐1つの費用がかかり、脱出するときは途中のフレーム数に比例した費用がかかる。`setjmp`/`longjmp` は、脱出先を作る時点（block・catch・unwind-protect に入るとき）に費用がかかる。**Phase 12 で、次の2つを同じベンチマークで比較し、速い方を採用する。**

**Phase 12 の計測の結果（2026-11-02）**：ネイティブバックエンドが生成した fib(30)（ReleaseFast、x86_64-windows、7回の中央値）で、呼び出しのたびの `Value.unwind` の検査を取り除いたもの（エラーが起きない場合だけ正しく動く、比較用のもの）と比べた。起動時間（約 5.7 ms）を除いて、検査ありが約 9.7 ms、検査なしが約 8.5 ms で、**検査の費用は約12%** だった。関数の呼び出しが大半を占める処理なので、これは費用の上限に近い値である。方式2（`setjmp`/`longjmp` に相当する方式）は、Zig 0.17.0 には「2回戻る関数」（`returns_twice`）を扱う仕組みがなく、C の `setjmp` を Zig から安全に呼べないため、インラインアセンブリでレジスタとスタック位置を保存・復元する仕組みを自作する必要がある。**この比較（方式2の試作と計測）は、block・catch・unwind-protect を実装する Phase 18 で、実際の非局所脱出も含めて行う**（2026-11-02 決定。tque #339）。それまでは方式1を使う。検査の費用は、同じファイル内の直接呼び出しと型推論（エラーが起きないと分かる呼び出しの検査を省く）でも減らせる。

1. 特別な戻り値で伝える方式（本節の方式）
2. `setjmp`/`longjmp` に相当する方式（脱出先でレジスタとスタック位置を保存し、直接戻る。Zig の後始末を飛ばすため、ランタイム側の `errdefer` に頼る処理を制御スタックに登録する必要がある）

**Phase 18 の比較の結果（2026-11-02。tque #339）**
- 方式2の試作（`tests/bench/nonlocal.zig`）：Zig 0.17.0 には `returns_twice` がないため、`setjmp` そのものではなく、「レジスタ（Windows x64 では rbx・rbp・rdi・rsi・r12〜r15・xmm6〜xmm15、System V では rbx・rbp・r12〜r15）、浮動小数の制御の状態（MXCSR・x87 の制御語。どちらの ABI でも callee-saved）、スタックの位置を保存してから関数を呼ぶ」までを1つのアセンブリの関数 `zl_catch_call` にした。`zl_jump_to` で脱出すると、`zl_catch_call` がその値で戻る。コンパイラから見ると `zl_catch_call` は1回だけ戻る普通の呼び出しなので、呼び出し側のレジスタの扱いは正しい。アセンブリはモジュールの大域のアセンブリに書き、`extern` の関数として宣言して直接呼ぶ（実際の処理系でランタイムの関数を呼ぶのと同じ形）。
  - 注意：はじめは naked の関数で書いたが、naked の関数は Zig の宣言では `noreturn` になるため、関数ポインタに変換して呼ぶと、ReleaseSafe・ReleaseFast の最適化が「戻らない呼び出し」とみなして後ろのコードを消した（Debug では起きない）。大域のアセンブリと `extern` の宣言にすると、この問題は起きない。
- 計測（`zig build bench -- nonlocal`、ReleaseFast、x86_64-windows、7回の中央値。1回 = 脱出先を作る → 深さ D の呼び出し → 脱出または普通に戻る。どちらも制御スタックの出し入れと、脱出先の上に別のタグのエントリを2つ積んだ状態でのタグの探索を含み、探した結果を使う。Codex・agy のレビューを受けて計測し直した値）

| 処理 | 方式1 | 方式2 |
|---|---|---|
| 脱出先を作るだけ（D = 0、脱出しない） | 1.51 ns | 5.50 ns |
| 深さ 10 まで呼んで普通に戻る | 8.90 ns | 12.01 ns |
| 深さ 100 まで呼んで普通に戻る | 90.1 ns | 106.4 ns |
| D = 0 で脱出 | 2.08 ns | 10.67 ns |
| 深さ 10 から脱出 | 9.85 ns | 17.05 ns |
| 深さ 20 から脱出 | 17.4 ns | 20.5 ns |
| 深さ 100 から脱出 | 89.0 ns | 50.8 ns |
| 深さ 1000 から脱出 | 820.8 ns | 408.8 ns |

- 読み取り：方式2は、脱出先を作る費用が約 4 ns 多く（レジスタ 18 本と浮動小数の制御の状態の保存）、脱出そのものに深さに関係なく約 5〜8 ns かかる。方式1の脱出は1段あたり約 0.4〜0.5 ns（戻りと検査）。分かれ目は深さ約 25 段（20 段では方式1、100 段では方式2が速い）で、それより深い脱出だけ方式2が速い。呼び出しのたびの検査の費用は、この計測（関数ポインタ経由の呼び出し）では差が出なかった（Phase 12 の fib(30) では約12%）。
- **決定：方式1を続ける**（2026-11-02）。理由：①block・catch・unwind-protect（`with-open-file`・`handler-case` などの展開にも現れる）に入るたびの費用は方式1が小さく、脱出しないで抜けることの方が多い。②方式2で呼び出しのたびの検査をなくすには、エラーも直接戻る必要があり、そうするとランタイムの Zig の後始末（`defer` によるルートの登録の解除など）を飛ばす。それをすべて制御スタックに登録し直す費用と危険が大きい。③深い脱出が多い処理（深い再帰からの `throw` など）で方式1が問題になる場合は、その時点で再計測する。

### 6.5 動的束縛

- shallow binding とする。束縛では、シンボルの値セルの旧値を束縛スタックに退避してから新しい値を書く。解除と巻き戻しで旧値を戻す。
- **旧値が未束縛の場合も、未束縛のまま退避・復元する**（レビュー #9）。例：`(defvar *x*)` の後の `(let ((*x* 1)) *x*)` は 1 を返し、`let` を抜けると `*x*` は再び未束縛になる（SBCL 2.6.7 で確認）。
- **未束縛のエラー（`unbound-variable`）は、値を読み出すときだけ通知する。** 代入（`setq`・`setf`）と動的束縛（`let`・`progv`）は、未束縛の特殊変数に対しても行える。
- `progv` で値の数がシンボルの数より少ない場合、残りのシンボルは束縛されるが値を持たない（未束縛になる）。束縛を解除すると旧値に戻る（CLHS `progv`）。
- スレッドを導入するときは、シンボルに TLS の添字を持たせる方式に拡張する。

**Phase 14 の実装**
- 束縛のスタックは `Thread.bindings`（シンボルと旧値の組。既定 65536 要素。溢れたら `storage-condition`）。GC のルートとして正確に走査する。
- VM の命令：`BINDING_DEPTH`（深さを積む）、`BIND_SPECIAL k`、`UNBIND_TO`（[値 深さ] → [値]）、`PROGV_BIND`。`let`・`let*`・特殊変数の引数・`progv` は、束縛の前の深さを名前のない局所変数に置き、本体の後で `UNBIND_TO` で戻す。ネイティブバックエンドも同じ手順（`N.bindingDepth`・`N.bindSpecial`・`N.unbindTo`）。
- **エラーで抜けるときの復元**：`vm.run` は、入った時点の束縛の深さを覚えておき、`Value.unwind` で抜けるときにそこまで戻す。脱出先（block・catch）と unwind-protect は、制御スタックのエントリに記録した深さまで戻す（§6.4、Phase 18）。
- Resolver：束縛を動的束縛にするのは、名前が特殊変数（`defvar`・`defparameter`・`proclaim`）のときと、束縛の `special` 宣言があるとき。範囲の中の特殊変数は、`special` の印の付いた変数で表す（`special` 宣言だけで束縛しない名前も、その範囲の変数として加える）。この変数への参照・代入は `global_ref`・`global_set` になり、内側の lambda からも同じ（SBCL 2.6.7 で確認）。特殊変数の引数は、名前の見えない局所変数で受け取り、本体を特殊変数の `let` で囲む。
- `defvar`・`defparameter` は、Zig で書いたブートストラップ用のマクロ（§11.1 の 6）。名前を特殊変数と宣言するのは、**実行した時点**（`zl-sys::%proclaim-special`）と、**トップレベルのフォームなら、コンパイルの時点**（同じフォームの後ろの部分や、後のフォームのコンパイルで束縛が動的束縛になるように。CLHS 3.2.3.1。トップレベルの `progn` の中もトップレベル）。実行されないトップレベルでない `defvar`（`(if nil (defvar x) nil)`）は宣言しない（Codex のレビュー P14 #3。SBCL 2.6.7 で確認）。
- **`load` と `compile-file` の違い**：関数の中の `defvar` を実行した後に、同じ名前を `let` で束縛するフォームは、VM（`--script`・REPL。フォームを1つずつコンパイルして実行する `load` の意味）では動的束縛、ネイティブバックエンド（ファイル全体を先にコンパイルする `compile-file` の意味）ではレキシカルな束縛になる。SBCL 2.6.7 も、`--script` では前者、`compile-file` では後者になる（CLHS 3.2.3.1 で許される違い）。このため、この形の試験は VM の単体テストだけで行う。
- ネイティブのプログラムも、トップレベルのフォームをエラーで抜けたときに、そのフォームの中で作った動的束縛を戻す（Codex のレビュー P14 #2）。

### 6.6 `Value.unwind` の理由と、Zig のエラー集合

```zig
// 戻り値が Value.unwind のときの理由（th.fault）
pub const Fault = enum(u8) {
    none,
    unwind,         // 非局所脱出の途中（異常ではない。th.unwinds の先頭が脱出先）
    out_of_memory,  // 確保の失敗。可能であれば storage-condition に変換する
    internal,       // 処理系の内部故障（バグ）。Lisp の condition にはしない
    lisp_error,     // Phase 08〜24 の暫定：Lisp のエラー。内容は th.err（種類・説明・値）
};

// ランタイムの内部（Zig の関数どうし）でだけ使うエラー集合
pub const Error = error{ LispUnwind, OutOfMemory, VmInternal };
```

- 関数の入口（§6.2 の汎用の入口・高速入口）を通る値の受け渡しでは、Zig のエラーは使わず、`Value.unwind` と `th.fault` で表す。
- ランタイムの内部で、速さが問題にならない処理（ロード、コンパイラ、FFI の準備など）は、Zig のエラー集合 `Error!T` を使ってよい。入口の境界で `Value.unwind` と `th.fault` に変換する（`fault` の値はエラーの種類に対応させる）。
- Zig のプリミティブで CL のエラーが起きた場合は、`return th.signalError(class, initargs)` を呼ぶ。handler を巻き戻さずに実行し（§9）、最終的に必ず `Value.unwind` を返す。
- `th.fault = .internal` は、診断情報を出力して処理系を停止する。
- **condition ができるまで（Phase 08〜24）の暫定の扱い**（Phase 08 で決定）：プリミティブ・VM・コンパイラが見つけた Lisp のエラーは、`th.signal(kind, message, datum, expected)` で `th.fault = .lisp_error` と `th.err` に記録し、`Value.unwind` を返す。`kind` は CL の condition 型に対応させる（`type-error`、`unbound-variable`、`undefined-function`、`program-error`、`division-by-zero`、`floating-point-overflow`、`storage-condition` など。未実装の機能は Zilisp の拡張の `zilisp:unimplemented`）。トップレベル（REPL・スクリプト・`--eval`）まで戻って、型の名前と説明を1行で報告する。
- **Phase 25 から**：`th.signal` は、handler か restart が1つでもあれば、その場で condition を作って handler に通知する（§9.2）。handler が脱出すれば `Value.unwind`（`fault` は `.unwind`）を返し、受け止められなければ、上と同じく `th.err` に記録してトップレベルへ戻る（報告の文面も同じ）。toplevel の `abort` restart は作らず、トップレベルまで戻ることがその役をする。Lisp の `error` で受け止められなかった condition は、`ErrorKind.condition`（`th.err.datum` が condition、`expected` がクラスの名前、`detail` が report の文字列）で記録する。説明の Lisp の文字列は `th.signalDetail` で渡す。

### 6.7 スタックの大きさ

- ネイティブのスタックの大きさは、起動時（Windows では実行ファイルのヘッダ、その他ではメインスレッドを作り直す方法）で指定する。既定値は計測して決める（初期案 64 MiB。要検証）。
- スタックが溢れそうになったら `storage-condition` を通知する。ネイティブコードの関数の入口で残り量を検査する（ページを保護する方式は後で検討する）。
- 定数（初版の案）：`call-arguments-limit` = 65536、`multiple-values-limit` = 1024、`lambda-parameters-limit` = 1024。

---

## 7. バイトコード VM

### 7.1 位置づけ

- VM は、REPL・`eval`・ソースの `load` で定義したコードを**すぐに**実行するための方式である。Phase 39 以降は、バックグラウンドでネイティブ化が終わるまでの間と、Zig がない環境で使う（§7A.6）。
- 速度の主経路はネイティブコードなので、VM は実装が単純な**スタック型**とする。ただし、命令の分岐にはラベル付き `switch` と `continue`（スレッデッドコード相当）を使う（**2026-11-02 に計測して確定**）。
  - 計測（`zig build bench -- vm/`、x86_64-windows・ReleaseFast、5回の中央値）：`while` と `switch` の実行ループでは fib(25) が 5.08 ms だったが、ラベル付き `switch` と `continue` にすると 2.97 ms になった（約41%短縮）。closure の呼び出し1万回は 0.40 ms から 0.27 ms になった。
  - `while` と `switch` の形では、実行ループと関係のない変更（エラーの種類を1つ増やすなど）で、fib(25) が 3.7〜5.1 ms の範囲で変わった。ラベル付き `switch` では、同じ種類の変更を加えても 2.88〜2.98 ms でほとんど変わらなかった。
  - このため、実行ループに命令を加えるときも、各命令の最後で次の命令を読んで `continue :dispatch` で分岐する形を守る。
- VM の値スタックは固定長で、起動時に確保する（既定 1M 要素 = 8 MiB、`--stack-size` で変更）。値スタックは正確に走査する。

### 7.2 VM のフレーム

```zig
pub const VmFrame = struct {
    closure: Value,        // VM の closure
    ip: u32,
    base: u32,             // 局所変数の先頭（引数が先頭から並ぶ）
    ret_sp: u32,
    control_base: u32,
};
```

### 7.3 符号化（確定）

- オペコードは u8 とする。オペランドはリトルエンディアンで、命令ごとに幅を固定する（`k` = 定数表の添字 u16、`i` = 局所変数の添字 u16、`n` = 個数 u8、`rel` = 相対ジャンプ i32）。
- 添字と**個数**が u16・u8 を超える場合は、接頭命令 `WIDE` で、添字を u32、個数を u32 にする（レビュー #17）。これにより、`call-arguments-limit`（65536）までの引数を直接の呼び出しで渡せる。
- 試験では、引数の個数が 255・256・65535・65536・65537 の場合（u8 の境界、上限の直前・上限・超過）を確かめる。
- **`call-arguments-limit` の解釈**（Phase 08 で確定）：CLHS の `call-arguments-limit` は「引数の個数の上限（この値を含まない）」なので、`call-arguments-limit` = 65536 では、渡せる引数は **65535 個まで**である。65536 個・65537 個の呼び出しは、コンパイル時（`apply` では実行時）に `program-error` にする。上の試験の「上限」（65536）は、エラーになることを確かめる。
- バイトコードは内部形式で、互換性を保証しない。`.zfasl` のヘッダの形式バージョンが一致しない場合は、ロードを拒否する。

### 7.4 命令表

| 分類 | 命令 | オペランド | スタックの変化・意味 |
|---|---|---|---|
| 定数 | `CONST` / `NIL` / `T` / `SMALLINT` | k / — / — / i16 | → v |
| スタック | `POP` / `DUP` / `POPN` | — / — / n | |
| 局所 | `LOAD_LOCAL` / `STORE_LOCAL` / `LOAD_CAPTURED` | i | |
| | `MAKE_CELL` / `CELL_REF` / `CELL_SET` | — | |
| 特殊変数 | `LOAD_SPECIAL` | k | 未束縛なら `unbound-variable` |
| | `STORE_SPECIAL` / `BIND_SPECIAL` | k | 未束縛でも実行できる（§6.5） |
| | `BINDING_DEPTH` / `UNBIND_TO` / `PROGV_BIND` | — | |
| 関数 | `LOAD_FUNCTION` / `LOAD_SETF_FUNCTION` | k | 未定義なら `undefined-function` |
| | `MAKE_CLOSURE` | k n | |
| | `CALL` / `CALL_MV` / `CALL_GLOBAL` / `CALL_GLOBAL_MV` / `APPLY` | n / n / k n / k n / n | §6.2 の規約で呼ぶ |
| | `RETURN` | — | |
| 引数 | `ARG_SUPPLIED_P` | i | |
| 制御 | `JUMP` / `JUMP_IF_NIL` / `JUMP_IF_NOT_NIL` | rel | |
| 多値 | `TO_MV` / `MV_PRIMARY` / `VALUES` / `VALUES_LIST` / `MV_SAVE` / `MV_RESTORE` / `MV_BIND` / `MV_MARK` / `MV_SPREAD` / `MV_CALL_MARKED` | | §6.3 |
| 非局所 | `BLOCK_ENTER` / `BLOCK_EXIT` / `RETURN_FROM_NL` | i rel / — / i | §6.4（Phase 18 の実装は §6.4 の「Phase 18 の実装」：`BLOCK_EXIT`・`CATCH_EXIT` は `CONTROL_POP n`、`UWP_EXIT` は `UWP_SAVE` にした） |
| | `TAGBODY_ENTER` / `TAGBODY_EXIT` / `GO_NL` | i n rel[n] / — / i u16 | |
| | `CATCH_ENTER` / `CATCH_EXIT` / `THROW` | rel / — / — | |
| | `UWP_ENTER` / `UWP_EXIT` / `UWP_END` | rel / — / — | |
| 条件 | （作らない。handler と restart は特殊変数の動的束縛で表す。Phase 25） | — | §9.2 |
| 高速経路 | `CONS` `CAR` `CDR` `EQ` `NULL` `ADD2` `SUB2` `LT2` `GT2` `NUMEQ2` 等 | — | fixnum の高速経路と汎用処理へのフォールバック |
| その他 | `LOAD_TIME_VALUE` / `WIDE` | k / — | |

**Phase 08 で実装した命令**（`src/vm/opcodes.zig`）：`CONST` `NIL` `T` `SMALLINT` `POP` `LOAD_LOCAL` `STORE_LOCAL` `LOAD_CAPTURED` `MAKE_CELL` `CELL_REF` `CELL_SET` `LOAD_SPECIAL` `STORE_SPECIAL` `LOAD_FUNCTION` `MAKE_CLOSURE` `CALL` `CALL_GLOBAL` `RETURN` `JUMP` `JUMP_IF_NIL`、高速経路の `CONS` `CAR` `CDR` `EQ` `NOT`（`null` と `not`）`ADD2` `SUB2` `LT2` `GT2` `LE2` `GE2` `NUMEQ2` `ADD1` `SUB1`、`WIDE`。
- `STORE_LOCAL`・`STORE_SPECIAL` は、書いた値をスタックに残す（`setq` の値になる）。値が要らない場所では、続けて `POP` を出す。
- 値スタックのフレームの形：`[base, base+nlocals)` が局所変数（引数が先頭から並ぶ）、その上の `max_stack` 個が式の評価に使う領域。GC は値スタックの `[0, sp)` を正確に走査する（使い終わった枠に残った値は走査しない。Codex のレビュー P08 #2）。実行ループは `sp` を局所変数に持つので、**確保（GC が起きうる処理）と VM 以外の関数の呼び出しの前に、必ず `Vm.sp` に書き戻す**。書き戻しの漏れは `--gc-stress` の試験で検出する。値スタックは起動時に NIL で埋める。
- Zig の関数から関数を呼ぶ経路（`funcall`・`apply` など）は、すべて `Thread.call` を通る。入れ子の深さは、VM の closure なら `vm.run` で、それ以外のプリミティブなら `Thread.call` で数える（二重には数えない。上限 1000。`apply` から `apply` を呼ぶ連鎖のように VM を挟まない場合も止める。P08 #1）。
- 捕捉のない `lambda` の closure は、コンパイル時に1つだけ作って定数表に置く（実行時に確保しない）。
- **`(funcall f …)` は `CALL` 命令にする**（関数の値を直接呼ぶ）。VM の closure を呼ぶ場合は、同じ実行ループの中でフレームを積む。

**検証器**（レビュー #20）
- コンパイラが生成した直後のバイトコードは、デバッグビルドで、スタックの深さの整合、ジャンプ先の範囲、定数表の添字の範囲を検証する。
- **`.zfasl` から読み込んだバイトコードは、リリースビルド（ReleaseFast）でも、ロードの時点で同じ検証を行う。** ファイルは処理系の外から来るため、CRC32 によるチェックサム（§14）だけでは、構造が安全であることを保証できない。検証はロード時に1回だけなので、実行速度には影響しない。

---

## 7A. ネイティブバックエンドと REPL のネイティブ化（D-7・D-10）

### 7A.1 方式

- Core IR から **Zig のソース**を生成し、Zig（LLVM）でコンパイルする。1つの Lisp ソースファイルが、1つの Zig ソースファイルに対応する。
- 生成した Zig ソースは、ランタイムの Zig ソースと一緒にコンパイルする（D-5）。このため、ランタイムの小さな関数（`car`、fixnum の判定、確保の高速経路など）が生成コードにインライン展開される。
- 使用場面：`zilisp build`（§15）と、処理系自身の標準ライブラリのビルド（§11.3）。

### 7A.2 生成するコードの形

```zig
// (defun add1 (x) (1+ x)) から生成するコードのイメージ（設計例）
// 汎用の入口（§6.2 の Entry）と、単値を返す高速入口
fn lisp_add1(th: *Thread, self: Value, args: [*]const Value, nargs: u32) callconv(.c) Value {
    if (nargs != 1) return th.argCountError(self, nargs, 1, 1);   // Value.unwind を返す
    const r = add1_fast(th, args[0]);
    if (r == Value.unwind) return r;
    th.mv_count = 1;
    return r;
}
fn add1_fast(th: *Thread, x: Value) Value {
    if (x.isFixnum()) {
        const r = @addWithOverflow(x.raw(), Value.fixnumOne().raw());
        if (r[1] == 0) return Value.fromRaw(r[0]);
    }
    return rt.genericAdd(th, x, Value.fromFixnum(1));  // bignum・浮動小数・型エラー（エラーなら Value.unwind）
}
```

高速入口（`add1_fast`）は、単値を返すことが分かっている関数にだけ生成し、`th.mv_count` を書かない（汎用の入口がまとめて書く）。どちらの入口も、エラーは `Value.unwind` で表す（§6.2、レビュー #24）。

### 7A.3 速度のための変換

| 変換 | 内容 |
|---|---|
| fixnum の高速経路 | タグ付きのまま演算し、溢れたときだけ汎用処理を呼ぶ |
| ボックス化の回避 | 型推論で double-float と判明した局所変数は、f64 のまま保持する。関数の外に出る時点でだけヒープに確保する |
| 特殊化配列 | `double_vector`・`fixnum_vector` の要素は、ボックス化せずに読み書きする |
| 同じファイル内の直接呼び出し | `notinline` が宣言されていなければ、関数セルを経由せずに高速入口を直接呼ぶ（CLHS 3.2.2.3） |
| インラインキャッシュ | 別のファイルの関数の呼び出しでは、関数セルの値と高速入口をキャッシュする |
| 末尾呼び出し（agy #9） | **自分自身の末尾呼び出し**（最も多い）は、Core IR の段階で**関数の中のループに変換**する（呼び出しにしない）。`@call(.always_tail, …)`（LLVM の `musttail`）は、呼び出し元と呼び出し先の型（引数・戻り値・呼び出し規約）が一致する場合にしか使えないため、使うのは**汎用の入口どうし**（`Entry` は全関数で同じ型）と、**型が同じ高速入口どうし**に限る。それ以外の末尾呼び出しは、汎用の入口を経由する。|
| 末尾呼び出しの条件 | 末尾呼び出しにする条件（レビュー #16）：①動的なエントリ（束縛・catch・unwind-protect・handler・restart）がない、②呼び出し先に渡す引数が、呼び出し元のフレームの領域を指していない（`args` 配列・スタックに確保した `&rest` リストや closure を渡さない）、③呼び出し元のフレームにある block・tagbody のトークンを、捕捉された closure が参照していない。②を満たすため、末尾呼び出しでは引数を**スレッドごとの専用の引数領域**に移してから呼ぶ。高速入口（レジスタ渡し）どうしの末尾呼び出しと、汎用の入口（配列渡し）を経由する末尾呼び出しは、別々に検証する。実現方法は `@call(.always_tail, …)`（要検証）とし、使えない場合は Gambit の方式（同じ関数の中は分岐、外へはトランポリンで戻る。`include/gambit.h.in` 6790〜6952行目、`lib/setup.c` 3223行目の `___trampoline`）を使う |
| 型検査の省略 | `safety 0`、または型推論で型が確定している場所 |
| CLOS | 総称関数の呼び出しは、§10.4 のキャッシュを引く高速経路を生成する |

### 7A.4 GC との関係

- 生成コードは、ローカル変数に保持した Lisp 値を GC に登録しない（§3.4 の保守的走査で見つける）。ネイティブバックエンドは、§3.4 の「生存の契約」を満たすコードを生成する。
- Clasp も、LLVM が生成するコードについて、ネイティブのスタックを保守的に走査し、ヒープは型ごとの配置情報で正確に走査している。LLVM の GC 用の仕組み（statepoint、gc.root）は使っていない（`include/clasp/gctools/roots.h` 27〜46行目、`src/gctools/gc_boot.cc` 398〜420行目）。
- GC が起こり得るのは確保の呼び出しだけである。確保の高速経路はインライン展開し、ページが尽きたときだけランタイムを呼ぶ。

### 7A.5 デバッグ情報

- 生成する Zig の関数名に、Lisp の関数名を含める（backtrace で Lisp の関数名を表示するため）。
  - **C1**：Zig の、任意の文字列を識別子にする書き方（`@"cl-user::foo-bar"`）を使えば、Lisp の名前を変換せずにそのまま使える見込みである（要検証。生成したシンボル名が、デバッガやリンカでそのまま表示されるかも確認する）。
  - 使えない場合は、Carp の変換方式（`-` → `_MINUS_`、`?` → `_QMARK_`、非 ASCII → `_U<コード>U_` など：`src/SymPath.hs` 29、85行目）を参考に、可逆な変換を定める。
- 生成する Zig ソースに、対応する Lisp のソース位置をコメントで出力する。
- **C2**：実行時に「ネイティブのアドレス → Lisp のソース位置」を引く方法は **要検証**。C を生成する Carp は、C の `#line` 指令で、C のコードを Lisp のソース行に対応づけている（`--line-directives` 指定時のみ。`src/Emit.hs` 145〜156行目）。Zig に同等の指令があるかを確認し（※ないと推測されます）、ない場合は、関数ごとの「生成した Zig の行 → Lisp のソース位置」の表を生成して、Zig のデバッグ情報と組み合わせる。決まるまでは、backtrace は関数名までとする。

### 7A.6 REPL・eval・load のネイティブ化（D-10、Phase 39）

**候補の調査結果（2026-11-01）**

調査の条件：ライセンスが MIT と両立すること、x86-64 と AArch64 に対応すること、Windows・Linux・macOS で動くこと。

| 候補 | ライセンス | Windows | 実行時に必要なもの | 判定 |
|---|---|---|---|---|
| MIR（vnmakarov/mir） | MIT | **公式の対応記載なし** | なし | 一次ターゲットの Windows で条件を満たさないため不採用 |
| libgccjit（Emacs のネイティブコンパイルが使用） | GPL（GCC） | MinGW で動作。ファイル名は ANSI のみ（Emacs の `src/comp.c` 4795〜4815行目） | **gcc と binutils（`as`・`ld`）**（Emacs の `doc/lispref/compile.texi` 761〜763行目）。生成物は DLL | ライセンスと外部ツールの必要性から不採用 |
| LLVM の JIT（ORC。Clasp が使用：`src/llvmo/runtimeJit.cc`） | Apache 2.0（LLVM 例外付き）と理解している（※未確認） | 対応 | LLVM のライブラリをリンクする（実行ファイルが大きくなる。大きさは要検証） | 配布した実行ファイルの中での `eval` を速くする場合の将来の候補 |
| **④ バックグラウンドで Zig により DLL を作る（採用）** | — | 対応 | **Zig**（SDK を入れた開発環境にある） | 新しい外部ライブラリが不要で、3つの OS で動くため**第一候補として採用** |

**④ の方式**（Clasp の自動コンパイル用スレッド `src/lisp/kernel/cleavir/auto-compile.lisp` と、Emacs の非同期ネイティブコンパイル `lisp/emacs-lisp/comp-run.el` を参考にする）

1. REPL・`eval`・ソースの `load` で定義された関数は、まずバイトコードにコンパイルし、VM で**すぐに**実行する（待ち時間をなくす）。
2. 同時に、その関数の Core IR から Zig ソースを**その場で（同期的に）生成**し、**別プロセスの Zig** で共有ライブラリ（Windows は DLL、Linux は `.so`、macOS は `.dylib`）にコンパイルする。Core IR はトップレベルフォームの処理が終わると破棄する（§5.1）ため、Zig ソースへの変換は破棄の前に済ませる（レビュー #13）。
3. 完成したら共有ライブラリを読み込み（Windows は `LoadLibraryW`、その他は `dlopen`）、**ネイティブの入口を code オブジェクトに設定する**（agy #1）。
4. **すでにある closure も、ネイティブのコードで動くようになる。** closure を作り直したり、関数セルの closure を差し替えたりはしない。同じ lambda から作った closure はすべて同じ code を共有しているので、code にネイティブの入口を設定すれば、次の呼び出しから（VM のトランポリンが code の入口を調べることで。§6.2）ネイティブのコードが使われる。closure の同一性（`eq`）と、捕捉した変数（`value_cell` を含む）の共有はそのまま保たれる。
   - 例：`(let ((count 0)) (defun next-id () (incf count)))` の `next-id` は、関数セルに入っている closure がそのまま、ネイティブのコードで動くようになる。
   - 関数が返した内側の closure、データ構造に格納された関数オブジェクトも、同じ code を共有していれば同じように切り替わる。
   - このため、**捕捉値の配列の並べ方と、`value_cell` の使い方は、VM とネイティブで同じにする**（同じ Core IR の `captured` / `assigned` の解析結果から決める。§5.2）。
   - ネイティブのコードは、第2引数の `self`（closure 自身。§6.2）から捕捉値の配列を参照する。

**ジョブの管理**（レビュー #13）
- 各コンパイルのジョブは、対象の**関数オブジェクト**と、その関数名の**定義の世代番号**（`defun` などで定義し直すたびに増える番号）を持つ。
- **まとめてコンパイルする**（agy #10）：ソースを `load` した場合は、関数ごとではなく**ファイル単位で1つの Zig ソース・1つの共有ライブラリ**にまとめる。REPL での定義は、短い時間（初期案 1秒）に定義されたものをまとめる。
- **同時に動かす Zig のプロセスの数に上限を設ける**（初期案 1〜2）。超えた分はジョブの待ち行列に入れる。
- **完了の確認と入口の置き換えは、メインの実行系の安全な地点でだけ行う**（1.0 は単一スレッドのため）。安全な地点は、REPL がプロンプトを出す時点、GC の開始時点、および一定回数の関数呼び出しごとの検査（長く動き続ける Lisp の処理の途中でも置き換えが進むようにするため）とする。
- 完了したジョブの世代番号が、その関数名の現在の世代番号と違う場合（コンパイル中に再定義された場合）は、**生成物を捨てる**。古い定義のネイティブコードを新しい定義に当てはめない。
- コンパイルの失敗（Zig のエラー、子プロセスの異常終了）は、警告を出して VM のまま実行を続ける。処理系を終了するときは、実行中の子プロセスを止め、未完了のジョブを捨てる。

**`compile` の動作**（レビュー #15）
- Zig がある環境で `compile` を明示的に呼んだ場合は、ネイティブ化が終わるまで待つ（同期）。
- **Zig がない環境（配布した実行ファイルの中など）では、`compile` はバイトコードにコンパイルして返す。** どちらの場合も、CLHS の `compile` の契約（3つの値：関数、警告の有無、失敗の有無を返す。名前を指定した場合はその関数の定義を置き換える。結果は `compiled-function-p` が真になる）を守る。CLHS の `compile` は、外部のツールで機械語を作ることを要求していない。

**設計上の注意**
- 共有ライブラリは、処理系のランタイムを重複して含まないようにする。ランタイムの関数は、読み込み時に渡す**関数ポインタの表**を経由して呼ぶ。定数は、読み込み時に埋める**定数の表**から参照する（Emacs の `freloc_link_table`・`d_reloc` と同じ考え方：`src/comp.c` 477〜487、5290〜5323行目）。Value のタグ操作などの小さな関数は、生成コードの中にインライン展開する。
- 共有ライブラリとの境界の呼び出し規約・ABI の版番号の照合は、§6.2 の「別にコンパイルした共有ライブラリとの境界」に従う（レビュー #11）。
- Windows では、読み込み中の DLL を上書きできない。共有ライブラリのファイル名は、生成するたびに一意にする（Emacs の `lisp/emacs-lisp/comp.el` 3508〜3530行目の対策を参考にする）。
- 1.0 では、読み込んだ共有ライブラリを解放しない（コードの回収は行わない）。
- **キャッシュの掃除**（agy #10）：再定義などで使われなくなった共有ライブラリは、Windows では読み込み中は削除できないため、**次に Zilisp を起動した時点**（まだ読み込んでいない時点）で削除する。キャッシュ全体の大きさに上限（初期案 1 GiB）を設け、超えた場合は古いものから削除する。

**キャッシュと信頼の範囲**（レビュー #14・#20）
- キャッシュのキーには、生成した Zig ソースのハッシュに加えて、**Zig の版、Zilisp の SDK の版、ABI の版番号（§6.2）、ターゲット（CPU・OS）、最適化の設定、生成コードが参照するランタイムのファイルのハッシュ**を含める。どれかが変われば、別のキャッシュ項目になる。
- キャッシュは、Zilisp が管理するディレクトリ（利用者ごとの `.zilisp-cache/`）だけに置く。共有ライブラリは、一時ファイルに書いてから名前を変えて配置する（書きかけのファイルを読み込まない）。読み込むときは**絶対パス**で指定し、ABI の版番号を照合する。
- 共有ライブラリが依存するライブラリを、OS の検索パス（カレントディレクトリなど）から探させない。共有ライブラリは、処理系の本体以外に依存しないように生成する。

**この方式で満たせない点（明記）**
- **Zig がない環境（配布した実行ファイルの中など）での `eval`・`load` は VM で実行され、ネイティブ速度にならない。** アプリ本体はすべてネイティブコード（§15）なので、影響を受けるのは、実行時に `eval` や `load` で読み込んだコードだけである。
- この点を解消するには、LLVM の JIT（ORC）を組み込むか、独自のコード生成器（D-10 の③）を作る必要がある。1.0 以降に、計測結果と実行ファイルの大きさを見て判断する。

### 7A.7 コンパイル時間

- Zig（LLVM）によるコンパイルは時間がかかる。※ファイルごとに数秒程度と推測されます（Phase 12 で計測する）。
- キャッシュする（`.zilisp-cache/`）。キーは、生成した Zig ソースのハッシュと、§7A.6 の「キャッシュと信頼の範囲」に挙げた版・設定の組とする。変更のないファイルは再コンパイルしない。
- **生成コードの規則（R2）：1つの Lisp 関数を1つの Zig 関数にし、巨大な関数を生成しない。** Gambit は、モジュール全体を1つの C 関数にまとめる方式について、「clang/LLVM では30分以上かかり、大量のメモリを使う（GCC では約1分）」と警告している（`configure.ac` 3969〜3975行目）。また、大きなモジュールでは関数ごとに最適化を下げている（`configure.ac` 516〜528行目、`include/gambit.h.in` 1255〜1265行目）。Zilisp も、関数の大きさがしきい値を超えた場合に最適化を下げる仕組みを用意する（しきい値は計測して決める）。

### 7A.8 Phase 12 の実装（最小のネイティブバックエンド）

- `src/native/emit.zig`：Core IR から Zig のソースを生成する。lambda 1つにつき汎用の入口（`Entry`、`callconv(.c)`）の関数を1つ、トップレベルのフォーム1つにつき引数のない関数を1つ作る。関数名は `@"lisp:名前:番号"`（§7A.5 の C1：Lisp の名前を識別子にそのまま使えることを確認した。デバッガ・リンカでの表示は未確認）。
- 式の値は Zig の局所定数に入れ、関数の呼び出しのたびに `Value.unwind` かを確かめて、そうなら返す（§6.4 の方式1）。fixnum の高速経路（`car`・`+`・`<` など）は `src/native/rt.zig` の inline 関数で、生成したコードに展開される。
- 定数（quote したデータ・シンボルなど）は `prin1` で印字したテキストとして埋め込み、起動時に Reader で読み直す。その後ろに、各 lambda の Code（印字用の名前と引数の個数）と、捕捉のない lambda の closure を置く（定数表。GC のルートに登録する）。uninterned のシンボルは、定数ごとに別のシンボルになる（定数をまたぐと、同じファイルの中での同一性を保たない）。Phase 24 から、定数を `*print-circle*` で書くので、1つの定数の中で共有・循環する構造（共有する uninterned のシンボルも）は保たれる（`#n=` と `#n#`）。
- 生成したコードは局所変数の Lisp の値を GC に登録しない（§7A.4）。関数の入口で、ネイティブのスタックの残りを確かめる（§6.7。生成した実行ファイルのスタックは 64 MiB）。
- まだ行わないこと（§7A.3）：同じファイル内の直接呼び出し、高速入口、末尾呼び出しの変換、型推論。呼び出しは常に関数セルを経由する。
- 開発用のコマンド `zilisp --emit-zig FILE OUT.zig` と、`zig build native-test`（`tests/language/eval/*.lisp` を生成・コンパイル・実行して、VM と同じ期待値と比べる。`-Doptimize` で最適化を指定）。単一の実行ファイルを作る `zilisp build`（Phase 36）は、この仕組みの上に作る。
- **計測**（fib(30)、ReleaseFast、x86_64-windows、7回の中央値、起動時間を除く）：VM 約 34.9 ms、ネイティブ約 9.7 ms（約3.6倍）。起動時間は VM 6.1 ms、ネイティブ 5.7 ms（CL の 978 シンボルの準備を含む）。

---

## 8. 名前空間・パッケージ・intern テーブル

### 8.1 シンボル

```zig
pub const Symbol = extern struct {
    header: ObjHeader,
    name: Value,        // 文字列（intern 後は変更しない）
    package: Value,     // パッケージ、または NIL（uninterned）
    value: Value,       // 大域値／動的値（unbound 可）
    function: Value,    // 関数・マクロ関数（unbound 可）
    setf_function: Value, // (setf 名前) の関数（unbound 可）
    plist: Value,
    fast_entry: usize,  // 高速入口（§6.2。未定義・VM・個数不一致のときは汎用の処理へ戻るトランポリン）
    // header.flags: special, constant, keyword, macro, global_symbol_macro, unimplemented, shadowing
};                      // 64 バイト（ヘッダ 8 ＋ 7 語）。64 バイトのサイズクラスに収まる
```

- **`(setf foo)` 形式の関数名は、シンボルの `setf_function` 欄に格納する**（agy #7）。通常の関数と同じく1回の間接参照で呼べる。表（ハッシュ表）に入れないので、シンボルが使われなくなれば一緒に回収される（弱参照の表が不要になる）。
- **定数**（agy #13。CLHS `defconstant`、3.1.2.1.1.3「Constant Variables」）
  - `constant` フラグを持つシンボルへの代入（`setq`・`setf`）と束縛（`let`・`let*`・`lambda` の引数・`progv`・`multiple-value-bind` など）は、**コンパイル時に検出できればコンパイル時に、それ以外は実行時に**エラーにする。
  - `defconstant` は、すでに定数で、新しい値が旧い値と `eql` であれば受け入れる（同じファイルを再び `load` した場合など）。`eql` でなければエラーを通知する（CLHS では結果は未定義だが、黙って値を変えない）。
  - コンパイル時の扱いは §16.1 を参照。
- `unimplemented` フラグ：CL のシンボルのうち、Zilisp がまだ実装していない関数・マクロに付ける。**コンパイル時に呼び出しを検出した時点でエラー**にする（「`COMMON-LISP:XXX` は Zilisp で未実装」）。

### 8.2 パッケージ

```zig
pub const Package = struct {
    header: ObjHeader,
    name: Value, nicknames: Value,
    internal: SymbolTable,   // UTF-8 の名前 → シンボル（キーは非GC領域に複製して保持する）
    external: SymbolTable,
    shadowing: Value,
    use_list: Value, used_by: Value,
    local_nicknames: Value,  // Phase 22 以降
};
```

- `find-symbol` の探索順序：自パッケージの external → internal → use しているパッケージの external（use-list の順）。
- 名前の衝突検出は Phase 22 で実装し、`package-error` と restart を提供する（CLHS 11.1.1.2.5）。
- `unintern` は、シンボルを**そのシンボルのホームパッケージから**取り除いた場合だけ、`symbol-package` を NIL にする（CLHS `unintern`。agy #14）。
- ~~シャドウイングシンボルかどうかの判定は、リストの探索ではなく、シンボルのフラグ（`shadowing`。パッケージごとに異なり得るため、パッケージ側の集合と併用する）で行う。~~
- シャドウイングシンボルは、パッケージごとのリスト（`PackageData.shadowing`）で持ち、判定はリストを探す（Phase 22 で、シンボルのフラグを使う案から変更。判定を使うのは名前の衝突を調べるときだけで、読み取りや検索では使わない。シャドウイングシンボルはふつう数個）。

**Phase 22 の実装（パッケージ）**
- **`*package*`**：CL の特殊変数として値を持ち（起動時は CL-USER）、`let` で束縛できる。`Runtime.current` はなくし、Reader・Printer・`intern` などは `*package*` の値を読む（`Runtime.currentPackage`。パッケージでない値や削除したパッケージなら、Reader は読み取りのエラーにする）。
- **パッケージの本体**（`PackageData`）：名前・別名、内部・外部の表、use しているパッケージと、自分を use しているパッケージの一覧、シャドウイングシンボル、ローカルの別名（SBCL 2.6.7 の拡張。`defpackage` の `:local-nicknames`）。`find-package` と Reader はローカルの別名を先に見て、Printer もローカルの別名で修飾する（SBCL と同じ）。
- **関数**（`src/primitives/packages.zig`）：`packagep`・`find-package`・`make-package`（`:use` の既定は空。SBCL と同じ）・`rename-package`・`delete-package`・`list-all-packages`・`package-name`・`package-nicknames`・`package-use-list`・`package-used-by-list`・`package-shadowing-symbols`、`intern`・`find-symbol`（2つ目の値は `:internal`・`:external`・`:inherited`）・`unintern`・`export`・`unexport`・`import`・`shadow`・`shadowing-import`・`use-package`・`unuse-package`・`find-all-symbols`・`symbol-package`・`keywordp`・`make-symbol`。
- **マクロ**（`src/lisp/boot.lisp`）：`in-package`、`defpackage`（`:nicknames`・`:use`・`:shadow`・`:shadowing-import-from`・`:import-from`・`:intern`・`:export`・`:documentation`・`:size`・`:local-nicknames`。処理の順序は CLHS のとおり、shadow・shadowing-import-from、use、import-from・intern、export。知らないオプション、`:documentation`・`:size` の重複、`:shadow`・`:shadowing-import-from`・`:import-from`・`:intern` の名前の重なり、`:intern` と `:export` の重なりは program-error。既にあるパッケージには設定を足す）、`do-symbols`・`do-external-symbols`・`do-all-symbols`。`in-package` と `defpackage` は `(eval-when (:compile-toplevel :load-toplevel :execute) ...)` に展開するので、ファイル全体を先にコンパイルするとき（ネイティブ）にも、後のフォームを読む前にパッケージが切り替わる。
- **名前の衝突**（CLHS 11.1.1.2.5）：`use-package`（同時に use するパッケージどうしも）、`export`（use しているパッケージに同名の別のシンボル）、`import`（同名の別のシンボルがアクセスできる）、`unintern`（シャドウイングシンボルを取り除くと、use している複数のパッケージの同名の外部シンボルが衝突する）。表を変える前にすべて調べ、あれば package-error（SBCL 2.6.7 は package-error の一種の name-conflict）。restart は condition の Phase 25 で加える。
- **`delete-package`**：本体は `Runtime.deleted_packages` に移して残す（パッケージのオブジェクトが指したままでよいように）。ホームパッケージがそのパッケージのシンボルは、ホームを NIL にする。標準のパッケージと、ほかのパッケージが use しているパッケージは削除できない（package-error。SBCL は continue の restart で unuse してから削除する）。
- **`load`**（`src/primitives/load.zig`）：ファイル（文字列。パス名は Phase 23）のフォームを1つ読むごとに評価する。読み込みの間 `*package*` を束縛する（ファイルの中の `in-package` は、読み込みが終われば元に戻る）。`:if-does-not-exist nil` ならファイルがなければ NIL。`:verbose`・`:print` を真にするのは未実装のエラー。エラーの種類 `file-error`・`reader-error`・`end-of-file` を加えた。
- **ネイティブバックエンド**：定数は、キーワードと uninterned 以外のシンボルをすべて「パッケージ::名前」の形で書く（`printer.qualify_all`。起動時の `*package*` や、まだ export していない順序によらず同じシンボルを読む）。起動時に定数を読むとき、まだ作られていないパッケージは仮のパッケージ（`Runtime.pending_packages`）にする（`ValueBuilder.create_packages`）。仮のパッケージはパッケージの一覧に入れないので、`find-package` などからは見えない（VM と同じく、`defpackage` の前の `find-package` は NIL）。同じ名前のパッケージを `make-package`・`defpackage` で作るときに、仮のパッケージを正式に登録して使う（Codex のレビュー P22 #1。コンパイル時と実行時の両方で `make-package` しても、名前は重複しない）。
- **CL の書き方の注意**：ファイル全体を先にコンパイルする場合（ネイティブ・`compile-file`）、後のフォームの読み方を変える `load`・`use-package` などはトップレベルで `eval-when` に囲む必要がある（`defpackage`・`in-package` は展開が `eval-when` なので不要）。`print` の中など、トップレベルでない `defpackage` も、コンパイルの時点では実行されない。どれも SBCL の `compile-file` と同じ。
- **Codex のレビュー P22 の修正**：#1 は上の仮のパッケージ。#2 ホームのないシンボルを既にあるパッケージへ `import` し直したときもホームを設定する。#3 `shadowing-import` はホームを変えない（SBCL と同じ）。#4 KEYWORD に `use-package` させるのは simple-error（SBCL と同じ）。#5 `NIL` もエスケープ付きの印字では、今のパッケージから見えなければ `COMMON-LISP:NIL` と修飾する（ローカルの別名があればそれ。ネイティブの定数は `COMMON-LISP::NIL`）。#6 `defpackage` の `:size` は負でない整数を1つ、`:documentation` は文字列を1つ（個数の誤りは program-error、文字列でなければ type-error。SBCL と同じ）。type-error を出す `ZILISP-SYSTEM::%TYPE-ERROR` を加えた。
- **修正**：Phase 21 の `seqfns.zig` の `collect` が、ベクタを集めるときに全体の容量（`ensureTotalCapacity`）を確保していたため、`concatenate` で前の列の後ろに続けると容量が足りなくなることがあった（Debug では assert で止まり、ReleaseFast ではメモリを壊すおそれ）。空きの容量（`ensureUnusedCapacity`）にした。`Thread.create` が、標準ライブラリの読み込みに失敗したときに VM などを解放していなかった。
- **試験**：言語試験 `packages.lisp`（パッケージの関数・`defpackage`・`in-package`・印字・教材の形）と `multi-file.lisp`（`load` した2つのファイルの名前の解決。受入）。どちらも SBCL 2.6.7 と同じ出力で、GC stress の版とネイティブでも同じ。エラーの種類の単体テスト（package-error・type-error・program-error・読み取りのエラー）。
- 結果：Level 15 の 32 ブロックのうち 8 が一致し、23 は両方ともエラー（前のブロックで定義したパッケージを使うもの）、Zilisp だけがエラーなのは `with-open-file`（Phase 23）の 1 つ。教材のブロックの一致は 421 から 429 に。

### 8.3 標準パッケージ（確定）

| パッケージ | 別名 | use | 内容 |
|---|---|---|---|
| `COMMON-LISP` | `CL` | — | CL の外部シンボル 978 個をすべて起動時に作成する |
| `COMMON-LISP-USER` | `CL-USER` | `CL` | 利用者の既定パッケージ |
| `KEYWORD` | — | — | |
| `ZILISP` | `ZL` | `CL` | 公開している拡張機能（`exit`、`gc-statistics` 等） |
| `ZILISP-SYSTEM` | `ZL-SYS` | `CL` | 内部用（`%` で始まるプリミティブ、quasiquote 等） |

- `CL-USER` は `CL` だけを use する（教材のコードと拡張機能の名前の衝突を避ける）。
- 978 個のシンボル名の一覧は、CLHS の索引から作成した生成ファイル `src/runtime/cl_symbols.zig` で持つ。作成時に Web にアクセスするため、Phase 05 の着手時に許可を得る。HyperSpec の本文は転載しない。

### 8.4 Reader と印字の大文字小文字

- 既定の `readtable-case` は `:upcase`、`*print-case*` は `:upcase` とする。
- エスケープ（`|...|`、`\`）、パッケージ修飾、`#:`、キーワードを Phase 03〜05 で実装する。

### 8.5 条件付きの読み込みと、読み込み時の評価（レビュー #23）

| 機能 | 扱い | 時期 |
|---|---|---|
| `#+` / `#-` | `*features*` に従う。読み飛ばす枝は `*read-suppress*` を真にして読む（存在しないパッケージ修飾や、読めない数の表記があってもエラーにしない。CLHS 2.4.8.17、`*read-suppress*`） | Phase 04 |
| `*features*` | 起動時に `:zilisp`、`:common-lisp`、`:ansi-cl`（※名前は CLHS の慣例を確認して決める）、OS・CPU を表すキーワードを入れる。**クロスビルド（§16.2）では、ビルドする PC ではなく、ターゲットの OS・CPU を表す `*features*` で読む** | Phase 04、Phase 36 |
| `#.` | `*read-eval*` が真のときだけ評価する。偽のときは `reader-error` を通知する（CLHS `*read-eval*`） | Phase 24 |
| `*read-eval*` の既定値 | 真（CLHS の既定値）。ただし、教材の自動収集（§12）では偽にして読む | Phase 02、Phase 24 |

---

## 9. Condition / restart の実行時構造

### 9.1 condition 型

- **Phase 25 の表し方**（2026-11-05 決定）：condition と restart は `record`（ObjKind。クラスの記述と、スロットの値の simple-vector を持つ。`src/values/object.zig`・`src/primitives/conditions.zig`）で表す。CLOS（Phase 27）ができたら condition-class の `instance` にまとめる（Phase 27 の rack と直接配置の比較の結論を、先に決めないため）。
- クラスの記述は Lisp で作る simple-vector：`#(名前 CPL 直接の上位 スロット report 既定の initarg 直接のスロット)`。クラスの名前のシンボルの属性 `zl-sys::%class` に置く。Zig が読むのは位置 0（名前。印字）と位置 1（CPL。`typep`）だけ。スロットは `(名前 initarg のリスト initform の関数)` のリストで、上位のクラスのスロットを含む（値のベクタはこの順）。
- CPL は、深さ優先・左から右に並べ、重なりは最後のものを残す（CLHS 4.3.5 の計算ではないが、標準の condition の階層の菱形（`reader-error`）では同じ結果になる。CLOS の Phase で CLHS の計算にする）。
- 標準の condition 型の階層は、`src/lisp/boot.lisp` の `define-condition` で作る（ブートストラップ時に Zig の表から作る予定を変えた）。Zig で見つけたエラーのうち説明の文を持つものには、Zilisp の型を使う（`zl-sys::simple-program-error`・`simple-control-error`・`simple-parse-error`・`simple-reader-error`・`simple-package-error`・`simple-stream-error`・`simple-end-of-file`・`simple-file-error`・`simple-storage-condition`。SBCL の `SB-INT:SIMPLE-PROGRAM-ERROR` などに当たる）。未実装の機能は `zilisp:unimplemented`（`simple-condition` と `serious-condition` の下位。**`error` の下位にしない**：`ignore-errors`・`(handler-case … (error …))` が未実装を黙って受け止めないように。基本設計 §3.1。2026-11-05 の決定）。COMMON-LISP パッケージの未実装の関数（未実装の印のあるシンボル）と、値のない CL の特殊変数も、handler には `zilisp:unimplemented` として通知する（トップレベルの報告は今までどおり undefined-function・unbound-variable の文面）。
- `define-condition` は、スロットの `:initarg`・`:initform`・`:reader`・`:writer`・`:accessor`（`:type`・`:documentation`・`:allocation` は受け付けて使わない）、オプションの `:report`（文字列・関数の名前・lambda 式）・`:default-initargs`・`:documentation` を扱う。`make-condition` は、initarg、既定の initarg、initform の順に値を決める。値のないスロットを読むと `unbound-slot`。
- **report の文面は SBCL 2.6.7 と同じ**（2026-11-05 決定）：`type-error` は `~@<The value ~@:_~2@T~S ~@:_is not of type ~@:_~2@T~S~:@>`、`arithmetic-error` は `arithmetic error ~S signalled` と、演算があれば `Operation was (…).`、`undefined-function` はパッケージ付きの名前（`*package*` を KEYWORD に束縛して印字。SBCL の `print-symbol-with-prefix`）、report のない型は `Condition ~S was signalled.`（`*package*` は COMMON-LISP）など。印字（`*print-escape*` が真）も SBCL と同じ形：`#<SIMPLE-ERROR "制御文字列" {アドレス}>`、`#<TYPE-ERROR expected-type: 型 datum: 値>`、`#<UNBOUND-VARIABLE 名前 {アドレス}>`、`#<型 {アドレス}>`。`*print-readably*` なら `print-not-readable`。
- 印字は Lisp の `zl-sys::%print-record` が行う。Zig の印字の入口（pprint の `outputUgly`。pretty でないときも、condition・restart は pretty printer の経路に回す：`streams.emitPrinted`・`printTo`・`format` の `printed`）がそれを呼ぶ。Phase 26 から、condition・restart を中に含むリスト・ベクタも、`*print-pretty*` が NIL のときに pretty printer の経路に回す（`streams.hasLispPrinted`。§10.5）ので、リストの中の condition も SBCL と同じ形で印字する（Phase 25 では Zig の既定の形 `#<型 {アドレス}>` だった）。
- **Zig で見つけたエラーの condition**：エラーの種類（`ErrorKind`）から型を決める（`zl-sys::%zig-condition`）。type-error（説明がなく期待する型があるとき）・unbound-variable・undefined-function・division-by-zero（`:operation` と `:operands`。0 除算の箇所が `expected` に `(演算 被演算子…)` を渡す。SBCL と同じく `floor`・`mod` なども演算は `/`）・floating-point-overflow などは、値を持つ標準の型で、report は SBCL の文面。そのほかは上の Zilisp の型で、report は今までの説明の文（日本語）と値。

### 9.2 handler

- **handler のスタックは特殊変数 `zl-sys::*handler-clusters*` で表す**（2026-11-05 変更。Thread のスタックと VM の `HANDLER_PUSH` などの命令は作らない）。値は cluster のリスト（新しい順）で、cluster は `((型 . 関数) …)`。`handler-bind` が新しい cluster を先頭に足したリストを動的に束縛する。非局所脱出で抜けると、動的束縛と一緒に戻る（§6.4 の「深さで戻す」と同じ仕組み）。VM とネイティブコードは同じマクロの展開を使うので、どちらにも特別な扱いは要らない。
- `signal` は新しい順に cluster を走査し、`typep` が真の handler を呼ぶ。呼ぶ間は `*handler-clusters*` を、その cluster より外側の cluster のリストに束縛する（CLHS 9.1.4.1）。
- handler は通知した場所の動的環境で実行する（巻き戻さない）。
- `handler-case`（`:no-error` も）と `ignore-errors` は、`handler-bind` ＋ `block`／`tagbody`／`go` のマクロとして boot.lisp に書く。
- **Zig で見つけたエラー**（§6.6 の `th.signal`）：handler か restart が1つでもあるか、`*debugger-hook*` があれば、`zl-sys::%signal-zig-error` を呼んで condition を作り、handler に通知する（受け止められなければ `*debugger-hook*` も呼ぶ）。受け止められなければ、使える restart の説明を返し、Zig の側でエラーを記録する。どれもなければ Lisp を呼ばない（確保もしない。今までと同じ速さ）。
  - VM の命令の途中のエラー（未束縛の変数の `load_special` など）では、`vm.sp` を書き戻していないことがある。handler の実行が今のフレームの計算の途中の値を上書きしないように、一番上のフレームが使いうる深さ（`base + nlocals + max_stack`）まで `vm.sp` を上げてから呼び、後で戻す。その間の古い値も GC のルートとして走査されるが、`findObject` で確保済みのオブジェクトかを確かめてからマークするので安全（余分に残すことがあるだけ）。
  - handler は Lisp のコードなので、`th.signal` の中で GC が起きる。Zig のローカル変数の値は、ネイティブのスタックの保守的な走査で守られる。`th.signal` を呼んだ後で処理を続ける箇所（`return th.signal(…)` の形でない約 30 か所）は、どれもすぐに失敗を返すことを確かめた。印字・読み取りの途中の状態（`pp_circle`・`pp_level`・`read_builder`）は handler に引き継がない。handler を呼ぶ入れ子は 32 段まで（`max_signal_depth`。処理系の誤りで同じエラーが起き続けないように）。
  - **スタックの溢れは handler に通知しない**（`th.stackExhausted`。VM の値スタックとフレーム、ネイティブのスタック、Zig の関数の入れ子、動的束縛と制御スタック）。handler を動かす予備の領域がないため（Phase 25 の制限。SBCL は予備の領域を持つ）。

### 9.3 restart

- restart のスタックは特殊変数 `zl-sys::*restart-clusters*`（restart のリストのリスト。新しい順）で、`restart-bind` が動的に束縛する。restart は record で、スロットは {名前、関数、report の関数、interactive の関数、test の関数、関連付けた condition}。
- `restart-case` は `restart-bind` ＋ `block`／`tagbody`／`go` のマクロ。フォームが `error`・`cerror`・`signal`・`warn` の呼び出しなら、通知する condition を先に作り、`with-condition-restarts` でその condition に restart を関連付ける（CLHS restart-case）。関連付けた restart は、その condition を指定したときだけ見える（CLHS 9.1.4.2.4）。
- 関数とマクロ：`restart-bind`・`restart-case`・`with-simple-restart`・`with-condition-restarts`・`compute-restarts`・`find-restart`・`invoke-restart`・`invoke-restart-interactively`・`restart-name`、標準の restart の関数 `abort`・`muffle-warning`（restart がなければ control-error）・`continue`・`store-value`・`use-value`（なければ NIL）。
- toplevel の restart は作らない（SBCL の `--script` には RETRY・CONTINUE・ABORT がある。`compute-restarts` の結果はそれだけ違う）。

### 9.4 デバッガ（D-4）

| 実行形態 | 処理されなかった `error` への動作 |
|---|---|
| REPL | condition の型・report・発生位置、使える restart の一覧（番号・名前・report）、呼び出しの履歴（新しい順、16 件まで）を表示する（Phase 25 から。それまでは型・説明・発生位置と呼び出しの履歴）。番号の入力で `invoke-restart` を実行する操作は後の Phase で加える（2026-11-05 決定） |
| `--script` / ソース実行 / ビルドした実行ファイル | 標準エラー出力に condition と restart の一覧（あれば）と呼び出しの履歴を出力し、**終了コード 1** で終了する |

- `invoke-debugger` は `*debugger-hook*` を（それを NIL に束縛して）呼び、戻ってきたらトップレベルへ戻る（`zl-sys::%unhandled-condition`）。Zig で見つけたエラーでも、受け止められなければ `*debugger-hook*` を呼ぶ（§9.2）。呼び出しの履歴からは、`error`・`invoke-debugger` など condition を通知する標準ライブラリの関数のフレームを除く。
- 処理されなかった `warning` は `*error-output*` に `WARNING: report` と書いて続行する（SBCL と同じ）。`muffle-warning` の restart で止められる。

---

## 10. CLOS：クラス表、標準メソッド結合、キャッシュ失効

### 10.1 クラス

```zig
pub const Class = struct {
    header: ObjHeader,
    name: Value,
    metaclass: enum { standard, structure, built_in, condition },
    direct_superclasses: Value, direct_slots: Value, default_initargs: Value,
    cpl: Value,              // CLHS 4.3.5「Determining the Class Precedence List」のアルゴリズムで計算する
    layout: Value,           // 現在の layout
    finalized: bool,
    direct_subclasses: Value,
};
```

- `find-class` 用の表（シンボル → クラス）を `Runtime.classes` に持つ。
- 組み込み型のクラスと CPL は CLHS の記載どおりに Zig の表で定義する（例：`null` → `(null symbol list sequence t)`）。`class-of` は、Value のタグと ObjKind から表を引いて求める。
- CPL に矛盾がある場合は、`defclass` の時点でエラーにする。

### 10.2 インスタンスと再定義

**クラスの番号（stamp）**（S1。SICL の方式：`Specification/chap-object-system.tex` 44〜49行目）
- クラスには、作成した時点と変更した時点で**新しい番号**を振る。番号は 0 から順に振り、**古い番号は再利用しない**。
- クラスを再定義した場合（スロット・上位クラスの変更）は、そのクラスと、**すべてのサブクラス**に新しい番号を振る（CPL やスロット配置が変わり得るため）。
- 組み込みクラスと構造体のクラスも番号を持つ。`class-of` と同じ表引きで、任意の Value から番号を求められる。

**インスタンスの表現**（S2。SICL の方式：`Specification/chap-data-representation.tex` 97〜190行目）

```text
instance                      rack
┌──────────────┐          ┌──────────────────┐
│ ヘッダ         │          │ ヘッダ             │
│ class        │          │ stamp（作成時の番号）│
│ rack ────────┼────────▶ │ layout           │
└──────────────┘          │ スロット0 … n      │
                          └──────────────────┘
```

- インスタンス本体は class と rack へのポインタだけを持つ。**ローカルスロット**（`:allocation :instance`）の値は rack に置く。**共有スロット**（`:allocation :class`）の値はクラスに置き、rack には置かない。未初期化のスロットは unbound とする。
- インスタンス本体は動かさないので、rack を差し替えても、オブジェクトの同一性と、オブジェクトを動かさない GC の前提が保たれる。
- **代償**：スロットを読むたびに、rack への読み込みが1回増える。**Phase 27 で、スロットをインスタンス本体に直接置く方式（再定義のときは転送用のポインタを置く）と速さを比べ、速い方を採用する。**

**クラスの再定義と、インスタンスの更新**（レビュー #7。CLHS 4.3.6「Redefining Classes」、`make-instances-obsolete`、`update-instance-for-redefined-class`）

- インスタンスの rack の stamp が、クラスの現在の番号と違えば、そのインスタンスは古い（obsolete）。古いかどうかの判定は、§10.4 の手順により、ディスパッチ・スロットへのアクセスのたびに必ず行われる。
- 古いインスタンスにアクセスした時点で、**標準の手順**で更新する。
  1. 新しい layout の rack を作る。
  2. 新旧どちらのクラスにもローカルスロットとして定義されているスロットは、値を引き継ぐ。
  3. 追加されたローカルスロットの一覧、破棄されたローカルスロット（共有スロットに変わったものを含む）と値の属性リストを求める。
  4. rack を差し替えたうえで、`update-instance-for-redefined-class` を、インスタンス・追加されたスロット・破棄されたスロット・属性リストを引数として呼ぶ。その既定のメソッドは `shared-initialize` で、追加されたスロットを initform で初期化する。
- **`change-class`**（CLHS `change-class`、`update-instance-for-different-class`）：元のインスタンスの複製を作ってから、新しいクラスの rack に差し替え、両方に共通のローカルスロットの値を引き継ぎ、`update-instance-for-different-class` を、複製・インスタンス・初期化引数を引数として呼ぶ。
- 利用者がこれらの総称関数にメソッドを定義した場合は、そのメソッドが呼ばれる（1.0 で対応する）。
- 1.0 で対応しない再定義（メタクラスの変更など）は、**意味を変えて実行せず、エラーを通知する**（基本設計 §3.1：黙って別の結果を返さない）。

### 10.3 総称関数とメソッド

- メソッド関数は、隠し引数 `%next-methods` / `%args` を持つ関数として生成する。`call-next-method` と `next-method-p` はこれを参照する。
- **`call-next-method` の引数**（agy #5。CLHS `call-next-method`）：引数なしで呼んだ場合は、現在のメソッドが受け取った引数（`%args`）を渡す。引数を渡して呼んだ場合は、その引数を、以降のすべてのメソッド（`:around` から呼んだ場合は、残りの `:around`、`:before`、primary、`:after` のすべて）に渡す。新しい引数に対する適用できるメソッドの並びが、元の引数に対するものと異なる場合はエラーを通知する（CLHS の規定。`safety` 0 では検査を省略してよい）。
- **標準メソッド結合**（レビュー #5。CLHS 7.6.6.2「Standard Method Combination」）
  1. **適用できるメソッドが1つもない**場合は、`no-applicable-method` を呼ぶ。
  2. **適用できるメソッドはあるが、適用できる primary メソッドがない**場合は、エラーを通知する。適用できる `:around` メソッドがある場合も同じである（CLHS 7.6.6.2：「if there is an applicable method but no applicable primary method, an error is signaled」。SBCL 2.6.7 でも、`:around` だけの総称関数の呼び出しは `NO-PRIMARY-METHOD-ERROR` になることを確認した）。
  3. `:around` メソッドがある場合は、最も特定的な `:around` を呼ぶ。`call-next-method` は次の `:around` を呼び、最後の `:around` から呼んだ場合は、下記 4〜6 をまとめた処理を呼ぶ。`:around` の戻り値が、総称関数の戻り値になる。
  4. すべての `:before` メソッドを、最も特定的なものから順に呼ぶ。戻り値は使わない。`:before` の中で `call-next-method` を使うとエラーを通知する（CLHS 7.6.6.2）。
  5. 最も特定的な primary メソッドを呼ぶ。`call-next-method` は次に特定的な primary を呼ぶ（primary は**自動では全部呼ばれず**、`call-next-method` による連鎖で呼ばれる）。次の primary がないときに `call-next-method` を呼ぶと、`no-next-method` を呼ぶ。最も特定的な primary の**全値**が、4〜6 の処理の戻り値になる。
  6. `:after` メソッドがある場合は、5 の**全値を退避**してから（§6.3）、すべての `:after` メソッドを、最も特定的でないものから順に呼ぶ。`:after` の戻り値は使わない。終わったら退避した全値を返す（agy #5）。`:after` の中で `call-next-method` を使うとエラーを通知する（CLHS 7.6.6.2。agy #5）。
  - `:before`・`:after` の中では、`next-method-p` も使えないようにする（隠し引数を渡さない）。
- 特定性は、各引数のクラスの CPL での位置を、引数の優先順序（既定は左から右）で比較して決める。`eql` 特定子はどのクラスよりも特定的とする。
- `define-method-combination` と `standard` 以外のメソッド結合は 1.0 では未対応とし、指定時にエラーにする。

### 10.4 ディスパッチのキャッシュと失効

- 総称関数ごとに「特定子の位置にある引数の**番号（stamp）の組** → 有効メソッド関数」のキャッシュを持つ（S1）。呼び出しの高速経路は、引数の番号を取り出して**整数の比較**でキャッシュを引くだけにする。`eql` 特定子がある位置では、値も比較する。
- どの引数の位置が特定子として使われているか（specializer profile）を総称関数ごとに記録し、使われていない位置の引数は番号を取り出さない（SICL の `Code/CLOS/compute-discriminating-function-support.lisp` 24〜49行目）。
- 失効の規則
  - `add-method` / `remove-method`：その総称関数のキャッシュを消去する。
  - クラスの定義・再定義：**全体のキャッシュは消去しない**。再定義したクラスとそのサブクラスには新しい番号を振り、**古い番号を含むキャッシュ項目だけを、その時点で取り除く**（レビュー #6）。
    - 古いインスタンスの rack には古い番号が残っている。古い番号の項目を残したままにすると、古いインスタンスがその項目に一致し、更新されないまま古い有効メソッドで処理されてしまう。このため、項目は「いっぱいになったら消す」のではなく、再定義の時点で必ず取り除く。
    - 取り除く対象を絞るため、クラスごとに「そのクラスの番号をキャッシュに含んでいる総称関数とアクセサ」の一覧を持つ。再定義では、その一覧の総称関数とアクセサのキャッシュだけを調べる。
  - 古い番号の項目がなくなるので、古いインスタンスは必ずキャッシュに一致しない。一致しなかった場合の遅い経路では、**まずインスタンスが古いかを調べ**、古ければ §10.2 の手順で更新してから引き直す。古い番号で新しいキャッシュ項目を作ることはない。
  - これは SICL の方式（`Specification/chap-data-representation.tex` 180〜186行目：古いインスタンスは判別に失敗して更新される）に対応する。
- アクセサ（`:reader`・`:accessor`）は、**番号ごとに**スロットの添字をキャッシュし、一致すれば rack から添字で直接読む。アクセサのキャッシュも、上記と同じ規則で古い番号の項目を取り除く。
- **後の段階の高速化（S3）**：呼び出しの記録から、番号を比べて分岐するコード（判別用のコード）を生成し、総称関数の入口に置く（SICL の discriminating automaton：`Code/CLOS/discriminating-automaton.lisp`、`compute-discriminating-function-support-c.lisp` 11〜80行目）。ネイティブバックエンドでは、この分岐を機械語にする。一致しなかった場合は、汎用のディスパッチに戻る。

### 10.5 defstruct

- `structure-class` として定義する。スロットは固定配列、アクセサは通常の関数でインライン化の対象とする。
- `:include`（単一継承）、`:constructor`（BOA を含む）、`:copier`、`:predicate`、`:conc-name`、`:print-object` / `:print-function` をサポートする。
- スロットに `:type` が指定された場合は、ネイティブバックエンドの型推論に使う。

**Phase 26 の実装**（2026-11-10 決定：表し方は専用のオブジェクト、範囲は上の項目と周辺の標準機能、スロットの `:type` は検査する）

- **表し方**：`ObjKind.structure`（`object.Structure`。`src/values/object.zig`）。ヘッダ・クラスの記述・スロットの値を 1 つのオブジェクトに並べる（`header.len` がスロットの数。condition の `record` のように、値のベクタを別に持たない）。構造体は互換でない再定義をしないので、Phase 27 の rack と直接配置の比較（§10.2）を待たずに直接配置にした。CLOS の `structure-class` にまとめるのは Phase 27。
- **クラスの記述**は Lisp で作る simple-vector：`#(名前 CPL :include の名前 スロット 標準の構築子の名前 印字の関数 読み取り用の構築子)`。condition と同じく、名前のシンボルの属性 `zl-sys::%class` に置く（Zig が読むのは位置 0・1 と、エラーの報告の印字のための位置 3）。CPL は自身を含む上位の構造体の名前のリストで、最後は `structure-object`。スロットは `(名前 initform 型 read-only アクセサの名前)` のリスト（`:include` した構造体のスロットを先頭に含む。値の順）。
- **`defstruct` マクロ**（`src/lisp/boot.lisp` の `zl-sys::%expand-defstruct`）の展開：
  - `(eval-when (:compile-toplevel :load-toplevel :execute) (zl-sys::%define-structure …))`：クラスの記述を置く。コンパイル時にも実行するのは、後ろの `defstruct` の `:include` が展開のときに元の構造体のスロットを読むため。**`:include` する構造体は、ファイルをコンパイルする場合（ネイティブ）はトップレベルで定義しておく**（CLHS 3.2.3.1。フォームを 1 つずつ評価する `--script`・REPL では、どこで定義してもよい）。
  - アクセサ：`(defun 名前 (object) (zl-sys::%structure-ref object '構造体 位置))` と、read-only でなければ `(defun (setf 名前) (value object) (zl-sys::%structure-set object '構造体 位置 value))`。`:include` した構造体のアクセサと同じ名前になるものは定義し直さない。
  - 構築子：キーワードの引数のもの（引数の変数は gensym。initform はスロットの名前の変数を見ない）と、引数の並びを指定したもの（BOA。CLHS 3.4.6：既定値のない `&optional`・`&key` の変数はスロットの initform を既定値にし、並びにないスロットは initform の値）。どちらも `(zl-sys::%make-structure '構造体 値…)` を呼ぶ。
  - 複製（`copy-structure` を呼び、その構造体でなければ type-error）、述語（`zl-sys::%structure-p`）。
  - オプション：`:conc-name`・`:constructor`（複数可、`nil` でなし）・`:copier`・`:predicate`・`:include`（スロットの既定値・型・read-only の書き換え）・`:print-function`・`:print-object`（引数なしは `#S(…)` の形に戻す）。文書の文字列は読み飛ばす。
  - **`(:type list)`・`(:type vector)`・`:named`・`:initial-offset` は `zilisp:unimplemented`**（教材で使われていない。別のタスク）。`print-object` のメソッドは Phase 28。
- **Zig の側**（`src/primitives/structures.zig`）：`zl-sys::%make-structure`・`%structure-ref`・`%structure-set`（名前の構造体か、それを `:include` した構造体でなければ type-error。同じ名前で定義し直した構造体の古いインスタンスは、スロットの数の範囲の外なら type-error）・`%structure-p`・`%structure-class-of`・`%check-slot-type`・`%print-depth`・`%print-descend`、CL の `copy-structure`。GC は class とスロットを走査する。
- **スロットの `:type`**：構築子と `setf` で `typep` により検査し、合わなければ type-error（SBCL 2.6.7 と同じ動作）。`typep` がどの値にもエラーなしで判定できる型だけを検査する（`types.slotCheckable`）：まだ定義していない型（後で定義する構造体など）、特殊化した配列の要素の型、`(complex 型)`、`satisfies` を含む型は検査しない（定義した後は検査する）。type-error の expected-type は書いた型指定子そのまま（SBCL は `(integer 0 10)` を `(MOD 11)` のように正規化する）。ネイティブバックエンドの型推論には、まだ使っていない。
- **型**：`typep` は、構造体の名前（`:include` した構造体の名前も真）と `structure-object` を判定する（クラスの CPL。condition と同じ `types.recordTypep`）。
- **`equalp`**：クラスが同じで、スロットがすべて `equalp` なら真（`equal` は `eq`）。`equalp` のハッシュ表のハッシュ値は、クラスの名前とスロット（先頭の 16 個、深さ 4 まで）から求める。
- **印字**：SBCL 2.6.7 の `default-structure-print` と同じ形 `#S(名前 :スロット 値 …)`（`zl-sys::%print-structure`・`%default-structure-print`。pretty のときは `pprint-logical-block` で、`:linear`・`:miser` の改行の位置も同じ。`*print-level*`・`*print-length*`・`*print-circle*`・`*print-readably*` に従う。スロットのない構造体は `#S(名前)` で、深さに数えない）。`:print-function` の 3 つ目の引数は今の印字の深さ。
  - Zig の印字の入口は、構造体を condition と同じ `zl-sys::%print-record` に渡す。**`*print-pretty*` が NIL のときも、リスト・ベクタの中に構造体か condition・restart があれば、pretty printer の経路（要素ごとに `outputObject` を通る）で書く**（`streams.hasLispPrinted` が先に走査する）。
  - Lisp の印字の関数を通らない場合（トップレベルのエラーの報告の中の値）は、Zig の印字が `#S(…)` の形で書く（`:print-function` などは使わない）。
- **`#S(名前 スロット 値 …)` の読み取り**（CLHS 2.4.8.13。`reader.zig` の `.sharp_s` → `ValueBuilder.structure` → `zl-sys::%read-structure`）：スロットの名前をキーワードにして、標準の構築子（キーワードの引数の構築子。名前を変えていてもよい）を呼ぶ。構造体がない・構築子がない・形の誤りは reader-error。
  - **構造体のリテラルは、定義を実行した後に読むときだけ使える**（`--script`・REPL・`read`）。ネイティブの定数は起動時にテキストから読み直すので、構造体の定数は書き出せず、コンパイル時にエラーにする（§14 の `make-load-form` の扱いと同じ）。
- **`fboundp`** は `(setf 名前)` も受け取る（CLHS の関数の名前。構造体のアクセサの確認に使う）。
- **SBCL 2.6.7 との違い**（`tests/differential/impl-dependent.toml`）：初期値のない `&aux` のスロットは NIL（SBCL は未束縛の印 `#<unbound>`）、type-error の expected-type の正規化、`(:type …)` などの未実装、構造体のリテラルをコンパイルできないこと。
- **試験**：言語試験 `defstruct.lisp`・`defstruct-read.lisp`（`#S` の読み取りと `#n#`）・`defstruct-review.lisp`（Codex のレビューで足した例）（SBCL 2.6.7 と同じ出力。GC stress の版とネイティブでも同じ。GC stress の実行に時間がかかるので 3 つに分けた）、単体テスト（未実装のオプション、`#S`、定義し直し、後から定義する型、GC stress）。

---

## 11. ブートストラップ順序と標準ライブラリのロード

### 11.1 起動時の手順

1. ヒープ（ページ表）とスレッドの状態を初期化し、スタックの先頭位置を記録する。
2. NIL シンボルの実体を作り、`CL`、`KEYWORD`、`CL-USER`、`ZILISP`、`ZILISP-SYSTEM` を作る。
3. CL の 978 個のシンボルを intern し、定数と特殊変数を設定する。未実装のものに `unimplemented` を付ける。
4. Zig のプリミティブを登録する（`src/primitives/` の登録表）。
5. 組み込みクラスと condition のクラス階層を作る。
6. Zig で書いたブートストラップ用マクロを登録する：`defmacro`、`defun`、`lambda`、`zl-sys:quasiquote`、`setf`（最小版）、`in-package`（最小版）。
7. 標準ライブラリを初期化する（§11.3）。
8. `*package*` を `CL-USER` にして、REPL・スクリプト・エントリ関数を開始する。

### 11.2 Lisp で書く標準ライブラリのロード順

**Phase 15 の時点**：`src/lisp/boot.lisp`（実行ファイルに埋め込む）を、スレッドを作るたびに VM で読み込む（`src/compiler/boot.zig`）。中身は Zig で書いた `defmacro`・`defun` の上に作る標準マクロ（`when`・`unless`・`cond`・`and`・`or`・`case`・`prog1`・`prog2`、場所が変数の場合の `incf`・`decf`・`push`・`pop`）。読み込みの間は、CL パッケージのシンボルに定義してよい（`Runtime.booting`）。起動時間の増加は約 1 ms（ReleaseFast、x86_64-windows：`zilisp --eval nil` が 6.1 ms から 7.1 ms）。標準ライブラリが大きくなったら、§11.3 の2段階ビルド（ネイティブにして組み込む）に移る。

**フェーズごとの起動時間（2026-11-03 計測）**：各フェーズのコミットを ReleaseFast でビルドし、`zilisp --eval nil` を 31 回動かした中央値（x86_64-windows）。何もしない空の Zig のプログラムを同じ方法で測ると 4.08 ms。

| フェーズ | boot.lisp（空でない行） | 中央値 | 実行ファイルの大きさ |
|---|---|---|---|
| P14 | 0 | 5.80 ms | 1.27 MB |
| P15 | 93 | 6.33 ms | 1.31 MB |
| P16 | 218 | 6.65 ms | 1.35 MB |
| P17 | 246 | 6.88 ms | 1.37 MB |
| P18 | 249 | 7.08 ms | 1.42 MB |
| P19 | 698 | 7.95 ms | 1.48 MB |
| P20 | 708 | 8.21 ms | 1.60 MB |
| P21 | 949 | 8.80 ms | 1.72 MB |
| P21.5 | 949 | 8.82 ms | 1.79 MB |
| P21.6 | 949 | 8.74 ms | 1.79 MB |
| P22 | 1016 | 9.08 ms | 1.85 MB |
| P23 | 1061 | 9.47 ms | 1.97 MB |
| P25 | 1934 | 13.55 ms | 2.35 MB |

- boot.lisp の空でない行が 100 行増えるごとに、約 0.3 ms 延びる。P21 の内訳は、空のプログラムでもかかる起動が約 4.1 ms、boot.lisp より前の準備が約 1.7 ms、boot.lisp の読み込みが約 3.0 ms。
- **決まり（2026-11-03 決定）**：各フェーズの終わりに同じ方法で起動時間を測り、CHANGELOG とこの表に記録する。**20 ms** を超えたら、§11.3 の2段階ビルドを前倒しにする。

| 順序 | ファイル（`lisp/bootstrap/`） | 内容 |
|---|---|---|
| 00 | `00-base.lisp` | `when` `unless` `cond` `and` `or` `prog1` `psetq` `do` `dotimes` `dolist` `case` `typecase` 等 |
| 10 | `10-setf.lisp` | `defsetf`、`define-setf-expander`、`get-setf-expansion`、`push` `pop` `incf` 等 |
| 20 | `20-list-seq.lisp` | リスト・sequence の関数のうち Lisp で書くもの |
| 30 | `30-loop.lisp` | `loop` マクロ（**独自実装**。D-3。速いコードに展開するよう、変数に型宣言を付ける） |
| 40 | `40-conditions.lisp` | `handler-case` `ignore-errors` `restart-case` `check-type` `assert` 等 |
| 50 | `50-defstruct.lisp` | `defstruct` |
| 60 | `60-clos.lisp` | `defclass` `defgeneric` `defmethod` `with-slots` 等（ディスパッチの中核は Zig） |
| 70 | `70-package.lisp` | `defpackage`、`do-symbols` 系 |
| 80 | `80-io.lisp` | `with-open-file` `with-output-to-string` 等 |

- `print`、`read`、`format` の中核は Zig で実装する。

**Phase 19 の時点**：反復の教材（Level 6）を通すため、上の表の 00・20・30 の一部と、`format` の最小版を前倒しで実装した（2026-11-02 決定）。
- `src/lisp/boot.lisp` の反復の節：`psetq`、`dolist`・`dotimes`（本体は暗黙の tagbody。結果は、dolist は変数を NIL に、dotimes は変数を回数にして評価する：CLHS）、`do`・`do*`、`mapcar`・`mapc`・`mapcan`・`nconc`・`reduce`（`:key`・`:from-end`・`:start`・`:end`・`:initial-value`）、`loop`。
- **loop**（独自実装）：`named`、`with`、`for`・`as`（`from`・`upfrom`・`downfrom`・`to`・`upto`・`below`・`downto`・`above`・`by`、`in`・`on`（`by`）、`= … then`、`across`、`being the hash-keys`・`hash-values`（`using`））、`repeat`、`initially`・`finally`、`do`、集める句（`collect`・`append`・`nconc`・`sum`・`count`・`maximize`・`minimize`、`into`）、`while`・`until`、`always`・`never`・`thereis`、`return`、`when`・`if`・`unless`（`and`・`else`・`end`・`it`）、`loop-finish`、変数の分解。展開は `(block 名前 (let* (束縛...) (tagbody 前処理 最初の検査 本体のタグ 本体 更新と検査 (go 本体のタグ) 終わりのタグ 後処理 (return-from 名前 既定の値))))`。for の句は、句の順に「更新・検査・代入」を行う（SBCL 2.6.7 と同じ順）。always・never・thereis は後処理を実行せずに返す（CLHS 6.1.4）。終わりのタグは `zl-sys::%loop-end`（`loop-finish` はそこへ go する。入れ子の loop では内側のタグが見える）。未対応の句（for・with の `and` による並列の束縛、`being` の `elements`・`symbols` など）は明示的なエラーにする。変数への型宣言はまだ付けない（速さの改善は後の Phase）。
- Zig で書いた関数：`evenp`・`oddp`・`zerop`・`plusp`・`minusp`・`max`・`min`・`abs`・`mod`・`rem`、`reverse`・`nreverse`・`copy-list`・`last`・`endp`、`symbol-name`・`string=`・`string-upcase`・`string-downcase`・`char=`、`princ`、`format` の最小版。大文字・小文字の変換は ASCII の文字だけ（Reader と同じ。SBCL 2.6.7 は Unicode の文字も変換する）。
- **format の最小版**：出力先は `T`（標準出力）と `NIL`（文字列を返す）。指示子は `~A`・`~S`・`~D`・`~%`・`~&`・`~~` と、`~` に続く改行。引数・修飾子の付いた指示子（`~5D`、`~:A`）とほかの指示子、ほかの出力先は明示的なエラー（Phase 24 で全体を実装する）。`~&` のため、スレッドは標準出力が行の先頭にいるかを覚える（`Thread.line_start`）。引数が足りないときのエラーは `simple-error`（SBCL 2.6.7 は処理系固有の `format-error`）。
- 結果：Level 6 の 48 ブロックは、一致 41、両方ともエラー 7（Zilisp だけがエラーのものはない）。教材のブロック全体の一致は 244 から 347 に。

**Phase 21 の時点**：文字・文字列・列・リスト・集合の関数（上の表の 20 の行）。`:test`・`:key` などを取る関数は、速さのため Zig で書き、残りを `boot.lisp` に書く。
- **Zig**（`src/primitives/seqfns.zig`）：`member`・`assoc`・`rassoc`・`find`・`position`・`count`・`remove`・`delete`・`substitute`・`nsubstitute`（それぞれ `-if`・`-if-not` も）、`remove-duplicates`・`delete-duplicates`、`sort`・`stable-sort`（どちらも安定なマージソート。リストは car を並べ替え、ベクタはその場で並べ替える）、`search`・`mismatch`、`elt`（と setf）・`subseq`・`fill`・`replace`、`concatenate`・`coerce`・`make-sequence`・`map`・`map-into`・`some`・`every`・`notany`・`notevery`、`make-list`・`list-length`（循環リストは NIL）。`:test`・`:test-not` が `eq`・`eql`・`equal` なら関数を呼ばずに比べ、キーワードのない `member` は速い道を通る。`delete` などは新しい列を返す（CLHS 17.2 で許される）。`:test`・`:key` の関数は要素の順に呼ぶ（`:from-end` でも。CLHS は順序を決めていない）。要素を一時的に Zig の配列に置くことがあるが、元の列から届くので GC に回収されない（結果を書き戻すのは最後）。
- **結果の型**（`concatenate`・`coerce`・`make-sequence`・`map`・`merge`）：`list`（と `cons`・`null`）、`vector`・`simple-vector`・`array`・`simple-array`、`string`・`simple-string`・`base-string`・`simple-base-string`、`(vector character)`・`(simple-array character (*))` などの複合の型指定。型指定の長さと、`cons`（要素が1つ以上）・`null`（要素がない）・`array` の型指定の次元の数（`(array t (2 3))` は列の型ではない）を確かめ、合わなければ SBCL 2.6.7 と同じく `type-error`。それ以外の型は明示的なエラー。`map`・`map-into`・`some`・`every`・`notany`・`notevery` に渡すリストは真リストでなければならない（そうでなければ `type-error`）。`coerce` は `character`、浮動小数の型、`t`・`function`、数の型（`number`・`real`・`rational`・`integer`。その型の値ならそのまま返す）も扱う。
- **Zig**（`src/primitives/strings.zig`）：`characterp`・`char-code`・`code-char`（`char-code-limit` は #x110000）・`char-int`・`char-upcase`・`char-downcase`・`upper-case-p`・`lower-case-p`・`both-case-p`・`alpha-char-p`・`alphanumericp`・`digit-char-p`・`digit-char`・`graphic-char-p`・`standard-char-p`、`char=`・`char-equal` の仲間、`string`、`string=`・`string-equal` の仲間（結果は違う位置の添字）、`string-upcase`・`string-downcase`・`string-capitalize` と `nstring-` の形、`string-trim`・`string-left-trim`・`string-right-trim`、`make-string`、`parse-integer`（bignum も。`parse-error`、`:junk-allowed` なら NIL）。文字の種類と大文字・小文字は ASCII の文字だけ（SBCL 2.6.7 は Unicode。`tests/differential/impl-dependent.toml` に記録）。**Unicode への対応（2026-11-03 決定）**：Phase 21.5（tque #342）で、CL の文字の関数と、Reader・Printer の大文字・小文字の変換を、SBCL 2.6.7 と同じ Unicode 15.0.0 に従わせる。やり方は SBCL の CL の関数と同じ（一般カテゴリ、往復する 1 対 1 の単純な大文字・小文字の対応。表は、同梱する UCD のファイルから生成する。UCD のファイルは Unicode License v3）。実装は下の「Phase 21.5 の実装」。Unicode の文字の名前（`char-name`）と、SBCL の `sb-unicode` に当たる機能は範囲の外。エラーの種類 `parse_error` を加えた。
- **Lisp**（`src/lisp/boot.lisp`）：`identity`・`complement`・`constantly`、`acons`・`pairlis`・`copy-alist`・`copy-tree`・`revappend`・`nreconc`・`butlast`・`nbutlast`・`tailp`・`ldiff`、`mapl`・`maplist`・`mapcon`、`subst`・`subst-if`・`subst-if-not`・`nsubst`・`nsubst-if`・`nsubst-if-not`・`sublis`・`nsublis`（`n` の形は木の car・cdr を書き換える）・`tree-equal`（T か NIL を返す）、`adjoin`・`union`・`intersection`・`set-difference`・`set-exclusive-or`・`subsetp`（と `n` の形。引数は壊さない）。`butlast`・`nbutlast` はドット対で終わるリストも受け付ける、`merge`、マクロ `pushnew`・`remf`、場所 `elt`・`subseq`。集合の関数の結果の順序は SBCL 2.6.7 と同じ（`union` は短い方のリストを調べ、長い方の前に積む）。
- エラーは SBCL 2.6.7 と同じ：`:start`・`:end` の誤りと範囲外の `elt` は `type-error`（SBCL の `bounding-indices-bad-error`・`index-too-large-error` は `type-error` の一種）、添字の数の誤りは `simple-error`。
- 結果：Level 11 の 25 ブロックのうち 19 が一致し、6 は両方ともエラー（Zilisp だけがエラーのものは 0）。Level 7・Level 10 で Zilisp だけがエラーで残るのは `defstruct`（Phase 26）と `format` の指示子（Phase 24）。教材のブロックの一致は 362 から 421 に。
- 試験：SBCL 2.6.7 の結果と比べる139通り（GC stress でも実行。ネイティブでも実行：`sequence-cases.lisp`）、大きな列の GC stress、エラーの種類。言語試験 `sequences.lisp`（データ処理のサンプル。gc-stress 版も）。

**Phase 21.5 の実装（Unicode 15.0.0）**
- **データ**：`data/unicode/` に、UCD 15.0.0 の `UnicodeData.txt`・`SpecialCasing.txt`（SBCL 2.6.7 のタグから取り出したもの。unicode.org の `Public/15.0.0/ucd/` のファイルと SHA-256 が一致することを確認）と、Unicode License v3 の本文（`LICENSE.txt`）を置く。配布物（ZIP・tar.gz・インストーラー）には `LICENSE-UNICODE.txt` として入れる。
- **生成器**：`tools/gen_unicode/main.zig`（`zig build gen-unicode`）が `src/unicode/tables.zig` を作る（`std.zig.Ast` で整形し、`zig fmt` と同じ形で書き出す）。**表はコミットする**。ネイティブバックエンドは `src/lib.zig` を `zig build-exe -Mzilisp=src/lib.zig` で直接コンパイルするので、ビルドの途中で作る表は使えないため（2026-11-03 の決定「ビルドのときに生成する」から変更）。`zig build test` は、コミットした表が UCD から作ったものと同じかを確かめる（`--check`。改行の CRLF は同じとみなす）。Reader の照合の道具（reader-check）は、Reader だけのモジュールではなく `src/lib.zig` のモジュールを使うようにした（モジュールの根の外にある `src/unicode/` を読めないため）。
- **表**（合わせて約 70 KB）：文字の性質の2段の表（256 文字のページ。上段 4,352 バイト、下段 118 ページ 30,208 バイト。1 バイトに、英字（一般カテゴリ L*）、Nd、10進数字の値）と、大文字・小文字の表（64 文字のページ。上段 1,958 バイト、下段 65 ページで小文字・大文字の符号が各 4,160 個）。
- **作り方**は SBCL 2.6.7 の `tools-for-build/ucd.lisp` と同じ：`SpecialCasing.txt` の条件のない項目で `UnicodeData.txt` の単純な対応を上書きし、1 文字から 1 文字への対応で、行き来が往復するものだけを、大文字・小文字のある文字にする（2,708 字。ß の大文字のように複数の文字になるものは含めない）。
- **SBCL 2.6.7 との違い**：大文字でも小文字でもない4文字（U+01C5 ǅ・U+01C8・U+01CB・U+01F2。タイトルケース）は、大文字・小文字のない文字とする（CLHS 13.1.4.3）。SBCL は `both-case-p` が T、`char-upcase` が大文字を返し、`char-equal` が非対称になる（`(char-equal ǅ ǆ)` は T、`(char-equal ǆ ǅ)` は NIL）。ほかの文字は SBCL と同じなので、`char-equal`・`char-lessp`・`equalp` は `char-downcase` の値を比べるだけでよい。
- **関数**（`src/unicode/unicode.zig`）：`isAlpha`・`isAlnum`・`isUpper`・`isLower`・`hasCase`・`upcase`・`downcase`・`digitWeight`。ASCII の文字は表を引かない。`digit-char-p` は、SBCL 2.6.7 と同じく U+0080〜U+0660 を数字としない（SBCL は U+0660 以下を ASCII の判定で調べるため、アラビア・インド数字のゼロ U+0660 は NIL、U+0661 以降は数字）。`graphic-char-p` は表を使わない（32〜126 と 160 以上）。
- **使う箇所**：文字・文字列の関数（`src/primitives/strings.zig`）、`equalp` と `equalp` のハッシュ、Reader の大文字への変換（`syntax.upcase`。`λx` は `ΛX`、`é` は `É`）、Printer のシンボル名を囲むかの判定（Unicode の小文字を含む名前は囲む）。`parse-integer` も ASCII 以外の10進数字を読む（SBCL と同じ）。
- **残る違い**（`tests/differential/impl-dependent.toml`）：`char-case-titlecase`（上の4文字）、`reader-symbol-normalization`（SBCL の Reader はシンボル名を NFKC で正規化する）、`reader-number-non-ascii-digits`（SBCL の Reader は `١٢` を 12 と読む。Zilisp はシンボル）、文字の名前（`reader-character-unicode-names`・`printer-character-names`。範囲の外）。Unicode に関する3項目（`reader-upcase-non-ascii`・`string-case-non-ascii`・`char-class-non-ascii`）と `printer-non-ascii-symbol-escape` は、違いがなくなったので外した。
- **試験**：全符号位置（0〜#x10FFFF）で、SBCL 2.6.7 の9つの結果（`alpha-char-p`・`alphanumericp`・`upper-case-p`・`lower-case-p`・`both-case-p`・`graphic-char-p`・基数 36 の `digit-char-p`・`char-upcase`・`char-downcase`）と比べる（`src/unicode/testdata/sbcl-2.6.7-chars.txt`。同じ結果が続く範囲ごとに 1 行、3,409 行。`tools/gen_unicode/sbcl-chars.lisp` を SBCL 2.6.7 で実行して作る）。大文字・小文字の往復（CLHS 13.1.4.3）。Reader の試験。言語試験 `unicode.lisp`（SBCL 2.6.7 と同じ出力。違う3行は注釈で記録）。
- 結果：教材のブロックの一致は 421 のまま（出力の違い 0）。起動時間は 8.82 ms（P21 は 8.80 ms。表は実行ファイルに埋め込む定数で、起動時の処理は増えない。実行ファイルは 1.72 MB から 1.79 MB に）。

**Phase 23 の実装（ストリーム・パス名）**
- **ストリーム**（`src/primitives/streams.zig`。オブジェクトは `object.Stream`）：種類は file・string-input・string-output・stdin・stdout・stderr・synonym・two-way・broadcast。Lisp の値（synonym のシンボル、two-way の組、broadcast のリスト、ファイルのパス名）はオブジェクトの `ref` に置き、GC が走査する。入出力のバッファとファイルのハンドルは Zig の側の状態（`StreamState`。gpa で確保）に置き、`Runtime.streams` が一覧で持つ。**GC は、回収されるストリームの状態を閉じて解放する**（ファイルの出力は書き出してから閉じる。§3.2 の「閉じ忘れたファイルは GC のときに閉じる」）。Runtime を破棄するときも、すべて書き出して閉じる。
- **入力**：どの入力ストリームも、UTF-8 のバイト列と位置で扱う（`read-line`・`read-char`・`read` が同じ位置を共有する）。ファイルと文字列の入力ストリームは、開いたときに全体を読む。標準入力は必要になった分だけ読み足す（REPL では、REPL と同じ Reader から読むので、REPL が先に読んだ行を取りこぼさない）。改行は変換しない：CR LF の CR も文字として読む（SBCL 2.6.7 と同じ。`read-char`・`read-line` で確認した。出力は LF だけ）。Latin-1 の入力を `read` するときは、UTF-8 にしてから読む。`file-position`・`file-length` はバイトで数える（文字列のストリームは文字）。`read` は、読んだ後ろの空白を1つ読み進める（SBCL と同じ）。
- **出力**：出力の関数は、いったんバイト列にしてから書く（`emit`）。ファイルは 64 KiB を超えたとき・`finish-output`・`close` で書き出す。ストリームごとに「行の先頭にいるか」を持ち、`fresh-line` と `format` の `~&` が使う。`print`・`prin1`・`princ`・`terpri`・`format` は出力先のストリームを受け取る（それまでは `th.out` に直接書いていた）。
- **標準のストリーム**（`Thread.create` が作る）：`*standard-output*`（`th.out` に書く）、`*standard-input*`、`*error-output*`（書く前に標準出力を書き出す）、`*terminal-io*`（two-way）、`*query-io*`・`*debug-io*`（`*terminal-io*` の synonym）、`*trace-output*`（`*standard-output*` の synonym）。
- **関数**：`open`（`:direction` は `:input`・`:output`・`:probe`。`:io` は未実装。`:element-type` は文字か `(unsigned-byte 8)`。`:if-exists` の既定は SBCL と同じくエラー。`:supersede`・`:append`・`:overwrite`・`:rename`・NIL。`:external-format` は `:utf-8`・`:latin-1`）・`close`・`with-open-file`・`with-open-stream`、`read-char`・`peek-char`・`unread-char`・`read-char-no-hang`・`read-line`（2つ目の値も）・`read-byte`・`read-sequence`・`listen`・`clear-input`・`read`・`read-preserving-whitespace`・`read-from-string`（2つ目の値は次の位置）、`write-char`・`write-string`・`write-line`・`write-byte`・`write-sequence`・`terpri`・`fresh-line`・`finish-output`・`force-output`・`clear-output`、`print`・`prin1`・`princ`・`pprint`（Phase 24 までは1行に書いていた。P24d から pretty printer）・`write`（`:stream`・`:escape` だけ）・`prin1-to-string`・`princ-to-string`・`write-to-string`、`make-string-input-stream`・`make-string-output-stream`・`get-output-stream-string`・`with-output-to-string`・`with-input-from-string`・`make-broadcast-stream`・`make-two-way-stream`・`make-synonym-stream` と、その中身を返す関数、`streamp`・`input-stream-p`・`output-stream-p`・`open-stream-p`・`interactive-stream-p`・`stream-element-type`・`file-length`・`file-position`。
- **パス名**（`src/primitives/pathnames.zig`。オブジェクトは `object.Pathname`）：欄は host（いつも NIL）・device（Windows のドライブ名）・directory・name・type・version。読み方と namestring は SBCL 2.6.7 と同じ（区切りは `/`、Windows では `\` も読む。`*` は `:wild`、`**` は `:wild-inferiors`、`..` は `:up`、`.emacs` は名前、名前があれば version は `:newest`）。`#P"..."` の読み取りと印字。関数は `pathname`・`pathnamep`・`pathname-host` などの欄・`make-pathname`・`merge-pathnames`（相対のディレクトリを既定のディレクトリの後ろに足す。`:up` は残す）・`namestring`・`file-namestring`・`directory-namestring`・`host-namestring`・`enough-namestring`・`parse-namestring`・`wild-pathname-p`・`pathname-match-p`・`probe-file`・`truename`・`directory`（`*`・`?`・`**` で照合し、名前の順に返す）・`ensure-directories-exist`・`delete-file`・`rename-file`・`file-write-date`。`*default-pathname-defaults*` は起動時の作業ディレクトリ。ファイルを開くときなどは、それと併合してから OS に渡す。`equal`・`equalp` とそのハッシュ表は、パス名を欄ごとに比べる。ただし版は比べない（SBCL 2.6.7 の `pathname=` も、物理パス名の版は比べない）。`load` もパス名指定子を受け取る。
- **スクリプトの終わり方**：ファイルを実行しているとき（`zilisp FILE`・ネイティブのプログラム）、標準入力の end-of-file と、標準出力に書けない（broken pipe）ときは、エラーを表示せずに正常に終える（SBCL 2.6.7 の `--script` の process-script と同じ）。
- **エラーの種類**：`stream-error`（閉じたストリーム）を加えた。ファイルの誤りは `file-error`、ストリームの終わりは `end-of-file`、向きや要素の型の違うストリームは type-error（どれも SBCL と同じ種類）。
- **修正**：パス名を読むときに、ディレクトリの要素の文字列を Zig の配列にためていたため、次の確保で GC が起きると回収されることがあった（GC stress で発見。すぐに Lisp のリストにつなぐようにした）。
- **Codex のレビューの修正（Phase 23）**、16 件（どれも SBCL 2.6.7 と照合した）：`:if-exists` の `:rename`・`:rename-and-delete` は、元のファイルを「名前.bak」に移す（`:rename-and-delete` は閉じるときに消し、`:abort` なら元に戻す）。REPL と `*standard-input*` は同じ Reader から読む。CR LF の変換をやめ（SBCL は変換しない）、Latin-1 の `read` を使えるようにした。バイナリのストリームへの文字の出力は、どの関数（`write-char`・`write-string`・`format` など）でも type-error。broadcast は `write-byte`・`finish-output`・`force-output` を中のストリームに伝え、要素の型は最後のストリームの型（空なら T）。閉じた synonym・two-way は closed-stream-error。`read-char-no-hang` は端末からの入力を待たない。出力のストリームの `file-length` は既にある長さも数える（`:overwrite`）。`pathname-match-p` はすべての欄を照合する（ワイルドカード側の NIL の欄は何でも合う。ディレクトリは `*`・`**` で照合。`?` は1文字）。`merge-pathnames` は `:back` を解決し、版がなければ default-version を使う。`make-pathname` の版は `:defaults` からだけ取る（なければ NIL。SBCL と同じ）。`directory` は名前・型の合うディレクトリも返し、重複しない。パス名の `equalp`。Latin-1 で表せない文字は stream-error。
- **SBCL 2.6.7 との違い**（`tests/differential/impl-dependent.toml`）：パス名の host、名前の途中の `*` の表し方（SBCL は pattern のオブジェクト）、ストリームの印字と型の名前、`close` の `:abort`（SBCL は新しいファイルを消す・元に戻す。Zilisp は閉じるだけ。ただし `:rename` で退避したファイルは元に戻す）、`*query-io*` などの作り、synonym を通した `file-position`（SBCL はバッファの終わりの位置を返す。Zilisp は今の位置）。
- **試験**：言語試験 `streams.lisp`（ファイルの読み書き、バイナリ、UTF-8、文字列のストリーム、合成のストリーム、標準出力）と `pathnames.lisp`（読み方、namestring、merge-pathnames、比較、ファイルの操作）。どちらも SBCL 2.6.7 と同じ出力で、GC stress の版とネイティブでも同じ。エラーの種類の単体テスト（file-error・stream-error・end-of-file・type-error・未実装）。
- 結果：教材のブロックの一致は 429 から 467 に。Level 9 は 7 から 27 に一致が増え（標準入力を読む 3 つは、上の「スクリプトの終わり方」で SBCL と同じになった。eval-check は標準入力を与えない）、Zilisp だけがエラーで残るのは `format` の指示子（Phase 24）の 7 つ。**Level 17 の本体のコード（`text-tools`）は、`handler-case`（Phase 25）と `format` の `~8D` などの指示子（Phase 24）も使うので、Phase 23 の範囲では動かない**。`handler-case` を外した写しで、`format` の指示子に当たるまでの入出力が SBCL と同じであることを確かめた。起動時間は 9.47 ms。

**Phase 24 の実装（format・Reader の拡張・印字の体系）**
Phase 24 は4つに分けて進める：P24a 印字の変数、P24b `format`、P24c Reader の拡張（readtable・ユーザー定義の reader macro・`#.`・`#n=`）、P24d pretty printer（2026-11-03 の決定：pretty printer と Reader の拡張のすべてを Phase 24 に含める）。
- **P24a：印字の変数**（`src/printer/printer.zig`）。印字の前に、`*print-escape*`・`*print-readably*`・`*print-base*`・`*print-radix*`・`*print-case*`・`*print-circle*`・`*print-level*`・`*print-length*`・`*print-array*`・`*print-gensym*`・`*read-default-float-format*` の値を `Settings` に読み取る（`Settings.current`）。処理系の内部の印字（エラーの報告・ネイティブの定数）は、変数によらない `Settings.standard` を使う。変数の初期値は SBCL 2.6.7 と同じ（`*print-pretty*` は pretty printer を実装するまで NIL とし、P24d から T）。
  - 整数と比は `*print-base*` 進（英字の数字は大文字）。`*print-radix*` は `#b`・`#o`・`#x`・`#Nr` か、末尾の `.` を付ける（10 進の比は `#10r`）。`*print-base*` の数として読める名前のシンボルは `|…|` で囲む（16 進では `ABC` は `|ABC|`）。
  - `*print-case*`：読み取りで大文字になる文字だけを変える。`:capitalize` は英数字の並びを単語とする（`Foo1bar`、`A-1b`。SBCL と同じ）。`|…|` で囲む名前は大文字・小文字を変えない。
  - `*print-level*`（`#`）と `*print-length*`（`...`）は、リスト・ベクタ・多次元の配列の各軸に効く（`#2A((1 ...) ...)`、`#2A#`）。
  - `*print-circle*`：先に同じ範囲（`*print-level*`・`*print-length*` の内側）を走査し、2回以上現れるものに `#n=` と `#n#` を付ける。数と intern されたシンボル以外のヒープのオブジェクトすべてが対象（uninterned のシンボル・文字列・関数・ハッシュ表・パス名も）で、共有するリストの尾は `. #n#` の形にする（どれも SBCL と同じ）。
  - `*print-readably*` は、エスケープ・`*print-array*`・`*print-gensym*` を真とし、`*print-level*`・`*print-length*` を無視する。読み戻せないもの（関数・ストリーム・パッケージ・ハッシュ表・NaN と無限大）は `print-not-readable`（新しいエラーの種類）。
  - `*print-array*` が NIL なら `#<(SIMPLE-VECTOR 3) {…}>`・`#<(VECTOR T 2) {…}>`・`#<(SIMPLE-ARRAY T (2 2)) {…}>` と書く。文字列はいつも中身を書く。
  - `*read-default-float-format*`：既定の型の浮動小数は指数の印を省く（`double-float` が既定なら `1.5f0` と `1.5`）。
  - `write`・`write-to-string` は、すべてのキーワード（`:array :base :case :circle :escape :gensym :length :level :lines :miser-width :pprint-dispatch :pretty :radix :readably :right-margin`）を受け取り、印字の間その変数を束縛する。`:base` は 2〜36 の整数、`:case` は3つのキーワードのどれか（ほかは type-error）。`prin1`・`princ`・`print`・`-to-string` の関数・`format` の `~A`・`~S`・REPL が印字する値も、変数に従う。
  - **修正**：Zig 0.17.0 の `toStringAlloc` は、基数 8 と 32 で bignum の桁を誤る（`(expt 2 70)` が、基数 8 では 2^72、基数 32 では 2^71 の桁になった。小さな試験で確認）。基数 4・8・32 は、2 進の文字列から作るようにした。
  - 試験：言語試験 `printer.lisp`（GC stress の版も。SBCL 2.6.7 と同じ出力）と、`print-not-readable` とキーワードの検査の単体テスト。
- **P24b：`format`**（`src/primitives/format.zig`。Phase 19 の最小版を置き換えた）。SBCL 2.6.7 の `target-format.lisp`・`format.lisp`・`print.lisp`（public domain）と同じ動作になるように、Zig で書いた。
  - 制御文字列を、SBCL と同じに指示子に分ける（`%tokenize-control-string`・`parse-directive`・`combine-directives`。`~` と改行・`~%`・`~~`・`~|` は文字にする）。引数は、整数・`'文字`・`v`（引数が NIL なら既定値）・`#`・空。
  - 指示子：`~A ~S`（欄の幅・埋め字・`:` で `()`）、`~W`、`~C`（`:` は `Space`・`Soh` などの名前、`@` は `#\a`）、`~D ~B ~O ~X`（幅・埋め字・`:` の桁区切り・`@` の符号。整数でなければその基数で `princ`）、`~R`（基数、英語の基数詞と序数詞（vigintillion まで）、新旧のローマ数字）、`~P`、`~F ~E ~G ~$`、`~% ~& ~| ~~`、`~T`（絶対・相対。ストリームの桁を使う）、`~*`（`:`・`@`）、`~?`（`@`）、`~( ~)`（4種類の大文字・小文字の変換。中の出力の全体に効く）、`~[ ~; ~]`（`:`・`@`・既定の `~:;`・`#`）、`~{ ~}`（`:`・`@`・`~:}`・回数・中身が空なら引数を制御にする）、`~^`（0〜3個の引数。`~:{` の中の `~:^`）、`~< ~>` の左右揃え（`:`・`@`・行の幅を指定する `~:;`。既定は 72）、`~/名前/`（名前は大文字にし、パッケージの指定がなければ CL-USER に intern する。関数には、ストリーム・引数・`:` と `@` の有無・指示子の引数を渡す）。
  - `~^` は Zig のエラー（`Up`・`UpUp`）で抜け、SBCL が catch する場所（`~{`・`~<`・`format`）で受け止める。出力はいったんバッファに溜め、終わりと、ユーザーの関数を呼ぶ前にストリームに書く（`~/名前/` と関数の制御には本来のストリームを渡す。出力先が文字列なら文字列の出力ストリームを渡す）。`~T` のため、ストリームは今の桁を持つようにした（`StreamState.column`）。
  - 浮動小数：`flonum-to-string` と `%flonum-to-digits`（Burger と Dybvig の方法に、桁の位置での丸めを加えたもの）を多倍長整数で移植したので、丸めは SBCL と同じ（`(format nil "~,2F" 0.005)` は `0.01`、0.25 の `~,1F` は `0.3`）。有理数は single-float にする。数でないものは、10 進の `~A` と同じに、幅を mincol として書く。
  - `formatter`（`boot.lisp` のマクロ。`zilisp-system:%format-rest` を呼ぶ）と、関数の制御も使える。
  - pretty printer の指示子は、P24d までは pretty printing のストリームでない場合と同じに扱っていた（`~_`・`~I`・`~:T` は何もせず、`~<…~:>` は明示的なエラー）。P24d で実装した。
  - エラー：SBCL の `format-error` は、Zilisp では `simple-error`（Phase 19 と同じ）。SBCL が type-error にする場合（`~{` の引数がリストでない、指示子の引数の型が違う）は、Zilisp も type-error。
  - 結果：教材のブロックの一致は 467 から 478 に。`format` のために Zilisp だけがエラーになるブロックはなくなった。試験：言語試験 `format.lisp`（145 行の出力が SBCL 2.6.7 と同じ。GC stress の版も）と、SBCL と比べた 24 個のエラーの場合の単体テスト。
- **P24c：Reader の拡張**（`src/reader/readtable.zig`・`src/reader/reader.zig`・`src/reader/value_builder.zig`）。
  - **readtable** は新しいオブジェクトの種類（`object.Readtable`）：ASCII の文字の構文型、マクロ関数の 128 要素の simple-vector、それ以外の文字の連想リスト、dispatch 文字ごとの表（129 要素のベクタ）。標準の readtable は `zilisp-system:*standard-readtable*` で、`*readtable*` の初期値はその写し（SBCL と同じ）。標準の readtable は変えられない。
  - 標準のマクロ文字は、組み込みの関数（`zilisp-system::%READ-LIST`・`%READ-SHARP-QUOTE` など。`reader.Builtin` ごとに1つ）。文字のマクロ関数がそのどれかなら、Reader は Zig のコードを直接使うので、標準のマクロを別の文字に写せる（`(set-macro-character #\] (get-macro-character #\)))`）。`get-macro-character` は、それらには名前のシンボルを返す（SBCL も `SB-IMPL::READ-LIST` などのシンボルを返す）。
  - Reader は、Builder の `charInfo`・`dispatchInfo` で文字を引く。readtable が標準の印を持つままなら、標準の静的な表を使う（速い経路）。`beginRead` が、read のたびに `*read-base*`・`*read-default-float-format*`・`*read-suppress*`・`*readtable*` から Options を作り直すので、それを変えるフォームは、同じファイルの次のフォームの読み方に効く。
  - **ユーザー定義の reader macro** には、Reader の位置に合わせたストリームを渡して呼ぶ（読んでいるストリーム。`load`・`read-from-string` では同じテキストの文字列の入力ストリーム）。呼んだ後は、ストリームの新しい位置から読み続ける。値を返さないマクロは、何も読まなかったことになる。`recursive-p` が真の `read` は、外側の read の `#n=` のラベルを使う。reader macro の中のエラーは、その種類のまま伝わる（Reader の新しいエラー `LispError` で外に出す）。
  - `#.` は `*read-eval*` が真なら評価する（偽なら reader-error）。`#n=` と `#n#` は循環する構造も読める（仮の cons を、cons・単純ベクタ・配列の中で置き換える）。`*read-suppress*` では、リストとベクタも NIL になる（SBCL と同じ）。
  - `readtable-case`（`:upcase`・`:downcase`・`:preserve`・`:invert`）は、トークンと印字（エスケープと `*print-case*`。SBCL の `output-symbol-case-dispatch`。`*print-readably*` のシンボルは標準の readtable 向けに書く）に効く。今の readtable のマクロ文字で始まるシンボルと、終端マクロ文字を含むシンボルは囲む（SBCL の `symbol-quotep`）。
  - 関数：`readtablep`・`copy-readtable`・`set-macro-character`・`get-macro-character`・`make-dispatch-macro-character`・`set-dispatch-macro-character`・`get-dispatch-macro-character`・`set-syntax-from-char`・`readtable-case` とその `setf`・`read-delimited-list`、マクロ `with-standard-io-syntax`。
  - ネイティブバックエンド：定数を `*print-circle*` で書くので、循環する定数（`'#1=(a . #1#)`）も保たれる。後ろのフォームで使う reader macro は、`compile-file` と同じく `eval-when` の中で定義する。
  - 試験：言語試験 `readtable.lisp`（SBCL 2.6.7 と同じ出力。GC stress の版とネイティブでも同じ）と、SBCL と比べた 17 個のエラーの場合の単体テスト。
- **P24d：pretty printer**（`src/printer/pretty.zig`・`src/printer/pprint.zig`）。SBCL 2.6.7 の `pprint.lisp`（パブリックドメイン）に倣って Zig で書いた。
  - **pretty stream** は新しいストリームの種類（`.pretty`）：通し番号の付いた操作（条件付きの改行・字下げ・タブ・論理ブロックの始めと終わり）の列、論理ブロックのスタック、接頭辞と接尾辞、バッファ。出力の決め方は SBCL と同じ（`enqueue-newline`・`maybe-output`・`fits-on-line-p`・`output-line`・`expand-tabs`）。行の長さは `*print-right-margin*`、なければ 80。`*print-miser-width*` と `*print-lines*`（「 ..」と接尾辞を書き、その後は何も書かない）も効く。
  - `*print-pretty*` が真なら、`print`・`prin1`・`princ`・`write`・`-to-string` の関数・`~A ~S ~W` は `output-object` で印字する。`*print-circle*` は、オブジェクトを2回走査し（1回目は何も書かないストリームに書く）、論理ブロックの中で印を付ける（SBCL の `check-for-circularity` と同じ）。`*print-level*`・`*print-length*` は論理ブロック（`pprint-pop`）にも効く。
  - **dispatch の表** は新しいオブジェクトの種類（`object.PprintDispatch`）：優先度と型を持つ項目と、car のシンボルで引く cons の項目。`pprint-dispatch`・`set-pprint-dispatch`・`copy-pprint-dispatch`。初期の表（`zilisp-system:*standard-pprint-dispatch-table*`）は Zig で扱い、その写しを変えたときにだけ項目に展開する。特殊形式とマクロ（`let`・`defun`・`cond`・`case`・`do`・`dolist`・`loop`・`tagbody`・`prog`・`setq`・ラムダリスト・`quote` と backquote・配列）の標準の印字は SBCL から移植した（一部は SBCL の format の制御文字列のまま）。関数の呼び出しと `&body` のあるマクロは、ラムダリストで字下げする。`defmacro` はラムダリストを属性リストに残すようにした（`zilisp-system::%macro-lambda-list`）。
  - 関数：`pprint`・`pprint-newline`・`pprint-indent`・`pprint-tab`・`pprint-fill`・`pprint-linear`・`pprint-tabular`、マクロ `pprint-logical-block`・`pprint-pop`・`pprint-exit-if-list-exhausted`。pretty stream でないストリームでは、`pprint-newline`・`pprint-indent`・`pprint-tab` は何もしない。pretty stream は桁を答えない（SBCL の `pretty-misc` は `charpos` に NIL を返す）ので、その上の `fresh-line` と `~&` は必ず改行する。`~<…~:>` の中の引数は、`pprint-pop` と同じくリストから1つずつ取り出し（循環するリストでも `*print-circle*` で止まる）、`~:*`・`~@*`・`~@[` はそのリストの中で位置を戻す。`format`：`~<…~:>`（論理ブロック、`~@;` の行ごとの接頭辞、`~:@>` の fill の形）・`~_`・`~I`・`~:T`、pretty stream での `~T`。
  - `*print-pretty*` の初期値を、SBCL と同じ T にした（2026-11-04 の決定）。小さなリストを 4 万回印字すると、NIL のときの約 2.3 倍の時間がかかる（70 ms と 162 ms。SBCL は 39 ms と 91 ms で、同じく約 2.3 倍）。教材のブロックの一致は 478 のまま。
  - 試験：言語試験 `pretty.lisp`（231 行の出力。SBCL 2.6.7 と同じ。GC stress の版も）と `pretty-default.lisp`（73 行。変数の初期値のままの印字。SBCL 2.6.7 と同じ）。
- **Phase 24 の受入（往復）**：`*print-readably*` で印字したものを読み戻すと `equalp` になる。`*print-pretty*` が NIL と T のどちらでも、`*print-right-margin*` を狭くしても同じ（言語試験 `round-trip.lisp`。GC stress の版も。SBCL 2.6.7 と同じ出力）。そのために2つの不足を埋めた。
  - Reader は `#nA`（SBCL の `sharp-A`：各軸の長さは、1つ上の軸の最初の要素の長さ。長さ 0 の軸より後ろの軸は 0）と、SBCL の `#A(次元 要素の型 . 中身)` を読む。ネイティブのプログラムはスレッドなしで定数を読むので、配列は `make-array` を呼ばずに Builder の中で作る。エラーの種類は SBCL と同じ：形の誤りは reader-error、長さが次元と合わなければ simple-error、次元の誤り・ドット対で終わるリスト・文字でない要素は type-error（スレッドがあるとき。なければ reader-error）。
  - ネイティブのプログラム：定数を `*print-readably*` で書くようにした（次元と要素の型が保たれる）。読み戻せない定数（`#.` で作ったハッシュ表・関数など）は、壊れたプログラムを作らずに `--emit-zig` でエラーにする。
  - `*print-readably*` のとき、`#nA` で表せない配列（文字の配列と、`(make-array '(0 3))` のように長さ 0 の軸の後ろに長さが 0 でない軸があるもの）は `#A((0 3) T)` の形で書く（SBCL の `array-readably-printable-p` と `output-unreadable-array-readably`。pretty printer では、SBCL と同じくそのリストを pretty printer で書く）。

**0.3 の変更のレビュー（2026-11-04）**
Phase 24 の後に、Phase 19〜24 の変更を agy（Antigravity CLI。5 回のうち 2 回で利用の上限に達した）と Codex（残りの 3 回）にレビューしてもらった。Zilisp と SBCL 2.6.7 で再現した 41 件を直した（一覧は CHANGELOG.ja.md の Fixed）。そのうち設計に関わるもの：
- ネイティブのプログラムは、トップレベルのフォームの定数を、そのフォームを実行する直前に読む（`Toplevel.nconsts`・`nlambdas`、`rt.zig` の `loadUpTo`。fasl と同じ）。定数表の全体を、1組の `*print-circle*` の番号で書き（`printer.writeObjects`）、Reader は定数をまたいでラベルを保つ。
- `reader.Source` に読み足しの口を設けた：標準入力から読むとき、続きが要ればフォームを読み直さずに同じ読み取りを続ける。
- 読み飛ばしの最中（`#+`・`*read-suppress*`）に呼ぶ reader macro は、`*read-suppress*` を T に束縛して呼び、値は NIL にする。reader macro の中の recursive な `read` は、外側の read の backquote の深さを引き継ぐ（`ValueBuilder.bq_depth`）。
- オブジェクトを作る関数は、ヘッダの 32 ビットの長さに入らない長さを拒む（OutOfMemory。storage-condition になる）。
- `do`・`loop` の形の誤りは program-error（SBCL は一部を simple-error にする。`error` は Phase 25）。Phase 25 で、SBCL 2.6.7 と同じく `do`・`do*`・`psetq` を simple-error にした（`loop` は SBCL も program-error）。

**Phase 25 の実装（condition・handler・restart）**
2026-11-05 の決定：condition は専用の `record` で表し、CLOS（Phase 27）で instance にまとめる。標準の condition の report の文面は SBCL 2.6.7 に合わせる。Zig で見つけたエラーは `th.signal` の場所ですぐに handler を呼ぶ。REPL は restart の一覧を表示するところまで（番号で選ぶ操作は後の Phase）。構造は §9。
- **Zig の側**：`ObjKind.record`（`object.Record`。GC が class と slots を走査する）、`src/primitives/conditions.zig`（`zl-sys::%make-record`・`%record-p`・`%record-class`・`%record-slots`・`%object-address`・`%unhandled-condition`）、`th.signal` の handler の呼び出し（`signalDetail`・`callSignalHook`）、スタックの溢れの `th.stackExhausted`、受け止められなかった condition の記録（`ErrorKind.condition`・`th.unhandledCondition`）と restart の一覧（`LispError.restarts`・`th.writeRestarts`。REPL・スクリプト・ネイティブのプログラムが書く）。印字の入口は condition・restart を `zl-sys::%print-record` に渡す。
- **`typep`**（`src/primitives/types.zig`。CL の関数として初めて実装した）：シンボルの型（数・文字・文字列・列・配列・シンボル・関数・ストリームなど）、`(integer 下限 上限)` などの範囲、`mod`・`unsigned-byte`・`signed-byte`、`member`・`eql`・`and`・`or`・`not`・`satisfies`・`cons`、`(vector 要素の型 長さ)`・`(simple-array …)`・`(string 長さ)`、condition と restart の型（クラスの CPL）。判定できない CL の型指定子は `zilisp:unimplemented`、型でないシンボルは simple-error。set-pprint-dispatch の型の判定（pprint.zig にあった部分的なもの）も、これに置き換えた。`type-of`・`subtypep`・`deftype` は未実装（教材で使われていない）。
- **Lisp の側**（`src/lisp/boot.lisp` の末尾）：クラスの記述と `define-condition`・`make-condition`、標準の condition 型の階層と report、`signal`・`error`・`cerror`・`warn`・`invoke-debugger`、`handler-bind`・`handler-case`・`ignore-errors`、restart の関数とマクロ、`typecase`・`etypecase`・`ctypecase`・`ecase`・`ccase`（漏れは SBCL と同じ文面の `zl-sys::case-failure`。type-error の一種）、`check-type`（SBCL と同じ文面の simple-type-error と `store-value`）、`assert`（`continue`。テストが関数の呼び出しなら、定数でない引数の値を `failed with X = 3.` の形で報告する。場所の値は尋ねない）、Zig で見つけたエラーから condition を作る `zl-sys::%zig-condition`。
- **0 除算の演算と被演算子**：`/`・`floor` などの 0 除算は `(/ 被除数 除数)`（浮動小数は浮動小数にした値。SBCL と同じ）、`expt` は `(EXPT 底 指数)` を condition に渡す。`log` の 0 は演算なし（SBCL と同じ）。
- **`eval`** を関数として加えた（教材 Level 13 の `safe-eval`。コンパイラの `eval` を呼ぶ）。
- **VM の値スタック**：handler を呼ぶ間 `vm.sp` を一番上のフレームが使いうる深さまで上げる（§9.2）。上げないと、呼び出し側の handler が同じフレームの `catch` に戻る場合に、書き戻していない `list` の引数が handler を呼ぶ処理の値で上書きされることを確かめた（単体テストと言語試験 `conditions.lisp` の `p25-mid`）。
- **SBCL 2.6.7 との違い**（`tests/differential/impl-dependent.toml`）：SBCL の内部の型（`SB-INT:SIMPLE-PROGRAM-ERROR` などは `zl-sys::simple-program-error` など）、SBCL のコンパイラの定数の畳み込みによる文面（`Value of "a" in (+ "a" 1) is "a", not a NUMBER.` は、Zilisp では値の型を報告する type-error の文面）、トップレベルの restart（SBCL の `--script` の RETRY・CONTINUE・ABORT）、ファイルのエラーの文面（SBCL は絶対パスと OS のメッセージ）、Zig で見つけたエラーの説明の文（日本語）、`*print-pretty*` が NIL のときのリストの中の condition の印字（この 1 つは Phase 26 でなくなった）。
- **試験**：言語試験 `conditions.lisp`（SBCL 2.6.7 と同じ出力。GC stress の版とネイティブでも同じ）、単体テスト（受け止められなかった condition の報告と restart の一覧、VM の命令の途中のエラーと GC）。
- **Codex のレビューの修正（Phase 25）**、6 件（どれも SBCL 2.6.7 と照合した）：`restart-case` の中の `cerror` は引数を書いた順に評価する。`restart-case` のフォームはマクロを展開してから通知の形かを調べる（大域のマクロだけ）。`abort`・`muffle-warning` の restart が戻ってきたら control-error。`typep` の `(vector t n)`・`(string n)` などの大きさは、fill-pointer でなく次元と照合する。Reader が reader-error・end-of-file を通知する前に、読んだところまでストリームの位置を進める（handler がその場でストリームを読むため。`#A` の中身の誤りなど ValueBuilder の中から通知するエラーは、まだ位置を進めない）。reader-error の condition にストリームを入れる。
- **Codex のレビューの修正（Phase 25、2回目）**、4 件（どれも SBCL 2.6.7 と照合した）：ValueBuilder の中から通知するエラー（`#A` の中身の誤り）も、通知の前にストリームの位置を進める（readOp が `ValueBuilder.sync_position` を渡す）。`read-from-string` の reader-error・end-of-file にも、同じ中身と位置の文字列の入力ストリームを入れる（エラーのときだけ作る）。`ccase`・`ctypecase` は場所の部分式を setf の展開で1回だけ評価する（`check-type` は SBCL と同じく、確かめるたびに場所を1回読む）。`*debugger-hook*` があれば、handler・restart がなくても Zig で見つけたエラーで呼ぶ（§9.4 の制限をなくした）。
- **Codex のレビューの修正（Phase 25、3回目）**、3 件：`ccase`・`ctypecase` は場所を最初の1回だけ読み、`store-value` の後は格納のフォームの値で分岐をやり直す（SBCL 2.6.7 と同じ）。格納の変数が複数ある場所は、すべてを `multiple-value-bind` で束縛する（足りない値は NIL。SBCL と同じ）。`read-from-string` のエラーのストリームを作る確保に失敗したら、元のエラーを通知せずにそこで戻る（記録した storage-condition を上書きしない。確保の失敗を起こす試験はない）。
- **Codex のレビューの修正（Phase 25、4回目）**、5 件（`zilisp:unimplemented` を error の下位にしない変更に伴うものを含む。どれも SBCL 2.6.7 と照合した）：マクロ・特殊演算子を関数として呼んだのは undefined-function のまま（未実装の印はマクロ・特殊演算子にも付くので除く）。`typep` が未実装とするのは、CLHS の標準の型の名前のうちまだ判定できないもの（`bit-vector`・`random-state`・ストリームの下位の型・CLOS のクラスなど）と、特殊化した配列の要素の型だけ（型でないシンボル・形の誤りは simple-error）。`pprint-logical-block` の `:prefix` と `:per-line-prefix` の両方の指定は simple-error、`loop` の CLHS にない句は program-error（CLHS の句の名前でまだ扱えないものだけ未実装）。`etypecase`・`ctypecase` の `otherwise` は型指定子。`(setf (values 場所 …))` の展開（`define-setf-expander`）と、格納の変数が複数の場所の `setf`（`multiple-value-bind`）を加えた。
- **Codex のレビューの修正（Phase 25、5回目）**、6 件（どれも SBCL 2.6.7 と照合した）：`zl-sys::%bind-stores` は、格納の変数がちょうど 1 個でなければ `multiple-value-bind` で束縛する。`setf`・`incf`・`decf`・`push`・`pop` はこれを使う（`(setf (values) …)`・`(incf (values a b))`）。`typep` は型指定子の形を、値を見ずに確かめる（types.zig の `validate`。ok・unimplemented・invalid）：形の誤り（`(random-state 3)`・`(mod 0)`・`(integer 1 2 3)`・型でない要素の型）は simple-error、形は正しいがまだ判定できないもの（`(bit-vector 3)`、`(unsigned-byte 8)` などの特殊化した要素の型）は未実装、`(base-string n)`・`(simple-base-string n)`・`(complex 型)` は偽（base-string と複素数はない）。`and`・`or`・`not`・`cons` の部分は、判定に使うときだけ確かめる。`loop` は CLHS の句をすべて最後の分岐より前で扱うので、そこに来る句（先頭でない `named`・書き間違い）は program-error。`being` の種類は symbol の種類（CLHS 6.1.2.1.7）と `elements`（SBCL 2.6.7 の拡張）だけを未実装とし、ほかの名前は program-error。
- **Codex のレビューの修正（Phase 25、6回目）**、5 件（コードは Codex が書き、こちらで確かめた。どれも SBCL 2.6.7 と照合した）：`getf` の setf-expander は内側の場所の格納の変数を `%bind-stores` ですべて束縛し、`values` の setf-expander は格納の変数のない場所に値を渡さない（その位置は NIL を返す）。`validate` は `and`・`or`・`not`・`cons` の外側の形（真リストと引数の数）だけを見て、`typep` は判定の前にいつもこれを呼ぶ。部分は判定に使うときに確かめる（`(typep 1 '(or fixnum car))` は T のまま）。`completeType` は部分も確かめ、配列の要素の型と `complex` の引数に使う。限界は、`integer` は整数、`rational` は有理数、`single-float`・`short-float` は単精度、`double-float`・`long-float` は倍精度、`float`・`real` は実数（SBCL も `(float 1 3)` を受け付ける）。`complex` の引数は `*` か `real` の下位の型（`realSubtype`）。
- **Codex のレビューの修正（Phase 25、7回目）**、3 件（どれも SBCL 2.6.7 と照合した）：`incf`・`decf`（`zl-sys::%expand-incf`）は、場所の部分 → 増やす量（数でなければ一時変数に入れる）→ 場所の値、の順に評価する（増やす量が場所を書き換えたら、書き換えた後の値に足す）。`complex` の引数は、確実に `real` の下位の型でないときだけ誤りとする（`surelyNotReal`：実数でない型、それを含む `or`、`not`、数でない `eql`・`member`、`(and)`）。ほかの `and` と `satisfies` は受け付ける（交わりは空や実数になることがあり、Zilisp には複素数もない）。要素の型 `base-char` は、どの配列にも当たらない（Zilisp の文字列の要素の型はいつも `character`。`base-string` と同じ）。
- **Codex のレビューの修正（Phase 25、8回目）**、2 件（どれも SBCL 2.6.7 と照合した）：`surelyNotReal` を `realness` に替えた。返すのは yes（確かに `real` の下位）・no（実数でない要素を必ず含む）・unknown の 3 つ。実数の型の名前と `nil` は yes、ほかのアトムは no。`and` は `t` を除き、0 個なら `t`（no）、1 個ならその型、それ以外はどれかが yes なら yes、なければ unknown。`or` はどれかが no なら no、すべて yes なら yes。`(not (not X))` は X、`(not t)` は yes。アトムと、`and`・`or`・`satisfies` 以外の合成の型の `not` は no（そうした型は実数でない値をすべて含むことがない）。それ以外の `not` は、部分が yes なら no、そうでなければ unknown。`eql`・`member` は要素がすべて実数なら yes、そうでなければ no。`satisfies` は unknown。no は `simple-error`、unknown は `zilisp:unimplemented` を通知する。そのため `(complex (and string symbol))` などの空の交わりは未実装になる（SBCL は NIL。互いに素な型を見分けるには `subtypep` が要る）。
- **Codex のレビューの修正（Phase 25、9回目）**、1 件（SBCL 2.6.7 と照合した）：`cons` の型の `realness` は、部分が `nil` なら yes（空の型）、両方の部分が空でないと言い切れれば no（`*`、`nil` 以外のアトム、`realness` が no の型）、それ以外は unknown。`complex` の合成の型は、`(complex)`・`(complex *)` だけが no で、ほかは unknown（SBCL では `(complex nil)`・`(complex (integer 0 0))` が空）。
- **Codex のレビューの修正（Phase 25、10回目）**、1 件（SBCL 2.6.7 と照合した）：`invoke-restart`・`invoke-restart-interactively` が使う `zl-sys::%find-restart-or-lose` は、restart のオブジェクトが `zl-sys::*restart-clusters*` の中にあれば（`zl-sys::%restart-active-p`）そのまま受け付け、`:test` を呼び直さない。condition なしで呼び直していたので、`(find-restart 名前 condition)` で見つけた restart を拒否し、condition を渡した `continue`・`store-value`・`use-value` も動かなかった。名前は今までどおり `find-restart` で探す（`:test` は NIL を受け取る。SBCL と同じ）。抜けた `restart-case` の restart をオブジェクトで呼ぶと、Zilisp は control-error（restart は dynamic extent なので結果は未定義。SBCL 2.6.7 は memory fault）。この例は言語試験でなく `eval_test.zig` で確かめる。
- **Codex のレビューの修正（Phase 25、11回目）**、1 件（SBCL 2.6.7 と照合した）：`assert` がテストの式の引数を一時変数に入れる（値を報告するため）のは、関数の呼び出しのときだけ。Zilisp では特殊演算子も `fboundp` が真なので、`(assert (if t t (incf n)))` は選ばれない分岐を評価し、`(assert (let ((x 1)) (= x 1)))` は `((x 1))` を式として評価していた。判定に `(not (special-operator-p 演算子))` を加えた。`special-operator-p` は新しいプリミティブ（`functions.specialOperatorP`）で、シンボルの `special_operator` の印を読む。CL の外部シンボルで真になるのは、SBCL 2.6.7 と同じ 25 個。
- **Codex のレビューの修正（Phase 25、12回目）**、1 件（SBCL 2.6.7 と照合した）：`define-condition` の `:report` に書いたシンボルを引用して保存していたので、印字するといつも大域の関数が呼ばれていた。CLHS では `(function report-name)` を現在の字句環境で評価するので、`flet`・`labels` の局所関数を指さなければならない。シンボルは `(lambda (c s) (funcall (function 名前) c s))` に展開するようにした。lambda の中の `function` は、局所関数があればそれを指し、なければ呼んだときに大域の関数を探す（`define-condition` の後で定義した関数も使える。SBCL と同じ）。
- **Codex のレビューの修正（Phase 25、13回目）**、1 件（SBCL 2.6.7 と照合した）：印字は Zig から Lisp の関数を 4 か所で呼ぶ（condition・restart の `zl-sys::%print-record`、`set-pprint-dispatch` の関数、`pprint-logical-block` の本体、`format` の `~/名前/`）が、その後で `th.mv_count` を戻していなかった。そのため、呼んだ関数の値が `princ-to-string`・`write-to-string`・`format nil` の値に混ざっていた（report が `(values 1 2 3)` を返すと `("r3" 2 3)`、`(values)` を返すと NIL）。4 か所とも、正常に戻ったら `th.mv_count = 1` にする（エラーと非局所脱出の経路は変えない）。調べる途中で別の問題が見つかった：印字を挟んだ際限のない再帰（report の中で自分の condition を `~A` で印字するなど）は Zig のスタックを溢れさせ、`storage-condition` にならずにプロセスが落ちる。Phase 25 の外の問題として別に扱う（tque #377）。
- **Codex のレビューの修正（Phase 25、14回目）**、同じ種類の 3 件（SBCL 2.6.7 と照合した）と、確かめる途中で見つけた 1 件：`typep` の `(satisfies …)` の述語（`types.zig`）が値の個数を残していた（`(values nil 2 3)` を返す述語を `set-pprint-dispatch` に登録すると `write-to-string` が `("5" 2 3)`）。`eval` に渡した空の `progn`、`:execute` がないか本体のない `eval-when`（`eval.zig`）は、前のフォームやマクロの展開関数の値を残したまま NIL を返していた。`(values)` を返すリーダーマクロの直後に入力が終わると、`read` が終わりの値を返さず値なしになっていた（`streams.zig` の `eofResult`）。`:initial-value` なしで要素のない列の `reduce`（`boot.lisp`）は、関数の値をすべて返していた。どれも値 1 つにした。Zig から Lisp を呼ぶ 24 か所（`th.call`）をすべて確かめ、関数を受け取る関数の 45 例（列・リスト・集合・木・ハッシュ表・reader・マクロの展開・signal）を SBCL 2.6.7 と比べた。これら以外の違いは `union` の順（処理系依存）だけ。
- `*break-on-signals*` は、デバッガのフェーズ（tque #351。どのようなデバッガにするかの検討から行う）で扱う。
- 結果（受入：Level 13 の主要コード）：Level 13 の 33 ブロックのうち、両方ともエラーで終わるもの（エラーを見せる例・断片）を除き、ファイルのエラーの文面の 1 つ（L455。処理系依存）と、未実装の `get-universal-time` を呼ぶ 1 つ（L704。`zilisp:unimplemented` は `error` でないので `ignore-errors` が受け止めない）以外は SBCL 2.6.7 と同じ出力。教材のブロックの一致は 478 から 513 に（出力の違いは L455 の 1 つ）。condition のために Zilisp だけがエラーになるブロックはなくなった。起動時間は 13.55 ms（boot.lisp の空でない行は 1192 から 1934 に）。

**Phase 26 の実装（defstruct・時刻）**
2026-11-10 の決定：構造体は専用のオブジェクト（スロットを直接並べる）で表す。範囲は §10.5 の項目と周辺の標準機能（`#S`・`copy-structure`・`equalp`・`typep`）。スロットの `:type` は検査する。時刻の関数（tque #378）を先に入れる。構造は §10.5。
- **defstruct**：Zig の側は `src/primitives/structures.zig`、Lisp の側は `src/lisp/boot.lisp` の末尾（`zl-sys::%expand-defstruct`、印字の `zl-sys::%print-structure`、`#S` の `zl-sys::%read-structure`）。内容は §10.5。
- **時刻**（CLHS 25.1.4）：`get-universal-time` は Zig（`src/primitives/time.zig`。`std.Io.Timestamp.now(io, .real)`）。`decode-universal-time`・`encode-universal-time`・`get-decoded-time` は boot.lisp に書く。
  - その土地の時刻との差（`zl-sys::%timezone`。Unix の時刻を受け取り、UTC からの西向きの秒数（夏時間を含む）と、夏時間かどうかを返す。SBCL の `sb-unix::get-timezone` と同じ値）：Windows は `SystemTimeToTzSpecificLocalTime` と `GetTimeZoneInformation`（1970 年より前は 1970 年として扱う。SBCL 2.6.7 の Windows 版と同じ）、ほかの OS は `/etc/localtime`（TZif）の切り替わりの表（`std.tz`。読めなければ UTC。**環境変数 `TZ` は見ない**）。
  - 引数の型は SBCL 2.6.7 と同じ（universal-time は `unsigned-byte`、time-zone は `(or null (rational -24 24))`、年は `(or (mod 100) (integer 1899))` など。合わなければ type-error。結果が負なら type-error）。2 桁の年は今の年の前後 50 年。`time-zone` を指定したら夏時間は考えない。
  - 32 ビットの `time_t` の範囲の外の時刻は、その年の 3 月 1 日からの秒数を 2035 年（後ろ）・1903 年（前）の 3 月 1 日に足した時刻の規則を使う（SBCL の方式）。
  - `get-internal-real-time`・`get-internal-run-time`・`internal-time-units-per-second`・`sleep` は未実装のまま。
- **試験**：言語試験 `defstruct.lisp`・`time.lisp`（SBCL 2.6.7 と同じ出力。GC stress の版とネイティブでも同じ。Linux（WSL）でも同じ）。`time.lisp` は、その土地の時刻と今の年によって変わるものは値の形だけを確かめる。
- **Codex のレビューの修正（Phase 26、1回目）**、5 件（どれも SBCL 2.6.7 と照合した）：
  - `#1=#S(node :next #1#)` のように `#n#` で自分（や外側のオブジェクト）を指す構造体：reader の `#n#` の置き換え（`value_builder.zig` の `patch`）が構造体のスロットをたどっていなかったので、仮の値がスロットに残っていた。`patch` が構造体のスロットも置き換える。`#n=` の仮の値は car が unbound の cons にして、ほかの cons と区別できるようにした。型の検査は、仮の値が置き換わった後で行う（方法は 2 回目の修正で変えた。下）。
  - BOA の構築子の supplied-p の変数（`(&optional (a 10 present))` の `present`）も、同じ名前のスロットの値にする（initform が入っていた）。
  - `:include` でスロットの型を書き換えたとき、元の型も満たさなければならない（元の構造体のアクセサからも読むため）。型は `(and 元の型 新しい型)` として持つ（片方が `t` か、同じならそのまま）。
  - `decode-universal-time` は、time-zone を秒にした値が整数でなければ type-error（`1/7`・`1/7200`。秒が比になっていた）。
  - `defstruct` のオプションの余分な引数（`(:copier nil extra)` など）、シンボルでない `:copier`・`:predicate` の名前、`:conc-name`・`:copier`・`:predicate` の重なりをエラーにする（`:constructor` は重ねてよい）。
- **Codex のレビューの修正（Phase 26、2回目）**、6 件（どれも SBCL 2.6.7 と照合した）：
  - `#S` のスロットの値の中（リスト・ベクタ・構造体の中も）に `#n=` の仮の値があるとき：1 回目の修正は、スロットの値そのものが仮の値の場合しか扱っていなかった（`#1=#S(n :next (#1#))` で、型 `(cons n null)` の正しい値を拒み、`(cons cons null)` の誤った値を通した）。`ValueBuilder.structure` が `containsPlaceholder` で値の中を調べ、仮の値があれば `th.skip_slot_type_check` を立てて構築子を呼び（`zl-sys::%check-slot-type` は検査しない）、できた構造体をラベルの表に `(unbound . 構造体)` として置く（recursive の read も同じ表を使う）。`labelFinish` は置き換えの後、表の構造体のうち中に仮の値がなくなったものを表から外して、`zl-sys::%check-structure-slots` でスロットの型を確かめる。
    - 入れ子のラベルで互いを指す形（`#1=#S(n :next (#2=#S(n :next (#1#))))`・`#1=(#2=#S(n :next (#1#)) #2#)`）は、すべてのラベルが解決した後の値が型に合えば読める。SBCL 2.6.7 はこの 2 つを type-error にする（`impl-dependent.toml`）。
  - `:include` のスロットの書き換えは、初期値が書いてあるときだけ初期値を書き換える：`(x)` と `x` は元の初期値のまま、`(x nil)` は NIL（いつも書き換えていた）。
  - pretty でない印字で、Lisp の印字の関数の中からの印字（構造体・condition のスロットの値、`:print-function` の中の印字）が Zig の印字に戻ると、深さ（`*print-level*`）と共有の表（`*print-circle*`）が伝わらなかった。`th.pp_level` が 1 以上か `th.pp_circle` があるとき（`streams.inLispPrinter`）は、リストだけの値も pretty printer の経路で書く（`emitPrinted`・`printTo`・`format` の `printed`）。
  - `(:conc-name "")` は、アクセサの名前を今のパッケージに intern する。スロットのシンボルそのものを使うのは `(:conc-name nil)`（と引数なし）だけ。
  - `(:print-function nil)`・`(:print-object nil)` は、引数なしと同じく `#S(…)` の形に戻す（`(function nil)` に展開してエラーになっていた）。
  - `:include` で同じスロットを 2 回書き換えるとエラー。`:include` の書き換えに裸のシンボル（`(:include base x)`）を書くのは受け付ける（SBCL 2.6.7 はエラーにする。CLHS の構文では slot-description はシンボルでもよいと読める。※原文は未確認）。
- **Codex のレビューの修正（Phase 26、3回目）**、2 件（どれも SBCL 2.6.7 と照合した）：
  - `th.skip_slot_type_check` はスレッド全体に効くので、循環する `#S` の構築子を呼んでいる間、initform が作る別の構造体・initform の中の `setf`・initform の中の別の `#S` の読み取りの型の検査まで省略していた。省略するのは、値の中に `#n=` の仮の値がある検査だけにした（`sysCheckSlotType` が `containsPlaceholder` で値を調べる。initform が作る値には仮の値が入らないので、ふつうに検査される）。
  - pretty printer の経路からアトムを Zig の印字に渡すとき（`pprint.zig` の `outputUgly`）、Zig の印字は深さ 0 から数えるので、`*print-level*` から今の深さ（`th.pp_level`）を引いた値を渡す。多次元の文字の配列はここで中身まで書くので、構造体やリストの中で 1 段深く書いていた（`#S(BOX :X #2A(# #))`。SBCL は `#S(BOX :X #2A#)`）。
- **Codex のレビューの修正（Phase 26、4回目）**、1 件（SBCL 2.6.7 と照合した）：3 回目の修正（値の中に仮の値がある検査を省略する）でも、reader macro が持ち出した `#n#` の仮の値を、`#S` の initform が別の構築子や `setf` に渡すと、その検査が省略され、後で確かめ直されなかった（確かめ直すのは reader が作った構造体だけ。`setf` の先が読んだ結果の外なら、仮の値がそのまま残った）。スレッドの印 `th.skip_slot_type_check` をやめ、**型を検査しない読み取り用の構築子**を使う形に変えた：`defstruct` は、標準の構築子と型のあるスロットがあれば、同じ引数と initform でスロットの型を検査しない関数を作り、クラスの記述の位置 6 に置く（`zl-sys::%structure-reader-constructor`・`%set-structure-reader`）。reader は、`#S` の値の中に仮の値があるときだけ、それを呼ぶ（`zl-sys::%read-structure` の 2 つ目の引数）。検査を省略するのは reader が作っている構造体のスロットだけで、initform の中の別の構築子・`setf` はいつもどおり検査する（仮の値が渡れば、その場で type-error。SBCL と同じ結果）。できた構造体は、今までどおりラベルが解決した後で確かめる。
- 結果（受入：Level 19 の主要コード）：Level 19 で `defstruct` のために Zilisp だけがエラーだった 10 ブロックは、すべて SBCL 2.6.7 と同じ出力（Level 19 に Zilisp だけがエラーのブロックはなくなった）。ほかの Level の `defstruct` のブロック（Level 7 の 7、Level 23 の 9、Level 24 の 2、Level 26 の 3）と、`get-universal-time` を呼ぶ Level 13 の 1 つも同じ出力になった。教材のブロックの一致は 513 から 545 に、Zilisp だけがエラーは 79 から 47 に（出力の違いは L455 の 1 つのまま）。boot.lisp の空でない行は 1934 から 2282 に。起動時間は 14.06 ms（変更の前の `4833203` と交互に 41 回ずつ測った中央値。変更の前は 13.40 ms）。pretty でない印字で先にリストを走査する費用は、4 万回の `prin1-to-string` で約 1 ms（起動時間の差を除く）。

### 11.3 標準ライブラリのビルド

- **Phase 08〜11**：Lisp の標準ライブラリを `@embedFile` で埋め込み、起動のたびに VM 向けにコンパイルする（ネイティブバックエンドができる前の暫定）。
- **Phase 12 以降**：`build.zig` を2段階にする。
  1. 第1段の zilisp（stage1。標準ライブラリを VM で実行する版）が、標準ライブラリを Core IR から Zig ソースに変換する。
  2. 第2段で、生成した Zig ソースをランタイムと一緒にコンパイルし、最終の zilisp を作る。**標準ライブラリはネイティブコードになり**、起動時のコンパイルも不要になる。
- 同じ仕組みを `zilisp build` に使う（§15）。
- 処理系自身の起動時間についても、§15.3 の「起動時間の対策（J1）」と同じ判断を行う。

---

## 12. 教材サンプルの A〜E 分類と依存関数一覧（手順）

分類作業そのものは、成果物 `compatibility/curriculum-inventory.md` と `compatibility/manifest.toml` として別に行う。

1. GitHub の `fukuyori/CommonLispBasicMaster` を取得し、対象のコミット SHA を固定する。
2. `tools/extract_samples/`（Zig）で、Markdown から `lisp` のコードブロックを抽出し、`level / ファイル / 行番号` の ID を付ける。
3. 各ブロックを SBCL 2.6.7（開発機にあることを確認済み）で読み込み、Reader エラーの有無、外部パッケージの参照、使用している CL シンボルを自動で収集する。
   - **読み込むだけで、評価はしない。** `*read-eval*` を偽にして、`#.` による読み込み時の評価を禁止する（レビュー #23。教材のコードを集めるだけの段階で、任意のコードを実行しないため）。
   - 存在しないパッケージを参照しているブロックは、エラーとして記録する（外部パッケージへの依存の検出に使う）。
   - 実行して結果を調べる必要がある作業（差分試験の期待値の作成など）は、この収集とは分けて、§13 の手順で行う。
4. 自動収集の結果をもとに、A〜E の分類を手作業で確定する（基本設計 §2.2）。
5. CL シンボルの使用頻度表を作り、`unimplemented` を外していく優先順位に使う。

---

## 13. SBCL との差分試験・性能計測

### 13.1 差分試験

**教材のブロックの実行**（Phase 13 から）：`zig build eval-check -Dsbcl=SBCL のパス` は、教材のブロックのうち分類の候補が A のもの（955 件）を、Zilisp（VM、`--script`）と SBCL 2.6.7（`--script`）で、ブロックごとの空の作業用ディレクトリの中で実行し（時間制限 10 秒）、結果を比べる。結果は `compatibility/eval-status.md`（集計と、Zilisp だけがエラーになったブロックの最初のエラーの内訳）と `compatibility/eval-check.tsv`（ブロックごと）に書く。未実装の機能の優先順位を決める材料にする。Phase 13 の時点：一致 82、両方ともエラー 362（前のブロックの定義を使うものなど）、出力の違い 0、Zilisp だけがエラー 511（すべて未実装の機能）。

- 試験用の Lisp ファイルは SBCL と Zilisp の両方で動くように書き、結果を正規化した文字列として出力する。
- `tools/compare_sbcl/`（Zig）が、両方を実行して出力を比較し、差分を分類（不具合／処理系依存／未実装）する。SBCL の期待出力は `tests/differential/*.expected` に保存する。
- **Zilisp の VM とネイティブコードの両方で同じ試験を実行**し、3者（SBCL、Zilisp VM、Zilisp ネイティブ）を比較する。
- **ANSI の試験集（ansi-test）を、VM だけの設定とネイティブの設定の両方で実行する**（R6）。ECL は、バイトコードだけの設定と C コンパイラありの設定の両方で ansi-test を実行し、想定どおり失敗する項目を一覧で管理している（`src/tests/config.lsp.in` 94〜97、137〜139行目、`src/tests/ansi-test-expected-failures.sexp`）。Zilisp も、実装範囲の外で失敗する項目を `tests/ansi/expected-failures` で管理する。ansi-test の入手先とライセンスは **未確認**（取り込む前に確認する）。

| 比較する | 比較しない（正規化する、または除外する） |
|---|---|
| 返り値（`prin1` 表現）、多値の数 | `#<...>` のアドレス部分 |
| 標準出力・標準エラー出力 | ハッシュテーブルの反復順序（ソートして比較する） |
| 通知された condition の型（標準の型に対する `typep`） | エラーメッセージの文面 |
| 副作用（ファイルの内容など） | 浮動小数の最下位桁（テストごとに許容差を指定） |
| | 処理系定数、`room`・`time` の出力 |
| | CLHS で未定義・処理系依存と明記された動作 |

処理系依存の差分は、根拠（CLHS の節番号）とともに `tests/differential/impl-dependent.toml` に記録して除外する。SBCL の結果を規格とはみなさない。

**方式が混ざる経路の試験**（レビュー #22）

VM だけ・ネイティブだけで同じ試験を通しても、方式の境界の不具合は見つからない。次の組み合わせの試験を `tests/language/mixed/` に置く。

| 試験の対象 | 組み合わせ |
|---|---|
| 呼び出しの経路 | VM → ネイティブ → VM、ネイティブ → VM → ネイティブ。共有ライブラリ（§7A.6）のコードを含む |
| 境界を越える処理 | 多値の受け渡し、`unwind-protect` の cleanup（正常終了・非局所脱出・cleanup の中の脱出）、動的束縛の解除、`handler-bind` / `restart-case` を越える脱出、境界の途中での GC（`--gc-stress`） |
| 入口の置き換え | 置き換えの前に取り出した関数オブジェクト、置き換えの前に作った closure、コンパイル中の再定義（§7A.6 のジョブの世代番号） |
| FFI | コールバックでの同じスレッドからの再入（§6.1） |

### 13.2 性能計測（速度最優先のための基盤）

- `tests/bench/` にベンチマークを置き、`zig build bench` で実行する。結果（実行時間、確保バイト数、GC 回数・停止時間）を `bench-results/` に記録し、前回の結果と比較する。
- 対象の処理：fixnum の算術、浮動小数の算術、リスト操作、再帰（fib、tak）、クロージャ、ハッシュテーブル、文字列、CLOS のディスパッチ、ファイル I/O、起動時間。
- 同じベンチマークを SBCL でも実行し、比較の参考値とする（最適化の設定を明記する）。
- **性能が下がる変更を入れる場合は、計測値と理由を記録する**（基本設計 §17）。
- **GC の方式の再判断**（レビュー #21）：1.0 は非移動型の mark-and-sweep とするが、Phase 30 で、寿命の長いデータと寿命の短い cons が混ざる処理（教材のデータ処理、REPL の長時間の利用を想定）で、GC の時間の割合と停止時間を計測する。**GC の時間が実行時間の一定の割合（初期案 20%）を超える場合は、1.0 の前に世代別 GC の導入を再検討する。**

---

## 14. コンパイル済みモジュール形式（`.zfasl`）

### 14.1 構成（確定）

```text
Header
  magic          "ZLFASL\0\0"（8 バイト）
  format_version u32         ── 形式・IR・バイトコードの版。不一致ならロードを拒否する
  zilisp_version 文字列
  flags          u32
  checksum       u32（CRC32。ヘッダを除く全体）
Sections
  STRS   文字列表（UTF-8）
  SYMS   シンボル参照（パッケージ名 + シンボル名、uninterned の識別子）
  OBJS   リテラルオブジェクト。共有構造と循環構造はオブジェクト ID で表す
  CIR    Core IR（型情報付き）── zilisp build がネイティブコードを生成する入力
  CODE   バイトコード（VM でロードする場合に使う）
  TOPL   トップレベルフォームの列。フォームごとに、そのフォームが使うシンボル・定数の参照を持つ
  LTV    load-time-value の一覧
  SRCS   ソースファイル名表
```

- **Core IR を保存する**ことで、`zilisp build` はソースを再びマクロ展開せずにネイティブコードを生成できる。
- **ロードの順序**（レビュー #8）：シンボルと定数は、**一括では解決しない**。TOPL のフォームを先頭から順に処理し、各フォームを実行する直前に、そのフォームが使うシンボルと定数だけを解決する。
  - これにより、同じファイルの前のトップレベルフォーム（`defpackage`・`in-package`・`use-package`・`shadow`・`import` など）の効果が、後のフォームのシンボルの解決に反映される（ソースを `load` した場合と同じ順序になる。CLHS `defpackage`、3.2.4）。
  - ロード時にパッケージを先回りして作ることはしない。シンボルの解決の時点でパッケージがなければ、`package-error` を通知する。
  - **uninterned のシンボル**（`#:foo` など）は、`intern` の経路とは別に、ファイルの中の識別子ごとに1つだけ作る。同じファイルの中で同じ識別子を参照する箇所は、同じシンボルを共有する（同一性を保つ）。
  - 一度解決したシンボル・定数は、ファイルの中の ID をキーにして再利用する。
- REPL の `load` と、ビルドした実行ファイルの起動で、トップレベルフォームの評価順序と意味は同じである。
- 読み込んだバイトコードは、リリースビルドでも検証してから使う（§7.4、レビュー #20）。ヘッダとセクションの長さ・添字・参照の範囲も、ロード時に検査する。
- リテラルの同一性・類似性は CLHS 3.2.4 に従う。構造体・インスタンスのリテラルは `make-load-form` を必要とし、ない場合はコンパイル時にエラーにする。
- 形式はエンディアンに依存せず、全ターゲットで共通に使える。

---

## 15. 実行ファイルの生成（`zilisp build`）（D-2・D-5・D-7）

### 15.1 方式

`zilisp build` は、アプリの全関数をネイティブコードにコンパイルし、ランタイムとリンクする。データと機械語は実行ファイルの正規のセクションに入るので、Windows（Authenticode）でも macOS（codesign）でも署名できる。

**SBCL の方式との比較**：SBCL の `save-lisp-and-die :executable t` は、ランタイムの**末尾にコアを追記**し、ファイルの最後にある目印からコアの位置を探す（確認済み：`src/runtime/coreparse.c` 104〜112行目）。macOS では、追記したデータが署名の領域より後ろに来るため、`codesign` の strict validation で失敗し、コアを別のファイルに分ける回避策が必要になる、という報告がある（§20 の参考資料。SBCL の公式文書ではなく、開発者のリリースノートでの報告）。Zilisp はこの問題を避けるため、追記ではなくリンクする方式をとる（D-2）。

### 15.2 処理の流れ

```text
zilisp build --manifest zilisp.toml
 1. マニフェストを読む（entry、sources、target、optimize）
 2. 新しいコンパイル環境で、sources を順に「compile-file → load」する
    （後のファイルが前のファイルのマクロとパッケージを使えるようにする）
 3. 各ソースの Core IR から Zig ソースを生成する（§7A）。Phase 12〜34 はメモリ上の Core IR から直接生成し、Phase 35 以降は .zfasl に保存した Core IR を使って、変更のないファイルのコンパイルを省く（agy #8）
 4. 作業ディレクトリ（.zilisp-cache/build/<target>/）に main.zig と build 用の記述を生成する
 5. ZIG 環境変数、または PATH 上の zig で、生成したソースと SDK 同梱のランタイムのソースを一緒にコンパイルする（D-5）
 6. 出力：app(.exe) と app.deps.txt（Zilisp の版、ターゲット、最適化モード、リンクした外部ライブラリ）
```

- 最適化モードの既定は **ReleaseFast**（速度最優先）とする。ランタイムの内部の安全検査（Zig の境界検査など）が必要な場合は `optimize = "ReleaseSafe"` を指定する。Lisp の安全検査（`type-error` など）は Zig の最適化モードとは独立で、`optimize` 宣言の `safety` に従う。
- 実行ファイルには、実行時の `eval`・`compile`・`load` のために、コンパイラと VM を含める。配布先には Zig がないため、実行時に `eval`・`load` したコードは VM で実行される（§7A.6 の「満たせない点」）。

### 15.3 起動の順序

1. ランタイムを初期化する（§11.1 の 1〜6）。
2. 標準ライブラリ（ネイティブコード）を初期化する。
3. アプリのモジュールを、マニフェストの順に初期化する（トップレベルフォームを実行する）。
4. `entry`（例：`app:main`）の関数を引数なしで呼ぶ。コマンドライン引数は `zilisp:*command-line-arguments*`（文字列のリスト）で参照できる。
5. 正常に戻ったら、ストリームをフラッシュして終了コード 0 で終了する。`(zilisp:exit :code n)` で任意の終了コードを返せる。処理されなかったエラーは §9.4 に従う（終了コード 1）。

**起動時間の対策（J1）**：手順 2・3 では、トップレベルフォームを実行し直してパッケージ・シンボル・クラス・グローバル変数を作る。Phase 36 で起動時間を計測し、遅い場合は、**標準ライブラリ（手順 2）についてだけ**、初期化が終わった状態（パッケージ、シンボル、定数、クラス表など）をバイト列にして実行ファイルに埋め込み、起動時に復元する方式に切り替える。Janet は、標準ライブラリの環境をバイト列（C の配列）として埋め込み、起動時に復元している（`src/boot/boot.janet` 5396〜5404行目、`src/core/corelib.c` 1400〜1418行目、`src/core/marsh.c`）。関数はネイティブコードなので、バイト列には入口の名前（または番号）だけを入れ、復元時に表から引く。

- **アプリのトップレベルフォーム（手順 3）は、置き換えずに必ず起動時に実行する**（レビュー #10）。ビルド時の状態に置き換えると、日時・乱数・環境変数・コマンドライン引数・ファイルの内容など、実行するたびに変わるはずの値がビルド時の値に固定され、動作が変わるためである。
- 標準ライブラリの初期化の中でも、実行環境に依存するもの（`*random-state*` の初期値、`*default-pathname-defaults*`、標準入出力のストリーム、環境変数を読む処理など）は、復元の後に起動時に実行する処理として分けておく。
- アプリの初期化済みの状態を保存して起動を速くする機能を将来提供する場合は、利用者が明示的に指定する別の機能とする（初期化が終わった状態をそのまま保存してよいことを、利用者が判断するため）。

---

## 16. `compile-file` と `zilisp build` の違い、マルチOS配布条件

### 16.1 2つの操作の違い

| 項目 | `compile-file` | `zilisp build` |
|---|---|---|
| 入力 | `.lisp` ファイル1つ | マニフェスト、または `.lisp` ファイル1つ |
| 出力 | `.zfasl` ファイル1つ（Core IR ＋ バイトコード。全ターゲット共通） | OS ネイティブの実行ファイルと `.deps.txt` |
| 実行時に必要なもの | Zilisp 処理系（`load` で読み込む） | 不要 |
| 実行方式 | `load` 後は VM（Phase 39 以降、Zig がある環境ではバックグラウンドでネイティブ化） | ネイティブコード |
| `eval-when` | CLHS 3.2.3.1 の表に従う | 各ソースに `compile-file` と同じ処理を行う |
| Zig ツールチェーン | 不要 | 必要 |

- **トップレベルフォームの処理**（agy #6。CLHS 3.2.3.1「Processing of Top Level Forms」）：ファイルの最上位のフォームだけでなく、次のフォームの本体にあるフォームも、トップレベルフォームとして**再帰的に**1つずつ処理する。
  - `progn` の本体
  - `locally` の本体（宣言を引き継ぐ）
  - `macrolet`・`symbol-macrolet` の本体（定義したローカルのマクロ・シンボルマクロの環境を引き継ぐ）
  - `eval-when` の本体（CLHS 3.2.3.1 の表に従う）
  - マクロの展開結果（展開してから、上の規則を当てはめる）
  - `let`・`flet` などの本体は、トップレベルとして扱わない（例：`(let ((x 1)) (defun foo () x))` の `defun` はトップレベルフォームではない）。
  - `.zfasl` の TOPL（§14.1）の1項目は、この分割後のトップレベルフォーム1つに対応する。
- トップレベルフォームのコンパイル時の効果（CLHS 3.2.3.1.1）：`defmacro` はコンパイル環境にマクロを登録し、`defun` は関数の存在を記録し、`defvar` / `defparameter` は special を宣言し、`defpackage` / `in-package` は `eval-when (:compile-toplevel :load-toplevel :execute)` に展開する。**`defconstant` は、コンパイル時に値のフォームを評価できる場合は評価して定数として記録し、後続のフォームでの定数畳み込みと、代入・束縛の検出（§8.1）に使う**（agy #13。CLHS `defconstant`）。
- 未定義関数の警告は、コンパイル単位の終わりにまとめて `style-warning` として出力する。

### 16.2 マルチOSの配布条件（すべて要検証）

| OS | 方針 | 実行時の依存 |
|---|---|---|
| Windows x86-64 | libc をリンクしない構成を第一案とする | OS の DLL（kernel32 等）のみ |
| Linux x86-64 | musl で静的リンクする | なし（GUI・TLS を使う場合を除く） |
| macOS AArch64 | libSystem に動的リンクする | libSystem |

GUI（Tk）や TLS などの外部ネイティブライブラリを使うアプリは、依存を `.deps.txt` に列挙し、「完全な静的リンク」とは表示しない。

### 16.3 単一の実行ファイルにするための条件

| 項目 | 条件 |
|---|---|
| 出力 | 実行ファイル1つ（`app.exe` / `app`）。依存の一覧 `app.deps.txt` は確認用で、実行には不要 |
| 実行ファイルに含めるもの | アプリのネイティブコード、標準ライブラリ（ネイティブコード）、ランタイム（GC・CLOS・condition 等）、実行時の `eval`・`compile`・`load` のためのコンパイラと VM |
| ビルドする PC | Zilisp の SDK と Zig が必要 |
| 実行する PC | Zilisp も Zig も不要 |
| 外部ファイル | 実行に `.lisp` ソースや `.zfasl` は不要 |
| 他 OS 向けのビルド | Zig のクロスコンパイルで作成する。クロスビルドの成否と、実機での動作確認は区別して報告する |
| 確認の時期 | 「Windows では OS の DLL のみ」「Linux では依存なしの1ファイル」は**要検証**。Phase 12 の試作で確認し、Phase 38 でクリーンな環境での動作を検証する |

---

## 17. 決定事項

判定の基準（2026-11-01、レモンの指示）：**推奨が条件（実行速度最優先、標準の意味論は前提条件）を満たす場合は、推奨を採用する。**

| ID | 事項 | 決定 | 反映箇所 |
|---|---|---|---|
| D-0 | 準拠の範囲 | 基本設計のとおり（実用的な互換サブセット。実装済み機能は標準に忠実） | 全体 |
| D-1 | 評価器を作るか | 作らない。すべてコンパイルしてから実行する | §5.1、§19 |
| D-2 | 実行ファイルの生成方式 | Zig でリンクする | §15 |
| D-3 | `loop` の実装 | 独自に実装する | §11.2 |
| D-4 | 処理されなかったエラーでの終了コード | 1 | §9.4、§15.3 |
| D-5 | SDK のランタイムの同梱方法 | ソースで同梱する（生成コードとまとめて最適化するため） | §7A.1、§15.2 |
| D-6 | 処理系のライセンス | MIT（著作権表示は fukuyori） | 冒頭、§18 |
| D-7 | ネイティブコード生成を主経路にするか | 主経路にする | §5.1、§7A、§11.3、§14、§15 |
| D-8 | ネイティブのフレームでの GC ルートの見つけ方 | ネイティブのスタックとレジスタを保守的に走査する。ヒープ内は正確に走査する | §3.3〜§3.5 |
| D-9 | Value の表現とヒープ | Value 8バイト（下位ビットのタグ）、cons 16バイト、ページ単位のヒープ、ページ外のマークビット | §2、§3 |
| D-10 | REPL・`eval`・`load` の速度 | Phase 08 は VM で始める。Phase 39 で、バックグラウンドで Zig により共有ライブラリを作って入口を置き換える方式（④）を実装する（2026-11-01 に MIR・libgccjit の調査結果を受けて変更）。Zig がない環境での `eval`・`load` は VM のまま（満たせない点として明記） | §5.1、§7.1、§7A.6 |

---

## 18. 処理系自身のビルド・リリーススクリプト

### 18.1 スクリプト

| ファイル | 役割 |
|---|---|
| `scripts/build-release.ps1` | `zig build -Doptimize=ReleaseFast` を各ターゲット向けに実行し、`dist/<target>/` に出力する。単体テスト・言語テスト・ベンチマークを実行する |
| `scripts/build-installer.ps1` | Inno Setup（`ISCC.exe`。開発機の `C:\Program Files (x86)\Inno Setup 6\` にあることを確認済み）で Windows 用インストーラーを作成する |
| `installer/zilisp.iss` | Inno Setup のスクリプト |
| `LICENSE` | MIT ライセンス。著作権表示は `Copyright (c) 2026 fukuyori`（Phase 01 で作成） |

### 18.2 署名（`-Sign` オプション）

- `scripts/build-installer.ps1 -Sign` を指定した場合、次の3つに電子署名を付ける。
  1. `zilisp.exe`（インストーラーに入れる前に署名する）
  2. アンインストーラー（Inno Setup の `SignTool` / `SignedUninstaller` の指定で署名する。`ISCC.exe` に `/Szlsign=$q<signtool>$q sign /n $q<CODESIGN_CERT>$q /fd sha256 /tr <タイムスタンプ> /td sha256 $f` と `/DSign` を渡す。0.2.0 で作成。実際に署名できるかは、利用者の `-Sign` の実行で確認する）
  3. インストーラー本体
- 署名に使う証明書は、環境変数 `CODESIGN_CERT` の値で指定する。値は証明書のサブジェクト名で、現在の利用者の証明書ストアから `signtool sign /n` で選ぶ（開発機で、ストアの証明書と一致することを確認した）。未設定で `-Sign` を指定した場合は、エラーで停止する。タイムスタンプは RFC 3161（既定 `http://timestamp.digicert.com`。`-TimestampUrl` で変更できる）。
- 配布物は `dist/release/` に出力する：`zilisp-<版>-x86_64-windows-setup.exe` と、ターゲットごとの `zilisp-<版>-<target>.zip`（`bin/` の実行ファイル、`LICENSE`、`README.md`・`README.ja.md`、`CHANGELOG.md`・`CHANGELOG.ja.md`）。インストーラーは利用者ごとのインストール（管理者権限は不要。選べば全利用者）で、PATH への追加を選べる。
- **配布物（ZIP、インストーラー）の作成は利用者（レモン）が `-Sign` を付けて行う。** Claude は配布物を作成しない。

### 18.3 バージョン更新のチェックリスト

`docs/version-update-checklist.md` に、バージョンを変更するときに更新するファイルを列挙する（`build.zig.zon` の `version`、`src/version.zig`、`installer/zilisp.iss` の `AppVersion`、`CHANGELOG.md`（英語）・`CHANGELOG.ja.md`（日本語）、`.zfasl` の `format_version`（IR・バイトコードを変更した場合のみ）等）。Phase 01 で作成する。


### 18.4 GitHub Actions（0.2.0 で追加）

| ワークフロー | 起動 | 内容 |
|---|---|---|
| `.github/workflows/test.yml` | `main` への push、pull request、`release.yml` からの呼び出し | Linux・macOS（arm64）・Windows で `zig fmt --check`、`zig build test`、`lang-test`、`native-test` |
| `.github/workflows/release.yml` | タグ `v*` の push | ①タグと `build.zig.zon`・`src/version.zig` のバージョン、`CHANGELOG.md`・`CHANGELOG.ja.md` の見出しの一致を確かめる ②試験（`test.yml`） ③ビルド：x86_64・aarch64 の Linux（musl）と macOS は ReleaseFast で `.tar.gz`（`bin/zilisp`・`LICENSE`・README と CHANGELOG の英語版・日本語版）、x86_64 の Windows は `scripts/build-installer.ps1`（署名なし）でインストーラーと ZIP。実行できるもの（x86_64 Linux、aarch64 macOS、Windows）は `--version` と言語試験の1つで確かめる ④`CHANGELOG.md`（英語）と `CHANGELOG.ja.md`（日本語）の該当バージョンの節をリリースノートにして、GitHub のリリースを登録する |

- Zig は `mlugg/setup-zig@v2` で 0.17.0 を入れる。
- **CI の配布物には署名を付けない**（2026-11-02 決定：証明書は開発機の証明書ストアにあり、CI では使わない）。リリースノートに、署名がないこと（SmartScreen・Gatekeeper の警告）を書く。署名付きの Windows の配布物は、利用者が `-Sign` で作り、リリースのファイルを差し替える（`docs/version-update-checklist.md`）。§18.2 の「配布物は利用者が `-Sign` を付けて作る」は、署名付きの配布物についての規則とする。
- 未確認：ワークフローの動作は、最初のタグの push（または `main` への push）で確かめる。

---

## 19. Phase 01〜08 の実装単位への分解

| Phase | 作業単位 | 受け入れ条件 |
|---|---|---|
| 01 | `build.zig` / `build.zig.zon`、`src/main.zig`（CLI の引数解析）、`src/version.zig`、`LICENSE`、`docs/zig-std-usage.ja.md`（§1.3 の検証結果）、`docs/version-update-checklist.md`、`scripts/build-release.ps1` の骨組み、**ベンチマーク実行器**（`zig build bench`） | `zilisp --version`、`zilisp --help` が動く。`zig build test` と `zig build bench` が動く |
| 02 | `tools/extract_samples/`、`compatibility/manifest.toml` の雛形、言語テストの実行器（`zig build lang-test`） | 教材のコミットを固定し、コードブロックを ID 付きで抽出できる |
| 03 | `src/reader/`：字句解析、整数・浮動小数、シンボル、コメント、`SourceMap` | 代表的な S 式を読み取れ、位置情報が記録される |
| 04 | Reader：quote、文字列、リスト、ドットペア、`#(`、`#\`、`#'`、backquote | Reader の試験が通る |
| 05 | `src/values/`（8バイトの Value、タグ操作）、`src/runtime/package.zig`、`cl_symbols.zig`、printer の最小版 | タグ操作の単体テスト、`eq` による同一性、印字の round-trip |
| 06 | `src/runtime/heap.zig`（ページ表、サイズクラス、確保の高速経路）、`roots.zig`（明示的ルート、FFI handle） | 確保と参照が安全にできる。確保速度をベンチマークで記録する |
| 07 | `src/runtime/gc.zig`（ビット表によるマーク、遅延スイープ、保守的スタック走査、`--gc-stress`、poison、統計） | 循環構造を回収できる。stress モードで単体テストが通る。停止時間を記録する |
| 08 | 最小の Resolver ＋ IR ＋ バイトコード生成 ＋ VM（`quote` `if` `progn` `let` `setq` `lambda` `funcall`、算術、リスト）、REPL | `(+ 1 2)`、`(list 1 2 3)`、クロージャの例題が REPL とファイル実行で動く |

**Phase 08 の CLI**（基本設計 §12.1）：`zilisp`（REPL。入力が終われば終わる）、`zilisp FILE` と `zilisp --script FILE`（フォームを1つ読むごとに評価する。エラーで止まり、終了コード 1。SBCL の `--script` と同じ）、`zilisp --eval TEXT`（値は印字しない。SBCL の `--eval` と同じ）、`zilisp --load FILE`（評価してから REPL）。エラーは標準エラー出力に `ファイル:行:列: 型の名前: 説明` の形で出す。

Phase 12 で、ネイティブバックエンドの最小実装（IR → Zig）を作り、VM とネイティブの結果の一致、Zig によるコンパイル時間、性能、単一の実行ファイルにできること（§16.3）を確認する（基本設計 §15）。

---

## 20. 参考資料

| 資料 | 版・取得日 | 参照した内容 |
|---|---|---|
| SBCL のソース（ローカル `D:\home\source\lisp\sbcl`） | `sbcl-2.6.10-68-g05b7eef0a`（2026-11-01 に参照） | `COPYING`、`src/compiler/generic/early-objdef.lisp`、`src/compiler/generic/early-vm.lisp`、`src/compiler/x86-64/parms.lisp`、`src/runtime/gencgc.c`、`src/runtime/coreparse.c`、`src/compiler/generic/genesis.lisp` |
| SBCL 2.6.7（インストール済み） | 2026-11-01 に実行 | `most-positive-fixnum`、`*evaluator-mode*`、cons の大きさ、内部の機能フラグ、`base-char-code-limit` |
| SBCL のライセンス | 同上 `COPYING` | パブリックドメイン（一部 BSD 系。LOOP・PCL は著作権表示を残す条件付き）。Zilisp にはコードを取り込まない |
| [utc-status-app v0.2.0 のリリースノート](https://github.com/lispnik/utc-status-app/releases/tag/v0.2.0) | 2026-11-01 に参照 | macOS で SBCL の実行ファイルを codesign できない問題と回避策（開発者による報告） |
| [MIR（vnmakarov/mir）](https://github.com/vnmakarov/mir) | 2026-11-01 に参照 | ライセンス、対応ターゲット、C API、生成コードの性能 |
| ECL のソース（ローカル `D:\home\source\lisp\ecl`） | `26.5.5-193-g2476efb4f`（2026-11-01 に参照） | 2経路（バイトコード・C）の構成、`setjmp`/`longjmp` による非局所脱出、多値、Boehm GC、`build-program`、タグの割り当て、ansi-test の実行方法。ライセンスは LGPL 2.1 以降（`COPYING`、`LICENSE`） |
| Clasp のソース（ローカル `D:\home\source\lisp\clasp`） | `3.0.1-432-g90f0ff882`（2026-11-01 に参照） | LLVM と保守的スタック走査の組み合わせ、非局所脱出の方式と速度の記録、主値と個数を返す呼び出し規約、バイトコードとバックグラウンドのネイティブ化、タグの割り当て。ライセンスは LGPL 2.1 以降（`licenses/clasp_Copyright`、`licenses/LGPL`） |
| Gambit のソース（ローカル `D:\home\source\lisp\gambit`） | `v4.9.8-35-gf1c787a0`（2026-11-01 に参照） | C を生成する方式での末尾呼び出し（トランポリン）、生成コードのコンパイル時間の対策、モジュールのリンクと初期化の順序。ライセンスは Apache 2.0 と LGPL 2.1 の選択（`doc/gambit.txi` 20022〜20025行目） |
| Emacs のソース（ローカル `D:\home\source\lisp\emacs`） | `emacs-31.1-1315-g9008bf64c33`（2026-11-01 に参照） | libgccjit によるネイティブコンパイルの構成、Windows での扱い、共有ライブラリの読み込みと再配置、保守的スタック走査。ライセンスは GPL 3 以降（`COPYING`） |
| SICL のソース（ローカル `D:\home\source\lisp\sicl`） | コミット `fce5770d4`（2026-11-01 に参照） | クラスの番号（stamp）によるディスパッチとキャッシュの失効、rack によるインスタンスの表現、判別用のコードの生成、タグの割り当て、中間表現の段階分け。ライセンスは BSD 2条項（`LICENSE-BSD`）。`loop`（Khazern）・`format`（Invistra）など外部リポジトリのライセンスは未確認 |
| Janet のソース（ローカル `D:\home\source\lisp\janet`） | `v1.42.1-97-ga2c0d0c8`（2026-11-01 に参照） | NaN-boxing（整数は ±2^53 まで）、レジスタ型 VM の命令形式と分岐の方式、VM の決まった時点でだけ動く GC、初期化済みの環境をバイト列で埋め込む方式。ライセンスは MIT（`LICENSE`） |
| Carp のソース（ローカル `D:\home\source\lisp\carp`） | `v0.6.0-58-gcda0b32d`（2026-11-01 に参照） | C の生成と名前の変換、REPL の実行方式（静的なコードは毎回全体をビルド）、`#line` によるソース位置の対応づけ。ライセンスは Apache 2.0（`LICENSE`） |
| 上記の処理系のライセンスについて | — | いずれも Zilisp（MIT）にはコードを取り込まず、設計の参考としてのみ参照する |
| [Common Lisp HyperSpec](https://www.lispworks.com/documentation/HyperSpec/Front/index.htm) | — | 規格の参照先 |
