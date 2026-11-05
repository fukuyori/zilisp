# Zilisp

[![test](https://github.com/fukuyori/zilisp/actions/workflows/test.yml/badge.svg)](https://github.com/fukuyori/zilisp/actions/workflows/test.yml)

[English](README.md)

Zilisp は、[Zig](https://ziglang.org/) で書いた、実用的な Common Lisp 互換の処理系です。
ANSI Common Lisp の完全な準拠は目指さず、範囲を決めた実用的な部分集合を実装します。
ただし、実装した機能の振る舞いは標準のとおりにします。
実行速度を設計の最優先とし、標準の意味は速度と引き換えにしません。

- **実行方式**：REPL・`eval`・`load` はバイトコード VM で実行します。ネイティブバックエンドは、Lisp を Zig の
  ソースにして、ランタイムと一緒にコンパイルします。単独の実行ファイルの生成は、後の版で行います。
- **対象の OS**：Windows・Linux・macOS（x86-64 と AArch64）
- **基準の教材**：[CommonLispBasicMaster](https://github.com/fukuyori/CommonLispBasicMaster)。
  教材のコードブロックを SBCL 2.6.7 と比べて、互換性を測っています（`compatibility/eval-status.md`）。

## 状況

今の版は **0.3.0** です。まだ初期の段階で、よく使う演算子の多くが未実装です。
未実装の機能は、評価の前または評価の途中でエラーとして報告します。黙って別の値を返すことはしません。

0.2.0 で実装したもの

- Reader（数、シンボル、パッケージ修飾、文字列、文字、`#` の構文、backquote、`#+`・`#-`）と印字（`prin1` の形。SBCL と同じ）
- ページ単位のヒープと mark-and-sweep GC（正確なルートと、ネイティブのスタック・レジスタの保守的な走査）
- コンパイラ（Resolver、Core IR、バイトコード）とスタック型のバイトコード VM、最小のネイティブバックエンド
- 特殊演算子とマクロ：`quote` `if` `progn` `let` `let*` `setq` `function` `lambda` `flet` `labels` `progv`
  `eval-when` `block` `return-from` `return` `catch` `throw` `unwind-protect`、
  `when` `unless` `cond` `and` `or` `case` `prog1` `prog2`
- `defun`、`defmacro`（分解束縛つき）、backquote、`macroexpand`、`destructuring-bind`
- ラムダリスト：`&optional`・`&rest`・`&key`・`&aux`
- 動的束縛：`defvar`・`defparameter`・`special` 宣言
- 多値：`values`・`multiple-value-bind`・`multiple-value-list`・`multiple-value-call`・`multiple-value-prog1`・
  `nth-value`・`multiple-value-setq`
- `setf` と場所（`defsetf`・`define-setf-expander`・`(defun (setf 名前) ...)`）、`incf` `decf` `push` `pop`
- ハッシュ表（`eq`・`eql`・`equal`）と1次元の配列（単純ベクタと文字列）

0.3.0 で実装したもの

- `tagbody`/`go`、`do`・`do*`・`dolist`・`dotimes`・`psetq`、`loop`（主な句）
- `mapcar`・`mapc`・`mapcan`・`nconc`・`reduce`・`reverse`・`nreverse`・`copy-list`・`last`・`max`・`min`・
  `evenp`・`oddp`・`mod`・`rem`・`string=`・`string-upcase`・`princ`
- bignum と比、浮動小数との正確な比較、`floor`・`ceiling`・`truncate`・`round`、`gcd`・`lcm`、`expt`・`sqrt`・`isqrt`・
  `exp`・`log`・三角関数、ビット演算（`logand`・`ash` など）
- 多次元の配列・fill-pointer・adjustable な配列（`vector-push-extend`・`adjust-array`）、`equalp` と `equalp` のハッシュ表
  （`maphash` は SBCL 2.6.7 と同じ順序でたどる）
- 列の関数（`find`・`position`・`remove-if`・`substitute`・`sort`・`subseq`・`search`・`concatenate`・`map`・`coerce` など）、
  リスト・集合の関数（`member`・`assoc`・`union`・`pushnew` など）、文字・文字列の関数（`char-upcase`・`string<`・
  `string-trim`・`parse-integer` など）。文字の種類と大文字・小文字は、SBCL 2.6.7 と同じく Unicode 15.0.0 に従う
- パッケージ：`defpackage`・`in-package`・`export`・`use-package`・`intern`・`find-symbol` などのパッケージの関数、名前の衝突の検出、
  `load`
- ストリームとファイル：`with-open-file`・`read-line`・`read`・`write-line`、文字列のストリーム（`with-output-to-string`・
  `read-from-string` など）、バイナリの入出力、パス名（`#P`・`merge-pathnames`・`probe-file`・`directory` など）
- 印字と読み取り：すべての指示子の `format`、印字の変数（`*print-base*`・`*print-circle*` など）、readtable と
  ユーザー定義の reader macro、pretty printer（`pprint`・`pprint-logical-block`・`set-pprint-dispatch`）
- condition：`define-condition`・`error`・`warn`・`signal`・`handler-case`・`handler-bind`・
  `ignore-errors`・`restart-case`・`invoke-restart`・`with-simple-restart`・`check-type`・`assert`・`typecase`・`ecase`、`typep`。
  標準の condition の report の文面は SBCL 2.6.7 と同じ

未実装（後の版で実装する予定）：
複素数・`defstruct`・CLOS。

## インストール

[Releases](https://github.com/fukuyori/zilisp/releases) のページから入手してください。

| OS | ファイル |
|---|---|
| Windows（x86-64） | `zilisp-<版>-x86_64-windows-setup.exe`（インストーラー）または `zilisp-<版>-x86_64-windows.zip` |
| Linux（x86-64・AArch64） | `zilisp-<版>-x86_64-linux.tar.gz`・`zilisp-<版>-aarch64-linux.tar.gz`（静的リンク、musl） |
| macOS（Apple Silicon・Intel） | `zilisp-<版>-aarch64-macos.tar.gz`・`zilisp-<版>-x86_64-macos.tar.gz` |

Windows のインストーラーは、既定では今の利用者だけにインストールし（管理者の権限は不要）、選べば `PATH` に
Zilisp を加えます。

## 使い方

```
zilisp                  REPL を始める（入力が終われば終わる）
zilisp FILE             FILE のフォームを順に評価する（--script FILE と同じ）
zilisp --script FILE    FILE のフォームを順に評価する。エラーで止まり、終了コード 1
zilisp --eval TEXT      TEXT のフォームを順に評価する（値は印字しない）
zilisp --load FILE      FILE を評価してから REPL を始める
zilisp --version        バージョンを表示する
zilisp --help           ヘルプを表示する
```

全体のオプション（コマンドの前に置く）：`--gc-stress`（確保のたびに GC を行う。試験用）、`--gc-stats`（終了時に GC の統計を表示する）。

```
$ zilisp
* (defun fact (n) (if (< n 2) 1 (* n (fact (- n 1)))))
FACT
* (fact 10)
3628800
* (catch 'done (throw 'done (values 1 2)))
1
2
```

## ソースからのビルド

**Zig 0.17.0** が必要です。

```
zig build                      # zig-out/bin/zilisp を作る
zig build test                 # 単体テスト
zig build lang-test            # 言語試験（tests/language）
zig build native-test          # 言語試験をネイティブバックエンドで実行して比べる
zig build bench                # ベンチマーク（ReleaseFast）
zig build -Doptimize=ReleaseFast
```

教材を SBCL と比べるには、SBCL と、抜き出した教材のコードブロックが必要です。

```
zig build extract-samples -- <CommonLispBasicMaster のディレクトリ> .work/samples
zig build eval-check -Dsbcl=<sbcl のパス>
```

リリース用のスクリプト（PowerShell）：`scripts/build-release.ps1` がリリースビルドを作り、
`scripts/build-installer.ps1 [-Sign]` が Windows のインストーラーと ZIP を作ります（`-Sign` を付けると、環境変数
`CODESIGN_CERT` の証明書で、実行ファイル・アンインストーラー・インストーラーに署名します）。
タグ `v<版>` を push すると、`.github/workflows/release.yml` が試験・ビルドをして、GitHub のリリースを登録します。

## 文書

- [`docs/Zilisp_詳細設計書_v0.2.md`](docs/Zilisp_詳細設計書_v0.2.md)：詳細設計（[English](docs/Zilisp_Detailed_Design_v0.2.md)）
- [`docs/zig-std-usage.ja.md`](docs/zig-std-usage.ja.md)：Zig 0.17.0 の標準ライブラリ・言語機能の照合の記録（[English](docs/zig-std-usage.md)）
- `docs/Zilisp_企画・基本設計書_v0.3.md`：企画と基本設計（日本語のみ）
- `docs/version-update-checklist.md`：バージョンを変えるときに更新するファイルと、リリースの手順（日本語のみ）

変更の記録は [CHANGELOG.ja.md](CHANGELOG.ja.md)（[English](CHANGELOG.md)）にあります。

## 予定

| 版 | 内容 |
|---|---|
| 0.3 | `tagbody`/`go` と `loop`、数値（bignum・有理数）、列、パッケージ、ストリームとファイル、`format` |
| 0.4 | condition と restart、`defstruct`、CLOS |
| 0.5 | 教材のための標準ライブラリの統合、FFI と OS の抽象化 |
| 0.6 | 教材が使う HTTP・Web・GUI の互換層 |
| 0.7 | コンパイル済みのモジュールと、ネイティブコンパイルによる単独の実行ファイル |
| 1.0 | 3つの OS での配布、試験の報告、互換性の範囲の確定 |

## ライセンス

[MIT](LICENSE) — Copyright (c) 2026 fukuyori

文字の表は Unicode 文字データベース（`data/unicode/`）から作っています。このデータは
[Unicode License v3](data/unicode/LICENSE.txt) で配布されています。配布物には `LICENSE-UNICODE.txt` として入れています。
