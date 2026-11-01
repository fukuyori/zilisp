;;; Reader と印字の試験：アトム（期待値は tools/sbcl_read_print.lisp で SBCL 2.6.7 から作る）
;;; SBCL と処理系依存の違いがあるもの（ASCII 以外の大文字への変換、非正規化数の桁数、
;;; fixnum の範囲を超える整数、比）は入れない。

;; 整数
0 42 +42 -42 42. -0 1000000 2305843009213693951 -2305843009213693952
#b101 #B-101 #o17 #xff #x-1F #36rZZ

;; 浮動小数
1.5 .5 -.5 +.5 1e5 1E5 1.5e3 1.5d0 1.5D0 1.5s0 1.5f0 1.5l0
100000.0 1234567.0 9999999.0 10000000.0 1.5e10 0.001 0.0001 123.456 0.1 -0.0 0.0 1.0
1.0d7 1.0d-4 0.1d0 100000.0d0 1d100 3.4028235e38 1.0e-50 1.0d-400

;; シンボル
foo Foo fOO-bar \a \aB |aB|c a|b c|d |a\|b| 1e 1e+ 1.0.0 1/2/3 1+ + - +.
1a a1 1- -1- ^ a#b 日本語 \1 |42| |.| |..| |a.b| |a:b| |(| || 1ab |1A|

;; キーワード・パッケージ修飾・uninterned
:kw :Kw ::a cl:car cl::car cl:nil common-lisp:t #:foo #:|bar|

;; 文字
#\a #\A #\Space #\space #\Newline #\Tab #\Return #\Linefeed #\Page #\Backspace #\Rubout #\Nul
#\( #\) #\; #\" #\

;; 文字列
"abc" "a\"b" "a\nb" "\\" "日本" ""
