# Zilisp — Zigによる実用的Common Lisp互換処理系

**開発企画・基本設計書 / Version 0.3 / 2026-11-01**

| 版 | 日付 | 改訂内容 |
|---|---|---|
| 0.2 | 2026-10-31 | 初期の企画・基本設計 |
| 0.3 | 2026-11-01 | **実行速度を優先順位の最上位に変更**（§1、§17）。詳細設計書の決定事項 D-0〜D-10 に合わせて §1.2、§4、§5、§7、§12A、§13.4、§15、§16、§18、§20 を改訂。ライセンスを MIT に決定 |
| 0.3（追記3） | 2026-11-01 | Codexによるレビューの指摘を反映（§5.2 世代別GCの再判断の基準、§8.1 クラスの再定義の標準手順、§12A.2 ビルド方式の図を現在の主経路に更新） |
| 0.3（追記2） | 2026-11-01 | §14 のリポジトリ構成案を詳細設計に合わせて更新（設計文書は詳細設計書1冊に集約）。§22 に調査した処理系を追加 |
| 0.3（追記） | 2026-11-01 | 他処理系（ECL・Clasp・Gambit・Emacs）の調査結果を受け、REPL・`eval`のネイティブ化を「プロセス内コード生成器」から「バックグラウンドでZigにより共有ライブラリを作る方式」に変更（冒頭の表、§4、§7.3、§12A.1、§15、§18） |

| 項目 | 内容 |
|---|---|
| 名称 | Zilisp（Zig + Lisp、ジリスプ） |
| プロジェクトの性格 | Common Lispの実用的な互換サブセットを実装する独立処理系 |
| 実装言語 | **Zig（確定）** |
| 対象OS | Windows、Linux、macOS（x86-64を優先、AArch64を段階追加） |
| 実行方式 | **ネイティブコンパイル（主経路）と単独実行ファイル生成（必須）**。REPL・`eval`・ソースの`load`はバイトコードVMですぐに実行し、Zigのある開発環境ではバックグラウンドでネイティブコードに置き換える |
| ライセンス | MIT |
| 基準教材 | [CommonLispBasicMaster](https://github.com/fukuyori/CommonLispBasicMaster) |
| 最初の安定版 | Zilisp 1.0：定義された互換性マトリクスと受け入れテストを満たす版 |
| 方針 | ANSI Common Lisp完全準拠は目指さず、**実装済み機能の振る舞いは標準に忠実**とする |

> **文書の位置づけ**：本書は開発開始のための企画と基本設計である。Zigのバージョン、バイトコード命令の数値符号化、外部パッケージの具体的な実装ライブラリ等は詳細設計時に確定する。記載されたコマンドは予定のインターフェースであり、実装済みを意味しない。

## 1. 背景・目的

Common Lispは、S式、マクロ、動的な再定義、クロージャ、汎用的なデータ構造、CLOS、コンディションシステムなどを備える。しかし、ANSI Common Lisp全体を新たに実装することは個人・小規模開発にとって極めて大きな負担となる。Zilispは完全実装を追求するのではなく、**教育用の例題からCLIツール、データ処理、DSL、簡単なWeb・GUIアプリまでを実行できる現実的な互換範囲**を定義する。

使用する言語はZigに固定する。Zigの明示的メモリ管理、C ABIとの親和性、ビルドシステム、移植性を活かし、ランタイムを小さく保つ。ただしZigには標準のGCがないため、Lispオブジェクトのための管理ヒープとGCはZilispが実装する。**実行速度を最優先とし、速度を犠牲にする設計は採用しない**（§17）。ただし、実装済み標準機能の意味論は速度と引き換えにしない前提条件とする。

### 1.1 成功条件

- インタラクティブなREPL、`.lisp`ファイルの読み込み、スクリプト実行が可能である。
- CommonLispBasicMasterの**外部依存を伴わない実行対象サンプル**が、原則として改変なしで実行できる。
- Common Lispの関数・マクロ・特殊変数・パッケージ・多値・非局所脱出が正しく機能する。
- CLOSの一般的なクラス、継承、総称関数、メソッド呼び出しが使える。
- テキスト処理、ファイルI/O、構造体・ハッシュテーブルによる小型アプリを構築できる。
- HTTP、Web、GUIサンプルは**言語互換性と互換ライブラリの問題を分離**して検証できる。
- Windows、Linux、macOSで共通のテスト群が走る。
- **Zilispで記述したアプリをコンパイルし、対象OSで直接起動できる実行ファイル（Windowsは`.exe`）を生成できる。** 配布先ではZilisp処理系の別途インストールを要求しない。

### 1.2 非目標

- ANSI Common Lispの全機能を初期版で実装すること。
- 完全なMOP、処理系内部API互換。（SBCLと同等の性能を1.0の合格条件にはしない。性能目標は計測基盤の整備後に設定する）
- Quicklisp上の全パッケージの無改変動作。
- SBCL固有の低水準API、実行イメージ保存、完全なソースレベルデバッガ。
- 1.0でのマルチスレッド実行、低レイテンシの世代別GC。**ネイティブコード生成は主経路であり、非目標には含めない**（v0.3で変更。v0.2ではJITと最適化重視のネイティブコード生成を非目標としていた）。

## 2. 対象教材と互換性の境界

公開版の教材はLevel 1からLevel 26までを含み、Level 18、20、21、23、24などには分冊がある。教材本文、完成コード、演習の解答、外部リポジトリ、説明用の断片を区別してテスト資産に取り込む。ローカルディレクトリ `D:\home\Documents\BasicMaster\CommonLispBasicMaster` は本作成環境から直接参照していないため、ローカル版が公開版と同じという前提は置かない。

### 2.1 教材との対応

| 教材・題材 | 必要な機能群 | 到達区分 |
|---|---|---|
| 基本式、関数、再帰、反復（Level 1–8） | Reader、束縛、関数、クロージャ、`loop`、`dotimes`、`dolist` | Core |
| ファイル操作（Level 9） | ストリーム、`format`、`read-line`、`with-open-file` | Core |
| エラー処理（Level 13） | `handler-case`、`ignore-errors`、`unwind-protect`、基本的なrestart | Practical |
| テキスト処理（Level 17） | package、文字列、ファイル、必要に応じた外部ユーティリティ | Practical |
| 簡易DB（Level 19） | `defstruct`、ハッシュテーブル、永続化、`setf` | Practical |
| 電卓インタプリタ（Level 20） | 字句・構文処理を記述できる関数、リスト、配列、条件分岐 | Practical |
| テキストアドベンチャー（Level 21） | `defclass`、`defmethod`、継承、`make-instance`、スロット、メソッド修飾 | Practical |
| HTTPクライアント（Level 22） | 外部HTTP API（Dexadorを含む使用APIの互換層） | Integration |
| タートル・DSL（Level 23） | マクロ、関数、状態管理、描画連携 | Practical / Integration |
| Web Todoアプリ（Level 24） | Webサーバー、HTMLマクロ、JSON、認証関連パッケージの使用API | Integration |
| シンボリック・スプレッドシート（Level 26） | GUI/Tk、ASDF互換ローダー、ファイル、CLOS | Integration |

**注意：** Level 22、24、26の「そのまま動く」は、Common Lisp標準仕様だけでなく、教材が依存する外部ライブラリの互換層も必要とする。完全なQuicklisp互換ではなく、教材の実際の使用APIを対象とする。外部パッケージの複雑なトランジティブ依存をすべて実装することは原則として避ける。

### 2.2 サンプルの分類

- **A：純粋な標準Common Lisp** — ソース変更なし、挙動をSBCLと比較する。1.0の必須条件。
- **B：標準Common Lisp + 簡単な処理系・OSユーティリティ** — 互換APIを提供し無変更実行を目指す。
- **C：外部パッケージ依存** — 必要な公開APIを薄い互換パッケージで実装し、教材を無変更で動かすことを最終目標とする。
- **D：説明用断片／未完成コード／練習課題** — 自動実行対象にせず、必要な前提を補った派生テストとして管理する。
- **E：外部リポジトリ・資源** — 対象のコミットとライセンスを固定した別の結合試験とする。

対応範囲と例外は `compatibility/manifest.toml` に宣言し、サンプルの無変更実行率、機能対応率、外部依存カバレッジを別々に報告する。

## 3. 言語互換性の原則

### 3.1 標準との関係

Zilispは**Common Lispと互換な機能の集合を増やしていく処理系**とする。実装済み標準演算子の振る舞いを独自に変更しない。未実装の機能は、可能な限り評価開始前に明確なエラーを出す。黙って別の値を返すフォールバックは禁止する。

1. `NIL`は偽・空リスト・シンボルであり、その他の値は真。
2. シンボルはパッケージに属し、名前解決と`CL`・`CL-USER`等を区別する。
3. 関数名前空間と変数名前空間を分ける（Lisp-2）。
4. レキシカル束縛と特殊変数の動的束縛を区別する。
5. マクロは**実行前の構文変換**として扱う。`eval`、`macroexpand`、`compile`系の扱いを整合させる。
6. `eq`、`eql`、`equal`、`equalp`の比較規則を混同しない。
7. `setf`は代入構文ではなく、generalized referenceとして設計する。
8. Common Lispの多値は関数呼び出し・制御構文をまたいで保持する。
9. `block`、`return-from`、`catch`、`throw`、`tagbody`、`go`、`unwind-protect`を正確に組み合わせる。
10. ローカル関数、マクロ、シンボルマクロのスコープは独立に扱う。

### 3.2 フェーズ別の標準機能

| 領域 | 初期Core | Practical到達時 | 当面見送るもの |
|---|---|---|---|
| Reader | S式、文字列、quote、backquote、リスト、ベクタ、文字リテラル | readtableの主要機能、ユーザーReaderマクロ | 全Reader edge caseの網羅 |
| 数値 | fixnum相当整数、浮動小数、基本算術 | 任意精度整数、有理数、複素数、数値変換 | すべての数値最適化 |
| 評価・関数 | lambda、defun、let/let*、if、progn、setf基礎 | flet、labels、multiple values、optional/key/rest、宣言 | 高度な宣言最適化 |
| 制御 | cond、when、unless、dotimes、dolist、主要loop | block/return-from、catch/throw、tagbody/go、unwind-protect | 全loop拡張句の網羅 |
| データ | cons、list、symbol、string、vector | array、hash-table、defstruct、sequence関数 | 特殊化配列の完全網羅 |
| マクロ | defmacro、macroexpand、backquote | macrolet、symbol-macrolet、get-setf-expansion | コンパイラマクロの高度な最適化 |
| パッケージ | defpackage、in-package、intern、export | use-package、shadow、競合検出 | 実装固有パッケージの互換 |
| 条件 | error、warn、handler-case | handler-bind、restart-case、invoke-restart、define-condition | 完全な対話型デバッガ |
| CLOS | — | defclass、slot-value、defgeneric、defmethod、make-instance、標準メソッド結合の主部 | 完全MOP、全ての再定義プロトコル |
| I/O | print、princ、read、format基礎 | stream、read-line、with-open-file、binary I/O、pathname基礎 | 全pathnames拡張と全format句 |

**重要な整合事項：** 単純なCoreでも、将来追加する動的束縛・多値・非局所脱出を実装不能にするVM形式を選ばないこと。最小実装と最終アーキテクチャは区別する。

## 4. 処理系のアーキテクチャ

```text
             REPL / CLI / Loader / Test Runner
                         |
                  Source / Stream
                         v
                 Reader / Readtable
                         |
                    Lisp Values
                         v
              Macroexpander / Resolver
                         |
                 Semantic Core IR（型情報付き）
                         |
        +----------------+-----------------+
        |                |                 |
 Bytecode Compiler  Background Native  Native Backend
        |          （IR→Zig→共有ライブラリ）（IR → Zig → LLVM）
   Bytecode VM           |                 |
 （REPL・eval・load）     |          Executable Builder
        |                |                 |
        +----- 共通の呼び出し規約・制御スタック -----+
                         |
       Runtime / Dynamic Environment
        |          |            |
     Heap+GC    CLOS+Condition  Streams+FFI
              |
        Standard / Compatibility Libraries
              |
      Zig Platform Abstraction (OS / ABI)
```

### 4.1 モジュールの責務

- **Reader**：トークンからCLオブジェクトを読み取る。Readerはコンパイラから独立させ、`read`、`eval`の経路でも同じものを使う。
- **Macroexpander**：マクロ、ローカルマクロ、環境依存展開、backquoteを扱う。循環・過剰展開を診断できる。
- **Semantic Core**：名前解決、lexical environment、special declaration、非局所制御を明示した中間表現。
- **Native Backend（主経路）**：Core IRからZigソースを生成し、Zig（LLVM）で最適化・コンパイルする。`zilisp build`と標準ライブラリのビルドに使う。
- **Background Native**：REPL・`eval`・ソースの`load`で定義した関数を、別プロセスのZigで共有ライブラリにコンパイルし、読み込んで関数の入口をネイティブコードに置き換える。Zigがある開発環境でのみ動作する（詳細設計書 §7A.6）。
- **Bytecode Compiler / VM**：Core IRからバイトコードを生成して実行する。REPL・`eval`・`load`のコードをすぐに実行するための経路であり、Zigがない環境（配布した実行ファイルの中など）ではこの経路だけを使う。
- **Runtime**：値、メモリ管理、intern、ハッシュ、CLOS、I/O、FFIを提供する。
- **Library**：可能な範囲でCommon Lisp自身による標準関数・マクロを保持する。
- **AOT / Executable Builder**：エントリーポイントと依存関係を確定し、Zigのビルド・リンクを利用してOSネイティブの実行ファイルを出力する。VMとの意味論を共有する。

### 4.2 InterpreterとVMの位置づけ

**評価器（AST/IRインタプリタ）は作らない**（v0.3で変更）。`eval`を含むすべての評価は、Core IRを経由してコンパイルしてから実行する。VMとネイティブコードは同じCore IR・同じ呼び出し規約・同じ制御スタック（動的束縛、非局所脱出、handler）を共有し、互いに呼び出せる。両者の意味論の一致は、同じ試験をVMとネイティブの両方で実行する差分試験で確認する。

## 5. 値・オブジェクト・メモリ管理

### 5.1 Valueモデル

`Value`は**8バイトの語で、下位ビットに型タグを置く表現**とする（v0.3で変更。v0.2では16バイトのtagged unionを当初案としていた）。fixnumは62ビット、consはヘッダなしの16バイト、single-floatは即値、double-floatはヒープに確保する。詳細は詳細設計書 §2 による。型と識別性の意味論は最初から固定する。

```text
Value
 ├─ nil / true / character / integer / float
 ├─ symbol / cons / string / vector / array / hash-table
 ├─ function / closure / macro / code-object
 ├─ package / stream / pathname
 ├─ structure / class / instance / generic-function / method
 └─ condition / foreign-object / opaque-handle
```

`NIL`と`T`はinternされた標準シンボルとしても扱える表現を採用する。fixnum範囲外の整数はbignumに昇格させ、数値の精度が静かに失われないようにする。初期開発で任意精度数を後回しにする場合は、対象外の入力を明示的に拒否する。文字列はUnicodeを前提とし、文字単位とUTF-8のバイト単位を分離する。

### 5.2 GCの第1実装

**非移動型のmark-and-sweep GCを、ページ単位のヒープで実装する**（v0.3で変更）。

- 管理ヒープは、大きさごとに分けたページで構成する。マークビットと使用中ビットはページの外の表に置き、確保はページの空きから取り出す。スイープは遅延して行う。
- ヒープ内のオブジェクト、VMスタック、グローバル束縛、パッケージ表、FFI handleは**正確に**走査する。
- **ネイティブのスタックとレジスタは保守的に走査する**（速度優先。非移動型なので保守的な走査と両立する）。
- Zigのヒープ上の構造体など、ネイティブのスタック以外にLisp値を保持する場合は、ルート登録API/handleで明示的に登録する。
- ネイティブのZigポインタをそのまま長寿命のLisp値参照として公開しない。
- `weak`参照、finalizer、循環参照、破棄順序は初期から仕様を明示し、未対応は明示する。
- 一時領域用Arenaと管理ヒープを混同しない。
- 停止時間、確保量、GC回数、到達オブジェクト数を計測できるようにする。

世代別GCは1.0以降に、計測で必要と判明した場合に検討する。ただし、Phase 30で寿命の長いデータと短いデータが混ざる処理を計測し、GCの時間の割合が基準（詳細設計書 §13.2）を超える場合は、1.0の前に導入を再検討する。保守的に走査した領域から参照されるオブジェクトは移動できないため、移動型にする場合は「保守的な参照先は固定し、それ以外を移動する」方式（mostly-copying）を前提とする。

### 5.3 所有権境界

ZigのAllocatorが管理する領域（コンパイル時の一時データ、OSハンドル等）と、Zilisp GCが管理する領域（Lispオブジェクト）は別の所有権モデルとする。FFIでは生ポインタの寿命とpinの必要性を明示する。

## 6. Reader・名前解決・マクロ

### 6.1 Reader

空白・コメント、シンボルの大文字化、エスケープ、文字列、整数、浮動小数、quote、backquote、comma、`,@`、`#'`、`#\`、`#(...)`、`#:`、radix、パッケージ修飾`pkg:sym`/`pkg::sym`等を段階的に実装する。case変換、Reader変数、Readerマクロは互換性テストの対象とする。

### 6.2 環境

コンパイラは少なくとも、変数環境、関数環境、マクロ環境、block/tag環境、宣言環境を区別する。`symbol-value`とレキシカル変数参照は別操作とする。special宣言による動的束縛はスレッドごとの動的環境に将来拡張できる構造にする。

### 6.3 Macro

マクロ展開は必須。`defmacro`のlambda-list（`&whole`、`&environment`を含む高度機能は互換マトリクスで段階対応）、backquote、`macrolet`、`symbol-macrolet`、generalized referenceを設計対象とする。reader、展開器、VMの境界でS式の同一性とソース位置を保持する。

## 7. Bytecode VM設計

### 7.1 VMモデル

VMはREPL・`eval`・ソースの`load`の初期の実行方式であり、速度の主経路はネイティブコードである（§4.2）。このためVMは実装が単純なstack-based VMとし、ネイティブコードと共通の呼び出し規約・制御スタックを使う。命令オペランドの型、バイト順、オブジェクト参照は内部仕様としてバージョン管理する。将来の変更に備えバイトコードは内部キャッシュとし、当初は永続的な互換フォーマットを約束しない。

**命令分類（案）**

| 分類 | 命令例（概念名） |
|---|---|
| 定数・変数 | `CONST`、`LOAD_LOCAL`、`STORE_LOCAL`、`LOAD_SPECIAL`、`STORE_SPECIAL` |
| 制御 | `JUMP`、`JUMP_IF_NIL`、`RETURN` |
| 関数 | `CALL`、`TAIL_CALL`（後期）、`MAKE_CLOSURE`、`LOAD_FUNCTION` |
| スタック | `POP`、`DUP`、`PUSH_NIL` |
| 多値 | `VALUES`、`SAVE_VALUES`、`RESTORE_VALUES` |
| 非局所脱出 | `PUSH_BLOCK`、`RETURN_FROM`、`PUSH_CATCH`、`THROW`、`UNWIND` |
| 構造・アクセス | `CONS`、`CAR`、`CDR`、`AREF`、`SET_REF`等 |
| 診断 | `CHECK_ARITY`、`SIGNAL_ERROR`、`BREAKPOINT`（後期） |

これらは概念上の分類であり、実際の命令をこの通り固定するものではない。

### 7.2 実行フレーム

各フレームは、コード参照、命令ポインタ、ローカル変数、クロージャ環境、動的束縛の復元位置、非局所脱出ハンドラ、ソース位置を保持する。`unwind-protect`のcleanupを例外・return・throw・goで確実に実行する。多値の保持方法を戻り値レジスタまたは専用の結果領域として統一する。

### 7.3 性能改善の順序

1. **Phase 01でベンチマーク基盤を整備し、以後すべてのフェーズで性能を計測する。**
2. Value表現・ヒープ・GCを、最初から速度を前提に設計する（§5）。
3. ネイティブバックエンド（Core IR → Zig → LLVM）を主経路とし、型推論・宣言・`optimize`宣言を反映する。
4. REPL・`eval`向けに、バックグラウンドでネイティブコードに置き換える仕組みを実装する。
5. 呼び出しのインラインキャッシュ、CLOSディスパッチのキャッシュ、tail-call等の個別改善。

## 8. CLOSの設計

### 8.1 最初に対応する範囲

- `defclass`、単一・多重継承、CPL（クラス優先順位）の整合。
- スロット定義、`:initarg`、`:initform`、`:accessor`、`:reader`、`:writer`。
- `make-instance`、`slot-value`、`slot-boundp`、`change-class`。
- クラスの再定義と`change-class`は、標準の手順（`update-instance-for-redefined-class`、`update-instance-for-different-class`）で行う。1.0で扱わない再定義は、意味を変えて実行せずエラーにする（詳細設計書 §10.2）。
- `defgeneric`、`defmethod`、`call-next-method`、`next-method-p`。
- primary、`:before`、`:after`、`:around`を含む標準メソッド結合。
- `initialize-instance`等、教材で使用される初期化フック。
- `print-object`の一般的なカスタマイズ。

### 8.2 実装構成

Class Registry、Slot Layout、Generic Function、Method、Method Cacheを分ける。dispatchの正確性を先に確立し、キャッシュはクラス再定義・メソッド追加の際に無効化できるようにする。MOP完全互換は対象外とするが、基本CLOSの意味論に独自仕様を入れない。

## 9. Condition・restart・デバッガ

`error`、`warn`、`signal`、`handler-case`、`handler-bind`、`ignore-errors`、`unwind-protect`、`restart-case`、`invoke-restart`、`define-condition`の主要機能を実装する。例外相当の「VMの内部故障」と、Common Lispの「通知・回復可能条件」を区別する。REPLでは条件型、メッセージ、発生位置、backtraceを表示する。後期に再起動選択UI、step実行、局所変数表示を追加する。

## 10. 標準ライブラリ・外部パッケージ

### 10.1 標準ライブラリ

Zigで実装すべきプリミティブ（数値演算、メモリ、I/O、ハッシュ等）と、Lisp自身で実装する高水準関数・マクロを分ける。ランタイムは`CL`と`CL-USER`の基本パッケージを生成して起動する。Lisp実装の標準ライブラリはブートストラップ順序を明確にする。

### 10.2 Quicklisp/ASDFの扱い

最初からQuicklispの完全移植は行わない。`require`や最小ローダーを先に作り、教材が使用する`ql:quickload`、`asdf:load-system`等については**必要な名前・引数・戻り値だけを実装する限定互換アダプター**を用意する。互換層を「Quicklisp互換」と総称して誤認させず、サポート対象パッケージをマニフェストに列挙する。

### 10.3 教材の外部依存（確認された例）

| 領域 | パッケージの例 | 基本方針 |
|---|---|---|
| HTTPクライアント | Dexador | 利用中の呼び出しAPIをZig HTTP実装へ橋渡し |
| Webサーバー | Hunchentoot | 最小限のルーティング、リクエスト・レスポンス、cookie、session APIを提供 |
| HTML生成 | CL-WHO | 教材で使用するマクロの展開・HTMLエスケープを再現 |
| JSON | CL-JSON等 | 必要APIをLisp／Zigで実装 |
| 暗号・エンコーディング | Ironclad、Babel | 標準的な既存暗号ライブラリを使い、独自暗号実装は避ける |
| GUI | LTK/Tk | Zig/C ABI経由でTkに接続する最小互換API、または対応専用アダプター |
| スレッド | Bordeaux Threads等 | 教材使用箇所に応じ、1.0以降に隔離した実装を追加 |

**ライブラリ互換性の受け入れ基準**：対象教材のソースに変更を加えず、同名のパッケージ・エクスポート・関数シグネチャを用いて、期待される副作用と戻り値を確認する。セキュリティに関わるTLS、暗号、認証、セッション管理は、機能が足りなければ「未対応」として実験用途に限定し、本番運用可能とは表示しない。

## 11. FFIとOS抽象化

ZigとC ABIを境界として外部関数を呼び出す。Lisp側には安全なopaque handleと明示的なリソース解放を提供する。コールバック、文字エンコーディング、バッファ寿命、GC pin、errno/OSエラーをブリッジの共通仕様として定義する。

OS依存の処理を`platform/`に置き、ファイルパス、改行、標準入出力、動的ライブラリ、ソケット、時刻の差異を吸収する。WindowsではUTF-8/UTF-16境界とパスの扱いに別テストを設ける。macOS AArch64、Windows x86-64、Linux x86-64を主対象とし、クロスコンパイルの成否と実機動作を区別して報告する。

## 12. CLI・REPL・開発者体験

### 12.1 計画するコマンド

```sh
zilisp                    # REPL
zilisp hello.lisp         # ソース実行
zilisp --script app.lisp  # スクリプト実行
zilisp --eval '(+ 1 2)'   # 式評価
zilisp --load lib.lisp    # ファイル読み込み
zilisp --version          # バージョン表示
zilisp --help             # CLIヘルプ
zilisp build app.lisp -o app  # 単独実行可能なアプリのビルド（必須）
```

**必須の追加**：`zilisp build`によるOSネイティブ実行ファイル生成、`zilisp compile-file`によるコンパイル済みモジュール生成。将来の追加：`zilisp test`、`zilisp fmt`（整形器は別仕様）。`.lisp`を標準のソース拡張子とし、内部バイトコードは実装バージョンを示すヘッダを持つ。

### 12.2 REPL要件

括弧・文字列を考慮した複数行入力、履歴（環境により段階導入）、出力先分離、終了コマンド、エラー後の継続、`*`/`**`/`***`等の結果履歴、`+`/`++`/`+++`等の入力履歴を対象にする。backtraceとGC統計はデバッグオプションで表示する。

## 12A. AOTコンパイルと単独実行ファイル生成（必須要件）

### 12A.1 目的と完了条件

Zilispは**対話実行だけのインタプリタにしない**。Common Lispソースから配布可能な実行ファイルを生成することを中核要件とする。完成時には `zilisp build app.lisp -o app` のような操作で、Windowsでは`app.exe`、Linux/macOSでは`app`という対象OS用の実行ファイルを生成する。**配布先にZilisp CLIやZigコンパイラを別途インストールする必要はない**。システムライブラリやGUI/SSL等の外部ネイティブ依存が残る場合は一覧化し、完全静的リンクを保証しない。

`zilisp build`は、アプリの**全関数をネイティブコードにコンパイル**し、ランタイムとリンクした実行ファイルを生成する（v0.3で変更。v0.2では「バイトコードとVMの埋め込み」を第一段階、直接AOTを拡張目標としていた）。実行ファイルには、実行時の`eval`・`compile`・`load`のためにコンパイラとVMも含める。配布先にはZigがないため、実行時に`eval`・`load`したコードはVMで実行される（アプリ本体はすべてネイティブコード）。

**Zilisp 1.0の必須受け入れ条件**は、ネイティブコンパイルによる実行ファイル生成がWindows/Linux/macOSで実用可能であることとする。

### 12A.2 ビルド方式

```text
app.lisp + project manifest
       |
       v
Reader -> Macro Expansion -> Core IR（型情報付き）
       |                            |
       |                  Native Backend（必須・主経路）
       v                            v
Dependency / Entry Analysis    生成した Zig ソース
       |                            |
       +--- Runtime（Zigソース） + 標準ライブラリ（ネイティブ） + コンパイラ・VM（実行時のeval用）
                                    |
                     Zig（LLVM）でまとめてコンパイル・リンク
                                    |
                             app.exe / app / app
```

- **ネイティブバックエンド（必須・主経路）**：Core IRからZigソースを生成し、ランタイムのZigソース（SDKに同梱）と一緒に`zig build-exe`相当の工程でコンパイル・リンクする。生成コードとランタイムをまとめて最適化できる。直接変換が難しい動的操作は共有ランタイムへ委譲し、VMとの意味論を一致させる。外部の`.lisp`ソースを必須としない。
- **ビルド時環境**：開発用SDKにZigツールチェーンを必要とする。将来、バンドルしたツールチェーンの配布を検討する。
- **実行時環境**：ZilispのCLI・コンパイラは不要。埋め込みランタイムのGC、動的束縛、Condition、CLOSを利用できる。

### 12A.3 プログラムの起動と依存解決

`defpackage`/`in-package`を含む複数ファイルを構築できるよう、プロジェクトマニフェストでエントリーポイント、モジュール順序、依存パッケージ、リソース、ビルドターゲットを指定する。初期版では明示的な依存解決を優先し、暗黙の全プログラム解析を必須としない。動的`eval`、`load`、シンボル名での関数参照、実行時のクラス再定義などは、静的削除の対象とせず、安全側に保守的な保持を行う。

```toml
# zilisp.toml（設計例）
[package]
name = "sample-app"
entry = "app:main"
sources = ["src/package.lisp", "src/main.lisp"]

[build]
target = "native"
optimize = "ReleaseFast"  # 速度最優先。Zig側の安全検査が必要な場合は "ReleaseSafe"
```

```sh
zilisp build --manifest zilisp.toml
zilisp build src/main.lisp -o myapp
zilisp build --target x86_64-windows src/main.lisp -o myapp.exe
./myapp                 # Linux/macOS の例
myapp.exe               # Windows の例
```

オプション名、Zigのターゲット表記、`entry`指定方法は詳細設計時に固定する。クロスコンパイルできてもGUIや動的依存を含むプログラムが対象OSで動作するとは限らないため、実機試験を別に設ける。

### 12A.4 コンパイルの意味論

`compile-file`はZilispの内部コンパイル済みモジュールを生成し、`zilisp build`はOS実行ファイルを生成する別の操作として定義する。`compile`、`eval-when`、ロード時初期化、トップレベルフォームの評価順序を検証し、REPL/ソース実行/ビルド済み実行の結果を一致させる。動的再定義可能性はランタイム上で維持し、最適化が必要な場合のみ明示的な制約を導入する。

### 12A.5 セキュリティ・配布・検証

外部コードのビルド時実行、マクロ展開時副作用、ビルドスクリプト起動は任意コード実行になり得るため、信頼できないソースの自動ビルドを前提にしない。出力物には実装バージョンと依存情報を記録し、デバッグ用シンボル有無、成果物サイズ、起動時間、実行時メモリを測定する。

受け入れ試験では、最低限 (1) 単一ファイルCLI、(2) 複数ファイル・パッケージ、(3) ファイルI/O、(4) CLOS、(5) Conditionと非局所脱出、(6) 配布先にZilispがないクリーン環境、(7) 三つの対象OSを検査する。GUI・HTTPを含む配布物は、ランタイムと外部ライブラリの依存を別に表示する。

## 13. テスト・品質保証

### 13.1 テストレイヤー

1. **Unit**：Reader、値、GC、ハッシュ、数値、VM命令、CLOS dispatch。
2. **Conformance subset**：採用したCommon Lisp仕様の境界例、特殊変数、多値、non-local exit、Reader、エラー。
3. **Differential**：同じコードをSBCLとZilispで実行し、値・出力・例外種別・副作用を比較。
4. **Curriculum**：CommonLispBasicMasterサンプルを章別に実行。
5. **Integration**：HTTP、Web、GUI、FFI、複数OS。
6. **Stress**：GC圧迫、深い再帰、循環リスト、大量ハッシュ、繰り返しロード、異常入力。

### 13.2 サンプル抽出パイプライン

```text
CommonLispBasicMaster（コミットSHAで固定）
    ↓ Markdownコードブロック抽出
候補分類（A/B/C/D/E）
    ↓ 手動確認・必要な前提定義
fixtures/ + manifest.toml
    ↓
SBCL基準実行 ─→ 期待値・正規化ルールを保存
    ↓
Zilisp実行 ─→ 比較・差分・原因分類
    ↓
章別達成率 / 言語機能別達成率 / 外部依存別達成率
```

日時、乱数、ハッシュの表示順、ファイルパス、環境差、非決定的な入力には正規化または固定シードを用いる。浮動小数の許容差は各テストで定義する。未定義動作や処理系依存動作をSBCLの結果だけで「規格」と扱わない。

### 13.3 主な試験例

```lisp
;; 字句・関数・クロージャ
(let ((x 10)) (funcall (lambda (y) (+ x y)) 5))  ; => 15

;; 動的束縛
(defparameter *x* 1)
(defun get-x () *x*)
(let ((*x* 7)) (get-x))                       ; => 7

;; Lisp-2の基本
(let ((car 42)) (list car (funcall #'car '(1 2)))) ; => (42 1)

;; 多値
(multiple-value-bind (a b) (values 2 3) (+ a b)) ; => 5

;; 非局所脱出とcleanup
(let ((x nil))
  (list (catch 'done
          (unwind-protect (throw 'done 10)
            (setf x t)))
        x))                                     ; => (10 T)

;; マクロ
(defmacro twice (form) `(+ ,form ,form))
(twice 6)                                      ; => 12

;; 基本CLOS
(defclass point () ((x :initarg :x :accessor point-x)))
(point-x (make-instance 'point :x 9))          ; => 9
```

注：このコードは設計時点の受け入れ試験案であり、Zilisp上での動作確認済みではない。

### 13.4 品質ゲート

- すべての変更でZig unit tests、lint/fmt、最低1つのプラットフォームでのCLI smoke testを実行。
- **すべての変更でベンチマークを実行し、性能の低下を検出する。** 低下を許容する場合は、理由と計測値を記録する。
- VMとネイティブコードの両方で同じ言語試験を実行し、結果の一致を確認する。
- GCに変更があれば長時間・確保負荷・循環参照テストを必須化。
- Reader／macro／non-local exitの変更は差分試験を必須化。
- リリース時は3 OSの実機テスト、互換マトリクス、既知の制限を公開。
- バグ修正には再現テストを追加する。

## 14. リポジトリ構成案

```text
zilisp/
├── README.md
├── LICENSE                         # MIT（著作権表示 fukuyori）
├── CHANGELOG.md
├── build.zig                       # 2段階ビルド（stage1で標準ライブラリをZigソースに変換）
├── build.zig.zon                   # minimum_zig_version = 0.17.0
├── docs/
│   ├── Zilisp_企画・基本設計書_v0.3.md  # 本書
│   ├── Zilisp_詳細設計書_v0.2.md        # 詳細設計（Value、GC、IR、VM、ネイティブバックエンド、CLOS、ビルド等を1冊に集約）
│   ├── version-update-checklist.md     # バージョン変更時に更新するファイルの一覧（Phase 01）
│   ├── zig-std-usage.ja.md                # Zig 0.17.0 のstd・言語機能の照合結果（Phase 01）
│   └── ffi.md                          # FFIの詳細設計（Phase 31）
├── src/
│   ├── main.zig
│   ├── version.zig
│   ├── cli/
│   ├── reader/                     # Reader、SourceMap
│   ├── values/                     # 8バイトValueとタグ操作（ビット操作はここに限定）
│   ├── runtime/
│   │   ├── heap.zig                # ページ単位のヒープ、サイズクラス
│   │   ├── gc.zig                  # ビット表によるマーク、遅延スイープ、保守的スタック走査
│   │   ├── roots.zig               # 明示的ルート、FFI handle
│   │   ├── package.zig
│   │   ├── cl_symbols.zig          # CLの978シンボル（生成ファイル）
│   │   ├── condition.zig
│   │   └── clos.zig                # クラス番号（stamp）、rack、ディスパッチのキャッシュ
│   ├── compiler/
│   │   ├── macro.zig
│   │   ├── resolver.zig
│   │   ├── ir.zig                  # 型情報付きCore IR
│   │   ├── bytecode.zig            # IR → バイトコード
│   │   └── native.zig              # IR → Zigソース（ネイティブバックエンド）
│   ├── builder/                    # zilisp build
│   │   ├── manifest.zig
│   │   ├── zfasl.zig               # .zfasl の読み書き
│   │   └── link.zig                # 生成ソースとランタイムをZigでコンパイル・リンク
│   ├── background/                 # REPL・eval・loadのバックグラウンドのネイティブ化（Phase 39）
│   ├── vm/                         # スタック型VM
│   ├── primitives/
│   ├── ffi/
│   ├── support/                    # std依存の吸収
│   └── platform/                   # OS依存の吸収（io.zig等）
├── lisp/
│   ├── bootstrap/                  # 00-base.lisp 〜 80-io.lisp
│   ├── standard/
│   └── compat/
├── tests/
│   ├── unit/
│   ├── language/                   # VMとネイティブの両方で実行
│   ├── differential/               # SBCLとの比較、impl-dependent.toml
│   ├── ansi/                       # ansi-test の実行設定と expected-failures
│   ├── bench/                      # ベンチマーク（zig build bench）
│   ├── curriculum/
│   ├── executable/
│   ├── integration/
│   └── stress/
├── bench-results/                  # ベンチマークの記録
├── compatibility/
│   ├── curriculum-inventory.md
│   └── manifest.toml
├── scripts/
│   ├── build-release.ps1
│   └── build-installer.ps1         # -Sign で署名（CODESIGN_CERT）
├── installer/
│   └── zilisp.iss
├── tools/
│   ├── extract_samples/
│   └── compare_sbcl/
└── examples/
```

設計文書は、分野ごとに分けず、詳細設計書1冊に集約する（v0.3で変更。v0.2では `runtime.md`・`gc.md`・`bytecode.md` 等への分割を予定していた）。ただしFFIは、Phase 31で別の文書として作成する。

ディレクトリ構成は初期案である。Zigの標準ライブラリやビルドAPIは版ごとに変化するため、初回実装時点で採用バージョンを固定し、CIと文書に記録する。

## 15. 開発ロードマップ（40フェーズ）

開発は各フェーズで**実行できる成果物とテスト**を残す。フェーズは期間の約束ではなく依存順序を示す。

| Phase | 開発内容 | 受け入れ条件 |
|---:|---|---|
| 01 | Zig版固定、リポジトリ、CI、CLI骨格、**ベンチマーク基盤** | `zilisp --version`が動く。ベンチマークを実行・記録できる |
| 02 | テストランナーと教材サンプル抽出基盤 | Markdownから分類可能 |
| 03 | 基本Reader：空白、コメント、数値、シンボル | S式を読み取れる |
| 04 | quote、文字列、リスト、ベクタ | Readerの代表構文が通る |
| 05 | Value、symbol interning、パッケージ基礎 | 同一性を検証できる |
| 06 | ページ単位のオブジェクトヒープとroot管理 | 明示root下で安全にアクセス。確保速度を計測 |
| 07 | mark-and-sweep GC（ビット表、遅延スイープ、保守的スタック走査） | 循環オブジェクトを回収。停止時間を計測 |
| 08 | 最小のコンパイラ（Core IR → バイトコード）、VM、REPL | 算術・リスト評価が動く |
| 09 | レキシカル変数、`let`、`let*` | 束縛とshadowingが正しい |
| 10 | 関数、`lambda`、`defun`、`funcall` | 再帰・関数呼び出し |
| 11 | クロージャと`flet`/`labels` | 閉包の寿命と捕捉が正しい |
| 12 | IR検証器と、**ネイティブバックエンドの最小実装**（IR → Zig） | VMとネイティブの結果が一致 |
| 13 | VMフレーム・分岐・呼び出し | ファイル実行が動く |
| 14 | 動的束縛とspecial宣言 | dynamic bindingが正しい |
| 15 | `defmacro`・backquote・展開器 | 教材の基礎マクロ実行 |
| 16 | `setf`とgeneralized reference基礎 | cons/array/hash更新 |
| 17 | 多値・optional/rest/key引数 | 引数・値伝搬が正しい |
| 18 | `block`/`catch`/`throw`/`unwind-protect` | cleanupと復元が正しい |
| 19 | `tagbody`/`go`、主要loop句 | 反復教材を通す |
| 20 | 数値モデル（bignum、有理数等） | 範囲・精度のテスト |
| 21 | sequence、array、hash-table、string | データ処理サンプルを通す |
| 22 | パッケージ操作、`defpackage`、`in-package` | 複数ファイルの名前解決 |
| 23 | streams、文字・バイナリI/O、pathnames | Level 9・17の主要コード |
| 24 | `format`、Reader拡張、印字体系 | round-tripと書式試験 |
| 25 | conditions、handlers、restarts | Level 13の主要コード |
| 26 | `defstruct`と構造体アクセス | Level 19の主要コード |
| 27 | CLOSのclass/instance/slot | 最小CLOSサンプル |
| 28 | generic function・method・継承 | Level 21の基本動作 |
| 29 | メソッド修飾子・初期化フック・再定義 | Level 21の完成コード |
| 30 | 標準ライブラリ統合・REPL診断 | Level 1–21の対象A群が通る |
| 31 | FFI・OS抽象化・ロードシステム | 複数OSで同じLispプログラム |
| 32 | HTTPクライアント互換層 | Level 22の対象API |
| 33 | Web/HTML/JSON/暗号互換層 | Level 24の検証用アプリ |
| 34 | 描画・Tk接続等GUI互換層 | Level 23/26の検証用アプリ |
| 35 | コンパイル済みモジュール形式（Core IR＋バイトコード）・ロード時初期化 | `.lisp`から中間成果物を生成・再ロードできる |
| 36 | ネイティブコンパイルによる実行ファイル生成 | 単一ソースからZilisp不要の実行ファイルを作れる |
| 37 | 複数モジュール・パッケージの実行ファイル化 | マニフェストによる実アプリ構築 |
| 38 | Windows/Linux/macOSの実行ファイル配布検証 | クリーン環境で実行でき、依存が明示される |
| 39 | REPL・`eval`・`load`のバックグラウンドのネイティブ化・ビルドサイズ最適化 | Zigのある環境で、REPLで定義した関数がネイティブコードに置き換わる。起動・容量を計測 |
| 40 | 互換性監査・ドキュメント・1.0判定 | 教材互換性とビルド要件を満たす |

各フェーズでは「実装」「単体試験」「教材の対象試験」「ユーザードキュメント」の4点を完了条件にする。フェーズ30以降の外部依存と実行ファイル構築は難度が高く、個別APIに分割して実施する。

## 16. マイルストーンとリリース案

| リリース | 範囲 | 動く成果物 |
|---|---|---|
| 0.1 | Phase 01–08 | Reader、REPL、基本評価 |
| 0.2 | Phase 09–18 | 関数、マクロ、多値、動的束縛、例外的制御 |
| 0.3 | Phase 19–24 | データ処理・ファイル処理、複数ファイル実行 |
| 0.4 | Phase 25–29 | Condition・CLOS・構造体 |
| 0.5 | Phase 30–31 | 教材の標準CLサンプルとFFI基盤 |
| 0.6 | Phase 32–34 | 教材固有のHTTP/Web/GUI互換層 |
| 0.7 | Phase 35–37 | コンパイル済みモジュールと、ネイティブコンパイルによる単独実行ファイル生成 |
| 1.0 | Phase 38–40 | 3 OSでの実行ファイル配布・試験報告・互換性保証範囲の確定 |

1.0の範囲は、**単独実行ファイルの生成とクリーン環境での起動を必須条件**とする。また、A群の無改変動作を必須とし、B/C群は対象パッケージおよび対応APIを一覧化して合格判定する。**外部ライブラリの完全互換を1.0の絶対条件にしない**代わり、教材の指定された統合サンプルの実行可否を偽らず公開する。最終的な「全サンプル動作」は後続の完全達成マイルストーンとして保持する。

## 17. 性能とサイズの評価

現時点では実測値がないため、起動時間、実行速度、バイナリサイズ、メモリ常駐量の具体的数値は確定しない。計測環境と比較条件を先に定める。

- **起動**：空REPL起動、標準ライブラリロード後起動を別々に計測。
- **演算**：算術、リスト操作、再帰、クロージャ、ハッシュ、ファイル、CLOS dispatch。
- **メモリ**：定常時RSS、100万cons、長時間反復、GC停止時間。
- **配布**：OS/アーキテクチャ別のビルド済みアプリのバイナリサイズ、ランタイム依存、生成時間、実行時にZilispを必要としないこと。
- **比較**：SBCLを互換性・参考性能基準とするが、最適化レベルとワークロードを明示する。

優先順位は **「実行速度 → 診断容易性 → 互換性 → 起動・メモリ効率」** とする（v0.3で変更。v0.2では実行速度が最下位）。

- **実行速度を最上位とする。** 設計上の選択肢で速度と他の性質が対立する場合は、速度を優先する。速度を下げる設計を採用する場合は、計測値と理由を文書に記録する。
- **正しさ（実装済み標準機能の意味論）は優先順位の比較対象ではなく、前提条件とする。** 速度のために標準の振る舞いを変えたり、黙って別の値を返したりしない（§3.1）。`(declare (optimize (safety 0)))` 等、標準が利用者に許す範囲での検査省略は行う。
- 速度の判断は推測ではなく計測で行う。計測基盤（§7.3 の1）は最初期のフェーズで整備する。

### 17.1 速度最優先に伴う改訂（v0.3で改訂済み）

次の記述は v0.2 の優先順位を前提としていたため、詳細設計書 §17 の決定事項に合わせて v0.3 で改訂した。

| 箇所 | v0.2 の記述 | 改訂の理由 |
|---|---|---|
| §1.2 非目標 | 「SBCLと同等の高速なネイティブ最適化」「最適化重視のネイティブコード生成」を非目標とする | 速度最優先ではネイティブコード生成が主経路になる |
| §4.2、§7 | バイトコードVMを主な実行方式とする | VMには命令解釈の固定費用があり、速度の上限になる |
| §5.1 | Valueは当初tagged union、タグ付きポインタは性能測定後に再検討 | 16バイトのValueはメモリ量・キャッシュ効率で不利。後から変えると全体の書き直しになる |
| §5.2 | 単純なmark-and-sweep GC | 確保速度・停止時間で不利。ページ単位の管理が必要 |
| §7.3 | 「必要と判明した場合のみCranelift/LLVM等への接続を検討」 | ネイティブバックエンドを前提にする必要がある |
| §12A.1–12A.2 | 直接AOTネイティブコード生成は「拡張目標」 | 主経路への格上げが必要 |
| §15 | 性能改善は Phase 39 | 計測基盤と性能設計を初期フェーズへ移す必要がある |

## 18. 主なリスクと対処

| リスク | 影響 | 対処 |
|---|---|---|
| Zig標準ライブラリAPI変更 | ビルド破綻 | Zig版・依存版の固定と計画的更新 |
| GCルート漏れ | 破損・クラッシュ | 正確なルート列挙、stress/poison tests |
| 動的束縛とクロージャの不整合 | CL互換性の根本的破綻 | 初期設計から別の環境で管理 |
| マクロと`setf`の複雑さ | 広範な教材失敗 | generalized referenceを早期設計 |
| 非局所脱出とcleanupの組合せ | 資源漏れ、誤動作 | unwindフレームをVMに明示 |
| CLOSの範囲拡大 | 開発肥大化 | 教材使用APIを先に抽出 |
| 外部パッケージの依存地獄 | 過大な実装負担 | 教材API限定の互換アダプター |
| HTTP/TLS/認証の安全性 | 脆弱性 | 検証済みライブラリ利用・本番提供を限定 |
| Windows/macOS/Linux差 | 振る舞い不一致 | platform層とCI/実機検証 |
| スコープの過大化 | 完成しない | フェーズごとの受け入れ条件 |
| ネイティブ実行ファイル生成の難しさ | 1.0の必須機能が遅延 | Phase 12でネイティブバックエンドの最小実装を作り、早期にリンク制約を確認する |
| VMとネイティブコードの意味論の不一致 | 実行方式で結果が変わる | 共通のCore IR・呼び出し規約・制御スタック。全言語試験を両方で実行 |
| 保守的スタック走査による誤った保持 | メモリ使用量の増加 | ヒープ内は正確に走査し、保守的な走査はネイティブのスタックとレジスタに限定。統計で監視 |
| Zigによるコンパイル時間 | `zilisp build`が遅い | モジュール単位のキャッシュ。計測して対策 |
| 配布した実行ファイル内での`eval`・`load`がVMになる | 実行時に読み込んだコードが遅い | アプリ本体はネイティブコードにする。必要が判明した場合、1.0以降にLLVMのJIT等を検討する |
| 生成コードのコンパイル時間（LLVM） | 巨大な関数でコンパイルが極端に遅くなる | 1つのLisp関数を1つのZig関数にし、大きな関数は最適化を下げる（詳細設計書 §7A.7） |
| ランタイム埋め込みによるファイルサイズ増大 | 配布物の肥大化 | 不要ライブラリ削減、サイズ計測、必要時のリンク最適化 |
| 教材本文内の未完成コード | 誤った不合格 | A〜E分類・前提を明記 |

## 19. 最初に決めるべき詳細設計事項

1. Zigの採用版、対応アーキテクチャ、標準ライブラリの使用範囲。
2. `Value`のタグの割り当てとヒープオブジェクトヘッダ。
3. GCのroot登録API、FFI handle、生存期間。
4. Reader、macroexpander、compilerに渡すソース位置情報。
5. VMフレーム構造、多値の引渡し、非局所脱出とcleanup。
6. 名前空間、パッケージシンボル、internテーブルの構造。
7. CLOSのクラス表、標準メソッド結合、キャッシュ失効方式。
8. ローダーと標準ライブラリのブートストラップ順序。
9. 教材全サンプルのA〜E分類と依存関数一覧。
10. 互換テストにおけるSBCLとの比較範囲および処理系依存の扱い。
11. ネイティブコンパイルによる実行ファイルのモジュール形式、エントリーポイント、初期化順序、Zigのリンク方式。
12. `compile-file`と`zilisp build`の成果物と動作の違い、およびマルチOS配布の依存条件。

## 20. 直近の実施順序

**着手前（設計固定）**：公開版教材のコミットSHAを固定し、全章のLispコード片を収集する。実行単位・依存パッケージ・標準関数の呼び出しを一覧化し、まずA群の対象数を決める。

**第一実装**：ZigのCLI、Reader、Value、GCルート設計、基本REPL、テストランナーを構築する。`(+ 1 2)`、`(list 1 2 3)`、クロージャの小さなコードが動くまで進める。

**ビルド方式の早期試作**：VMの安定化を待たず、Core IRから生成したZigソースとランタイムをリンクして単独実行ファイルを作る最小プロトタイプを作成し（Phase 12）、Windows/Linux/macOSのリンク制約と性能を確認する。

**第一レビュー**：Reader、名前空間、動的束縛、マクロ、non-local exitの構造が、後続のCLOSやConditionに適用可能かを確認する。必要ならこの時点でVMフレーム設計を修正する。

**教材への展開**：章の順番ではなく、必要機能の依存関係で実装を進める。一方、進捗表示は章順の達成率も用意して教育上の見通しを保つ。

## 21. 機能対応マトリクスの雛形

```toml
# compatibility/manifest.toml（概念例）
source_repo = "https://github.com/fukuyori/CommonLispBasicMaster"
source_commit = "<pin-after-audit>"
reference_implementation = "SBCL"

[[cases]]
id = "level09-file-read-write"
level = "09"
category = "A"
source = "tests/curriculum/level09/file-read-write.lisp"
requires = ["with-open-file", "read-line", "format"]
expected = "tests/curriculum/level09/file-read-write.expected"
status = "planned"

[[cases]]
id = "level24-todo"
level = "24"
category = "C"
source = "tests/curriculum/level24/todo.lisp"
requires_packages = ["hunchentoot", "cl-who", "cl-json", "ironclad", "babel"]
status = "planned"
```

マニフェストのソース名は例示であり、教材から抽出済みのファイル名ではない。

## 22. 参考資料

- [CommonLispBasicMaster（基準教材）](https://github.com/fukuyori/CommonLispBasicMaster)
- [Common Lisp HyperSpec](https://www.lispworks.com/documentation/HyperSpec/Front/index.htm)
- [Common Lisp the Language, 2nd Edition](https://www.cs.cmu.edu/Groups/AI/html/cltl/clm/clm.html)（歴史的参考。ANSI仕様そのものではない）
- [Zig公式ドキュメント](https://ziglang.org/documentation/)
- [Zig公式概要・クロスコンパイル](https://ziglang.org/learn/overview/)
- [SBCL](https://www.sbcl.org/)（ソース：[sbcl/sbcl](https://github.com/sbcl/sbcl)）
- [ECL](https://ecl.common-lisp.dev/)（ソース：[embeddable-common-lisp/ecl](https://gitlab.com/embeddable-common-lisp/ecl)）
- [Clasp](https://github.com/clasp-developers/clasp)

設計の参考として調査した処理系（2026-11-01）。参照した版・ファイル・ライセンスは詳細設計書 §20 に記録する。いずれもZilispにコードは取り込まない。

| 処理系 | ソース | 主に参考にした点 |
|---|---|---|
| SBCL | [sbcl/sbcl](https://github.com/sbcl/sbcl) | タグの割り当て、保守的スタック走査、実行ファイルの形式 |
| ECL | [embeddable-common-lisp/ecl](https://gitlab.com/embeddable-common-lisp/ecl) | バイトコードとネイティブの2経路、ansi-testの実行方法 |
| Clasp | [clasp-developers/clasp](https://github.com/clasp-developers/clasp) | LLVMと保守的スタック走査、非局所脱出、REPLのバイトコード化 |
| SICL | [robert-strandh/SICL](https://github.com/robert-strandh/SICL) | クラス番号（stamp）によるディスパッチ、rackによるインスタンス表現 |
| Gambit Scheme | [gambit/gambit](https://github.com/gambit/gambit) | Cを生成する方式での末尾呼び出し、生成コードのコンパイル時間 |
| Emacs（ネイティブコンパイル） | [emacs-mirror/emacs](https://github.com/emacs-mirror/emacs) | libgccjitの使い方、共有ライブラリの読み込み |
| Janet | [janet-lang/janet](https://github.com/janet-lang/janet) | レジスタ型VM、初期化済み環境の埋め込み |
| Carp | [carp-lang/Carp](https://github.com/carp-lang/Carp) | Cの生成、REPLの実行方式 |
| MIR | [vnmakarov/mir](https://github.com/vnmakarov/mir) | プロセス内コード生成器の候補（Windows非対応のため不採用） |

---

**結論**：Zilispは、Zigで構築する小型のCommon Lisp互換処理系である。完成判定は「言語機能をいくつ実装したか」ではなく、「定義されたCommon Lispの意味論を保ち、CommonLispBasicMasterの対象プログラムを実際に走らせられるか」に置く。実装済み標準機能の互換性を崩さず、教材の実用アプリに必要な外部APIを選択的に提供することで、小規模な処理系の開発と実用性の両立を目指す。
