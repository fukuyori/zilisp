# 教材のブロックの実行の結果（自動生成）

このファイルは `zig build eval-check` が生成する。手で編集しない。
教材のブロックのうち、分類の候補が A のものを、Zilisp（VM。`--script`）と SBCL 2.6.7（`--script`）で実行して比べた結果。
ブロックは教材の1つのコードブロックで、単独では動かないもの（前のブロックの定義を使うもの）も含む。

| 結果 | 意味 | ブロック数 |
|---|---|---|
| match | 両方とも正常に終わり、標準出力が同じ | 513 |
| both-error | 両方ともエラーで終わった | 362 |
| output-diff | 両方とも正常に終わったが、標準出力が違う | 1 |
| zilisp-error | Zilisp だけがエラー | 79 |
| sbcl-error | SBCL だけがエラー | 0 |
| timeout | 時間内に終わらなかった | 0 |
| 計 | | 955 |

## Zilisp だけがエラーになったブロックの、最初のエラー

| 最初のエラー | ブロック数 |
|---|---|
| 未実装：DEFSTRUCT | 31 |
| 未実装：DEFCLASS | 21 |
| 未実装：TRACE | 3 |
| READER-ERROR | 2 |
| 未実装の関数：RANDOM | 2 |
| 未実装："FOR" | 2 |
| 未定義の関数：QUIT | 1 |
| 未実装の変数：*RANDOM-STATE* | 1 |
| 未実装の関数：APROPOS | 1 |
| 未実装の関数：COMPLEX | 1 |
| 未実装の関数：DESCRIBE | 1 |
| 未実装の関数：DISASSEMBLE | 1 |
| 未実装の関数：DOCUMENTATION | 1 |
| 未実装の関数：GET-INTERNAL-REAL-TIME | 1 |
| 未実装の関数：GET-UNIVERSAL-TIME | 1 |
| 未実装の関数：INSPECT | 1 |
| 未実装の関数：LOGBITP | 1 |
| 未実装の関数：RATIONALIZE | 1 |
| 未実装の関数：ROOM | 1 |
| 未実装の関数：SINH | 1 |
| 未実装：DECLAIM | 1 |
| 未実装：DEFMETHOD | 1 |
| 未実装：TIME | 1 |
| 未実装：結果が複素数になる演算は未実装です | 1 |

各ブロックの結果は `eval-check.tsv`（同じディレクトリ）にある。
