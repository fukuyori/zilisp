;; 動的束縛と special 宣言（Phase 14）
(defvar *level* 0 "入れ子の深さ")
(defparameter *name* 'top)
(print (list *level* *name*))
;; defvar は値があれば変えない。defparameter は毎回設定する
(defvar *level* 100)
(defparameter *name* 'changed)
(print (list *level* *name*))

;; 動的束縛は、呼んだ関数からも見える。抜けると元に戻る
(defun show-level () *level*)
(print (list (let ((*level* 1)) (show-level)) (show-level)))
(defun nested (n)
  (if (= n 0)
      (show-level)
      (let ((*level* (+ *level* 1)))
        (nested (- n 1)))))
(print (list (nested 5) *level*))

;; 束縛の中の setq は、その束縛だけを変える
(print (let ((*level* 10)) (setq *level* 20) (show-level)))
(print *level*)

;; クロージャは特殊変数を捕捉しない（呼んだ時点の値を見る）
(setq get-level (let ((*level* 99)) (lambda () *level*)))
(print (funcall get-level))

;; 引数として束縛する
(defun with-level (*level*) (show-level))
(print (list (with-level 7) *level*))

;; special 宣言（束縛の宣言と、自由な宣言）
(defun read-depth () (declare (special depth)) depth)
(print (let ((depth 3)) (declare (special depth)) (read-depth)))
(print (let ((v 'lexical)) (let ((v 'dynamic)) (declare (special v)) (list v (funcall (lambda () v))))))

;; progv
(print (progv '(*p* *q*) '(1) (list (symbol-value '*p*) (boundp '*q*))))
(print (list (boundp '*p*) (boundp '*q*)))

;; set・symbol-value
(set '*name* 'via-set)
(print (list *name* (symbol-value '*name*)))
(terpri)
