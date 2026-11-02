;; 反復（Phase 19）：tagbody・go、dolist・dotimes・do、loop、mapcar・reduce、format
;; tagbody と go（同じ関数の中のジャンプ）
(defun count-down (n)
  (let ((log nil))
    (tagbody
     top
       (when (> n 0)
         (push n log)
         (decf n)
         (go top)))
    (nreverse log)))
(print (count-down 5))

;; 別の関数から go で抜ける（実行時の脱出）。unwind-protect の cleanup も実行する
(defun call-thunk (f) (funcall f))
(let ((steps nil))
  (tagbody
     (unwind-protect
          (call-thunk (lambda () (go escaped)))
       (push 'cleanup steps))
     (push 'not-reached steps)
   escaped
     (push 'escaped steps))
  (print (reverse steps)))

;; dolist・dotimes・do
(dolist (fruit '(apple banana cherry))
  (format t "~A~%" fruit))
(dotimes (i 5)
  (format t "~A " i))
(terpri)
(print (let ((sum 0)) (dotimes (i 5 sum) (incf sum i))))
(print (dolist (x '(2 4 6 7 8)) (when (oddp x) (return x))))
(print (do ((i 0 (1+ i)) (acc nil (cons (* i i) acc))) ((= i 5) (nreverse acc))))

;; loop
(loop for i from 1 to 5 do (format t "~A " i))
(terpri)
(print (loop for x in '(3 8 2 7 5) sum x))
(print (loop for n in '(1 2 3 4 5) collect (* n 2)))
(print (loop for n from 1 to 10 when (evenp n) collect n))
(print (loop for x in '(5 3 9 1) maximize x))
(print (loop for (name . score) in '((alice . 90) (bob . 75) (carol . 82))
             when (> score 80) collect name))
(print (loop for x across #(1 2 3) for i from 0 collect (* x i)))
(print (loop with total = 0
             for x in '(1 2 3 4)
             do (incf total x)
             finally (return (list :total total))))
(print (loop for i from 1
             for sq = (* i i)
             while (< sq 50)
             collect sq))
(let ((h (make-hash-table)))
  (setf (gethash 'a h) 1)
  (print (loop for k being the hash-keys of h using (hash-value v) collect (list k v))))

;; mapcar・reduce・format
(print (mapcar #'+ '(1 2 3) '(10 20 30)))
(print (mapcar #'string-upcase '("apple" "banana")))
(print (reduce #'+ '(1 2 3 4) :initial-value 100))
(print (reduce #'max (mapcar #'abs '(-3 9 -12 4))))
(format t "~&~A has ~D items, ~S~%" "list" 3 "quoted")
(print (format nil "~A-~A" 'left 'right))
(terpri)
