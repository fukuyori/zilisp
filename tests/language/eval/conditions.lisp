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

;;; Codex のレビュー P25 3回目で直したもの
;; #1 ccase・ctypecase は場所を1回だけ読み、store-value の後は格納のフォームの値で分岐をやり直す
(defvar *p25-reads* 0)
(defvar *p25-cell* 9)
(defun p25-probe () (incf *p25-reads*) *p25-cell*)
(defun p25-put-probe (v) (setq *p25-cell* v))
(defsetf p25-probe p25-put-probe)
(print (handler-bind ((type-error (lambda (c) (store-value 1 c))))
         (list (ccase (p25-probe) (1 :ok)) *p25-reads* *p25-cell*)))
(setq *p25-reads* 0 *p25-cell* 9)
(print (handler-bind ((type-error (lambda (c) (store-value "s" c))))
         (list (ctypecase (p25-probe) (string :str)) *p25-reads* *p25-cell*)))
;; #2 格納の変数が複数ある場所（足りない値は NIL）
(defvar *p25-a* 9)
(defvar *p25-b* 8)
(define-setf-expander p25-pair ()
  (let ((x (gensym)) (y (gensym)))
    (values nil nil (list x y) `(progn (setq *p25-a* ,x *p25-b* ,y) (values ,x ,y)) `(values *p25-a* *p25-b*))))
(print (handler-case (handler-bind ((type-error (lambda (c) (store-value 1 c))))
                       (list (ccase (p25-pair) (1 :ok)) *p25-a* *p25-b*))
         (unbound-variable () :unbound)))

;;; Codex のレビュー P25 4回目で直したもの（未実装の機能は error の下位でない zilisp:unimplemented。ほかのエラーは SBCL と同じ型）
;; #1 マクロ・特殊演算子を funcall したのは undefined-function
(print (list (handler-case (funcall 'if t 1 2) (undefined-function () :undefined) (serious-condition () :serious))
             (handler-case (funcall 'with-slots) (undefined-function () :undefined) (serious-condition () :serious))))
;; #2 型でない CL のシンボル、#3 pprint-logical-block の指定の誤り、LOOP の知らない句は error
(print (list (handler-case (typep 1 'car) (error () :error) (serious-condition () :serious))
             (handler-case (eval '(pprint-logical-block (s nil :prefix "a" :per-line-prefix "b") nil))
               (error () :error) (serious-condition () :serious))
             (handler-case (macroexpand '(loop for x in nil frob 3)) (error () :error) (serious-condition () :serious))))
;; #4 etypecase・ctypecase の otherwise は型指定子（typecase の otherwise はどれにも当たらない節）
(print (list (handler-case (eval '(let ((x 1)) (ctypecase x (otherwise :ok)))) (error () :error))
             (handler-case (eval '(let ((x 1)) (etypecase x (otherwise :ok)))) (error () :error))
             (typecase 5 (string :s) (otherwise :other))))
;; #5 (setf (values …))、ccase の場所の (values a b)
(print (let ((a 0) (v (vector 1 2))) (list (multiple-value-list (setf (values a (aref v 1)) (values 7 8 9))) a v)))
(print (let ((a 0) (b 0)) (setf (values a b) 5) (list a b)))
(print (let ((a 9) (b 8))
         (list (handler-bind ((type-error (lambda (c) (store-value 1 c)))) (ccase (values a b) (1 :ok))) a b)))

;;; Codex のレビューの 5 回目の指摘（どれも SBCL 2.6.7 と同じ結果）
;; #1・#2 格納の変数が 0 個・複数の場所（setf・incf・decf・push・pop）
(print (let ((a 0)) (list (multiple-value-list (setf (values) (incf a))) a)))
(print (let ((a 1) (b 2)) (list (multiple-value-list (incf (values a b))) a b)))
(print (let ((a 5) (b 2)) (list (multiple-value-list (decf (values a b) 2)) a b)))
(print (let ((a (list 1 2)) (b 9)) (list (multiple-value-list (pop (values a b))) a b)))
(print (let ((a (list 1)) (b 9)) (list (multiple-value-list (push 0 (values a b))) a b)))
;; #3〜#5 型指定子の形の誤りはエラー、正しい形の base-string・complex は偽
(print (mapcar (lambda (spec) (handler-case (typep 1 spec) (error () :error) (serious-condition () :serious)))
               '((base-string 3) (simple-base-string 3) (complex single-float) (base-string -1) (complex car)
                 (random-state 3) (bit-vector 3 4) (mod 0) (integer 1 2 3) (or fixnum car))))
(print (list (handler-case (typep #(1) '(vector car)) (error () :error) (serious-condition () :serious))
             (typep "ab" '(vector character 2))))
;; #6 先頭でない named と、知らない being の種類は形の誤り
(print (list (handler-case (macroexpand '(loop repeat 1 named foo do (print 1))) (error () :error))
             (handler-case (macroexpand '(loop for x being each frob of nil collect x)) (error () :error))))

;;; Codex のレビューの 6 回目の指摘（SBCL 2.6.7 と比較）
;; Codex のレビュー P25 6回目 #1：getf の内側の多値の場所は、後続の格納の変数も NIL にする
(print (let ((p nil) (b 9))
         (list (handler-case (setf (getf (values p b) :x) 7) (unbound-variable () :unbound)) p b)))
(print (let ((p nil) (b 9))
         (list (push 7 (getf (values p b) :x)) p b)))
(print (let ((p (list :x (list 7 8))) (b 9))
         (list (pop (getf (values p b) :x)) p b)))
(print (let ((p nil) (b 9) (log nil))
         (list (push (progn (push :item log) 7)
                     (getf (values p b) (progn (push :indicator log) :x)
                           (progn (push :default log) nil)))
               p b (reverse log))))
;; Codex のレビュー P25 6回目 #2：格納の変数が 0 個の場所は値を消費しない。複数なら先頭だけ消費する
(print (handler-case
           (eval '(let ((a 0)) (list (multiple-value-list (setf (values (values) a) (values 1 2))) a)))
         (program-error () :program-error)))
(print (let ((a 0) (b 0) (c 0))
         (list (multiple-value-list (setf (values (values a b) c) (values 1 2 3))) a b c)))
(print (let ((a 0) (b 0))
         (list (multiple-value-list (setf (values a (values) b) (values 1 2 3))) a b)))
(print (multiple-value-list (setf (values (values) (values)) (values 1 2))))
(print (let ((a 0) (b 0))
         (list (multiple-value-list (setf (values (values) a b) (values))) a b)))
;; Codex のレビュー P25 6回目 #3：外側の形は短絡の前に検査し、部分の型は使うときだけ検査する
(print (mapcar (lambda (s) (handler-case (typep (cons 1 2) s) (error () :error)))
               '((cons t t t) (not integer integer) (and . integer))))
(print (mapcar (lambda (s) (handler-case (typep 1 s) (error () :error)))
               '((cons t t t) (cons . integer) (not) (not integer integer) (not integer . t)
                 (and . integer) (and fixnum . integer) (or fixnum . integer)
                 (or fixnum car) (and integer car) (cons car car) (not (or fixnum car)))))
;; Codex のレビュー P25 6回目 #4：型ごとの境界（閉区間・開区間・既定値）
(print (mapcar (lambda (s) (handler-case (typep 2 s) (error () :error)))
               '((integer 1.5 3) (integer (1.5) 3) (rational 1.5 3) (rational (1.5) 3)
                 (single-float 1 3) (single-float (1) 3.0) (short-float 1 3)
                 (double-float 1.0 3.0) (double-float (1.0) 3.0d0) (long-float 1.0 3.0)
                 (float 1 3) (float (1) (3)) (real 1.5 3) (real (1.5) (3))
                 (integer 1 3) (integer (1) (3)) (rational 1/2 3) (rational (1/2) (3))
                 (integer *) (real * *) (integer (1 2) 3) (integer (*) 3)
                 (real nil 3) (float "x" 3))))
(print (mapcar (lambda (s) (handler-case (typep 2.0 s) (error () :error)))
               '((single-float 1.0 3.0) (short-float (1.0) (3.0)) (float 1 3) (real 1 3))))
(print (mapcar (lambda (s) (handler-case (typep 2.0d0 s) (error () :error)))
               '((double-float 1.0d0 3.0d0) (long-float (1.0d0) (3.0d0)) (float 1 3))))
;; Codex のレビュー P25 6回目 #5：complex の実部に使える型と、合成・不正な型
(print (mapcar (lambda (s) (handler-case (typep 1 (list 'complex s)) (simple-error () :error)))
               '(* real rational integer ratio float single-float short-float double-float long-float
                 fixnum bignum bit (mod 4) unsigned-byte signed-byte (unsigned-byte 8) (signed-byte 8)
                 (integer 1 3) (rational (1/2) 3) (float 1 3) (single-float 1.0 3.0)
                 (and real integer) (or integer single-float) (and real string) (and integer (not bit))
                 (eql 1) (member 1 2) nil (or)
                 string t number complex (or integer string) (not string) (and)
                 (integer 1.5 3) (mod 0) (member 1 "x") (eql "x") car)))

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
