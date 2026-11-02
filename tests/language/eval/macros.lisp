;; defmacro・backquote・展開器（Phase 15）
;; backquote
(print `(a b ,(+ 1 2)))
(print `(a ,@(list 1 2) c))
(print `(a . ,(+ 1 1)))
(print `#(1 ,(+ 1 1)))
(print (let ((x '(b c))) `(a ,@x d)))

;; defmacro と、マクロを使うマクロ
(defmacro my-inc (x) `(+ ,x 1))
(defmacro my-twice-inc (x) `(my-inc (my-inc ,x)))
(print (list (my-inc 5) (my-twice-inc 5)))
(print (macroexpand-1 '(my-twice-inc 5)))
(print (macroexpand '(my-twice-inc 5)))

;; &body と &optional・&key・入れ子の分解
(defmacro my-when (test &body body) `(if ,test (progn ,@body)))
(print (list (my-when t 1 2) (my-when nil 1)))
(defmacro with-defaults (a &optional (b 10) &key (c 'none)) `(list ,a ,b ',c))
(print (list (with-defaults 1) (with-defaults 1 2 :c yes)))
(defmacro pair-sum ((a b) c) `(+ ,a ,b ,c))
(print (pair-sum (1 2) 3))

;; gensym で変数の衝突を避ける
(defmacro swap (a b)
  (let ((tmp (gensym)))
    `(let ((,tmp ,a)) (setq ,a ,b) (setq ,b ,tmp))))
(let ((x 1) (tmp 2))
  (swap x tmp)
  (print (list x tmp)))

;; 局所関数はマクロより優先する
(print (flet ((my-inc (x) (* x 100))) (my-inc 2)))

;; destructuring-bind
(print (destructuring-bind (a (b c) &rest d) '(1 (2 3) 4 5) (list a b c d)))

;; 標準マクロ
(print (list (when t 'yes) (unless t 'no)))
(defun classify (n)
  (cond ((< n 0) 'negative)
        ((= n 0) 'zero)
        (t 'positive)))
(print (list (classify -5) (classify 0) (classify 7)))
(print (list (and 1 2 3) (and 1 nil 3) (or nil 2) (or)))
(defun day-type (d)
  (case d
    ((sat sun) 'weekend)
    ((mon tue wed thu fri) 'weekday)
    (otherwise 'unknown)))
(print (list (day-type 'sun) (day-type 'wed) (day-type 'xyz)))
(print (list (prog1 1 2 3) (prog2 1 2 3)))
(let ((n 0) (stack nil))
  (incf n)
  (incf n 10)
  (decf n 2)
  (push 'a stack)
  (push 'b stack)
  (print (list n (pop stack) stack)))
(terpri)
