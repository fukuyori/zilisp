;; クロージャと flet・labels（Phase 11）
;; flet：局所関数。本体からは外側の関数が見える
(defun helper () 'global)
(print (flet ((helper () 'local) (call () (helper))) (list (helper) (call))))
;; labels：同じ labels の関数どうしが見える（再帰・相互再帰）
(print (labels ((helper () 'local) (call () (helper))) (list (helper) (call))))
(print (labels ((fact (n) (if (<= n 1) 1 (* n (fact (- n 1)))))) (fact 10)))
(print (labels ((ev (n) (if (= n 0) t (od (- n 1))))
                (od (n) (if (= n 0) nil (ev (- n 1)))))
         (list (ev 10) (od 7) (ev 7))))
(print (flet ((f () 1)) (flet ((f () (+ 1 (f)))) (f))))
;; 局所関数を値として渡す
(print (flet ((double (x) (* x 2))) (funcall #'double 21)))
(print (labels ((sum (l) (if (null l) 0 (+ (car l) (sum (cdr l)))))) (apply #'sum (list '(1 2 3 4)))))
;; 局所関数は外側の変数を捕捉する（代入も見える）
(print (let ((n 10)) (flet ((add (x) (+ x n))) (setq n 20) (add 1))))
;; closure の寿命：作った関数から戻った後も、捕捉した束縛は生きている
(defun make-account (balance)
  (list (lambda (x) (setq balance (+ balance x)))
        (lambda () balance)))
(setq acc1 (make-account 100))
(setq acc2 (make-account 500))
(funcall (car acc1) 50)
(funcall (car acc2) -100)
(print (list (funcall (car (cdr acc1))) (funcall (car (cdr acc2)))))
;; 再帰の各段で作った closure は、その段の束縛を捕捉する
(setq fs (labels ((collect (n) (if (= n 0) nil (cons (lambda () n) (collect (- n 1)))))) (collect 3)))
(print (list (funcall (car fs)) (funcall (car (cdr fs))) (funcall (car (cdr (cdr fs))))))
;; 末尾の位置の自己呼び出し（1 万段）
(print (labels ((loop-sum (n acc) (if (= n 0) acc (loop-sum (- n 1) (+ acc n))))) (loop-sum 10000 0)))
(terpri)
