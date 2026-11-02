;; クロージャ（Phase 08）
(setq make-counter
      (lambda ()
        (let ((n 0))
          (lambda () (setq n (+ n 1))))))
(setq c1 (funcall make-counter))
(setq c2 (funcall make-counter))
(print (list (funcall c1) (funcall c1) (funcall c1) (funcall c2)))

(setq make-adder (lambda (n) (lambda (x) (+ x n))))
(print (funcall (funcall make-adder 10) 5))

;; 2 つの closure が同じ変数を共有する
(let ((balance 100))
  (setq deposit (lambda (x) (setq balance (+ balance x))))
  (setq get-balance (lambda () balance)))
(funcall deposit 50)
(print (funcall get-balance))

;; 再帰（大域変数に入れた関数）
(setq fact (lambda (n) (if (<= n 1) 1 (* n (funcall fact (- n 1))))))
(print (funcall fact 10))
(setq fib (lambda (n) (if (< n 2) n (+ (funcall fib (- n 1)) (funcall fib (- n 2))))))
(print (funcall fib 20))

;; レキシカルな範囲
(let ((x 'outer))
  (let ((f (lambda () x)))
    (let ((x 'inner))
      (print (list x (funcall f))))))
(print ((lambda (a b) (list b a)) 1 2))
(terpri)
