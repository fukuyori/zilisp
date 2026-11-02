;; 関数、lambda、defun、funcall（Phase 10）
(print (defun square (x) (* x x)))
(print (square 7))

;; 再帰
(defun fact (n)
  "n の階乗"
  (if (<= n 1) 1 (* n (fact (- n 1)))))
(print (fact 10))
(defun fib (n) (if (< n 2) n (+ (fib (- n 1)) (fib (- n 2)))))
(print (fib 20))
(defun sum-to (n) (if (= n 0) 0 (+ n (sum-to (- n 1)))))
(print (sum-to 10000))

;; 相互再帰（後で定義する関数を呼んでよい）
(defun my-evenp (n) (if (= n 0) t (my-oddp (- n 1))))
(defun my-oddp (n) (if (= n 0) nil (my-evenp (- n 1))))
(print (list (my-evenp 10) (my-oddp 7) (my-evenp 7)))

;; 関数を値として扱う
(print (funcall #'square 5))
(print (funcall 'square 6))
(print (apply #'+ 1 2 '(3 4)))
(defun compose (f g) (lambda (x) (funcall f (funcall g x))))
(print (funcall (compose #'1+ #'square) 3))
(defun twice (f x) (funcall f (funcall f x)))
(print (twice (lambda (y) (* y 3)) 2))
(print #'square)

;; 再定義はすぐに反映される
(defun greeting () 'hello)
(defun greet () (greeting))
(print (greet))
(defun greeting () 'goodbye)
(print (greet))

;; let の中の defun（変数を閉じ込める）
(let ((count 0))
  (defun next-count () (setq count (+ count 1))))
(next-count)
(print (next-count))
(terpri)
