# 教材のブロックの実行の結果（自動生成）

このファイルは `zig build eval-check` が生成する。手で編集しない。
教材のブロックのうち、分類の候補が A のものを、Zilisp（VM。`--script`）と SBCL 2.6.7（`--script`）で実行して比べた結果。
ブロックは教材の1つのコードブロックで、単独では動かないもの（前のブロックの定義を使うもの）も含む。

| 結果 | 意味 | ブロック数 |
|---|---|---|
| match | 両方とも正常に終わり、標準出力が同じ | 347 |
| both-error | 両方ともエラーで終わった | 362 |
| output-diff | 両方とも正常に終わったが、標準出力が違う | 0 |
| zilisp-error | Zilisp だけがエラー | 246 |
| sbcl-error | SBCL だけがエラー | 0 |
| timeout | 時間内に終わらなかった | 0 |
| 計 | | 955 |

## Zilisp だけがエラーになったブロックの、最初のエラー

| 最初のエラー | ブロック数 |
|---|---|
| 未実装：DEFSTRUCT | 31 |
| 未実装：WITH-OPEN-FILE | 23 |
| 未実装：DEFCLASS | 21 |
| 未実装：HANDLER-CASE | 16 |
| 未実装：DEFPACKAGE | 8 |
| 未実装の関数：EXPT | 5 |
| 未実装の関数：REMOVE-IF-NOT | 5 |
| 未実装：ASSERT | 5 |
| 未実装：DEFINE-CONDITION | 5 |
| 未実装の関数：ASSOC | 4 |
| 未実装の関数：EVAL | 4 |
| 未実装の関数：FIND | 4 |
| 未実装の関数：POSITION | 4 |
| 未実装の関数：SORT | 4 |
| 未実装：WITH-OUTPUT-TO-STRING | 4 |
| 未実装の関数：FLOAT | 3 |
| 未実装の関数：FLOOR | 3 |
| 未実装の関数：REMOVE-DUPLICATES | 3 |
| 未実装の関数：STRING-EQUAL | 3 |
| 未実装の関数：SUBSEQ | 3 |
| 未実装："~5" | 3 |
| 未実装：TRACE | 3 |
| READER-ERROR | 2 |
| 未実装の関数：CONCATENATE | 2 |
| 未実装の関数：DIGIT-CHAR-P | 2 |
| 未実装の関数：ELT | 2 |
| 未実装の関数：FIND-IF | 2 |
| 未実装の関数：RANDOM | 2 |
| 未実装の関数：READ | 2 |
| 未実装の関数：REMOVE-IF | 2 |
| 未実装の関数：SEARCH | 2 |
| 未実装の関数：SUBSTITUTE | 2 |
| 未実装："FOR" | 2 |
| 未実装："~:" | 2 |
| 未実装："~{" | 2 |
| 未実装：REMF | 2 |
| 未実装：RESTART-CASE | 2 |
| 未定義の関数：QUIT | 1 |
| 未実装の変数：*PACKAGE* | 1 |
| 未実装の変数：*RANDOM-STATE* | 1 |
| 未実装の関数：ALPHA-CHAR-P | 1 |
| 未実装の関数：APROPOS | 1 |
| 未実装の関数：CHAR-CODE | 1 |
| 未実装の関数：CHAR-EQUAL | 1 |
| 未実装の関数：CHAR-UPCASE | 1 |
| 未実装の関数：COERCE | 1 |
| 未実装の関数：COUNT | 1 |
| 未実装の関数：DESCRIBE | 1 |
| 未実装の関数：DIRECTORY | 1 |
| 未実装の関数：DISASSEMBLE | 1 |
| 未実装の関数：DOCUMENTATION | 1 |
| 未実装の関数：EQUALP | 1 |
| 未実装の関数：FLOATP | 1 |
| 未実装の関数：GCD | 1 |
| 未実装の関数：GET-INTERNAL-REAL-TIME | 1 |
| 未実装の関数：IDENTITY | 1 |
| 未実装の関数：INSPECT | 1 |
| 未実装の関数：LOG | 1 |
| 未実装の関数：LOGAND | 1 |
| 未実装の関数：LOGBITP | 1 |
| 未実装の関数：MAKE-PATHNAME | 1 |
| 未実装の関数：MAKE-STRING | 1 |
| 未実装の関数：MERGE-PATHNAMES | 1 |
| 未実装の関数：PPRINT | 1 |
| 未実装の関数：PROBE-FILE | 1 |
| 未実装の関数：READ-CHAR | 1 |
| 未実装の関数：READ-LINE | 1 |
| 未実装の関数：REALP | 1 |
| 未実装の関数：REMOVE | 1 |
| 未実装の関数：ROOM | 1 |
| 未実装の関数：SIN | 1 |
| 未実装の関数：SINH | 1 |
| 未実装の関数：SQRT | 1 |
| 未実装の関数：STRING | 1 |
| 未実装の関数：STRING-CAPITALIZE | 1 |
| 未実装の関数：STRING-TRIM | 1 |
| 未実装の関数：UPPER-CASE-P | 1 |
| 未実装の関数：WARN | 1 |
| 未実装："~B" | 1 |
| 未実装："~[" | 1 |
| 未実装："~v" | 1 |
| 未実装：DECLAIM | 1 |
| 未実装：DEFMETHOD | 1 |
| 未実装：ECASE | 1 |
| 未実装：HANDLER-BIND | 1 |
| 未実装：IGNORE-ERRORS | 1 |
| 未実装：TIME | 1 |
| 未実装：TYPECASE | 1 |
| 未実装：割り切れない整数の割り算 | 1 |

各ブロックの結果は `eval-check.tsv`（同じディレクトリ）にある。
