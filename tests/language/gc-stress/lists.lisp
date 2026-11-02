;;; Reader と印字の試験：リスト・ベクタ・quote・#+ / #-（期待値は SBCL 2.6.7 から作る）

(a b c) () ( ) (a . b) (a b . c) (a ; comment
 b) (a #| block |# b) ((a) (b (c))) (a .b) (1 . 2)
'a '(a b) ''a #'car #'(lambda (x) x)
#(1 2 3) #() #3(a b) #0() (#\a #\b) (#\))
(defun fact (n)
  (if (<= n 1)
      1
      (* n (fact (- n 1)))))

;; #+ / #-（SBCL と Zilisp の両方にある機能だけを使う）
#+common-lisp yes #-common-lisp no
#+nosuch (a b) after-skip
#+nosuch nopkg:x after-package
(x #+nosuch #+common-lisp a b c)
#+(or nosuch common-lisp) or-ok
#+(and common-lisp (not nosuch)) and-ok
