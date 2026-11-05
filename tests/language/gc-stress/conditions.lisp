;; Phase 25：condition・handler・restart（CLHS 9 章）。期待値は SBCL 2.6.7 と同じ出力
;; （アドレスを含む印字と、SBCL のトップレベルの restart は含めない）

;;; handler-case・handler-bind
(print (handler-case (/ 10 0) (division-by-zero () :div)))
(print (handler-case (car 5) (type-error (c) (list (type-error-datum c) (type-error-expected-type c)))))
(print (handler-case (symbol-value 'no-such-var-xyz) (unbound-variable (c) (cell-error-name c))))
(print (handler-case (no-such-fn-xyz 1) (undefined-function (c) (cell-error-name c))))
(print (handler-case (floor 1 0) (arithmetic-error (c) (list (arithmetic-error-operation c) (arithmetic-error-operands c)))))
(print (handler-case (parse-integer "abc") (parse-error () :parse)))
(print (handler-case (error "plain") (simple-error (c) (list (simple-condition-format-control c) (simple-condition-format-arguments c)))))
(print (handler-case (/ 10 0) (division-by-zero () :first) (arithmetic-error () :second) (error () :third)))
(print (handler-case (error 'type-error :datum 1 :expected-type 'string) ((or division-by-zero type-error) () :or-type)))
(print (handler-case (handler-bind ((error (lambda (c) (format t "inner saw ~A~%" c))))
                       (error "boom ~A" 1))
         (error (c) (list :outer (princ-to-string c)))))
(print (handler-case (handler-case (error 'type-error :datum 1 :expected-type 'string)
                       (division-by-zero () :inner))
         (type-error () :outer)))
;; handler の中のエラーは外側の handler が受け止める
(print (handler-case (handler-bind ((error (lambda (c) (declare (ignore c)) (error "second"))))
                       (error "first"))
         (error (c) (princ-to-string c))))
;; :no-error
(print (handler-case (values 1 2) (error () :err) (:no-error (a b) (list :ok a b))))
(print (handler-case (error "e") (error () :err) (:no-error (a b) (list :ok a b))))
;; ignore-errors
(print (multiple-value-list (ignore-errors (values 1 2 3))))
(print (let ((r (multiple-value-list (ignore-errors (/ 1 0))))) (list (first r) (typep (second r) 'division-by-zero))))
;; unwind-protect の cleanup は handler-case の本体より先
(handler-case (unwind-protect (error "u") (format t "~&cleanup~%"))
  (error (c) (format t "handled ~A~%" c)))
;; 動的束縛：handler-bind の handler は通知した場所で、handler-case の本体は抜けた後で動く
(defvar *dyn* :outer)
(print (list (handler-case (let ((*dyn* :inner)) (error "d")) (error () *dyn*)) *dyn*))
(print (handler-case (let ((*dyn* :at-signal))
                       (handler-bind ((error (lambda (c) (declare (ignore c)) (format t "~&dyn=~A~%" *dyn*))))
                         (error "e")))
         (error () :ok)))
;; 投げ直し
(print (handler-case (handler-case (/ 1 0) (error (e) (error e)))
         (division-by-zero (c) (list :again (arithmetic-error-operands c)))))
;; signal は handler がなければ NIL
(print (signal "nobody"))
(print (handler-case (signal "sig ~A" 1) (simple-condition (c) (princ-to-string c))))

;;; define-condition
(define-condition base-err (error) ((code :initarg :code :initform 0 :accessor err-code)) (:report "Base error"))
(define-condition sub-err (base-err) ((extra :initarg :extra :reader err-extra)) (:default-initargs :extra :dflt))
(define-condition out-of-range (error)
  ((value :initarg :value :reader out-of-range-value)
   (min :initarg :min :reader out-of-range-min)
   (max :initarg :max :reader out-of-range-max))
  (:report (lambda (c stream)
             (format stream "~A is out of range [~A, ~A]"
                     (out-of-range-value c) (out-of-range-min c) (out-of-range-max c)))))
(let ((c (make-condition 'sub-err :code 7)))
  (print (list (err-code c) (err-extra c) (typep c 'base-err) (typep c 'error) (typep c 'warning) (princ-to-string c)))
  (setf (err-code c) 9)
  (print (err-code c)))
(print (handler-case (error 'sub-err) (base-err (c) (list (err-code c) (err-extra c)))))
(print (handler-case (error 'out-of-range :value 150 :min 0 :max 100) (out-of-range (c) (format nil "~A" c))))
(print (handler-case (signal 'sub-err) (sub-err () :caught)))
(print (handler-case (make-condition 'no-such-condition) (error (c) (princ-to-string c))))

;;; restart
(print (restart-case (invoke-restart 'my-restart 1 2) (my-restart (a b) (+ a b))))
(print (restart-case (remove-if-not (lambda (n) (member n '(r1 r2 r3))) (mapcar #'restart-name (compute-restarts)))
         (r1 () 1)
         (r2 () :test (lambda (c) (declare (ignore c)) nil) 2)
         (r3 () 3)))
(print (multiple-value-list (with-simple-restart (skip "Skip it") (invoke-restart 'skip))))
(print (multiple-value-list (with-simple-restart (skip "Skip it") 10)))
(print (restart-case (princ-to-string (find-restart 'foo)) (foo () :report "Foo report" 1)))
(print (restart-case (princ-to-string (find-restart 'bar)) (bar () 1)))
(print (handler-case (invoke-restart 'nonexistent) (control-error (c) (princ-to-string c))))
(print (restart-case (abort) (abort () :aborted)))
;; restart がなければ NIL（continue は SBCL のトップレベルの restart があるので、ここでは試さない）
(print (list (use-value 1) (store-value 2)))
(print (restart-case (use-value 5) (use-value (v) (list :used v))))
;; Zig で見つけたエラーから restart を呼ぶ（教材 Level 13 の safe-parse-integer）
(defun parse-or (s)
  (restart-case (parse-integer s)
    (use-zero () 0)))
(print (handler-bind ((error (lambda (c) (declare (ignore c)) (invoke-restart 'use-zero)))) (parse-or "abc")))
;; condition に関連付けた restart
(print (let ((c1 (make-condition 'simple-error :format-control "c1"))
             (c2 (make-condition 'simple-error :format-control "c2")))
         ;; error のフォームの restart-case は、通知する condition に restart を関連付ける（ほかの condition からは見えない）
         (handler-bind ((error (lambda (c)
                                 (let ((r1 (find-restart 'assoc-r c)) (r2 (find-restart 'assoc-r c2)))
                                   (invoke-restart r1 (and r1 t) r2)))))
           (restart-case (error c1)
             (assoc-r (seen other) :report "R" (list :assoc seen other))))))
(print (handler-bind ((error (lambda (c) (invoke-restart (find-restart 'r1 c)))))
         (restart-case (error "x") (r1 () :r1-via-condition))))
;; cerror と continue、warn と muffle-warning
(print (handler-bind ((error (lambda (c) (continue c)))) (list (cerror "Go on" "cerr ~A" 5) :after)))
(print (handler-bind ((warning #'muffle-warning)) (warn "silent") :done))
(print (handler-bind ((warning (lambda (c) (format t "~&warned: ~A~%" c) (muffle-warning c)))) (warn "loud ~A" 2) :done))

;;; 型の検査と分岐
(print (list (typecase 1 (string :s) (integer :i)) (typecase 'a (string :s) (t :other)) (typecase 1.5 (string :s))))
(print (handler-case (etypecase 3 (string 1) (symbol 2)) (type-error (c) (princ-to-string c))))
(print (handler-case (ecase 3 (1 1) ((2 4) 2)) (type-error (c) (princ-to-string c))))
(print (handler-case (let ((x 3)) (check-type x string) x) (type-error (c) (princ-to-string c))))
(print (handler-case (let ((x 3)) (assert (= x 2)) x) (error (c) (princ-to-string c))))
(print (handler-case (let ((x 3)) (assert (= x 2) (x) "x was ~A" x)) (error (c) (princ-to-string c))))
(print (let ((x 3))
         (handler-bind ((type-error (lambda (c) (store-value "fixed" c))))
           (check-type x string))
         x))
(print (let ((x 7))
         (handler-bind ((type-error (lambda (c) (store-value 2 c))))
           (ccase x (1 :one) (2 :two)))))
(print (list (typep 1 'integer) (typep 1 '(integer 0 5)) (typep 6 '(integer 0 5)) (typep "a" 'string)
             (typep 'a '(or string symbol)) (typep 5 '(mod 5)) (typep nil 'list) (typep (make-condition 'error) 'condition)))

;;; Codex のレビュー P25 で直したもの
;; #1 restart-case の中の cerror も引数を書いた順に評価する
(print (let ((log nil))
         (handler-bind ((error (lambda (c) (declare (ignore c)) (continue))))
           (restart-case (cerror (progn (push :control log) "Continue") (progn (push :datum log) "Error"))
             (other () nil)))
         (reverse log)))
;; #2 マクロを展開すると signal になるフォームも、restart をその condition に関連付ける
(defmacro p25-signal-x () '(signal "x"))
(print (let ((r :none))
         (handler-bind ((condition (lambda (c) (declare (ignore c))
                                     (setq r (not (null (find-restart 'r (make-condition 'simple-condition))))))))
           (restart-case (p25-signal-x) (r () :r)))
         r))
;; #3 abort・muffle-warning の restart が戻ってきたら control-error
(print (handler-case (restart-bind ((abort (lambda () :returned))) (abort)) (control-error (c) (princ-to-string c))))
(print (handler-case (restart-bind ((muffle-warning (lambda () :returned))) (muffle-warning)) (control-error () :control-error)))
;; #4 型指定子の大きさは配列の次元（fill-pointer ではない）
(print (let ((v (make-array 5 :fill-pointer 2))) (list (typep v '(vector t 5)) (typep v '(vector t 2)))))
(print (let ((s (make-array 5 :element-type 'character :fill-pointer 2 :initial-element #\a)))
         (list (typep s '(string 5)) (typep s '(string 2)) (typep s '(vector character 5)))))
;; #5 reader-error・end-of-file の handler から読むと、エラーの位置から読む
(print (let ((s (make-string-input-stream "(1 . 2 3) 42")))
         (catch 'done
           (handler-bind ((reader-error (lambda (c) (declare (ignore c)) (throw 'done (read-char s)))))
             (read s)))))
(print (let ((s (make-string-input-stream "(1 2"))) (list (handler-case (read s) (end-of-file () :eof)) (read-char s nil :end))))
;; #6 reader-error の stream-error-stream は読んでいたストリーム
(print (let ((s (make-string-input-stream "#<bad>"))) (handler-case (read s) (reader-error (c) (eq s (stream-error-stream c))))))

;;; Codex のレビュー P25 2回目で直したもの（*debugger-hook* は sbcl --script が呼ばないので、単体テスト）
;; #1 #A の中身の誤りでも、handler から読むとエラーの位置から読む
(print (let ((s (make-string-input-stream "#2A((1) (2 3)) 42")))
         (catch 'done (handler-bind ((error (lambda (c) (declare (ignore c)) (throw 'done (read-char s nil :end))))) (read s)))))
(print (let ((s (make-string-input-stream "#2A((1) (2 . 3)) 42")))
         (catch 'done (handler-bind ((error (lambda (c) (declare (ignore c)) (throw 'done (read-char s nil :end))))) (read s)))))
;; #2 read-from-string の reader-error・end-of-file もストリームを持つ
(print (list (handler-case (read-from-string "#<bad>") (reader-error (c) (streamp (stream-error-stream c))))
             (handler-case (read-from-string "(") (end-of-file (c) (streamp (stream-error-stream c))))
             (handler-case (read-from-string "") (end-of-file (c) (streamp (stream-error-stream c))))
             (multiple-value-list (read-from-string "" nil :none))))
;; #3 ccase・ctypecase は場所の部分式を1回だけ評価する。check-type は確かめるたびに読む（SBCL と同じ）
(print (let ((v (vector 9 8)) (i -1) (n 0))
         (list (catch 'stop
                 (handler-bind ((type-error (lambda (c) (if (= (incf n) 1) (store-value 1 c) (throw 'stop :second-error)))))
                   (ccase (aref v (incf i)) (1 :ok))))
               v i)))
(print (let ((v (vector "a" 8)) (i -1) (n 0))
         (list (catch 'stop
                 (handler-bind ((type-error (lambda (c) (if (= (incf n) 1) (store-value "s" c) (throw 'stop :second-error)))))
                   (ctypecase (aref v (incf i)) (symbol :sym) (string :str))))
               v i)))
(print (let ((v (vector 9 8)) (i -1) (n 0))
         (list (catch 'stop
                 (handler-bind ((type-error (lambda (c) (if (= (incf n) 1) (store-value "s" c) (throw 'stop :second)))))
                   (check-type (aref v (incf i)) string) :ok))
               v i)))

;;; 計算の途中で VM の命令が見つけたエラー（未束縛の変数）：handler が同じ関数の catch に戻っても、途中の値は壊れない
(defvar *p25-unbound*)
(defun p25-mid (x y) (list x y x y (catch 'p25-tag (+ x *p25-unbound*))))
(print (handler-bind ((error (lambda (c) (declare (ignore c)) (throw 'p25-tag :h)))) (list (p25-mid 5 7) (p25-mid 6 8))))
(defun p25-mid2 (x) (list x (cons x x) (handler-case (+ x *p25-unbound*) (error () (list :h x)))))
(print (list (p25-mid2 5) (p25-mid2 6)))

;;; report の文面（SBCL 2.6.7 と同じ）
(print (princ-to-string (make-condition 'error)))
(print (princ-to-string (make-condition 'simple-error :format-control "a ~A" :format-arguments '(1))))
(print (princ-to-string (make-condition 'unbound-variable :name 'foo)))
(print (princ-to-string (make-condition 'undefined-function :name 'foo)))
(print (princ-to-string (make-condition 'type-error :datum 1 :expected-type 'string)))
(print (prin1-to-string (make-condition 'type-error :datum 1 :expected-type 'string)))
(print (princ-to-string (make-condition 'division-by-zero :operation '/ :operands '(1 0))))
(print (princ-to-string (make-condition 'end-of-file :stream nil)))
(print (princ-to-string (make-condition 'file-error :pathname "x.txt")))
(print (handler-case (/ 10 0) (division-by-zero (c) (format nil "~A" c))))
(format t "~&[~A]~%" (handler-case (error 'type-error :datum "a" :expected-type 'number) (error (c) c)))
