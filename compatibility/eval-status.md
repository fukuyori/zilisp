# 教材のブロックの実行の結果（自動生成）

このファイルは `zig build eval-check` が生成する。手で編集しない。
教材のブロックのうち、分類の候補が A のものを、Zilisp（VM。`--script`）と SBCL 2.6.7（`--script`）で実行して比べた結果。
ブロックは教材の1つのコードブロックで、単独では動かないもの（前のブロックの定義を使うもの）も含む。

| 結果 | 意味 | ブロック数 |
|---|---|---|
| match | 両方とも正常に終わり、標準出力が同じ | 100 |
| both-error | 両方ともエラーで終わった | 362 |
| output-diff | 両方とも正常に終わったが、標準出力が違う | 0 |
| zilisp-error | Zilisp だけがエラー | 493 |
| sbcl-error | SBCL だけがエラー | 0 |
| timeout | 時間内に終わらなかった | 0 |
| 計 | | 955 |

## Zilisp だけがエラーになったブロックの、最初のエラー

| 最初のエラー | ブロック数 |
|---|---|
| 未実装：DEFMACRO | 33 |
| 未実装：SETF | 32 |
| 未実装：DEFSTRUCT | 30 |
| 未実装：COND | 29 |
| 未実装：LOOP | 28 |
| 未実装：DOLIST | 22 |
| 未実装：DEFCLASS | 20 |
| 未実装：&KEY | 19 |
| 未実装の関数：FORMAT | 16 |
| 未実装：WITH-OPEN-FILE | 16 |
| 未実装：WHEN | 15 |
| 未実装の関数：MACROEXPAND-1 | 13 |
| 未実装：&REST | 9 |
| 未実装：HANDLER-CASE | 9 |
| 未実装：&OPTIONAL | 8 |
| 未実装：DEFPACKAGE | 8 |
| 未実装：PUSH | 8 |
| 未実装：CASE | 6 |
| 未実装：DOTIMES | 6 |
| 未実装の関数：ABS | 5 |
| 未実装の関数：EVENP | 5 |
| 未実装の関数：EXPT | 5 |
| 未実装の関数：REDUCE | 5 |
| 未実装の関数：STRING= | 5 |
| 未実装：ASSERT | 5 |
| 未実装：DEFINE-CONDITION | 5 |
| 未実装の関数：MAKE-HASH-TABLE | 4 |
| 未実装の関数：MAPCAR | 4 |
| 未実装：OR | 4 |
| 未実装：PROG1 | 4 |
| 未実装：UNLESS | 4 |
| 未実装の関数：APPEND | 3 |
| 未実装の関数：COPY-LIST | 3 |
| 未実装の関数：EQUAL | 3 |
| 未実装の関数：EVAL | 3 |
| 未実装の関数：FIND | 3 |
| 未実装の関数：FLOOR | 3 |
| 未実装の関数：LENGTH | 3 |
| 未実装の関数：REMOVE-IF-NOT | 3 |
| 未実装：AND | 3 |
| 未実装：TRACE | 3 |
| 未実装の関数：ASSOC | 2 |
| 未実装の関数：MAX | 2 |
| 未実装の関数：POSITION | 2 |
| 未実装の関数：PRINC | 2 |
| 未実装の関数：RANDOM | 2 |
| 未実装の関数：READ | 2 |
| 未実装の関数：REVERSE | 2 |
| 未実装の関数：SUBSEQ | 2 |
| 未実装の関数：SUBSTITUTE | 2 |
| 未実装：INCF | 2 |
| 未実装：RESTART-CASE | 2 |
| READER-ERROR | 1 |
| UNBOUND-VARIABLE | 1 |
| 未定義の関数：QUIT | 1 |
| 未定義の関数：ZILISP-SYSTEM:UNQUOTE | 1 |
| 未実装の変数：*PACKAGE* | 1 |
| 未実装の変数：*RANDOM-STATE* | 1 |
| 未実装の関数：ALPHA-CHAR-P | 1 |
| 未実装の関数：APROPOS | 1 |
| 未実装の関数：AREF | 1 |
| 未実装の関数：CHAR | 1 |
| 未実装の関数：CHAR-CODE | 1 |
| 未実装の関数：CHAR-UPCASE | 1 |
| 未実装の関数：CHAR= | 1 |
| 未実装の関数：COERCE | 1 |
| 未実装の関数：CONCATENATE | 1 |
| 未実装の関数：COUNT | 1 |
| 未実装の関数：DIGIT-CHAR-P | 1 |
| 未実装の関数：DIRECTORY | 1 |
| 未実装の関数：DISASSEMBLE | 1 |
| 未実装の関数：DOCUMENTATION | 1 |
| 未実装の関数：FLOAT | 1 |
| 未実装の関数：FLOATP | 1 |
| 未実装の関数：GENSYM | 1 |
| 未実装の関数：GET-INTERNAL-REAL-TIME | 1 |
| 未実装の関数：GETF | 1 |
| 未実装の関数：INSPECT | 1 |
| 未実装の関数：LOG | 1 |
| 未実装の関数：LOGAND | 1 |
| 未実装の関数：LOGBITP | 1 |
| 未実装の関数：MAKE-PATHNAME | 1 |
| 未実装の関数：MAKE-STRING | 1 |
| 未実装の関数：MERGE-PATHNAMES | 1 |
| 未実装の関数：PLUSP | 1 |
| 未実装の関数：PROBE-FILE | 1 |
| 未実装の関数：READ-CHAR | 1 |
| 未実装の関数：READ-LINE | 1 |
| 未実装の関数：REALP | 1 |
| 未実装の関数：REMOVE | 1 |
| 未実装の関数：REMOVE-DUPLICATES | 1 |
| 未実装の関数：ROOM | 1 |
| 未実装の関数：SEARCH | 1 |
| 未実装の関数：SECOND | 1 |
| 未実装の関数：SIN | 1 |
| 未実装の関数：SINH | 1 |
| 未実装の関数：SORT | 1 |
| 未実装の関数：STRING | 1 |
| 未実装の関数：STRING-TRIM | 1 |
| 未実装の関数：STRING-UPCASE | 1 |
| 未実装：DECLAIM | 1 |
| 未実装：DEFMETHOD | 1 |
| 未実装：HANDLER-BIND | 1 |
| 未実装：IGNORE-ERRORS | 1 |
| 未実装：MULTIPLE-VALUE-BIND | 1 |
| 未実装：REMF | 1 |
| 未実装：TIME | 1 |
| 未実装：TYPECASE | 1 |
| 未実装：UNWIND-PROTECT | 1 |
| 未実装：WITH-OUTPUT-TO-STRING | 1 |
| 未実装：割り切れない整数の割り算 | 1 |

各ブロックの結果は `eval-check.tsv`（同じディレクトリ）にある。
