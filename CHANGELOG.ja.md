# 変更履歴

[English](CHANGELOG.md)

## Unreleased

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

### Fixed
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
