;; 列・配列・ハッシュ表・文字列（Phase 21）：データ処理のサンプル
;; 売上の記録（日付 商品 数量 単価）を集計する
;; SBCL の print が長い行を折り返さないよう、*print-pretty* を偽にする（Zilisp は使わない）
(setq *print-pretty* nil)

(defparameter *sales*
  '(("2026-01-05" "apple" 3 120)
    ("2026-01-05" "banana" 5 80)
    ("2026-01-06" "Apple" 2 120)
    ("2026-01-07" "cherry" 10 30)
    ("2026-01-07" "banana" 1 80)
    ("2026-02-01" "apple" 4 110)
    ("2026-02-03" "durian" 1 900)))

(defun amount (row) (* (third row) (fourth row)))

;; 商品ごとの合計（大文字・小文字を区別しない：equalp のハッシュ表）
(let ((totals (make-hash-table :test 'equalp)))
  (dolist (row *sales*)
    (incf (gethash (second row) totals 0) (amount row)))
  (let ((pairs nil))
    (maphash (lambda (k v) (push (cons (string-downcase k) v) pairs)) totals)
    (print (sort pairs #'> :key #'cdr))))

;; 月ごとの件数と金額（文字列の切り出しと parse-integer）
(let ((months (make-array 13 :initial-element 0))
      (counts (make-array 13 :initial-element 0)))
  (dolist (row *sales*)
    (let ((m (parse-integer (first row) :start 5 :end 7)))
      (incf (aref months m) (amount row))
      (incf (aref counts m))))
  (print (loop for m from 1 to 12
               when (plusp (aref counts m))
                 collect (list m (aref counts m) (aref months m)))))

;; 条件に合う行を選び、並べ替え、重複を除く
(print (remove-if-not (lambda (row) (> (amount row) 300)) *sales*))
(print (mapcar #'second (stable-sort (copy-list *sales*) #'string< :key #'first)))
(print (remove-duplicates (mapcar (lambda (r) (string-capitalize (second r))) *sales*) :test #'string= :from-end t))
(print (count-if (lambda (r) (search "an" (second r))) *sales*))
(print (position "durian" *sales* :key #'second :test #'string=))
(print (find-if (lambda (r) (string-equal (second r) "APPLE")) *sales* :from-end t))
(print (reduce #'+ *sales* :key #'amount))
(print (every (lambda (r) (plusp (third r))) *sales*))
(print (some (lambda (r) (and (> (fourth r) 500) (second r))) *sales*))

;; CSV の1行を分ける（fill-pointer のある文字列に文字を積む）
(defun split (line sep)
  (let ((fields nil)
        (buf (make-array 0 :element-type 'character :fill-pointer 0 :adjustable t)))
    (loop for c across line
          do (if (char= c sep)
                 (progn (push (copy-seq buf) fields) (setf (fill-pointer buf) 0))
                 (vector-push-extend c buf)))
    (push (copy-seq buf) fields)
    (nreverse fields)))
(print (split "id, name ,score" #\,))
(print (mapcar (lambda (f) (string-trim " " f)) (split "id, name ,score" #\,)))
(print (map 'list #'parse-integer (split "10,20,30" #\,)))

;; 2次元の配列（九九の表の一部）と行優先の添字
(let ((table (make-array '(3 4))))
  (dotimes (i 3)
    (dotimes (j 4)
      (setf (aref table i j) (* (1+ i) (1+ j)))))
  (print table)
  (print (array-dimensions table))
  (print (loop for k below (array-total-size table) sum (row-major-aref table k))))

;; 文字の分類と変換
(let ((text "Hello, World! 123"))
  (print (list (count-if #'alpha-char-p text)
               (count-if #'digit-char-p text)
               (count-if #'upper-case-p text)
               (map 'string (lambda (c) (if (alpha-char-p c) (char-upcase c) #\_)) text)
               (reverse text)
               (substitute #\- #\Space text)
               (remove-if-not #'alphanumericp text))))

;; 集合と連想リスト
(let ((a '(1 2 3 4 5)) (b '(4 5 6 7)))
  (print (list (sort (copy-list (union a b)) #'<) (sort (copy-list (intersection a b)) #'<) (sort (copy-list (set-difference a b)) #'<)
               (subsetp '(4 5) b) (adjoin 3 a) (member 6 b))))
(let ((alist (pairlis '(a b c) '(1 2 3))))
  (print (list (cdr (assoc 'b alist)) (car (rassoc 3 alist)) (sublis alist '(a (b c))))))
(let ((stack nil))
  (dolist (x '(1 2 1 3 2)) (pushnew x stack))
  (print stack))
(terpri)
