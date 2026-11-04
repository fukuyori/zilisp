;; 印字と読み取りの往復（Phase 24 の受入）：*print-readably* で印字したものを読み戻すと equalp になるか、
;; *print-pretty* が偽と真の両方で確かめる。#nA と #A(次元 要素の型 . 中身) の読み取りも。期待値は SBCL 2.6.7 と同じ出力

;; #nA の読み取り
(print (read-from-string "#2A((1 2 3) (4 5 6))"))
(print (array-dimensions (read-from-string "#2A((1 2 3) (4 5 6))")))
(print (read-from-string "#1A(a b)"))
(print (read-from-string "#0A x"))
(print (array-dimensions (read-from-string "#3A(() ())")))
(print (array-dimensions (read-from-string "#2A(\"ab\" \"cd\")")))
(print (array-dimensions (read-from-string "#2A(#(1 2) #(3 4) #(5 6))")))
(print (read-from-string "#A((2 2) character \"ab\" \"cd\")"))
(print (array-element-type (read-from-string "#A((2 2) character \"ab\" \"cd\")")))
(print (read-from-string "#A(3 t 1 2 3)"))
(print (read-from-string "#+nosuch #2A((1)) 5"))
(print '#2A((x y) (z w)))
(print (aref #2A((1 2) (3 4)) 1 0))
(print (let ((*print-readably* t)) (prin1-to-string (make-array '(2 3) :initial-element 7))))
(let ((*print-circle* t)) (print (read-from-string "#1=#2A((1 #1#) (2 3))")))
(print (read-from-string "#2A((#1=(a) #1#) (b c))"))
(let ((x (read-from-string "#2A((#1=(a) #1#) (b c))"))) (print (eq (aref x 0 0) (aref x 0 1))))

;; #nA で読み戻せない配列は、*print-readably* なら #A(次元 要素の型 . 中身) の形で書く
(dolist (pretty '(nil t))
  (let ((*print-pretty* pretty) (*print-readably* t))
    (print (list (make-array '(0 3)) (make-array '(3 0)) (make-array '(2 0 4)) (make-array '(0 0)) (make-array '()) (make-array '(2 2) :initial-element 'x)))))
(print (make-array '(0 3)))

;; 往復
(defvar *objects*
  (list 0 1 -5 most-positive-fixnum (expt 2 100) (- (expt 3 70)) 1/3 -22/7 1.5 -0.0 2.5d0 1d100 1.0e-10
        #\a #\Space #\Newline #\( "" "str\"q\\x" "日本語"
        'sym :key '|Mixed Case| '|a b| '|1| 'cl-user::foo '\#x nil t
        '(a . b) '(1 (2 (3 (4)))) (make-list 50 :initial-element 'abcdef)
        #() #(1 2 3) (vector 'a "b" #\c 1.5) (make-array '(2 3) :initial-element 7)
        (make-array '(2 2 2) :initial-contents '(((1 2) (3 4)) ((5 6) (7 8)))) (make-array '(0 3)) (make-array '(3 0)) (make-array '(2 0 4)) (make-array '())
        (make-array '(2 3) :element-type 'character :initial-element #\z) (make-array '() :element-type 'character :initial-element #\b)
        '(defun f (x) (let ((y (* x x))) (if (> y 10) (list 'quote y) `(a ,y ,@(list y)))))
        ''(quote x) '#'car '(function) '(quote a b)
        (loop for i below 40 collect (list i (* i i) (format nil "s~d" i)))
        #p"/tmp/file.txt"))
(dolist (pretty '(nil t))
  (dolist (margin '(nil 20))
    (let ((*print-pretty* pretty) (*print-readably* t) (*print-right-margin* margin) (ok 0) (ng nil))
      (dolist (o *objects*)
        (if (equalp o (read-from-string (prin1-to-string o))) (incf ok) (push o ng)))
      (let ((*print-readably* nil)) (format t "~&pretty ~a margin ~a: ok ~d ng ~s~%" pretty margin ok ng)))))
;; 循環するものは *print-circle* で
(let ((*print-circle* t) (*print-readably* t))
  (dolist (pretty '(nil t))
    (let* ((*print-pretty* pretty)
           (l (list 1 2 3)) (v (vector 1 2)) (shared (list 'x)))
      (setf (cdr (last l)) l (aref v 1) v)
      (let ((l2 (read-from-string (prin1-to-string l)))
            (v2 (read-from-string (prin1-to-string v)))
            (s2 (read-from-string (prin1-to-string (list shared shared)))))
        (print (list (eq (cdddr l2) l2) (eq (aref v2 1) v2) (eq (first s2) (second s2))))))))
(terpri)

;; #A の形のシンボルは、CL を use しないパッケージでも読み戻せるように書く（Codex P24 の指摘）
(let ((p (make-package "P24-EMPTY" :use nil)))
  (print (array-dimensions (let ((*package* p)) (read-from-string (write-to-string (make-array nil :element-type 'character :initial-element #\x) :readably t :pretty nil)))))
  (print (array-dimensions (let ((*package* p)) (read-from-string (write-to-string (make-array '(0 2)) :readably t :pretty t)))))
  (print (array-dimensions (let ((*package* p)) (read-from-string (write-to-string (make-array '(0 2)) :readably t :pretty nil))))))
;; 定数の配列（ネイティブのプログラムでも次元と要素の型を保つ）
(print (array-dimensions '#A((0 3) t)))
(print (list (array-dimensions '#A((2 2) character "ab" "cd")) (array-element-type '#A((2 2) character "ab" "cd"))))
(print (aref '#A((2 2) character "ab" "cd") 1 0))
(print (array-dimensions '#3A(((1 2) (3 4)) ((5 6) (7 8)))))
(terpri)
