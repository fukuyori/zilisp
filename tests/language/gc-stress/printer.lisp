;; 印字の変数（Phase 24）：*print-base*・*print-radix*・*print-case*・*print-level*・*print-length*・*print-circle*・
;; *print-readably*・*print-array*・*print-gensym*・*read-default-float-format*、write・write-to-string のキーワード。
;; 期待値は SBCL 2.6.7 と同じ出力（アドレスを含むものは出力しない）
(setq *print-pretty* nil)
(print (list *print-array* *print-base* *print-case* *print-circle* *print-escape* *print-gensym* *print-length* *print-level*
             *print-lines* *print-miser-width* *print-radix* *print-readably* *print-right-margin*))
(print (list *read-base* *read-default-float-format* *read-eval* *read-suppress*))

;; 基数
(dolist (b '(2 3 4 7 8 10 16 32 36))
  (print (list b (write-to-string 255 :base b) (write-to-string 255 :base b :radix t) (write-to-string -1/3 :base b :radix t)
               (write-to-string -255 :base b) (write-to-string (expt 2 70) :base b) (write-to-string (- (expt 3 50)) :base b)
               (write-to-string (1- (expt 2 64)) :base b :radix t) (write-to-string (/ (expt 2 70) 7) :base b :radix t))))
(print (list (write-to-string 10 :radix t) (write-to-string 1/2 :radix t) (write-to-string 1.5 :radix t :base 16) (write-to-string '(1 2) :base 16 :radix t)))
;; *print-base* の数として読める名前は |…| で囲む
(print (list (write-to-string 'abc :base 16) (write-to-string '|10| :base 16) (write-to-string 'a :base 16) (write-to-string 'g :base 16)
             (write-to-string 'fa :base 16) (write-to-string 'fa) (write-to-string '|1E| :base 16)))
(let ((*print-base* 16)) (print (list 255 (* 2 (expt 2 64)) 'abc 'xyz)))

;; *print-case*
(print (list (write-to-string 'foo :case :downcase) (write-to-string 'foo-bar :case :capitalize) (write-to-string '|foo| :case :downcase)
             (write-to-string '|FooBar| :case :capitalize) (write-to-string 'foo1bar :case :capitalize) (write-to-string :key :case :downcase)
             (write-to-string 'cl-user::abc*def :case :capitalize) (write-to-string 'a.b :case :capitalize) (write-to-string '|a| :case :capitalize)
             (write-to-string 'x :case :capitalize :escape nil) (write-to-string 'foo-bar :case :downcase :escape nil)
             (write-to-string 'hello-world2x :case :capitalize :escape nil) (write-to-string 'abc123def :case :capitalize)
             (write-to-string '|ABC-def| :case :capitalize) (write-to-string 'a-1b :case :capitalize) (write-to-string nil :case :downcase)
             (write-to-string '|aBC| :escape nil :case :downcase) (write-to-string '|aBC| :escape nil :case :capitalize)))
(defpackage "P24-OTHER" (:use) (:export "EXT"))
(let ((*print-case* :downcase)) (print (list 'car :kw (intern "FOO" "P24-OTHER") (find-symbol "EXT" "P24-OTHER") "Str" #\A 1.5d0)))

;; *print-level*・*print-length*
(print (list (write-to-string '(1 (2 (3 (4)))) :level 2) (write-to-string '(1 2 3 4 5) :length 3) (write-to-string #(1 2 3 4) :length 2)
             (write-to-string '((a b) (c d) (e f)) :level 1 :length 2) (write-to-string '(1 2 3) :length 0) (write-to-string '(1 2 3) :level 0)
             (write-to-string '(1 . 2) :length 1) (write-to-string '(1 2 . 3) :length 2) (write-to-string #(#(1)) :level 1)
             (write-to-string "abc" :length 1) (write-to-string (make-array '(2 2) :initial-contents '((1 2) (3 4))) :length 1)
             (write-to-string (make-array '(2 2) :initial-contents '((1 2) (3 4))) :level 1)
             (write-to-string '(1 #(2 (3))) :level 2) (write-to-string #(1 #(2 #(3))) :level 2)
             (write-to-string (make-array '(2 2) :initial-contents '((1 2) (3 4))) :level 0) (write-to-string #() :level 0)
             (write-to-string '(1 . (2 . (3 . (4)))) :length 2)))
(let ((*print-length* 2) (*print-level* 2)) (print '(a (b (c d)) e f)) (prin1 (list 1 2 3)) (terpri))

;; *print-gensym*・*print-escape*
(print (list (write-to-string (make-symbol "G") :gensym nil) (write-to-string (make-symbol "G") :gensym t)
             (write-to-string (make-symbol "G") :gensym nil :readably t) (write-to-string (list (make-symbol "A") 'b) :gensym nil)
             (write-to-string :foo :gensym nil) (write-to-string "ab\"c" :escape nil) (prin1-to-string #\") (princ-to-string '(a "b" #\c))))

;; *read-default-float-format*
(print (list (write-to-string 1.5d0)
             (let ((*read-default-float-format* 'double-float))
               (list (write-to-string 1.5d0) (write-to-string 1.5) (write-to-string 1.0e10) (write-to-string 1d10)
                     (prin1-to-string 1.5) (princ-to-string 1.5) (prin1-to-string 1.5d-5)))
             (let ((*read-default-float-format* 'long-float)) (prin1-to-string 2.5d0))))

;; *print-circle*
(print (let ((x (list 1 2))) (write-to-string (list x x) :circle t)))
(print (let ((x (list 1 2))) (setf (cdr (last x)) x) (write-to-string x :circle t)))
(print (let ((g (make-symbol "G"))) (write-to-string (list g g) :circle t)))
(print (let ((s "ab")) (write-to-string (list s s) :circle t)))
(print (let ((s (vector 1))) (write-to-string (list s s) :circle t)))
(print (let ((x (list 1))) (write-to-string (list x (list x x) x) :circle t)))
(print (let ((x (list 1))) (write-to-string (list 'a x) :circle t)))
(print (let ((v (vector 1 2))) (setf (aref v 1) v) (write-to-string v :circle t)))
(print (let ((x (cons 1 2))) (write-to-string (cons x x) :circle t)))
(print (let ((x (list 1 2 3))) (write-to-string (list x (cdr x)) :circle t)))
(print (let ((x (list 1 2))) (write-to-string (list x x) :circle t :length 1)))
(print (let ((x (list 1 2))) (write-to-string (list x (list x)) :circle t :level 1)))
(print (write-to-string (list #'car #'car) :circle t))
(print (let ((p #p"/a")) (write-to-string (list p p) :circle t)))
(print (let ((b (expt 2 80))) (write-to-string (list b b) :circle t)))
(print (let ((d 1.5d0)) (write-to-string (list d d) :circle t)))
(print (let ((a (make-array 2 :fill-pointer 2 :initial-element 0))) (write-to-string (list a a) :circle t)))
(print (let ((x (list 1))) (write-to-string (vector x x) :circle t)))
(print (let ((x (list 1 2))) (write-to-string (list x x) :circle t :escape nil)))
(print (let ((x (list 'a))) (format nil "~S ~S" x x)))
(print (let ((*print-circle* t) (x (list 'a))) (format nil "~S ~S" (list x x) x)))
(let ((*print-circle* t) (x (list 1 2))) (setf (cdr (cdr x)) x) (print x) (prin1 (list x x)) (terpri))

;; *print-readably*
(print (list (write-to-string 1.5 :readably t) (write-to-string "a" :readably t) (write-to-string 'foo :readably t :escape nil)
             (write-to-string '(1 2 3) :readably t :length 1) (write-to-string "x" :readably t :escape nil)
             (write-to-string '|a b| :readably t :escape nil) (write-to-string (make-symbol "x") :readably t :escape nil)
             (write-to-string (make-array '(2 2) :initial-element 1) :readably t) (write-to-string (make-array 2 :initial-element 1 :fill-pointer 1) :readably t)
             (write-to-string (make-array 2 :element-type 'character :initial-element #\a :adjustable t) :readably t)
             (write-to-string (make-array 0) :readably t) (write-to-string (make-array '() :initial-element 5) :readably t)
             (write-to-string 1/2 :readably t) (write-to-string 12 :readably t :base 16) (write-to-string #p"/a/b" :readably t)))

;; *print-array*（アドレスを含まないものだけ）
(print (list (write-to-string "abc" :array nil) (write-to-string (make-array 2 :element-type 'character :initial-element #\x :fill-pointer 1) :array nil)))

;; write：:stream と印字の変数のキーワード
(write '(a b) :stream *standard-output* :case :downcase :length 1)
(terpri)
(print (with-output-to-string (s) (write 255 :stream s :base 16 :radix t) (write " " :stream s :escape nil) (write 'abc :stream s :case :capitalize)))
(print (list (write-to-string ''x) (write-to-string '(function x)) (prin1-to-string #(1 2))))
