;; format（Phase 24）：CLHS 22.3 の指示子。期待値は SBCL 2.6.7 と同じ出力
(setq *print-pretty* nil)
(defun f (control &rest args) (apply #'format nil control args))
(defmacro show (&rest forms) `(progn ,@(mapcar (lambda (x) `(print ,x)) forms)))

;; ~A ~S（欄の幅・埋め字・:）
(show (f "[~A] [~S] [~5A] [~5@A] [~5S] [~:A] [~:S] [~A]" "ab" "ab" "ab" "ab" "ab" nil nil nil)
      (f "[~10,3,2,'*A] [~10,3,2,'*@A] [~3,,,'-A] [~,,3A] [~1A]" "abc" "abc" "x" "y" "toolong")
      (f "~A ~S ~A ~S" #\a #\a 'sym :key)
      (f "[~40,,,'-A]" "title")
      (f "~20A|" "日本語"))
;; ~D ~B ~O ~X（幅・埋め字・桁区切り・符号）
(show (f "~D ~5D ~5,'0D ~:D ~@D ~:@D ~,,'.,4:D" 42 42 42 1234567 42 1234567 123456789)
      (f "~D ~D ~D ~D" -5 (expt 2 70) 1/2 1.5)
      (f "~B ~O ~X ~8,'0B ~:X" 10 64 255 5 (expt 2 40))
      (f "~2,'0D:~2,'0D" 5 7)
      (f "~4D|~5,2F|" 3 1.5)
      (f "~D" 'abc) (f "~5D|" "ab")
      (f "~@D ~@D" 0 -0))
(let ((*print-base* 16) (*print-radix* t)) (show (f "~D ~A" 255 255)))
;; ~R
(show (f "~R ~R ~R ~R" 0 7 13 45)
      (f "~R" 1234567)
      (f "~R" -101)
      (f "~R" (expt 10 21))
      (f "~:R ~:R ~:R ~:R ~:R ~:R ~:R ~:R" 0 1 2 3 11 12 20 21)
      (f "~:R ~:R ~:R" 100 101 1000000)
      (f "~@R ~@R ~@R ~@:R ~@:R" 1999 4 3999 4 1999)
      (f "~2R ~16R ~36,8,'0R ~3,,,' ,2:R" 10 255 35 80))
;; ~P ~C
(show (f "~D item~:P, ~D item~:P, ~D famil~:@P ~D famil~:@P" 1 2 1 3)
      (f "~P~P" 1 2)
      (f "~C ~:C ~:C ~:C ~@C ~@C ~:C" #\a #\Space #\Newline #\a #\a #\Space (code-char 1)))
;; ~F
(show (f "~F ~F ~F ~F ~F" 1.5 0.1 100.0 1e10 1.5d0)
      (f "~,1F ~,2F ~,3F ~,0F ~,1F" 3.14159 2.5 1.0005 2.5 0.05)
      (f "~5,2F|~8,3F|~1,1F|~3F|" 3.14159 -2.5 99.99 123.456)
      (f "~,2F ~,2F ~,2F ~,2F" 0.005 0.015 0.025 1.005)
      (f "~,1F ~,1F ~,1F ~,1F" 0.25 0.35 0.45 -0.05)
      (f "~@F ~,2@F ~,2,2F ~,,-1F" 1.5 1.5 1.5 123.0)
      (f "~F ~,2F ~F" 1/3 2/3 5)
      (f "~5,1,,'*F ~3,1,,'*F" 1234.5 1.5)
      (f "~10,3,,,'_F|" 1.5)
      (f "~F ~,3F" 1d-5 1d-5)
      (f "~,1F" 12345678.9)
      (f "~F" 'notnum) (f "~8F|" "str"))
;; ~E
(show (f "~E ~E ~E" 1.5 12345.678 1d-10)
      (f "~,2E ~,3,2E ~10,2E ~,2,,2E" 1234.5 0.000123 3.14159 1234.5)
      (f "~,2,,-1E ~,2,,0E" 1234.5 1234.5)
      (f "~@E ~,1E ~E" 1.0 -0.5 0.0)
      (f "~8,2,1,,'*E|~,2,,,,,'dE" 1d100 1.5))
;; ~G ~$
(show (f "~G ~G ~G ~G" 1.5 123456789.0 0.0001 1d20)
      (f "~,2G ~10,2G|" 3.14159 3.14159)
      (f "~$ ~$ ~$ ~$" 1.5 -2.346 1234.5 0.001)
      (f "~,3$ ~3,2$ ~10,2$| ~,,10:$| ~@$" 1.5 1.5 -1.5 -1.5 1.5)
      (f "~$ ~$" 3 1/3))
;; ~% ~& ~| ~~ ~ と改行
(show (f "a~%b~2%c") (f "~&a~&~&b") (f "x~3&y") (f "~~ ~3~") (f "~0&a")
      (f "a~
         b") (f "a~:
         b") (f "a~@
         b"))
;; ~T
(show (f "a~10Tb") (f "abc~2Td") (f "abcdefghijkl~10,4Tz") (f "a~3@Tb") (f "abc~4,8@Tz") (f "~%xy~5Tz")
      (f "~A~10T~A~20T~A" "name" "age" "city"))
;; ~* ~? ~:* ~@*
(show (f "~A ~* ~A" 1 2 3) (f "~A ~:* ~A" 1) (f "~A ~A ~@* ~A" 1 2) (f "~A ~2* ~A" 1 2 3 4) (f "~A ~1@* ~A" 1 2)
      (f "<~? >" "~A-~A" '(1 2)) (f "~@? ~A" "~A+~A" 1 2 3))
;; ~( ~)
(show (f "~(Hello WORLD~)" ) (f "~:(hello world foo-bar~)") (f "~@(hello WORLD foo~)") (f "~:@(hello world~)")
      (f "~(~A ~S~)" 'abc "Xyz") (f "~:(~A~)" "ONE two-THREE 4four"))
;; ~[ ~; ~]
(show (f "~[zero~;one~;two~]" 1) (f "~[zero~;one~:;other~]" 5) (f "~[a~;b~]" 9) (f "~1[a~;b~;c~]")
      (f "~:[false~;true~]" nil) (f "~:[false~;true~]" 3) (f "~@[x=~A~] ~A" 5 6) (f "~@[x=~A~]~A" nil 6)
      (f "~#[none~;one ~A~;two ~A ~A~:;many~]" 1 2) (f "~#[none~;one~]"))
;; ~{ ~}
(show (f "~{~A~^, ~}" '(1 2 3)) (f "~{~A~}" nil) (f "~:{(~A ~A)~}" '((1 2) (3 4))) (f "~@{~A~^-~}" 1 2 3)
      (f "~:@{~A=~A~^; ~}" '(a 1) '(b 2)) (f "~2{~A~}" '(1 2 3 4)) (f "~{~}" "~A." '(1 2))
      (f "~{x~:}" nil) (f "~{~A ~A~^|~}" '(1 2 3 4)) (f "~:{~A~:^, ~}" '((1) (2) (3)))
      (f "~{~{~A~^ ~}~^ / ~}" '((1 2) (3 4)))
      (f "~0{~A~}" '(1)) (f "~{~&~A~}" '(1 2)))
;; ~^（引数あり）
(show (f "~{~A~0^-~}" '(1 2)) (f "~{~A~1,1^-~}" '(1 2)) (f "~{~A~1,2,3^-~}" '(1 2)) (f "A~^B" ) (f "~A~^~A" 1))
;; ~< ~>（左右揃え）
(show (f "[~10<abc~>]") (f "[~10@<abc~>]") (f "[~10:<abc~>]") (f "[~10:@<abc~>]")
      (f "[~20<foo~;bar~;baz~>]") (f "[~20:<foo~;bar~>]") (f "[~20,,2<a~;b~>]") (f "[~15,4<a~;b~;c~>]")
      (f "[~10,,,'*<x~>]") (f "[~<~A~;~A~>]" 1 2) (f "[~9<~A~^~;~A~>]" 1)
      (f "~%;; ~{~<~%;; ~1,30:; ~A~>~^,~}.~%" '("first" "second" "third" "fourth" "fifth" "sixth" "seventh")))
;; ~/名前/
(defun my-fmt (stream arg colon at &rest params) (format stream "<~A ~A ~A ~S>" arg colon at params))
(defun cl-user::upper (stream arg &rest r) (declare (ignore r)) (write-string (string-upcase arg) stream))
(show (f "~/my-fmt/ ~:@/my-fmt/ ~1,'x,v/my-fmt/" 1 2 3 4) (f "x~/upper/y" "abc") (f "~/cl-user::upper/" "q"))
;; formatter と関数の制御
(show (f (formatter "~A+~A") 1 2) (funcall (formatter "~A ") *standard-output* 1 2)
      (f "~?" (formatter "<~A>") '(9)) (f "~{~}" (formatter "[~A]") '(1 2)))
(terpri)
;; 出力先
(format t "to t: ~A~%" 1)
(format *standard-output* "~&fresh~&")
(print (with-output-to-string (s) (format s "abc~10Td") (format s "~&x")))
(print (with-output-to-string (s) (write-string "12345" s) (format s "~10Ty")))
(print (let ((*print-case* :downcase)) (f "~A ~S ~:(~A~)" 'foo 'bar 'baz)))
(print (f "~W ~:W ~@W" '(1 2) "s" '(a b)))
