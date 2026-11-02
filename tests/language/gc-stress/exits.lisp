;; block・return-from・catch・throw・unwind-protect（Phase 18）
;; 関数の本体は、関数の名前の block
(defun find-first (pred list)
  "list の中で pred を満たす最初の要素（なければ NIL）"
  (labels ((walk (l)
             (if (null l)
                 nil
                 (if (funcall pred (car l))
                     (return-from find-first (car l))
                     (walk (cdr l))))))
    (walk list)))
(print (find-first (lambda (x) (> x 2)) '(1 2 3 4)))
(print (find-first (lambda (x) (> x 9)) '(1 2 3 4)))

;; return は (return-from nil ...)
(print (block nil (return 'early) 'late))
(print (multiple-value-list (block done (return-from done (values 1 2 3)))))

;; catch と throw は動的なので、別の関数から投げられる
(defun check-positive (x)
  (if (< x 0) (throw 'negative x) x))
(defun sum-positive (list)
  (catch 'negative
    (labels ((sum (l acc)
               (if (null l) acc (sum (cdr l) (+ acc (check-positive (car l)))))))
      (sum list 0))))
(print (sum-positive '(1 2 3)))
(print (sum-positive '(1 -5 3)))

;; unwind-protect の cleanup は、どの抜け方でも実行する
(defvar *log* nil)
(defun note (x) (setq *log* (cons x *log*)))
(print (unwind-protect 'normal (note 'cleanup-1)))
(print (catch 'out (unwind-protect (throw 'out 'thrown) (note 'cleanup-2))))
(print (block b (unwind-protect (return-from b 'returned) (note 'cleanup-3))))
(print (catch 'out
         (unwind-protect
              (unwind-protect (throw 'out 'nested) (note 'inner))
           (note 'outer))))
(print *log*)

;; 脱出は、途中の動的束縛を戻す。cleanup は unwind-protect に入った時点の動的環境で実行する
(defvar *depth* 'top)
(defun show-depth () *depth*)
(print (catch 'c
         (let ((*depth* 'level-1))
           (unwind-protect
                (let ((*depth* 'level-2)) (throw 'c (show-depth)))
             (note (show-depth))))))
(print (list *depth* (car *log*)))

;; cleanup の中の脱出
(print (block b (unwind-protect (return-from b 'first) (return-from b 'second))))
(print (catch 'c (unwind-protect (throw 'c 1) (catch 'c2 (throw 'c2 2)) (note 'cleanup-ran))))
(print (car *log*))

;; 多値は cleanup を通しても保たれる
(print (multiple-value-list (unwind-protect (values 1 2) (values 3 4 5))))
(terpri)
