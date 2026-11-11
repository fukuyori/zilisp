# 変更履歴

[English](CHANGELOG.md)

## Unreleased

### Added
- Phase 26：`defstruct`（CLHS defstruct）。オプション `:conc-name`・`:constructor`（キーワードの引数のものと、引数の並びを
  指定するもの（BOA）。複数可）・`:copier`・`:predicate`・`:include`（スロットの既定値・型・read-only の書き換え）・
  `:print-function`・`:print-object`、スロットの `:type`（構築子と `setf` で検査し、合わなければ type-error）・`:read-only`、
  `copy-structure`、`#S(…)` の印字と読み取り、`typep`（構造体の名前と `structure-object`）、`equalp` と `equalp` のハッシュ表。
  印字は SBCL 2.6.7 と同じ形（pretty printer の改行の位置、`*print-level*`・`*print-length*`・`*print-circle*` も）。
  `(:type list)`・`(:type vector)`・`:named`・`:initial-offset` は未実装（`zilisp:unimplemented`）。構造体のリテラルは、
  定義を実行した後に読むときだけ使える（ネイティブでコンパイルするファイルには書けない）
- 時刻：`get-universal-time`・`get-decoded-time`・`decode-universal-time`・`encode-universal-time`（引数の型と、範囲の外の年の
  扱いは SBCL 2.6.7 と同じ。その土地の時刻との差は、Windows は OS の規則、ほかは `/etc/localtime` から求める）
- `fboundp` が `(setf 名前)` を受け取る
- 試験：言語試験 `defstruct.lisp`・`defstruct-read.lisp`・`defstruct-review.lisp`・`time.lisp`（SBCL 2.6.7 と同じ出力。GC stress の版とネイティブでも同じ）と単体テスト。
  教材の `defstruct` を使うブロック（Level 7・19・23・24・26 の 31 個）と `get-universal-time` を使う 1 個が SBCL と同じ出力になり、
  教材のブロックの一致は 513 から 545 に
- Codex のレビュー（P26）で見つけた 5 件を直した（どれも SBCL 2.6.7 と照合した）：`#1=#S(node :next #1#)` のように `#n#` で
  自分を指す構造体を読める（スロットに仮の値が残っていた。型のあるスロットは置き換えた後で確かめる）、BOA の構築子の
  supplied-p の変数と同じ名前のスロット、`:include` でスロットの型を書き換えても元の型を検査する、`decode-universal-time` の
  time-zone が秒にして整数にならなければ type-error、`defstruct` のオプションの余分な引数と重なりをエラーにする
- Codex の 2 回目のレビュー（P26）の 6 件を直した（どれも SBCL 2.6.7 と照合した）：`#S` のスロットの値のリスト・ベクタの中に
  `#n#` があるとき、置き換えた後の値で型を確かめる（正しい値を拒み、誤った値を通していた）、`:include` の `(x)` は元の初期値の
  まま、pretty でない印字で構造体・condition の中のリストに `*print-level*` と `*print-circle*` が伝わる、`(:conc-name "")` は
  今のパッケージのシンボル、`(:print-function nil)`・`(:print-object nil)` は `#S(…)` の形、`:include` で同じスロットを 2 回
  書き換えるとエラー
- Codex の 3 回目のレビュー（P26）の 2 件を直した（どれも SBCL 2.6.7 と照合した）：循環する `#S` を読んでいる間も、initform が
  作る別の構造体・`setf`・入れ子の読み取りの型を検査する（省略するのは `#n=` の仮の値を含む値だけ）、pretty でない印字で
  構造体やリストの中の多次元の文字の配列を 1 段深く書いていた
- Codex の 4 回目のレビュー（P26）の 1 件を直した（SBCL 2.6.7 と照合した）：循環する `#S` を読んでいる間に、reader macro が
  持ち出した `#n#` の仮の値を initform が別の構築子・`setf` に渡すと、型の検査が漏れた。検査を省略するのは、reader が作って
  いる構造体のスロットだけにした（型を検査しない読み取り用の構築子を使う）
- Codex の 5 回目のレビュー（P26）の 1 件を直した（SBCL 2.6.7 と照合した）：reader macro が、読んだ `#S` の構造体の代わりに
  複製や別の値を返すと、元の構造体に `#n#` の仮の値が残り、型の検査が行われなかった。検査待ちの構造体の中も置き換える
- Codex の 6 回目のレビュー（P26）の 2 件を直した（どれも SBCL 2.6.7 と照合した）：`#n#` を置き換えたら、読んだ結果の中の
  構造体すべての型を確かめる（reader macro が複製を返して元だけを書き換えると、複製の検査が漏れた）、`#S` の型のエラーの後に
  同じストリームの続きを読める（位置が進まず、次の `read` が同じエラーを繰り返していた）
- Codex の 7 回目のレビュー（P26）の 3 件を直した（6 回目の修正が原因）：`#S` の initform が同じストリームを読んだら、
  外側の読み取りはその続きから読む（読んだ分をもう一度読んでいた）、`#n#` と関係のない既存の構造体を確かめ直して拒まない、
  外側のラベルが残っているときに多くの構造体を読む時間が二乗に増えない
- Codex の 8 回目のレビュー（P26）の 3 件を直した：`#S` の initform からの recursive な `read` が外側の `#n=` のラベルを
  参照できる。reader が型を確かめるのは、reader が `#S` で作った構造体だけにした（reader macro が作った・書き換えた構造体の
  型は reader macro の責任。関係のない構造体を拒む・遅くなる問題が続いたため）。多くの `#S` が同じラベルを指す入力の
  読み取りが二乗の時間にならない（6,400 個で、ReleaseFast の 5.1 秒が 24 ms に）
- Phase 25：condition・handler・restart（CLHS 9 章）。`define-condition`（`:initarg`・`:initform`・`:reader`・`:writer`・
  `:accessor`・`:report`・`:default-initargs`）・`make-condition`、標準の condition 型の階層、`signal`・`error`・`cerror`・
  `warn`・`invoke-debugger`・`*debugger-hook*`、`handler-bind`・`handler-case`（`:no-error` も）・`ignore-errors`、`restart-bind`・
  `restart-case`（`:report`・`:interactive`・`:test`、通知する condition への関連付け）・`with-simple-restart`・
  `with-condition-restarts`・`compute-restarts`・`find-restart`・`invoke-restart`・`invoke-restart-interactively`・`restart-name`・
  `abort`・`continue`・`muffle-warning`・`store-value`・`use-value`、condition のアクセサ（`type-error-datum` など）。
  Zig で見つけたエラー（`car` の type-error、0 除算、未束縛の変数など）も handler で受け止められ、restart も使える。
  標準の condition の report の文面と印字は SBCL 2.6.7 と同じ。受け止められなかったエラーの報告に、使える restart の一覧を加えた
  （番号で選ぶ操作は後の Phase）
- `typep`（数の範囲・`mod`・`member`・`and`・`or`・`not`・`satisfies`・`cons`・ベクタと配列の要素の型と大きさ・condition の型）、
  `typecase`・`etypecase`・`ctypecase`・`ecase`・`ccase`・`check-type`・`assert`（文面は SBCL と同じ）、関数としての `eval`
- 試験：言語試験 `conditions.lisp`（SBCL 2.6.7 と同じ出力。GC stress の版とネイティブでも同じ）と単体テスト。
  教材 Level 13 は、ファイルのエラーの文面の 1 つ（処理系依存）と、未実装の `get-universal-time` を呼ぶ 1 つ以外は SBCL と同じ出力。
  教材のブロックの一致は 478 から 513 に。
  起動時間は 13.55 ms
- Codex のレビュー（P25）で見つけた 6 件を直した（どれも SBCL 2.6.7 と照合した）：`restart-case` の中の `cerror` の引数の評価順、
  マクロを展開すると `signal`・`error` になるフォームの restart の関連付け、`abort`・`muffle-warning` の restart が戻ったときの
  control-error、`typep` の `(vector t n)`・`(string n)` を fill-pointer でなく次元で照合、reader-error・end-of-file の handler
  から読んだときの位置、reader-error の `stream-error-stream`。`*break-on-signals*` はデバッガのフェーズ（tque #351）で扱う
- Codex の 2 回目のレビュー（P25）の 4 件を直した：`#A` の中身の誤りのときのストリームの位置、`read-from-string` の
  reader-error・end-of-file のストリーム、`ccase`・`ctypecase` の場所の部分式を1回だけ評価、handler・restart がなくても
  Zig で見つけたエラーで `*debugger-hook*` を呼ぶ
- Codex の 3 回目のレビュー（P25）の 3 件を直した：`ccase`・`ctypecase` は場所を1回だけ読む、格納の変数が複数ある場所、
  `read-from-string` のエラーのストリームの確保に失敗したときに元のエラーで上書きしない
- Codex の 4 回目のレビュー（P25）の 5 件を直した：マクロ・特殊演算子の funcall は未実装でなく undefined-function、
  型でない CL のシンボルの `typep` と `pprint-logical-block` の指定の誤りと `loop` の知らない句は未実装でなく error、
  `etypecase`・`ctypecase` の `otherwise` は型指定子、`(setf (values …))` を加えた（格納の変数が複数の場所の `setf`）
- Codex の 5 回目のレビュー（P25）の 6 件を直した：格納の変数が 0 個・複数の場所（`(values)`・`(values a b)`）の
  `setf`・`incf`・`decf`・`push`・`pop` はすべての格納の変数を束縛する、`typep` は型指定子の形を確かめる（`(random-state 3)`・
  `(mod 0)`・`(integer 1 2 3)`・型でない要素の型は error、`(base-string n)`・`(simple-base-string n)`・`(complex 型)` は偽）、
  `loop` の先頭でない `named` と知らない `being` の種類は program-error（`being` の symbol の種類と SBCL の `elements` だけ未実装）
- Codex の 6 回目のレビュー（P25）の 5 件を直した：`getf` と入れ子の `values` の場所はすべての格納の変数を束縛する（格納の
  変数のない場所は値を受け取らず NIL を返す）、`typep` は `and`・`or`・`not`・`cons` の外側の形をいつも確かめる（部分は使うとき
  だけ）、数の範囲の限界を型ごとに確かめる（`(integer 1.5 3)`・`(single-float 1 3)` は error）、`(complex 型)` の引数は `*` か
  `real` の下位の型
- Codex の 7 回目のレビュー（P25）の 3 件を直した：`incf`・`decf` は増やす量を場所の値を読む前に評価する、
  `(complex (and …))` を受け付ける（交わりは空や実数になることがある）、要素の型 `base-char` は文字列に当たらない
  （Zilisp の文字列の要素の型はいつも `character`）
- Codex の 8 回目のレビュー（P25）の 2 件を直した：`complex` の引数の判定を 3 つに分けた。実数の下位と言い切れれば受け付け
  （`(not (not real))` も）、実数でない要素を必ず含めば誤り（`(and string)`・`(and t string)` も）、どちらとも言い切れなければ
  `zilisp:unimplemented`（`(and string symbol)` などの空の交わり。SBCL は NIL）
- Codex の 9 回目のレビュー（P25）の 1 件を直した：部分が `nil` の `cons`（`(cons nil t)` など）は空の型なので
  `complex` の引数に使える。空かどうか言い切れない `cons` と `complex` の合成の型（`(complex nil)` など）は
  `zilisp:unimplemented`（SBCL は NIL）
- Codex の 10 回目のレビュー（P25）の 1 件を直した：`invoke-restart`・`invoke-restart-interactively` に restart の
  オブジェクトを渡したら、いま有効かだけを確かめる（`:test` を condition なしで呼び直さない）。condition を指定して
  見つけた restart（`continue`・`store-value`・`use-value` の経路も）を control-error で拒否していた
- Codex の 11 回目のレビュー（P25）の 1 件を直した：`assert` は、テストの式が特殊演算子（`if`・`let` など）なら引数を
  先に評価しない（選ばれない分岐を評価し、`let` の束縛の並びを式として評価していた）。そのために `special-operator-p` を
  実装した（CL の 25 個の特殊演算子で SBCL 2.6.7 と一致）
- Codex の 12 回目のレビュー（P25）の 1 件を直した：`define-condition` の `:report` に書いたシンボルは、その形の字句環境の
  関数（`(function 名前)`。CLHS）を指すようにした。`flet`・`labels` の局所関数も書ける（引用して保存していたので、
  いつも大域の関数が呼ばれていた）
- Codex の 13 回目のレビュー（P25）の 1 件を直した：印字の中で呼んだ関数（condition・restart の report、`format` の
  `~/名前/`、`set-pprint-dispatch` の関数）の値が、`princ-to-string`・`write-to-string`・`format` の値に混ざらないように
  した（report が `(values)` を返すと `princ-to-string` が NIL を返していた）
- Codex の 14 回目のレビュー（P25）の同じ種類の 3 件を直した：`(satisfies …)` の述語の値（`set-pprint-dispatch` で見える）、
  `eval` に渡した空の `progn`・`eval-when` の前の値、入力の終わりの直前のリーダーマクロの値が、結果に混ざらないように
  した。`:initial-value` なしで要素のない列に `reduce` を使うと、関数の主値だけを返すようにした

### Changed
- リリースに `SHA256SUMS.txt` を付けず、リリースノートに配布物の署名の有無を書かないようにした
- `do`・`do*`・`psetq` の形の誤りを、SBCL 2.6.7 と同じく simple-error にした（今までは program-error）
- 未実装の機能（`zilisp:unimplemented`）は `error` の下位でない（`serious-condition` の下位）。`ignore-errors` や
  `(handler-case … (error …))` は未実装を受け止めず、トップレベルまで届く。CL の未実装の関数・変数も、handler には
  `zilisp:unimplemented` として通知する
- スタックの溢れ（VM・ネイティブのスタック、動的束縛と制御スタック）の storage-condition は、handler に通知しない
  （handler を動かす予備の領域がないため）
- `*print-pretty*` が NIL のとき、リスト・ベクタの中の condition・restart も SBCL 2.6.7 と同じ形で印字する
  （今までは `#<型 {アドレス}>`）
- トップレベルのエラーの報告は、構造体の値を `#S(…)` の形で書く
- `zig build native-test` は試験を並列に実行する（並列の数は環境変数 `ZILISP_NATIVE_TEST_JOBS`、既定は論理プロセッサの数の半分で
  1〜8。結果は名前の順に表示する。38 ファイルの Debug が約 37 分から約 7 分に）

## 0.3.0 - 2026-11-04

データ処理・ファイル処理と、複数のファイルからなるプログラム（Phase 19〜24）：繰り返しと `loop`、数の塔（bignum と比）、
一般の配列と列の関数、Unicode 15.0.0 の文字、SBCL と同じ配置のハッシュ表、パッケージと `load`、ストリームとパス名、
`format` の全体、Reader の拡張と pretty printer。condition（`handler-case`・restart）・`defstruct`・CLOS は未実装
（`compatibility/eval-status.md`）。

### Added
- Phase 21：一般の配列（多次元の配列・fill-pointer・adjustable な配列。添字がいくつでもよい `aref`、`row-major-aref`、
  `array-dimensions` などの配列の問い合わせ、`vector-push`・`vector-push-extend`・`vector-pop`・`adjust-array`、`#2A(...)` の印字）、
  `equalp`・`equalp` のハッシュ表・`sxhash`、文字の関数（`char-code`・`code-char`・`char-upcase`・`alpha-char-p`・`digit-char-p`、
  `char<`・`char-equal` の仲間など）、文字列の関数（`string`、`string<`・`string-equal` の仲間、`string-capitalize`・
  `nstring-upcase`・`string-trim`・`make-string`・`parse-integer`）、`:test`・`:test-not`・`:key`・`:start`・`:end`・`:from-end`・
  `:count` を取る列の関数（`find`・`position`・`count`・`remove`・`delete`・`substitute`・`remove-duplicates`・`sort`・
  `stable-sort`・`search`・`mismatch`・`subseq`・`elt`・`fill`・`replace`・`concatenate`・`coerce`・`map`・`map-into`・`some`・
  `every`・`merge` など）、リスト・木・集合の関数（`member`・`assoc`・`rassoc`・`acons`・`pairlis`・`butlast`・`ldiff`・`maplist`・
  `subst`・`sublis`・`union`・`intersection`・`set-difference`・`adjoin`・`pushnew`・`remf` など）。displaced な配列は未実装
  （明示的なエラー）。文字の種類と大文字・小文字は ASCII の文字だけ。試験：SBCL 2.6.7 の結果と比べる139通り（GC stress でも
  実行）、言語試験 `sequences.lisp`（データ処理のサンプル。gc-stress 版も）・`sequence-cases.lisp`（ネイティブでも一致）。
  教材のブロックの一致は 362 から 421 に
- README（英語・日本語）を加え、変更履歴を英語（`CHANGELOG.md`）と日本語（`CHANGELOG.ja.md`）に分けた
- Phase 20：数の階層。bignum（limb をオブジェクトの中に置く。fixnum に収まる値はいつも fixnum）、比（約分済み）、浮動小数との
  混在（正確な比較、正しく丸める変換）、`floor`・`ceiling`・`truncate`・`round`（2つの値）、`mod`・`rem`・`gcd`・`lcm`・
  `numerator`・`denominator`・`rational`・`float`、`expt`・`sqrt`・`isqrt`・`exp`・`log`・三角関数、`logand`・`logior`・`logxor`・
  `lognot`・`ash`・`integer-length`・`logcount`、型の述語。Reader は大きな整数と比を読む。複素数は未実装（明示的なエラー）。
  試験：SBCL 2.6.7 の結果と比べる192通り（GC stress でも実行）、言語試験 `numbers.lisp`（と gc-stress 版）・`number-cases.lisp`
  （ネイティブでも一致）
- Phase 19：`tagbody`・`go`（同じ関数の中はジャンプ、それ以外は実行時の脱出。着地してもエントリは残る。VM の命令
  `TAGBODY_ENTER`・`GO_NL`、ネイティブはラベル付き switch）、`psetq`・`dolist`・`dotimes`・`do`・`do*`、`loop`（独自実装。主な句）、
  `mapcar`・`mapc`・`mapcan`・`nconc`・`reduce`、`evenp`・`oddp`・`zerop`・`plusp`・`minusp`・`max`・`min`・`abs`・`mod`・`rem`、
  `reverse`・`nreverse`・`copy-list`・`last`・`endp`、`symbol-name`・`string=`・`string-upcase`・`string-downcase`・`char=`、`princ`、
  `format` の最小版（`T`・`NIL`、`~A ~S ~D ~% ~& ~~`。それ以外は明示的なエラー）。試験：SBCL 2.6.7 の結果と比べる139通り
  （GC stress でも実行）、言語試験 `iteration.lisp`（と gc-stress 版）・`iteration-cases.lisp`（ネイティブでも一致）。
  反復の教材（Level 6）は Zilisp だけがエラーのブロックが 0 に。教材のブロックの一致は 244 から 347 に
- 詳細設計書の英語版（`docs/Zilisp_Detailed_Design_v0.2.md`）と、Zig 0.17.0 の照合結果の英語版（`docs/zig-std-usage.md`。日本語版は `docs/zig-std-usage.ja.md` に移した）
- Phase 21.5：`alpha-char-p`・`alphanumericp`・`upper-case-p`・`lower-case-p`・`both-case-p`・`char-upcase`・`char-downcase`・
  `digit-char-p`・`char-equal`・`char-lessp`、文字列の大文字・小文字と比較の関数、`parse-integer`、`equalp` の文字の種類と
  大文字・小文字を、Unicode 15.0.0（SBCL 2.6.7 と同じ版）に従わせた。Reader は ASCII 以外の小文字も大文字にし（`λx` は `ΛX`）、
  Printer はそのような名前を囲む。表は同梱した UCD のファイル（`data/unicode/`。Unicode License v3。`zig build gen-unicode`）から
  作って `src/unicode/tables.zig` にコミットし、`zig build test` が、表が UCD と同じかと、全符号位置で SBCL 2.6.7 と同じかを
  確かめる。配布物に Unicode のライセンスを `LICENSE-UNICODE.txt` として入れた。起動時間 8.82 ms（ReleaseFast、`--eval nil`）
- Phase 21.6：ハッシュ表を SBCL 2.6.7 と同じ並べ方にした（キーと値の配列、バケットの表と鎖、空き枠の一覧、`equal`・`equalp` の表の
  ハッシュ値。墓標はなくした）。`maphash` と `loop` の `being the hash-keys` は SBCL と同じ順序でたどる（入れた順。`remhash` の後の
  枠の再利用、大きくする規則、小さい flat の表も同じ）。削除と挿入の繰り返しは約 1.8 倍、`maphash` は約 1.3 倍速くなり、
  ほかの操作はほぼ同じ。起動時間 8.74 ms

- Phase 22：パッケージ。`*package*` を本当の特殊変数にした。パッケージの関数（`find-package`・`make-package`・`rename-package`・
  `delete-package`・`intern`・`find-symbol`・`unintern`・`export`・`unexport`・`import`・`shadow`・`shadowing-import`・`use-package`・
  `unuse-package`・`find-all-symbols`・`symbol-package`・`keywordp`・`make-symbol` など）、`defpackage`（SBCL の `:local-nicknames`
  も）、`in-package`、`do-symbols`・`do-external-symbols`・`do-all-symbols`、名前の衝突の検出（package-error）、文字列で指定した
  ファイルの `load`（`*package*` を束縛する）。シンボルは `*package*` を基準にパッケージで修飾して印字する。ネイティブのプログラムは
  定数を「パッケージ::名前」で書く。教材のブロックの一致は 421 から 429 に。起動時間 9.08 ms

- Phase 23：ストリームとパス名。標準のストリーム（`*standard-output*`・`*standard-input*`・`*error-output*`・`*terminal-io*` など）、
  ファイルのストリーム（`open`・`close`・`with-open-file`。文字と `(unsigned-byte 8)` の要素、UTF-8 と Latin-1）、文字列の
  ストリーム（`with-output-to-string`・`with-input-from-string`・`read-from-string`・`prin1-to-string` など）、broadcast・two-way・
  synonym のストリーム、読み書きの関数（`read-line`・`read-char`・`read`・`read-byte`・`read-sequence`・`write-string`・`write-line`・
  `write-byte`・`fresh-line` など）、出力先のストリームを受け取る印字の関数と `format`。パス名（`#P`・`make-pathname`・
  `merge-pathnames`・`namestring`・`probe-file`・`truename`・`directory`・`ensure-directories-exist`・`delete-file`・`rename-file`・
  `file-write-date`・`*default-pathname-defaults*`。読み方は SBCL 2.6.7 と同じ）。回収されるストリームは GC が閉じる。
  スクリプトは、標準入力の終わりで黙って終わる（SBCL の `--script` と同じ）。教材のブロックの一致は 429 から 467 に。
  起動時間 9.47 ms
- Phase 24（P24a）：印字の変数。`*print-base*`・`*print-radix*`・`*print-case*`・`*print-level*`・`*print-length*`・
  `*print-circle*`（`#n=` と `#n#`）・`*print-readably*`（読み戻せないものは `print-not-readable`）・`*print-array*`・
  `*print-gensym*`・`*print-escape*`・`*read-default-float-format*` が、`prin1`・`princ`・`print`・`-to-string` の関数・
  `format` の `~A`・`~S`・REPL が印字する値に効く。`write`・`write-to-string` は、すべてのキーワードを受け取る。印字と
  読み取りの変数の初期値は SBCL 2.6.7 と同じ（`*print-pretty*` は P24d の pretty printer で T に）。言語試験 `printer.lisp`
  （SBCL 2.6.7 と同じ出力）
- Phase 24（P24b）：pretty printer 以外のすべての指示子の `format`（SBCL 2.6.7 と同じ）：`~A ~S ~W ~C`、`~D ~B ~O ~X ~R ~P`、
  `~F ~E ~G ~$`（SBCL の `flonum-to-string` を移植したので丸めも同じ）、`~% ~& ~| ~~ ~T`、`~* ~? ~( ~) ~[ ~; ~] ~{ ~} ~^`、
  `~< ~>` の左右揃え、`~/名前/`。指示子の引数（`v`・`#`・`'文字`）と修飾子。`formatter` と関数の制御。教材のブロックの一致は
  467 から 478 に。言語試験 `format.lisp`
- Phase 24（P24c）：Reader の拡張。readtable（`*readtable*`・`copy-readtable`・`readtablep`・`readtable-case` とその `setf`）、
  ユーザー定義の reader macro（`set-macro-character`・`get-macro-character`・`make-dispatch-macro-character`・
  `set-dispatch-macro-character`・`get-dispatch-macro-character`・`set-syntax-from-char`・`read-delimited-list`）、
  `*read-eval*` に従う `#.`、`#n=` と `#n#`（循環も）、読み取りと印字の `readtable-case`、すべての read に効く
  `*read-base*`・`*read-default-float-format*`・`*read-suppress*`、`with-standard-io-syntax`。ネイティブのプログラムは
  循環する定数を保つ。言語試験 `readtable.lisp`
- Phase 24（P24d）：pretty printer（SBCL 2.6.7 の `pprint.lisp` に倣う）。`pprint`・`pprint-logical-block`・`pprint-pop`・
  `pprint-exit-if-list-exhausted`・`pprint-newline`・`pprint-indent`・`pprint-tab`・`pprint-fill`・`pprint-linear`・
  `pprint-tabular`、`*print-pprint-dispatch*` と `pprint-dispatch`・`set-pprint-dispatch`・`copy-pprint-dispatch`、
  特殊形式・マクロ・関数の呼び出し・quote と backquote・配列の SBCL と同じ標準の形、`*print-right-margin*`・
  `*print-miser-width*`・`*print-lines*`、`format` の `~<…~:>`・`~_`・`~I`・`~:T`。`*print-pretty*` の初期値は
  SBCL と同じ T。言語試験 `pretty.lisp`・`pretty-default.lisp`（SBCL 2.6.7 と同じ出力）
- Phase 24 の受入：Reader が `#nA` と `#A(次元 要素の型 . 中身)` を読む。`*print-readably*` では、`#nA` で表せない配列
  （`(make-array '(0 3))` など）を SBCL と同じく `#A` の形で書く。読み戻せる形で印字したものは、pretty printer の
  有無によらず `equalp` なものとして読み戻せる。言語試験 `round-trip.lisp`

### Fixed
- 基数 8 と 32 で印字する bignum の桁が誤っていた（Zig 0.17.0 の `toStringAlloc`。2 進の桁から作るようにした）
- 0.3 の変更のレビュー（agy と Codex。Phase 19〜24）で再現した 41 件を直した：
  - 落ちる問題：列の型の指定の負の長さ（`(make-sequence '(vector t -1) 0)`）、オブジェクトのヘッダに入らない長さ
    （`(make-string 4294967296)` は storage-condition にした）、`format` の `~0,0<…~>`（division-by-zero にした）で
    panic していた。
  - `loop`：`with` の分解と `and`、`for … from` の部分節を書いた順に評価、上り・下りの矛盾と正でない `by` はエラー、
    `in`・`on` の `by` は一度だけ評価、`it` は条件の直後の最初の句の中だけ、種類の違う集め方の混在と誤った `using` は
    program-error。`do` は誤った変数の指定を拒む。`reduce` は `:start`・`:end` を確かめる。`mapcan` は
    `call-arguments-limit` より長いリストにも使える。`(expt -2 2.0)` は 4.0。
  - 列と配列：シンボルの `sxhash` は名前から求める。`remove-duplicates :from-end t` は `:test` に SBCL と同じ順で
    渡す。`coerce` は、すでにその複合の配列の型のものをそのまま返し、ラムダ式から関数を作る。`butlast`・`nbutlast`
    は 0 ならドット対の末尾を保ち、負の数を拒む。`adjust-array`・`make-string` はキーワード引数を確かめる。
    `:initial-contents` はドット対で終わるリストを拒み、リストでも二乗の時間にならない。文字列を写すときの
    メモリ不足を伝える。
  - ストリーム：閉じたストリーム・入力ストリームへの `fresh-line`・`~&`・`clear-output` はエラー。閉じたストリームの
    `file-position`・`file-length` は stream-error。読み飛ばす `peek-char` の後の `unread-char` は読み飛ばした文字を
    戻す。`make-synonym-stream` は NIL を受け付ける。`make-broadcast-stream`・`make-two-way-stream` はストリームの
    向きを確かめる。`write-sequence` は broadcast のストリームにバイトを書く。`:probe` のストリームは向きを持たない。
    標準入力を読み足しても、フォームを読み直さない（`#.` と reader macro の副作用が2回起きていた）。
  - `load` は `*readtable*` を束縛する。`equal` はリストの cdr にあるパス名も比べる。KEYWORD に出入りするシンボルの
    キーワードの印を付け外しする。パス名の関数は、単純でない文字列を受け付け、`:back` を取り除き、ディレクトリの
    ない名前と `**/` を照合し、`parse-namestring` の2つ目の値に `:start` を返し、synonym のストリームをたどる。
    `make-pathname` は欄を確かめる。パッケージの別名は重複とパッケージ自身の名前を除き、`:local-nicknames` は
    CL・COMMON-LISP・KEYWORD とパッケージ自身の名前を拒む。
  - Reader と印字：`#+`・`#-` で読み飛ばしている間と `*read-suppress*` のときの reader macro は、`*read-suppress*` を
    束縛して呼び、値は NIL。reader macro の中の recursive な `read` は backquote の深さを引き継ぐ。`NIL` も readtable に
    従って囲む。`read-delimited-list` は別の閉じ括弧を拒む。初期の pprint-dispatch の表の写しを変えても、標準の形を
    保つ（SBCL と同じ優先度）。`#nA` のリストの読み取りは二乗の時間にならない。
  - ネイティブのプログラム：トップレベルのフォームの定数は、そのフォームを実行する直前に読む（後ろのフォームの
    シンボルを先に intern していたので、前のフォームの `shadow` と衝突した）。定数全体で `#n=` の番号を共有する
    （2つの定数が使う uninterned なシンボルは同じシンボルのまま）。
  - 言語試験 `review-cases.lisp`（SBCL 2.6.7 と同じ出力。GC stress の版も）と、SBCL と比べた 31 個のエラーの場合の
    単体テスト。
  - これらの修正の Codex のレビューで見つかった 8 件も直した：パッケージの別名の重複を除くときに、解放した文字列を
    読んでいた。`make-pathname` が写した文字列を GC から見えない所に持っていた。KEYWORD へ import したシンボルの値を
    書き換えていた。初期値のない `with` の分解の既定値。入れ子の条件の式の `it`。ディレクトリのないパス名と
    `(:absolute :wild-inferiors)` の照合。`make-pathname` の誤ったディレクトリ（SBCL と同じく simple-error）。
    ストリームを渡した `parse-namestring` の2つ目の値。
  - さらに Codex のレビューで見つかった 5 件も直した：`for … from` が `to`・`by` を評価する前にループの変数を束縛していた
    （新しい変数を見ていた）。入れ子の条件の `and`・`else` に外側の `it` が漏れていた。`:back` が直前の `:wild`・
    `:wild-inferiors` を取り除かなかった。`make-string` が `:element-type nil` を拒んでいた。閉じたストリームへの
    `format` が、何も書かないときもエラーにしていた（SBCL と同じく、書くときと `~&` だけエラー）。
  - さらに 3 件：`#.` の中で標準入力を読み足すと（`read-line` など）、外側の Reader が使っている入力のバッファが動いた
    （落ちていた。reader macro の後と同じく、`#.` の後にも取り直す）。閉じた `*standard-output*` への `(format t "")`。
    `make-pathname` のディレクトリの空の文字列は、SBCL と同じく `:back` を処理する前に除く。
- 標準出力と標準エラー出力を、ファイルの位置 0 から書いていたため、両方を1つのファイルにリダイレクトしたときや `>>` で
  追記したときに、前の出力を上書きしていた（ストリームとして書くようにした）
- Codex のレビュー（Phase 24）の指摘 8 件：`format` がリストの引数を GC から見えない所に写していたため、`~/名前/` の関数が
  リストを切ると後ろの引数が回収された。pretty printer で、代わりの印字で書く配列の要素が `*print-circle*` の番号を失っていた
  （循環するベクタでスタックがあふれた）。循環するリストを渡した `~:<…~:>` が終わらなかった。ネイティブの定数を readably で
  書いていなかった（`#A((0 3) T)` が `(0 0)` になった。読み戻せない定数は `--emit-zig` でエラーにした）。`#A` の形の
  `NIL`・`T`・`CHARACTER` をパッケージ修飾なしで書いていた。論理ブロックの中で `~:*`・`~@*`・`~@[` が引数の位置を戻さなかった。
  論理ブロックの中の `~&` が古い行の状態を見ていた（pretty stream の上の `fresh-line` と `~&` は、SBCL と同じく必ず改行する）。
  `with-standard-io-syntax` が `*print-pprint-dispatch*` を束縛していなかった
- Codex のレビュー（Phase 23）の指摘 16 件：`:if-exists` の `:rename`・`:rename-and-delete` が、ファイルを「名前.bak」に移さずに
  切り詰めていた、REPL と `*standard-input*` が別のバッファで標準入力を読んでいたので、入力を取りこぼすことがあった、Windows で
  CR LF を1つの改行として読んでいた（SBCL 2.6.7 は変換しない）、Latin-1 のストリームの `read` がバイト列を UTF-8 として読んでいた、
  バイナリのストリームへの `write-string`・`format` などの文字の出力がエラーにならなかった、broadcast の `write-byte`・`finish-output`・
  `force-output` が中のストリームに届かなかった、閉じた synonym・two-way を通して読み書きできた、`read-char-no-hang` が端末の入力を
  待っていた、`:overwrite` のストリームの `file-length` が既にある長さを数えなかった、`pathname-match-p` が名前と型だけを、バイト単位で
  照合していた、`merge-pathnames` が `:back` を残し、版がないときに default-version を使わなかった、`directory` が合うディレクトリを
  返さず、`**/**/` などで重複を返した、`equalp` がパス名を比べなかった、`input-stream-p`・`stream-element-type`・`file-position`・
  `file-length` が synonym の先をたどらなかった、Latin-1 で表せない文字を `?` で書いていた（stream-error にした）。あわせて、
  `:defaults` のない `make-pathname` の版を `:newest` にしていた（SBCL は NIL）のを直し、パス名の `equal` は版を比べないようにした
  （SBCL と同じ）
- Codex のレビュー（Phase 22）の指摘 6 件：ネイティブのプログラムが、起動時に定数を読むときにパッケージを登録していたので、
  `defpackage` の前の `find-package` がそれを返し、コンパイル時と実行時の両方で `make-package` するとエラーになった、既にあるパッケージに
  ホームのないシンボルを `import` してもホームを設定しなかった、`shadowing-import` がホームを変えていた、KEYWORD に
  ほかのパッケージを use させられた、`*package*` から見えないときも `NIL` を修飾せずに印字していた、`defpackage` が
  `:size`・`:documentation` の引数を検査していなかった
- `concatenate` など、複数のベクタを集める関数で、確保した容量が足りなくなることがあった（Debug では assert で止まり、
  ReleaseFast ではメモリを壊すおそれ）。`Thread.create` が、標準ライブラリの読み込みに失敗したときに VM の領域を解放していなかった
- Codex のレビュー（Phase 21.6）の指摘 4 件：とても大きなハッシュ表を大きくすると、u32 のバケット数が溢れることがあった
  （枠の数が 2^28 を超えるときは `storage-condition` にした）、大きくするのに失敗した flat の表が flat でない表の印のまま
  残った、`:rehash-size` を無視していたので `maphash` の順序が SBCL と違った（使うようにし、`:rehash-size` と
  `:rehash-threshold` の型を検査する）、`clrhash` が表の全体を消していた（使った範囲だけにした）
- Codex のレビュー（Phase 21）の指摘 9 件：fill-pointer のない配列に `:fill-pointer` を指定した `adjust-array` がエラーに
  ならなかった（0次元の配列では異常終了した）、0次元の配列の `(setf (aref a) x)` が引数の個数のエラーになった、
  `nsubst`・`nsubst-if`・`nsubst-if-not`・`nsublis` が木を書き換えなかった、`remf` が指示子を評価する前に場所を読んでいた、
  `(or character integer)` などの複合の要素の型で文字の配列を作っていた、`make-sequence`・`coerce`・`concatenate`・`map` が
  `null`・`cons`・多次元の `array` の型の制約を無視していた、`butlast`・`nbutlast` がドット対で終わるリストを受け付けなかった、
  `tree-equal` が比較の関数の余分な値を返していた、`map`・`map-into`・`some`・`every` がドット対で終わるリストの末尾を黙って
  無視していた
- Codex のレビュー（Phase 19・20）の指摘 11 件：`(gcd most-negative-fixnum 0)` と `(floor 1d308 1d-308)` で異常終了した、
  底が 0 の `expt` と、指数が 0 の非整数の `expt` が 0.0 を返した（SBCL 2.6.7 と同じく 1.0 か division-by-zero にした）、
  有理数から浮動小数への変換が非正規化数の近くで2回丸めていた、`ash` の大きな右シフトで巨大な整数を作っていた、
  とても大きい（小さい）正確な数の `log` が溢れた、`dolist` の結果の式で本体の宣言が失われた、`reduce :from-end` の
  `:key` を呼ぶ順が逆だった、`loop with x of-type fixnum` の初期値が 0 でなかった、bignum を `tagbody` のタグにできなかった
  （タグは `eql` で比べる）、`last` が bignum の個数を受け付けなかった

## 0.2.0 - 2026-11-02

最初の公開版。Reader・印字・GC・バイトコード VM・最小のネイティブバックエンドの上に、関数、マクロ、多値、
動的束縛、非局所脱出（block・catch・unwind-protect）までを実装した（Phase 01〜18）。
LOOP・DOLIST・FORMAT・DEFSTRUCT・CLOS・condition などは未実装（`compatibility/eval-status.md`）。

### Added
- リリース用のスクリプト：`scripts/build-installer.ps1`（Inno Setup による Windows 用インストーラーと、ターゲットごとの ZIP。
  `-Sign` で、環境変数 `CODESIGN_CERT` の証明書により `zilisp.exe`・アンインストーラー・インストーラーに署名する）、
  `installer/zilisp.iss`（利用者ごとのインストール、PATH への追加の選択）
- GitHub Actions：push・pull request ごとに Linux・macOS・Windows で試験（`.github/workflows/test.yml`）。
  タグ `v<バージョン>` の push で、試験の後に x86_64・aarch64 の Linux（musl）・macOS と x86_64 の Windows をビルドし、
  GitHub のリリースを登録する（`.github/workflows/release.yml`。署名なし。SHA256SUMS.txt を添付）
- 企画・基本設計書（v0.3）と詳細設計書（v0.2）
- MIT ライセンス
- Phase 01：`build.zig` / `build.zig.zon`（Zig 0.17.0）、CLI の骨組み（`--version` / `--help`）、
  ベンチマークの実行器（`zig build bench`、`scripts/run-bench.ps1`）、
  リリースビルドのスクリプト（`scripts/build-release.ps1`）、
  バージョン更新チェックリスト、Zig 0.17.0 の std・言語機能の照合結果（`docs/zig-std-usage.ja.md`）
- Phase 02：言語試験の実行器（`zig build lang-test`）、教材のコードブロックの抽出（`zig build extract-samples`）、
  SBCL による読み込みだけの分類（`tools/classify_samples/classify.lisp`）、
  `scripts/curriculum-inventory.ps1`、`compatibility/curriculum-inventory.md`、`compatibility/manifest.toml`（初期版）
- Phase 03：Reader の基本（`src/reader/`）。空白、コメント（`;`・`#| |#` の入れ子）、整数・比・浮動小数
  （`*read-base*`・`*read-default-float-format*`・指数の記号）、シンボル（エスケープ、パッケージ修飾、
  大文字への変換）、位置情報（行・列）。値を作る処理は Builder として差し替え可能（Value との接続は Phase 05）。
  SBCL との処理系依存の違いを `tests/differential/impl-dependent.toml` に記録
- Phase 04：Reader のマクロ文字。quote、文字列、リスト（ドット対）、`#'`、`#(`（`#n(` を含む）、`#\`（標準・準標準の名前、`U+XXXX`）、
  `#:`、`#b #o #x #nR`、backquote（`zl-sys:quasiquote` など）、`#+` / `#-`（`*read-suppress*`、`*features*`）。
  `#P #S #C #A #. #= ##` は後の Phase まで明示的な reader-error。
  教材のブロックを Zilisp の Reader で読み SBCL と比べる道具（`zig build reader-check`）
- Phase 05：8 バイトの Value（`enum(u64)`、下位ビットのタグ。`src/values/`）、オブジェクトの形（シンボル 64 バイト、
  cons 16 バイト、文字列、単純ベクタ、double-float、パッケージ）、仮のヒープ（Phase 06 で置き換え）、
  パッケージと intern（CL・CL-USER・KEYWORD・ZILISP・ZILISP-SYSTEM。CL の 978 シンボルは SBCL から生成：
  `tools/gen_cl_symbols/gen.lisp`）、Reader を Value につなぐ Builder、印字（prin1 相当。SBCL 2.6.7 と同じ形）、
  `zilisp --read FILE`、言語試験 `tests/language/reader/`（SBCL の出力と一致）、NIL の表現 A/B/C の計測（A を採用）
- Phase 06：ページ単位のヒープ（`src/runtime/heap.zig`）。4 MiB のチャンク（4 MiB 境界）、32 KiB のページ、
  cons 専用のページ、28 のサイズクラス、大きいオブジェクトの連続ページ、ページ外の使用中ビット・マークビット、
  アドレスからオブジェクトの先頭を求める処理（途中を指すポインタを含む）、確保の統計。
  明示的なルートと FFI handle（世代番号つき。`src/runtime/roots.zig`）。
  Windows で大きな境界にそろえた確保を行う `src/support/os_memory.zig`（Zig 0.17.0 の page_allocator の問題の回避）。
  確保のベンチマーク（`tests/bench/alloc.zig`）
- Phase 07：mark-and-sweep GC（`src/runtime/gc.zig`）。マークスタック、正確なルート（パッケージ・NIL・明示的ルート・
  FFI handle）と保守的なルート（ネイティブのスタックとレジスタ）、finalize 待ちの一覧（文字列のバッファの解放）、
  大きいオブジェクトの即時回収、小さいページの遅延スイープ、空になったページの再利用、GC の契機
  （max(8 MiB, 生存量 × 2)）、`--gc-stress`、回収した領域を 0xAA で埋める（Debug）、統計と `--gc-stats`。
  言語試験 `tests/language/gc-stress/`、GC の停止時間のベンチマーク（`tests/bench/gc.zig`）
- Phase 08：最小のコンパイラと VM、REPL。
  Resolver（`src/compiler/resolver.zig`。`quote` `if` `progn` `let` `setq` `function` `lambda`、捕捉と代入の解析）、
  Core IR（`ir.zig`）、バイトコードの生成（`codegen.zig`。捕捉され代入される変数は value_cell に入れる）と検証器（`src/vm/verify.zig`）、
  スタック型の VM（`src/vm/vm.zig`。VM の closure どうしの呼び出しは同じ実行ループの中でフレームを積む、fixnum の高速経路、`WIDE`）、
  関数オブジェクト（`src/runtime/function.zig`：code・closure・native_function）、スレッドの状態（`src/runtime/thread.zig`）、
  プリミティブ（`src/primitives/`：`+ - * / 1+ 1- = /= < > <= >=`、`cons car cdr first rest list list* null not atom consp listp
  symbolp numberp functionp eq eql`、`funcall apply`、`print prin1 terpri`）、
  CLI（`zilisp`＝REPL、`zilisp FILE`・`--script FILE`、`--eval TEXT`、`--load FILE`）。
  condition（Phase 25）ができるまでは、Lisp のエラーを型の名前と説明で報告する。
  言語試験 `tests/language/eval/`（SBCL の出力と一致）、VM のベンチマーク（`tests/bench/vm.zig`）
- Phase 09：`let*`（束縛を順に行う。同じ名前を2回束縛してよい。SBCL 2.6.7 と同じ）。
  `let`・`let*` の束縛と shadowing の試験（SBCL 2.6.7 の結果と比べる20通り。GC stress でも実行）、
  言語試験 `tests/language/eval/let.lisp`（と gc-stress 版）
- Phase 10：`defun`（Zig で書いたブートストラップ用のマクロ。`zl-sys::%defun` に展開する。名前の付いた関数は
  `#<FUNCTION 名前>` と印字する。COMMON-LISP パッケージのシンボルの関数の定義は package-error）、`fboundp`、`symbol-function`。
  VM のフレームの上限を値スタックの 1/4（既定 262144）に。再帰・相互再帰・再定義・高階関数の試験（SBCL 2.6.7 の結果と比べる）、
  言語試験 `tests/language/eval/functions.lisp`（と gc-stress 版）
- Phase 11：`flet`・`labels`（局所関数）。関数の名前空間の束縛を Resolver の範囲に持ち、関数の値は名前の見えない局所変数に入れる。
  `labels` の互いに参照する関数は value_cell に入れる。局所関数は大域の関数・マクロより優先し、`#'名前` でも参照できる。
  COMMON-LISP パッケージのシンボルと特殊演算子の名前は局所関数にできない（SBCL 2.6.7 と同じく program-error）。
  印字は `#<FUNCTION (FLET 名前) {アドレス}>`。flet・labels とクロージャの寿命の試験（SBCL 2.6.7 の結果と比べる20通り、
  GC の後も closure と共有した変数が正しいこと）、言語試験 `tests/language/eval/local-functions.lisp`（と gc-stress 版）
- Phase 12：IR の検証器（`src/compiler/verify_ir.zig`。デバッグビルドと試験でコンパイルのたびに実行）、
  ネイティブバックエンドの最小実装（`src/native/emit.zig`・`src/native/rt.zig`。IR → Zig のソース → ランタイムと一緒に
  コンパイル）、開発用のコマンド `zilisp --emit-zig FILE OUT.zig`、`zig build native-test`（言語試験をネイティブで実行し、
  VM と同じ結果かを確かめる。8件すべて一致）、言語試験 `tests/language/eval/cases.lisp`（P08〜P11 の単体テストの式 160 あまり）。
  計測：fib(30) で VM 約 34.9 ms、ネイティブ約 9.7 ms。`Value.unwind` の検査の費用は約12%
- Phase 13：教材のブロックを VM と SBCL 2.6.7 で実行して比べる道具（`zig build eval-check`。結果は
  `compatibility/eval-status.md` と `eval-check.tsv`）。955 件のうち一致 82、出力の違い 0、Zilisp だけがエラー 511（すべて未実装の機能。
  多いのは defparameter・defmacro・defstruct・cond・loop・setf・dolist）。
  エラーの報告に、VM のフレームの関数名の呼び出しの履歴を加えた（関数の中で起きたエラーのとき。16 件まで）。
  CL の定数 `most-positive-fixnum`・`most-negative-fixnum`・`call-arguments-limit`・`lambda-parameters-limit`・
  `multiple-values-limit`・`char-code-limit`・`pi` に値を設定。値のない CL の変数は「未実装です」と報告する
- Phase 14：動的束縛（shallow binding。束縛のスタック、VM の命令 `BINDING_DEPTH`・`BIND_SPECIAL`・`UNBIND_TO`・`PROGV_BIND`）、
  `special` 宣言（束縛の宣言と自由な宣言）、特殊変数の引数、`defvar`・`defparameter`（名前の特殊変数の宣言はコンパイルの時点）、
  `progv`、`boundp`・`symbol-value`・`set`・`makunbound`。エラーで抜けるときは動的束縛を元に戻す。
  ネイティブバックエンドも対応。試験：SBCL 2.6.7 の結果と比べる23通り（GC stress でも実行）、エラーの後の復元、
  未束縛の変数の束縛と復元、深い束縛と溢れ、言語試験 `tests/language/eval/special.lisp`（と gc-stress 版。ネイティブでも一致）。
  教材のブロックの一致は 82 から 100 に
- Codex による Phase 09〜14 のレビューの指摘6件
  - `progv` の深さを置く局所変数の番号が、シンボル・値の式の中の `let` と重なっていた
  - ネイティブのプログラムで、エラーで抜けたときに動的束縛を戻していなかった（トップレベルのフォームごとに戻す）
  - 実行されない `defvar`・`defparameter` も、コンパイルの時点で特殊変数と宣言していた（トップレベルのフォームだけを
    コンパイルの時点で宣言し、どちらの場合も実行した時点で宣言する）
  - 値を捨てる位置の `let`・`progv` から生成した Zig のコードに、使われない変数が残っていた
  - 検証器が、添字・個数のオペランドを持たない命令の前の `WIDE` を受け付けていた
  - 生成したネイティブのプログラムを GC stress で試験していなかった（`--gc-stress`。`native-test` は通常と両方で実行）
- Phase 15：マクロ展開器（Resolver。トップレベルの展開結果もトップレベル）、`defmacro`（トップレベルならコンパイルの時点でも定義）、
  分解束縛（必須・`&optional`・`&rest`・`&body`・`&key`・`&allow-other-keys`・`&aux`・`&whole`・`&environment`・入れ子）と
  `destructuring-bind`、backquote の展開（`,`・`,@`・`,.`・ベクタ・入れ子）、`macroexpand-1`・`macroexpand`・`macro-function`・`gensym`・
  `append`・`vector`。Lisp で書く標準ライブラリ `src/lisp/boot.lisp`（`when`・`unless`・`cond`・`and`・`or`・`case`・`prog1`・`prog2`、
  変数の場所の `incf`・`decf`・`push`・`pop`）を起動時に読み込む。試験：SBCL 2.6.7 の結果と比べる57通り（GC stress でも実行）、
  言語試験 `tests/language/eval/macros.lisp`（と gc-stress 版。ネイティブでも一致）。教材のブロックの一致は 100 から 179 に
- Phase 16：`setf`（複数の組）と場所の展開（Lisp で書く。`defsetf` の短い形・長い形、`(defun (setf 名前) …)`、`#'(setf 名前)`）、
  場所：変数・`car`・`cdr`・`first`〜`tenth`・`cXXr`・`nth`・`aref`・`svref`・`char`・`schar`・`gethash`・`getf`・`get`・`symbol-value`・
  `symbol-function`・`fdefinition`。展開を共有する `incf`・`decf`・`push`・`pop`。`eval-when`。VM の eval はトップレベルの
  `progn`・マクロの展開結果・`eval-when` の中のフォームを1つずつ評価する。ハッシュ表（`make-hash-table` の `:test` は `eq`・`eql`・`equal`、
  `gethash`・`remhash`・`clrhash`・`maphash`・`hash-table-count`・`hash-table-p`）、1次元の配列（`make-array`・`aref`・`svref`・`char`・
  `length`・`copy-seq` など）、`equal`・`rplaca`・`rplacd`・`nth`・`nthcdr`・`getf`・`get`・`symbol-plist`・`fdefinition`。
  試験：SBCL 2.6.7 の結果と比べる48通り（GC stress でも実行）、言語試験 `tests/language/eval/setf.lisp`（と gc-stress 版。ネイティブでも一致）。
  教材のブロックの一致は 179 から 223 に
- Phase 17：多値（`values`・`values-list`・`multiple-value-bind`・`multiple-value-list`・`multiple-value-prog1`・`multiple-value-call`・
  `nth-value`・`multiple-value-setq`。ValueMode により、関数の本体の最後の式から値の個数を伝える。VM の命令 `VALUES`・`SINGLE`・
  `MV_LIST`・`MV_PUSH_N`・`MV_RESTORE`。ネイティブバックエンドも対応）、REPL はすべての値を印字する。
  関数の `&optional`（既定値・供給の変数）・`&rest`・`&key`（`((:k v) …)`・`&allow-other-keys`・`:allow-other-keys t`）・`&aux`。
  `get-setf-expansion`・`define-setf-expander`。試験：SBCL 2.6.7 の結果と比べる50通り（GC stress でも実行）、言語試験
  `tests/language/eval/values.lisp`（と gc-stress 版。ネイティブでも一致）。教材のブロックの一致は 223 から 244 に
- Phase 18：`block`・`return-from`・`return`・`catch`・`throw`・`unwind-protect`（詳細設計 §6.4）。制御スタックと処理途中の脱出のスタック、
  同じ関数の中の return-from はジャンプ（横切る動的束縛・エントリを戻す）、それ以外は実行時の脱出。多値を運ぶ。
  unwind-protect の cleanup は、脱出・エラーのどちらで抜けるときも、入った時点の動的環境で実行する。cleanup の中の脱出
  （cleanup の外へ出るものだけが、進行中の脱出を取り消す）。`defun`・`flet`・`labels`・`defmacro` の本体の暗黙の block。
  VM の命令 `BLOCK_ENTER`・`CATCH_ENTER`・`UWP_ENTER`・`CONTROL_POP`・`UWP_SAVE`・`UWP_END`・`RETURN_FROM_NL`・`THROW`・`SLIDE`。
  ネイティブバックエンドも対応。試験：SBCL 2.6.7 の結果と比べる63通り（GC stress でも実行）、言語試験 `exits.lisp`
  （と gc-stress 版）・`exit-cases.lisp`・`error-cleanup.lisp`。非局所脱出の方式2（レジスタの保存と復元。インラインアセンブリ）の
  試作と比較の計測（`zig build bench -- nonlocal`）。方式1を続ける（詳細設計 §6.4）

### Changed
- VM の命令の分岐を、ラベル付き `switch` と `continue` に書き換えた（詳細設計 §7.1）。
  fib(25) が 5.08 ms から 2.97 ms に（約41%短縮）。実行ループと関係のない変更で速さが揺れる問題もなくなった

### Fixed
- Codex による Phase 07 のレビューの指摘10件
  - `readAll` が読んだ値を GC が走査しない Zig の配列に溜めていた（Lisp のリストで返し、読んでいる間は明示的なルートに登録する）
  - ベクタを作るときに要素を Zig の配列に写していた（ベクタを確保してからリストから直接埋める）
  - レジスタの退避をコンパイラ任せにしていた（callee-saved レジスタの値を直接読み、現在のスタックポインタから走査する）。
    レジスタにだけ参照がある場合の試験を追加
  - シンボルの表への登録とパッケージの作成で、確保に失敗すると表・一覧が壊れていた（確保を先に済ませる）。
    確保をすべての位置で失敗させる試験を追加
  - 大きいオブジェクトの大きさを u32 で持っていたため、4 GiB を超えると途中のポインタを認識できなかった
  - 大きいオブジェクトの再利用で、空きページの一覧に同じページが重なって増え続けた
  - `1||` が整数に、`:||` がエラーになっていた（空のエスケープ `||` もエスケープとして扱う。SBCL 2.6.7 と同じ）
  - 読み飛ばしの最中の `#n=` が、続くオブジェクトを読み飛ばしていなかった
  - GC のベンチマークが、値を持つ関数自身の `@frameAddress()` を走査の上端にしていた
- Codex による Phase 08 のレビューの指摘6件
  - Zig の関数どうしの呼び出し（apply から apply など）が、入れ子の深さの上限を通らなかった（プリミティブの呼び出しも Thread.call で数える）
  - VM の値スタックの使い終わった枠に残った値まで GC のルートにしていた（[0, sp) だけを走査する）
  - REPL で、フォームの途中で入力が終わっても何も報告せず、終了コード 0 で終わっていた（END-OF-FILE を報告し、終了コード 1）
  - `notinline` の宣言を無視して、高速経路の命令にしていた
  - 本体の先頭の説明文字列を何個でも読み飛ばしていた（1つまで。2つ目の文字列の後の declare はエラー）
  - 検証器が、到達しない命令のジャンプ先が命令の途中を指すものを見逃していた
- Codex・agy のレビュー（Phase 18）：暗黙の block がラムダリストの初期値の式まで囲んでいた（本体だけにした）、
  `defmacro` のコンパイル時の定義に暗黙の block がなかった、エラーの cleanup が入れ子になると処理途中の脱出の記録が
  溢れた（制御スタックとの和で上限を確かめ、`storage-condition` にした）、cleanup の中で受け止めたエラーが元のエラーの
  内容を上書きした（内容と呼び出しの履歴を退避する）、検証器が制御スタックの不正な操作を受け付けた（エントリの並びを
  位置ごとに検査する。実行時にも確かめる）。方式2の試作：浮動小数の制御の状態を保存していなかった、方式1の比較で
  タグの探索の結果を使っていなかった（直して再計測。分かれ目は約12段ではなく約25段）
- Linux・macOS で単体テストが panic した（GC の保守的走査のスタックの先頭を、Linux は /proc/self/maps、macOS は
  pthread_get_stackaddr_np から得る）。Linux の Debug ビルドで、ヒープのチャンクが 0 で埋まっていなかった
  （`Allocator.alignedAlloc` が未定義の印で埋めるので、`rawAlloc` で OS の領域をそのまま使う）。
  方式2の試作は、大域のアセンブリを出力しない Zig 自前のコード生成器では対象にしない
- GitHub Actions の試験で見つかった問題：GC の試験で、回収されるはずのオブジェクトが、スタックに残った古い値で保守的に
  残っていた（AVX2 のビルドの Linux。スタックを消す試験用の関数を2段にし、ゴミを作る関数を深いフレームで呼ぶ）。Windows の
  runner が CRLF で取り出して `zig fmt --check` が失敗した（`.gitattributes` で LF に固定。`.ps1`・`.iss` は CRLF）
