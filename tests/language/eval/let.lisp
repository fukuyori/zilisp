;; レキシカル変数、let、let*（Phase 09）
;; 並列の束縛と順の束縛
(print (let ((x 1)) (let ((x (+ x 1)) (y x)) (list x y))))
(print (let ((x 1)) (let* ((x (+ x 1)) (y x)) (list x y))))
(print (let ((x 1) (y 2)) (let ((x y) (y x)) (list x y))))
(print (let* ((x 1) (y 2)) (let* ((x y) (y x)) (list x y))))
(print (let* ((x 1) (x (+ x 10))) x))
;; shadowing：内側の束縛は外側を隠し、抜けると元に戻る
(print (let ((x 1)) (list (let ((x 2)) (let ((x 3)) x)) x)))
(print (let ((x 1)) (let ((x 2)) (setq x 20)) x))
(print (let ((x 1)) (let ((y 2)) (setq x 10)) x))
(print (funcall (lambda (x) (let* ((y x) (x 100)) (list x y))) 5))
;; クロージャは、作ったときの束縛を捕捉する
(print (let* ((x 1) (f (lambda () x)) (x 2)) (list (funcall f) x)))
(print (let ((x 'outer)) (let ((f (lambda () x))) (let ((x 'inner)) (list x (funcall f))))))
(print (let* ((n 3) (f (lambda (k) (* n k)))) (setq n 4) (funcall f 10)))
;; 同じ番号の局所変数を使い回しても、別々の束縛として捕捉される
(setq fs nil)
(let ((x 1)) (setq fs (cons (lambda () x) fs)))
(let ((x 2)) (setq fs (cons (lambda () x) fs)))
(print (list (funcall (car fs)) (funcall (car (cdr fs)))))
;; 宣言
(print (let* ((x 'b) (y x)) (declare (ignore y)) x))
(terpri)
