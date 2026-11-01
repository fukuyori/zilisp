# 教材サンプルの一覧（自動収集）

このファイルは `scripts/curriculum-inventory.ps1` が生成する。手で編集しない。

| 項目 | 値 |
|---|---|
| 教材 | https://github.com/fukuyori/CommonLispBasicMaster |
| コミット | `639544c8133fdc51ffe4c2184aad785345128419` |
| 読み込みに使った処理系 | SBCL 2.6.7 |
| Lisp のブロック | 1107 |
| 使われている CL のシンボル | 347 種類 |

## 分類の候補

候補は読み込みの結果だけから機械的に決めたものであり、A〜E の確定は手作業で行う（基本設計 §2.2）。

| 候補 | 意味 | ブロック数 |
|---|---|---|
| A | 読み込めた（または教材の中で定義したパッケージを参照している）。外部ライブラリの参照なし（A の候補） | 955 |
| C | 外部ライブラリ・処理系固有のパッケージへの参照あり（C の候補） | 113 |
| U | 存在しないパッケージの修飾あり（教材内で定義したものか外部かを手作業で判断） | 16 |
| D | 読み込みに失敗（断片・説明用のコードの候補） | 23 |

## 章ごとのブロック数

| 章 | A | C | U | D | 計 |
|---|---|---|---|---|---|
| chapters/03-Level 1.md | 2 | 1 | 0 | 0 | 3 |
| chapters/04-Level 2.md | 24 | 0 | 0 | 1 | 25 |
| chapters/05-Level 3.md | 59 | 0 | 0 | 0 | 59 |
| chapters/06-Level 4.md | 40 | 0 | 0 | 1 | 41 |
| chapters/08-Level 5.md | 29 | 0 | 0 | 6 | 35 |
| chapters/09-Level 6.md | 48 | 0 | 0 | 0 | 48 |
| chapters/10-Level 7.md | 39 | 0 | 0 | 0 | 39 |
| chapters/11-Level 8.md | 43 | 0 | 0 | 0 | 43 |
| chapters/13-Level 9.md | 50 | 0 | 0 | 1 | 51 |
| chapters/14-Level 10.md | 41 | 0 | 0 | 0 | 41 |
| chapters/15-Level 11.md | 25 | 0 | 0 | 0 | 25 |
| chapters/16-Level 12.md | 40 | 0 | 0 | 2 | 42 |
| chapters/18-Level 13.md | 32 | 0 | 0 | 1 | 33 |
| chapters/19-Level 14.md | 39 | 0 | 0 | 2 | 41 |
| chapters/20-Level 15.md | 32 | 9 | 2 | 0 | 43 |
| chapters/21-Level 16.md | 29 | 0 | 0 | 0 | 29 |
| chapters/23-Level 17.md | 12 | 3 | 0 | 0 | 15 |
| chapters/24-Level 18-A.md | 38 | 0 | 0 | 0 | 38 |
| chapters/25-Level 18-B.md | 62 | 1 | 0 | 0 | 63 |
| chapters/26-Level 18-C.md | 12 | 42 | 11 | 0 | 65 |
| chapters/27-Level 19.md | 40 | 10 | 0 | 0 | 50 |
| chapters/29-Level 20-A.md | 25 | 0 | 0 | 0 | 25 |
| chapters/30-Level 20-B.md | 6 | 16 | 0 | 0 | 22 |
| chapters/31-Level 21-A.md | 32 | 0 | 0 | 1 | 33 |
| chapters/32-Level 21-B.md | 21 | 0 | 0 | 2 | 23 |
| chapters/33-Level 21-C.md | 2 | 0 | 0 | 0 | 2 |
| chapters/35-Level 22.md | 7 | 23 | 1 | 3 | 34 |
| chapters/36-Level 23-A.md | 38 | 0 | 0 | 1 | 39 |
| chapters/37-Level 23-B.md | 36 | 0 | 0 | 0 | 36 |
| chapters/38-Level 24-A.md | 13 | 2 | 1 | 2 | 18 |
| chapters/39-Level 24-B.md | 16 | 4 | 0 | 0 | 20 |
| chapters/42-Level 26.md | 23 | 2 | 1 | 0 | 26 |

## 参照されているパッケージ（in-package・defpackage・修飾）

| パッケージ | ブロック数 |
|---|---|
| `QL` | 38 |
| `DEX` | 20 |
| `LTK` | 12 |
| `CL-CSV` | 11 |
| `YASON` | 8 |
| `JONATHAN` | 8 |
| `ASDF` | 7 |
| `CL-JSON` | 6 |
| `UIOP` | 6 |
| `HUNCHENTOOT` | 4 |
| `DEFPACKAGE:MY-APP` | 3 |
| `SSP` | 2 |
| `CL-PPCRE` | 2 |
| `QUICKLISP-QUICKSTART` | 2 |
| `IN-PACKAGE:CL-USER` | 2 |
| `IN-PACKAGE:MY-APP` | 2 |
| `IN-PACKAGE:SSP` | 1 |
| `DEFPACKAGE:SSP` | 1 |
| `IRONCLAD` | 1 |
| `IN-PACKAGE:TODO-APP` | 1 |
| `TODO-APP` | 1 |
| `QURI` | 1 |
| `IN-PACKAGE:WEATHER-APP` | 1 |
| `DEFPACKAGE:WEATHER-APP` | 1 |
| `IN-PACKAGE:HTTP-CLIENT` | 1 |
| `DEFPACKAGE:HTTP-CLIENT` | 1 |
| `IN-PACKAGE:SECURE-UTILS` | 1 |
| `DEFPACKAGE:SECURE-UTILS` | 1 |
| `IN-PACKAGE:MY-CALC` | 1 |
| `DEFPACKAGE:MY-CALC` | 1 |
| `IN-PACKAGE:MATH-UTILS` | 1 |
| `DEFPACKAGE:MATH-UTILS` | 1 |
| `MATH-UTILS` | 1 |
| `IN-PACKAGE:MY-APP.CONFIG` | 1 |
| `DEFPACKAGE:MY-APP.CONFIG` | 1 |
| `IN-PACKAGE:STRING-UTILS` | 1 |
| `DEFPACKAGE:STRING-UTILS` | 1 |
| `IN-PACKAGE:MY-PROJECT` | 1 |
| `IN-PACKAGE:MY-PROJECT.CORE` | 1 |
| `IN-PACKAGE:MY-PROJECT.UTILS` | 1 |
| `DEFPACKAGE:MY-PROJECT` | 1 |
| `DEFPACKAGE:MY-PROJECT.CORE` | 1 |
| `DEFPACKAGE:MY-PROJECT.UTILS` | 1 |
| `MY-UTILS` | 1 |
| `MY-LIB` | 1 |
| `IN-PACKAGE:MY-LIB` | 1 |
| `DEFPACKAGE:MY-LIB` | 1 |
| `IN-PACKAGE:MY-UTILS` | 1 |
| `DEFPACKAGE:MY-UTILS` | 1 |
| `#<PACKAGE "COMMON-LISP-USER">` | 1 |
| `MY-APP` | 1 |
| `IN-PACKAGE:MY-PACKAGE` | 1 |

## よく使われている CL のシンボル（上位 100）

| シンボル | ブロック数 |
|---|---|
| `defun` | 360 |
| `quote` | 326 |
| `let` | 225 |
| `t` | 225 |
| `format` | 185 |
| `if` | 134 |
| `function` | 133 |
| `lambda` | 126 |
| `setf` | 125 |
| `defparameter` | 120 |
| `+` | 118 |
| `*` | 85 |
| `length` | 78 |
| `when` | 75 |
| `loop` | 74 |
| `cdr` | 66 |
| `mapcar` | 64 |
| `dolist` | 62 |
| `error` | 61 |
| `cond` | 60 |
| `push` | 57 |
| `do` | 55 |
| `list` | 54 |
| `/` | 53 |
| `and` | 52 |
| `null` | 51 |
| `<` | 47 |
| `>` | 47 |
| `incf` | 47 |
| `assoc` | 45 |
| `car` | 44 |
| `let*` | 44 |
| `=` | 43 |
| `progn` | 43 |
| `gethash` | 42 |
| `funcall` | 41 |
| `print` | 40 |
| `with-open-file` | 39 |
| `>=` | 38 |
| `-` | 37 |
| `defmacro` | 36 |
| `first` | 36 |
| `unless` | 36 |
| `defstruct` | 33 |
| `string` | 33 |
| `cons` | 32 |
| `equal` | 32 |
| `or` | 32 |
| `reduce` | 32 |
| `nreverse` | 31 |
| `&key` | 30 |
| `1+` | 30 |
| `char` | 30 |
| `member` | 30 |
| `subseq` | 30 |
| `second` | 28 |
| `string=` | 28 |
| `defclass` | 27 |
| `defmethod` | 27 |
| `make-hash-table` | 27 |
| `not` | 27 |
| `remove-if-not` | 27 |
| `declare` | 26 |
| `ignore` | 25 |
| `&rest` | 24 |
| `zerop` | 24 |
| `case` | 23 |
| `eq` | 23 |
| `getf` | 23 |
| `make-instance` | 23 |
| `char=` | 22 |
| `&optional` | 21 |
| `handler-case` | 21 |
| `read-line` | 21 |
| `macroexpand-1` | 20 |
| `abs` | 19 |
| `maphash` | 19 |
| `string-downcase` | 19 |
| `1-` | 18 |
| `return` | 18 |
| `third` | 18 |
| `defvar` | 17 |
| `digit-char-p` | 17 |
| `in-package` | 17 |
| `max` | 16 |
| `numberp` | 16 |
| `stream` | 16 |
| `<=` | 15 |
| `count` | 15 |
| `listp` | 15 |
| `remove` | 15 |
| `&body` | 14 |
| `apply` | 14 |
| `defpackage` | 14 |
| `dotimes` | 14 |
| `evenp` | 14 |
| `parse-integer` | 14 |
| `read` | 14 |
| `get-universal-time` | 13 |
| `otherwise` | 13 |
