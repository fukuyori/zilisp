# Zilisp 詳細設計書

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
| 0.2（追記8） | 2026-11-02 | Phase 08 の実装に合わせて、condition ができるまでのエラーの扱い（§6.6）、`call-arguments-limit` の解釈（§7.3）、Phase 08 で実装した命令とフレームの形（§7.4）、CLI の動作（§19）を追記 |
| 0.2（追記7） | 2026-11-02 | Phase 07 の実装に対する Codex のレビュー（10件）を受けて、レジスタの退避の方法と走査の下端を確定（§3.4）。実装側では §3.5 の規則（Zig のヒープに Lisp の値を置くなら明示的なルートに登録する）への違反を修正 |
| 0.2（追記6） | 2026-11-01 | Phase 01 の照合結果（`docs/zig-std-usage.md`）を受けて、Value を `enum(u64)` で定義（§2.1）、戻り値の規約を案 A に変更（主値だけをレジスタで返し、個数は `th.mv_count`、非局所脱出・エラーは特別な即値 `Value.unwind` と `th.fault`。§2.2・§6.1〜§6.4・§6.6・§7A.2）、汎用の入口を `callconv(.c)` に（§6.2） |
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

**Phase 01 の検証項目**：上表の各機能について、0.17.0 に実在すること、シグネチャ、使用例を `docs/zig-std-usage.md` に記録する。存在しない機能があれば本書を改訂する。

---

## 2. Value 表現とヒープオブジェクトヘッダ（D-9）

### 2.1 方針

- `Value` は **8バイト（64ビット）の1語**とし、**下位3ビットに型タグ**を置く。ヒープのオブジェクトは8バイト境界（cons は16バイト境界）に配置するので、ポインタの下位3ビットは常に 0 であり、タグに使える。
- `Value` のビット操作は `src/values/` の中だけで行う。他の層はメソッド（`isCons()`、`asFixnum()`、`Value.fromFixnum()` など）経由でのみ扱う。
- **Zig での定義は `enum(u64)`（非網羅の enum）とする**（2026-11-01 確定）。Zig 0.17.0 の既定の呼び出し規約では、`enum(u64)` の値はレジスタで返されるが、8バイトの `extern struct` はメモリ経由で返される（`docs/zig-std-usage.md` §3 で、x86_64-windows・x86_64-linux・aarch64-macos のアセンブリを確認）。

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
| `hash_table` | other | 比較関数、エントリ配列、インデックス表 | `hash-table` |
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
| `stream` | other | 種別、OS ハンドル／文字列バッファ、エンコーディング | `stream` |
| `pathname` | other | host、device、directory、name、type、version | `pathname` |
| `environment` | other | コンパイラの環境（動的エクステントのみ有効） | `&environment` の値 |
| `foreign_pointer` | other | アドレス、所有フラグ | （拡張） |
| `random_state` / `readtable` | other | | `random-state` / `readtable` |

- マクロ専用の ObjKind は設けない。マクロ関数は関数オブジェクトで表し、シンボルの関数セルに「マクロ」フラグを付けて区別する。
- condition は condition-class の `instance` とする（§9）。
- 要素型を特殊化した配列（`double_vector`、`fixnum_vector`）は、値をボックス化せずに並べる。数値計算の速度のために 1.0 から用意する。

### 2.5 文字列

- 型は `(simple-array character (*))`。内部的には幅1バイト（コード ≤ #xFF）と幅4バイトの2通りの表現を持つ。幅1の文字列に #xFF を超える文字を `setf` した時点で、バッファだけを幅4に再確保する（オブジェクトは移動しない）。
- `base-char` はコード < 128 の文字とする。SBCL も Unicode 対応版では同じ境界である（確認済み：`src/compiler/generic/early-vm.lisp` 121行目 `base-char-code-limit #-sb-unicode 256 #+sb-unicode 128`。SBCL 2.6.7 で `sb-int:base-char-code-limit` = 128、`(typep (code-char 200) 'base-char)` = NIL）。
- UTF-8 への変換は、ストリームと FFI の境界でのみ行う。

### 2.6 ハッシュテーブル

- **`eq` のハッシュ**：非移動型 GC なので、アドレス（即値は語そのもの）を使える。
- **`eql` のハッシュ**（レビュー #4）：アドレスは使えない。`eql` は、型が同じで値が等しい数（bignum・ratio・double-float・complex）と文字を等しいとみなすため（例：`(eql (expt 2 100) (expt 2 100))` は T、`eq` は NIL。SBCL 2.6.7 で確認）。数と文字は値からハッシュを計算し、それ以外のオブジェクトはアドレスを使う。
- **`equal` と `equalp` のハッシュは別の関数にする**（agy #12）。
  - `equal` 用：CLHS `sxhash` と整合させる（`equal` な2つのオブジェクトは同じ値になる）。
  - `equalp` 用：`equalp` で等しいものが同じ値になるようにする。具体的には、**数は数値として等しければ同じ値**（`1`・`1.0f0`・`1.0d0`・`#c(1.0 0.0)` など。`equalp` は数を `=` で比べるため）、**文字は大文字小文字を区別しない**（`char-equal`）、**文字列と文字のベクタは同じ計算方法**（`"abc"` と `#(#\A #\b #\c)` は `equalp`）、配列・構造体・ハッシュ表は要素を再帰的に使う。`sxhash` は `equal` 用であり、`equalp` 用には使えない（CLHS `equalp`、`sxhash`）。
  - キーとして使っている間にオブジェクトを変更した場合の結果は未定義である（CLHS 18.1.2）。
- **エントリの並べ方**（レビュー #21）：挿入順のエントリ配列とオープンアドレス方式のインデックス表で構成する案を初期案とする。CLHS は `maphash` の順序を規定しておらず、差分試験は順序を並べ替えて比べる（§13.1）ため、挿入順を保つ必要はない。**Phase 21 で、挿入順を保たない方式と、検索・挿入・削除・走査の速さとメモリ使用量を比べ、速い方を採用する。**
- `:weakness` 引数は 1.0 では未対応とし、指定された場合はエラーにする。

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
   - レジスタを出力に指定する書き方（`"={rbx}"`）で読む。メモリを指す書き方（`0(%[r])`）は Zig の x86_64 用コード生成器で使えない。フレームポインタ（`rbp`・`x29`）は指定できないので `mov` 命令で読む（`docs/zig-std-usage.md` §2）。
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
- `let*` は、変数1つの `let_` を入れ子にして表す（Phase 09）。各初期値は、それより前の変数が見える範囲で解決する。`let` と違い、同じ名前の変数を2回束縛してよい（後の束縛が前を隠す。SBCL 2.6.7 で確認）。`let`・`let*` の変数の局所変数の番号は、本体を抜けた後で再利用する（closure は作った時点の値か value_cell を捕捉するので、番号の再利用の影響を受けない）。
- `Var` は `captured` と `assigned` を持つ。両方が真の変数だけを `value_cell` に入れる（assignment conversion）。
- `Var` と `Node` は推論した型（`TypeId`：fixnum、double-float、cons、simple-vector、`t` など）を持つ。ネイティブバックエンドは型に応じてボックス化と型検査を省く（§7A.3）。
- `BlockInfo` / `TagbodyInfo` は `nonlocal`（内側のクロージャから脱出される）を持つ。偽の場合はジャンプにする。
- CL の 25 個の特殊演算子は Resolver が直接解釈する。
- `prim`（インライン化）の対象は CL パッケージの関数に限り、`flet` / `labels` で局所的に隠されていない場合だけ行う（CL パッケージの関数の再定義は未定義の動作：CLHS 11.1.2.1.2）。
- **CL パッケージの関数の直接呼び出し**（agy #11）：インライン化しない CL パッケージの関数（`format`、`mapcar`、`sort` など）も、同じ理由で、関数セルを経由せずにネイティブの入口を直接呼ぶ（`flet` / `labels` で局所的に隠されている場合を除く）。
- **`&environment` と `define-symbol-macro`**（agy #15）：`defmacro` の `&environment`（§2.4 の `environment` オブジェクト）と `&whole` は Phase 15、`define-symbol-macro`（シンボルのフラグ `global_symbol_macro`）と `symbol-macrolet` は Phase 15 で実装する。
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
- **この規約にした理由**：Zig 0.17.0 では、`Error!Ret`、エラーを含む型、16バイトの構造体は、x86_64-windows・x86_64-linux・aarch64-macos のどれでもメモリ経由で返される。`callconv(.c)` の16バイトの構造体は Linux・macOS ではレジスタで返るが、開発の一次ターゲットの Windows ではメモリ経由になる。`enum(u64)` の値だけが、3つのターゲットすべてでレジスタで返る（`docs/zig-std-usage.md` §3）。
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
    resume: Resume,        // VM：フレーム番号・sp・ip。ネイティブ：エントリの番号だけ（復帰は Zig のエラーで行う）
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

1. 特別な戻り値で伝える方式（本節の方式）
2. `setjmp`/`longjmp` に相当する方式（脱出先でレジスタとスタック位置を保存し、直接戻る。Zig の後始末を飛ばすため、ランタイム側の `errdefer` に頼る処理を制御スタックに登録する必要がある）

### 6.5 動的束縛

- shallow binding とする。束縛では、シンボルの値セルの旧値を束縛スタックに退避してから新しい値を書く。解除と巻き戻しで旧値を戻す。
- **旧値が未束縛の場合も、未束縛のまま退避・復元する**（レビュー #9）。例：`(defvar *x*)` の後の `(let ((*x* 1)) *x*)` は 1 を返し、`let` を抜けると `*x*` は再び未束縛になる（SBCL 2.6.7 で確認）。
- **未束縛のエラー（`unbound-variable`）は、値を読み出すときだけ通知する。** 代入（`setq`・`setf`）と動的束縛（`let`・`progv`）は、未束縛の特殊変数に対しても行える。
- `progv` で値の数がシンボルの数より少ない場合、残りのシンボルは束縛されるが値を持たない（未束縛になる）。束縛を解除すると旧値に戻る（CLHS `progv`）。
- スレッドを導入するときは、シンボルに TLS の添字を持たせる方式に拡張する。

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
- **condition ができるまで（Phase 08〜24）の暫定の扱い**（Phase 08 で決定）：プリミティブ・VM・コンパイラが見つけた Lisp のエラーは、`th.signal(kind, message, datum, expected)` で `th.fault = .lisp_error` と `th.err` に記録し、`Value.unwind` を返す。`kind` は CL の condition 型に対応させる（`type-error`、`unbound-variable`、`undefined-function`、`program-error`、`division-by-zero`、`floating-point-overflow`、`storage-condition` など。未実装の機能は Zilisp の拡張の `zilisp:unimplemented`）。トップレベル（REPL・スクリプト・`--eval`）まで戻って、型の名前と説明を1行で報告する。Phase 25 で、`th.signal` を handler を探して呼ぶ処理に置き換え、最後は toplevel の `abort` restart へ脱出する形にする。

### 6.7 スタックの大きさ

- ネイティブのスタックの大きさは、起動時（Windows では実行ファイルのヘッダ、その他ではメインスレッドを作り直す方法）で指定する。既定値は計測して決める（初期案 64 MiB。要検証）。
- スタックが溢れそうになったら `storage-condition` を通知する。ネイティブコードの関数の入口で残り量を検査する（ページを保護する方式は後で検討する）。
- 定数（初版の案）：`call-arguments-limit` = 65536、`multiple-values-limit` = 1024、`lambda-parameters-limit` = 1024。

---

## 7. バイトコード VM

### 7.1 位置づけ

- VM は、REPL・`eval`・ソースの `load` で定義したコードを**すぐに**実行するための方式である。Phase 39 以降は、バックグラウンドでネイティブ化が終わるまでの間と、Zig がない環境で使う（§7A.6）。
- 速度の主経路はネイティブコードなので、VM は実装が単純な**スタック型**とする。ただし、命令の分岐にはラベル付き `switch` と `continue`（スレッデッドコード相当）を使う（要検証）。
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
| 非局所 | `BLOCK_ENTER` / `BLOCK_EXIT` / `RETURN_FROM_NL` | i rel / — / i | §6.4 |
| | `TAGBODY_ENTER` / `TAGBODY_EXIT` / `GO_NL` | i n rel[n] / — / i u16 | |
| | `CATCH_ENTER` / `CATCH_EXIT` / `THROW` | rel / — / — | |
| | `UWP_ENTER` / `UWP_EXIT` / `UWP_END` | rel / — / — | |
| 条件 | `HANDLER_PUSH` / `HANDLER_POP` / `RESTART_PUSH` / `RESTART_POP` | — | §9 |
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
- シャドウイングシンボルかどうかの判定は、リストの探索ではなく、シンボルのフラグ（`shadowing`。パッケージごとに異なり得るため、パッケージ側の集合と併用する）で行う。

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

- condition は condition-class の `instance` として表す。標準の condition 型の階層は、ブートストラップ時に Zig の表から作成する。
- `define-condition` は `:report` と `:reader` をサポートする。

### 9.2 handler

- `handlers` スタックの各要素は cluster（`(型 . 関数)` の並び）である。`handler-bind` 1つが cluster 1つに対応する。
- `signal` はスタックを上から走査し、型が一致した関数を呼ぶ。呼ぶ間は、handler スタックの有効な上端を、その cluster より下に一時的に下げる（CLHS 9.1.4.1）。
- handler は通知した場所の動的環境で実行する（巻き戻さない）。
- `handler-case` と `ignore-errors` は、`handler-bind` ＋ `block` / `return-from` のマクロとして Lisp で定義する。

### 9.3 restart

- `restarts` スタックの各要素は {name、function、test、report、interactive、関連付けられた condition} を持つ。
- `restart-case` は `restart-bind` ＋ `tagbody` / `go` のマクロとして Lisp で定義する。
- 標準の restart 関数 `abort`、`continue`、`muffle-warning`、`store-value`、`use-value` を提供する。

### 9.4 デバッガ（D-4）

| 実行形態 | 処理されなかった `error` への動作 |
|---|---|
| REPL | condition の型・メッセージ・発生位置・backtrace と、restart の一覧を番号付きで表示する。番号の入力で `invoke-restart` を実行する。toplevel の `abort` で REPL に戻る |
| `--script` / ソース実行 / ビルドした実行ファイル | 標準エラー出力に condition と backtrace を出力し、**終了コード 1** で終了する |

- `*debugger-hook*` と `invoke-debugger` は標準どおりに実装する。
- 処理されなかった `warning` は `*error-output*` に出力して続行する。

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
  2. アンインストーラー（Inno Setup の `SignTool` / `SignedUninstaller` の指定で署名する。指定方法は要検証）
  3. インストーラー本体
- 署名に使う証明書は、環境変数 `CODESIGN_CERT` の値で指定する。未設定で `-Sign` を指定した場合は、エラーで停止する。
- **配布物（ZIP、インストーラー）の作成は利用者（レモン）が `-Sign` を付けて行う。** Claude は配布物を作成しない。

### 18.3 バージョン更新のチェックリスト

`docs/version-update-checklist.md` に、バージョンを変更するときに更新するファイルを列挙する（`build.zig.zon` の `version`、`src/version.zig`、`installer/zilisp.iss` の `AppVersion`、`CHANGELOG.md`、`.zfasl` の `format_version`（IR・バイトコードを変更した場合のみ）等）。Phase 01 で作成する。

---

## 19. Phase 01〜08 の実装単位への分解

| Phase | 作業単位 | 受け入れ条件 |
|---|---|---|
| 01 | `build.zig` / `build.zig.zon`、`src/main.zig`（CLI の引数解析）、`src/version.zig`、`LICENSE`、`docs/zig-std-usage.md`（§1.3 の検証結果）、`docs/version-update-checklist.md`、`scripts/build-release.ps1` の骨組み、**ベンチマーク実行器**（`zig build bench`） | `zilisp --version`、`zilisp --help` が動く。`zig build test` と `zig build bench` が動く |
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
