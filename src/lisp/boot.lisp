;;;; Zilisp の標準ライブラリ（Lisp で書く部分。詳細設計 §11.2）。
;;;; 起動時に VM で読み込む（Phase 15）。ネイティブにしてから組み込む方式（§11.3 の2段階ビルド）は後の Phase で行う。
;;;; ここで定義するのは、Zig で書いた defmacro・defun の上に作る標準マクロ。
;;;; setf と一般の場所は Phase 16 から。

;;; 脱出（Phase 18）
(defmacro return (&optional value)
  `(return-from nil ,value))

;;; 条件
(defmacro when (test &body body)
  `(if ,test (progn ,@body) nil))

(defmacro unless (test &body body)
  `(if ,test nil (progn ,@body)))

;; (cond (test form...) ...)：form のない節はテストの値を返す（CLHS cond）
(defmacro cond (&rest clauses)
  (if (null clauses)
      nil
      (let ((clause (car clauses))
            (rest (cdr clauses)))
        (if (not (consp clause))
            (zl-sys::%macro-form-error "COND の節はリストでなければなりません" clause)
            (if (null (cdr clause))
                (let ((g (gensym)))
                  `(let ((,g ,(car clause)))
                     (if ,g ,g (cond ,@rest))))
                `(if ,(car clause)
                     (progn ,@(cdr clause))
                     (cond ,@rest)))))))

(defmacro and (&rest forms)
  (if (null forms)
      t
      (if (null (cdr forms))
          (car forms)
          `(if ,(car forms) (and ,@(cdr forms)) nil))))

(defmacro or (&rest forms)
  (if (null forms)
      nil
      (if (null (cdr forms))
          (car forms)
          (let ((g (gensym)))
            `(let ((,g ,(car forms)))
               (if ,g ,g (or ,@(cdr forms))))))))

;; (case key (keys form...) ... (otherwise form...))：keys はアトムかリスト。t・otherwise は最後の節だけ（CLHS case）
(defun zl-sys::%case-key-test (var keys)
  (if (listp keys)
      `(or ,@(zl-sys::%case-key-tests var keys))
      `(eql ,var ',keys)))

(defun zl-sys::%case-key-tests (var keys)
  (if (null keys)
      nil
      (cons `(eql ,var ',(car keys)) (zl-sys::%case-key-tests var (cdr keys)))))

(defun zl-sys::%case-clauses (var clauses)
  (if (null clauses)
      nil
      (let ((clause (car clauses)))
        (if (and (null (cdr clauses))
                 (or (eq (car clause) t) (eq (car clause) 'otherwise)))
            `(progn ,@(cdr clause))
            `(if ,(zl-sys::%case-key-test var (car clause))
                 (progn ,@(cdr clause))
                 ,(zl-sys::%case-clauses var (cdr clauses)))))))

(defmacro case (keyform &rest clauses)
  (let ((g (gensym)))
    `(let ((,g ,keyform))
       ,(zl-sys::%case-clauses g clauses))))

;;; 順の評価
(defmacro prog1 (first &body rest)
  (let ((g (gensym)))
    `(let ((,g ,first))
       ,@rest
       ,g)))

(defmacro prog2 (first second &body rest)
  (let ((g (gensym)))
    `(progn ,first
            (let ((,g ,second))
              ,@rest
              ,g))))

;;; ---------------------------------------------------------------------------
;;; setf と一般の場所（Phase 16。CLHS 5.1）
;;; 場所の展開は、CLHS 5.1.1.2 の5つの要素（一時変数・値の式・格納変数・格納フォーム・読み出しフォーム）を
;;; 並べたリストで表す（多値は Phase 17 なので、今はリスト。get-setf-expansion は Phase 17 で公開する）。
;;; 場所の展開関数は、シンボルの属性 zl-sys::setf-expander に置く。

(defun zl-sys::%map-gensyms (list)
  (if (null list) nil (cons (gensym) (zl-sys::%map-gensyms (cdr list)))))

(defun zl-sys::%zip (as bs)
  (if (null as) nil (cons (list (car as) (car bs)) (zl-sys::%zip (cdr as) (cdr bs)))))

;; 展開の順序：場所の展開関数（defsetf など）→ マクロの展開 → setf 関数（CLHS 5.1.2.7・5.1.2.9）
(defun zl-sys::%setf-expansion (place)
  (cond ((symbolp place)
         (let ((store (gensym)))
           (list nil nil (list store) `(setq ,place ,store) place)))
        ((not (consp place))
         (zl-sys::%macro-form-error "setf の場所ではありません" place))
        (t
         (let* ((head (car place))
                (expander (and (symbolp head) (get head 'zl-sys::setf-expander))))
           (cond (expander (funcall expander place))
                 ((and (symbolp head) (macro-function head))
                  (zl-sys::%setf-expansion (macroexpand-1 place)))
                 (t
                  (let ((temps (zl-sys::%map-gensyms (cdr place)))
                        (store (gensym)))
                    (list temps (cdr place) (list store)
                          `(funcall #'(setf ,head) ,store ,@temps)
                          `(,head ,@temps)))))))))

(defun zl-sys::%expand-setf (place value)
  (if (symbolp place)
      `(setq ,place ,value)
      (destructuring-bind (temps vals stores store-form access) (zl-sys::%setf-expansion place)
        (declare (ignore access))
        `(let* (,@(zl-sys::%zip temps vals) (,(car stores) ,value))
           ,store-form))))

(defmacro setf (&rest pairs)
  (cond ((null pairs) nil)
        ((null (cdr pairs))
         (zl-sys::%macro-form-error "SETF の引数は場所と値の組です" pairs))
        ((null (cddr pairs))
         (zl-sys::%expand-setf (car pairs) (cadr pairs)))
        (t
         `(progn ,(zl-sys::%expand-setf (car pairs) (cadr pairs))
                 (setf ,@(cddr pairs))))))

;; (defsetf 読み出し 更新関数)：(更新関数 引数... 値) を呼ぶ。更新関数は値を返すこと（CLHS defsetf）
;; (defsetf 読み出し ラムダリスト (格納変数...) 本体...)：本体が格納フォームを作る
(defmacro defsetf (access &rest rest)
  (if (and rest (car rest) (symbolp (car rest)))
      (let ((update (car rest)))
        `(eval-when (:compile-toplevel :load-toplevel :execute)
           (zl-sys::%put ',access 'zl-sys::setf-expander
                         (lambda (place)
                           (let ((temps (zl-sys::%map-gensyms (cdr place)))
                                 (store (gensym)))
                             (list temps (cdr place) (list store)
                                   (cons ',update (append temps (list store)))
                                   (cons ',access temps)))))
           ',access))
      (destructuring-bind (lambda-list store-vars &body body) rest
        `(eval-when (:compile-toplevel :load-toplevel :execute)
           (zl-sys::%put ',access 'zl-sys::setf-expander
                         (lambda (place)
                           (let* ((temps (zl-sys::%map-gensyms (cdr place)))
                                  (stores (zl-sys::%map-gensyms ',store-vars))
                                  (store-form (destructuring-bind ,store-vars stores
                                                (destructuring-bind ,lambda-list temps ,@body))))
                             (list temps (cdr place) stores store-form (cons ',access temps)))))
           ',access))))

;; 標準の場所
(defsetf car zl-sys::%set-car)
(defsetf cdr zl-sys::%set-cdr)
(defsetf first zl-sys::%set-car)
(defsetf rest zl-sys::%set-cdr)
(defsetf caar (x) (v) `(zl-sys::%set-car (car ,x) ,v))
(defsetf cadr (x) (v) `(zl-sys::%set-car (cdr ,x) ,v))
(defsetf cdar (x) (v) `(zl-sys::%set-cdr (car ,x) ,v))
(defsetf cddr (x) (v) `(zl-sys::%set-cdr (cdr ,x) ,v))
(defsetf caddr (x) (v) `(zl-sys::%set-car (cddr ,x) ,v))
(defsetf cdddr (x) (v) `(zl-sys::%set-cdr (cddr ,x) ,v))
(defsetf cadddr (x) (v) `(zl-sys::%set-car (cdddr ,x) ,v))
(defsetf second (x) (v) `(zl-sys::%set-car (cdr ,x) ,v))
(defsetf third (x) (v) `(zl-sys::%set-car (nthcdr 2 ,x) ,v))
(defsetf fourth (x) (v) `(zl-sys::%set-car (nthcdr 3 ,x) ,v))
(defsetf fifth (x) (v) `(zl-sys::%set-car (nthcdr 4 ,x) ,v))
(defsetf sixth (x) (v) `(zl-sys::%set-car (nthcdr 5 ,x) ,v))
(defsetf seventh (x) (v) `(zl-sys::%set-car (nthcdr 6 ,x) ,v))
(defsetf eighth (x) (v) `(zl-sys::%set-car (nthcdr 7 ,x) ,v))
(defsetf ninth (x) (v) `(zl-sys::%set-car (nthcdr 8 ,x) ,v))
(defsetf tenth (x) (v) `(zl-sys::%set-car (nthcdr 9 ,x) ,v))
(defsetf nth (n l) (v) `(zl-sys::%set-car (nthcdr ,n ,l) ,v))
(defsetf aref zl-sys::%aset)
(defsetf svref zl-sys::%svset)
(defsetf char zl-sys::%set-char)
(defsetf schar zl-sys::%set-char)
(defsetf gethash zl-sys::%puthash)
(defsetf get zl-sys::%put)
(defsetf symbol-value set)
(defsetf symbol-function zl-sys::%set-fdefinition)
(defsetf fdefinition zl-sys::%set-fdefinition)

;; (setf (getf 場所 指示子 [既定値]) 値)：場所の属性リストを書き換える（場所そのものにも新しいリストを書く）
(zl-sys::%put 'getf 'zl-sys::setf-expander
              (lambda (form)
                (destructuring-bind (plist-place indicator &optional default) (cdr form)
                  (destructuring-bind (temps vals stores store-form access) (zl-sys::%setf-expansion plist-place)
                    (let ((itemp (gensym))
                          (dtemp (gensym))
                          (store (gensym)))
                      (list (append temps (list itemp dtemp))
                            (append vals (list indicator default))
                            (list store)
                            `(let ((,(car stores) (zl-sys::%putf ,access ,itemp ,store)))
                               ,store-form
                               ,store)
                            `(getf ,access ,itemp ,dtemp)))))))

;; 場所を更新するマクロ（CLHS 5.1.2：場所の部分のフォームは1回だけ、左から順に評価する）
(defmacro incf (place &optional (delta 1))
  (if (symbolp place)
      `(setq ,place (+ ,place ,delta))
      (destructuring-bind (temps vals stores store-form access) (zl-sys::%setf-expansion place)
        `(let* (,@(zl-sys::%zip temps vals) (,(car stores) (+ ,access ,delta)))
           ,store-form))))

(defmacro decf (place &optional (delta 1))
  (if (symbolp place)
      `(setq ,place (- ,place ,delta))
      (destructuring-bind (temps vals stores store-form access) (zl-sys::%setf-expansion place)
        `(let* (,@(zl-sys::%zip temps vals) (,(car stores) (- ,access ,delta)))
           ,store-form))))

;; push：item は場所の部分より先に評価する（CLHS push）
(defmacro push (item place)
  (if (symbolp place)
      `(setq ,place (cons ,item ,place))
      (let ((g (gensym)))
        (destructuring-bind (temps vals stores store-form access) (zl-sys::%setf-expansion place)
          `(let* ((,g ,item) ,@(zl-sys::%zip temps vals) (,(car stores) (cons ,g ,access)))
             ,store-form)))))

(defmacro pop (place)
  (let ((g (gensym)))
    (if (symbolp place)
        `(let ((,g ,place))
           (setq ,place (cdr ,g))
           (car ,g))
        (destructuring-bind (temps vals stores store-form access) (zl-sys::%setf-expansion place)
          `(let* (,@(zl-sys::%zip temps vals) (,g ,access) (,(car stores) (cdr ,g)))
             ,store-form
             (car ,g))))))

;;; ---------------------------------------------------------------------------
;;; 多値（Phase 17。CLHS 5.3）

(defmacro nth-value (n form)
  `(nth ,n (multiple-value-list ,form)))

;; (multiple-value-setq (変数...) フォーム)：変数に値を順に代入し、主値を返す
(defmacro multiple-value-setq (vars form)
  (let ((temps (zl-sys::%map-gensyms vars)))
    `(multiple-value-bind ,temps ,form
       ,@(zl-sys::%mvsetq-assignments vars temps)
       ,(if temps (car temps) nil))))

(defun zl-sys::%mvsetq-assignments (vars temps)
  (if (null vars)
      nil
      (cons `(setq ,(car vars) ,(car temps))
            (zl-sys::%mvsetq-assignments (cdr vars) (cdr temps)))))

;; get-setf-expansion：場所の展開の5つの値（Phase 16 の zl-sys::%setf-expansion のリストを多値にする）
(defun get-setf-expansion (place &optional environment)
  (declare (ignore environment))
  (values-list (zl-sys::%setf-expansion place)))

;; (define-setf-expander 読み出し ラムダリスト 本体...)：本体が5つの値を返す（CLHS define-setf-expander）
(defmacro define-setf-expander (access lambda-list &body body)
  (let ((place (gensym)))
    `(eval-when (:compile-toplevel :load-toplevel :execute)
       (zl-sys::%put ',access 'zl-sys::setf-expander
                     (lambda (,place)
                       (multiple-value-list
                        (destructuring-bind ,lambda-list (cdr ,place) ,@body))))
       ',access)))


;;; 反復（Phase 19）：psetq・dolist・dotimes・do・do*、mapcar・mapc・mapcan・nconc・reduce、loop

;; 本体の先頭の宣言と、残りのフォーム
(defun zl-sys::%body-declarations (body)
  (if (and (consp body) (consp (car body)) (eq (car (car body)) 'declare))
      (cons (car body) (zl-sys::%body-declarations (cdr body)))
      nil))

(defun zl-sys::%body-forms (body)
  (if (and (consp body) (consp (car body)) (eq (car (car body)) 'declare))
      (zl-sys::%body-forms (cdr body))
      body))

;; (psetq 変数 値 ...)：値をすべて求めてから代入する（CLHS psetq）
(defmacro psetq (&rest pairs)
  (let ((temps nil) (sets nil) (p pairs))
    (tagbody
     next
       (if (null p) (go done))
       (if (null (cdr p)) (zl-sys::%macro-form-error "PSETQ の引数は変数と値の組です" pairs))
       (let ((g (gensym)))
         (setq temps (cons (list g (car (cdr p))) temps))
         (setq sets (cons (car p) (cons g sets))))
       (setq p (cdr (cdr p)))
       (go next)
     done)
    `(let ,(reverse temps) (setq ,@sets) nil)))

;; (dolist (変数 リスト [結果]) 本体...)：本体は暗黙の tagbody。結果は変数を NIL に束縛して評価する（CLHS dolist）
(defmacro dolist ((var list-form &optional result) &body body)
  (let ((l (gensym "LIST")) (top (gensym "TOP")) (end (gensym "END")))
    `(block nil
       (let ((,l ,list-form))
         (tagbody
          ,top
            (if (endp ,l) (go ,end))
            (let ((,var (car ,l)))
              ,@(zl-sys::%body-declarations body)
              (tagbody ,@(zl-sys::%body-forms body)))
            (setq ,l (cdr ,l))
            (go ,top)
          ,end))
       (let ((,var nil))
         (declare (ignorable ,var))
         ,result))))

;; (dotimes (変数 回数 [結果]) 本体...)：結果は変数が回数のときに評価する（CLHS dotimes）
(defmacro dotimes ((var count-form &optional result) &body body)
  (let ((n (gensym "COUNT")) (top (gensym "TOP")) (end (gensym "END")))
    `(block nil
       (let ((,n ,count-form) (,var 0))
         ,@(zl-sys::%body-declarations body)
         (tagbody
          ,top
            (if (>= ,var ,n) (go ,end))
            (tagbody ,@(zl-sys::%body-forms body))
            (setq ,var (1+ ,var))
            (go ,top)
          ,end)
         ,result))))

;; do・do* の展開（do は並列に、do* は順に束縛・更新する）
(defun zl-sys::%do-expansion (specs end-clause body let-op set-op)
  (let ((bindings nil) (steps nil) (top (gensym "TOP")) (end (gensym "END")))
    (if (not (consp end-clause))
        (zl-sys::%macro-form-error "DO の終了の節はリストでなければなりません" end-clause))
    (dolist (s specs)
      (cond ((symbolp s) (setq bindings (cons s bindings)))
            ((consp s)
             (setq bindings (cons (if (cdr s) (list (car s) (car (cdr s))) (list (car s))) bindings))
             (if (cdr (cdr s))
                 (setq steps (cons (car (cdr (cdr s))) (cons (car s) steps)))))
            (t (zl-sys::%macro-form-error "DO の変数の指定が正しくありません" s))))
    `(block nil
       (,let-op ,(reverse bindings)
         ,@(zl-sys::%body-declarations body)
         (tagbody
          ,top
            (if ,(car end-clause) (go ,end))
            (tagbody ,@(zl-sys::%body-forms body))
            ,@(if steps (list (cons set-op (reverse steps))))
            (go ,top)
          ,end)
         ,@(if (cdr end-clause) (cdr end-clause) (list nil))))))

(defmacro do (specs end-clause &body body)
  (zl-sys::%do-expansion specs end-clause body 'let 'psetq))

(defmacro do* (specs end-clause &body body)
  (zl-sys::%do-expansion specs end-clause body 'let* 'setq))

;;; 写像と畳み込み（Phase 19。列の関数の全体は Phase 21）

(defun zl-sys::%cars (lists)
  (if lists (cons (car (car lists)) (zl-sys::%cars (cdr lists))) nil))

(defun zl-sys::%cdrs (lists)
  (if lists (cons (cdr (car lists)) (zl-sys::%cdrs (cdr lists))) nil))

(defun zl-sys::%any-endp (lists)
  (if lists (if (endp (car lists)) t (zl-sys::%any-endp (cdr lists))) nil))

(defun mapcar (function list &rest more-lists)
  (let ((head nil) (tail nil))
    (if (null more-lists)
        (dolist (x list)
          (let ((c (cons (funcall function x) nil)))
            (if tail (rplacd tail c) (setq head c))
            (setq tail c)))
        (do ((lists (cons list more-lists) (zl-sys::%cdrs lists)))
            ((zl-sys::%any-endp lists))
          (let ((c (cons (apply function (zl-sys::%cars lists)) nil)))
            (if tail (rplacd tail c) (setq head c))
            (setq tail c))))
    head))

(defun mapc (function list &rest more-lists)
  (if (null more-lists)
      (dolist (x list) (funcall function x))
      (do ((lists (cons list more-lists) (zl-sys::%cdrs lists)))
          ((zl-sys::%any-endp lists))
        (apply function (zl-sys::%cars lists))))
  list)

(defun nconc (&rest lists)
  (let ((result nil) (tail nil))
    (do ((ls lists (cdr ls)))
        ((null ls) result)
      (let ((l (car ls)))
        (cond ((null (cdr ls)) (if tail (rplacd tail l) (setq result l)))
              ((null l))
              (t (if tail (rplacd tail l) (setq result l))
                 (setq tail (last l))))))))

(defun mapcan (function list &rest more-lists)
  (apply #'nconc (apply #'mapcar function list more-lists)))

;; 列の start〜end の要素のリスト
(defun zl-sys::%sequence-list (seq start end)
  (let ((result nil) (i 0))
    (if (listp seq)
        (dolist (x seq)
          (if (and (>= i start) (or (null end) (< i end))) (setq result (cons x result)))
          (setq i (1+ i)))
        (do ((j start (1+ j)))
            ((>= j (or end (length seq))))
          (setq result (cons (aref seq j) result))))
    (nreverse result)))

(defun reduce (function sequence &key key from-end (start 0) end (initial-value nil initial-value-p))
  (let ((items (zl-sys::%sequence-list sequence start end)))
    (if key (setq items (mapcar key items)))
    (if from-end (setq items (reverse items)))
    (if (null items)
        (if initial-value-p initial-value (funcall function))
        (let ((acc (if initial-value-p initial-value (car items))))
          (dolist (x (if initial-value-p items (cdr items)) acc)
            (setq acc (if from-end (funcall function x acc) (funcall function acc x))))))))

;;; loop（Phase 19。独自の実装。CLHS 6.1）
;;; 対応する句：named、with、for・as（from・upfrom・downfrom・to・upto・below・downto・above・by、in・on（by）、
;;; = … then、across、being the hash-keys・hash-values（using））、repeat、initially・finally、do・doing、
;;; collect・append・nconc・sum・count・maximize・minimize（into）、while・until、always・never・thereis、return、
;;; when・if・unless（and・else・end・it）、loop-finish。分解（(a b)、(a . b)、nil で読み飛ばす）。
;;; 未対応の句（for・with の and による並列の束縛、being の elements・symbols など）は明示的なエラーにする。
;;; 展開：(block 名前 (let* (束縛...) (tagbody 前処理 最初の検査 本体のタグ 本体 更新と検査 (go 本体のタグ) 終わりのタグ 後処理 (return-from 名前 既定の値))))

(defun zl-sys::%loop-keyword-p (x names)
  (if (and x (symbolp x))
      (let ((n (symbol-name x)) (found nil))
        (dolist (k names found) (if (string= n k) (setq found t))))
      nil))

(defmacro loop-finish ()
  '(go zl-sys::%loop-end))

(defmacro loop (&rest forms)
  (if (and forms (consp (car forms)))
      ;; 単純な loop：(loop 複合フォーム...)
      (let ((top (gensym "TOP")))
        `(block nil (tagbody ,top ,@forms (go ,top))))
      (zl-sys::%loop-expand forms)))

(defun zl-sys::%loop-expand (forms)
  (let ((rest forms)
        (name nil)
        (bindings nil)
        (prologue nil)
        (epilogue nil)
        (first-code nil)
        (step-code nil)
        (body nil)
        (result-var nil)
        (default-return nil)
        (bound-accumulators nil)
        (it-var nil)
        (body-tag (gensym "BODY")))
    (labels ((peek () (car rest))
             (next () (let ((x (car rest))) (setq rest (cdr rest)) x))
             (at (&rest names) (zl-sys::%loop-keyword-p (car rest) names))
             (need-form (what)
               (if (null rest) (zl-sys::%macro-form-error "LOOP の句の後ろにフォームがありません" what))
               (next))
             (bind (var init) (setq bindings (cons (list var init) bindings)))
             (bind-pattern (pat)
               (cond ((null pat))
                     ((symbolp pat) (bind pat nil))
                     ((consp pat) (bind-pattern (car pat)) (bind-pattern (cdr pat)))
                     (t (zl-sys::%macro-form-error "LOOP の変数が正しくありません" pat))))
             (destructure (pat expr)
               (cond ((null pat) nil)
                     ((symbolp pat) (list (list 'setq pat expr)))
                     (t (append (destructure (car pat) (list 'car expr))
                                (destructure (cdr pat) (list 'cdr expr))))))
             (assign (pat form)
               (if (symbolp pat)
                   (if pat (list (list 'setq pat form)) nil)
                   (let ((g (gensym)))
                     (list `(let ((,g ,form)) ,@(destructure pat g))))))
             (skip-type ()
               (cond ((at "OF-TYPE") (next) (next))
                     ((at "FIXNUM" "FLOAT" "INTEGER" "NUMBER" "REAL" "SINGLE-FLOAT" "DOUBLE-FLOAT") (next))))
             (no-and (clause)
               (if (at "AND")
                   (zl-sys::%unimplemented-error "LOOP の並列の束縛（and）は未実装です" clause)))
             (add-first (forms) (setq first-code (append (reverse forms) first-code)))
             (add-step (forms) (setq step-code (append (reverse forms) step-code)))
             ;; for・as の句
             (parse-for ()
               (let ((var (next)))
                 (skip-type)
                 (cond
                   ((at "IN")
                    (next)
                    (let ((tail (gensym "TAIL")) (list-form (need-form "IN")) (by nil))
                      (if (at "BY") (progn (next) (setq by (need-form "BY"))))
                      (bind tail list-form)
                      (bind-pattern var)
                      (let ((test `(if (endp ,tail) (go zl-sys::%loop-end))))
                        (add-first (cons test (assign var `(car ,tail))))
                        (add-step (cons `(setq ,tail ,(if by `(funcall ,by ,tail) `(cdr ,tail)))
                                        (cons test (assign var `(car ,tail))))))))
                   ((at "ON")
                    (next)
                    (let ((tail (gensym "TAIL")) (list-form (need-form "ON")) (by nil))
                      (if (at "BY") (progn (next) (setq by (need-form "BY"))))
                      (bind tail list-form)
                      (bind-pattern var)
                      (let ((test `(if (atom ,tail) (go zl-sys::%loop-end))))
                        (add-first (cons test (assign var tail)))
                        (add-step (cons `(setq ,tail ,(if by `(funcall ,by ,tail) `(cdr ,tail)))
                                        (cons test (assign var tail)))))))
                   ((at "=")
                    (next)
                    (let ((init (need-form "=")) (then nil) (has-then nil))
                      (if (at "THEN") (progn (next) (setq then (need-form "THEN")) (setq has-then t)))
                      (bind-pattern var)
                      (add-first (assign var init))
                      (add-step (assign var (if has-then then init)))))
                   ((at "ACROSS")
                    (next)
                    (let ((vec (gensym "VECTOR")) (i (gensym "INDEX")))
                      (bind vec (need-form "ACROSS"))
                      (bind i 0)
                      (bind-pattern var)
                      (let ((test `(if (>= ,i (length ,vec)) (go zl-sys::%loop-end))))
                        (add-first (cons test (assign var `(aref ,vec ,i))))
                        (add-step (cons `(setq ,i (1+ ,i)) (cons test (assign var `(aref ,vec ,i))))))))
                   ((at "BEING")
                    (next)
                    (if (at "EACH" "THE") (next))
                    (let ((kind (next)) (pairs (gensym "PAIRS")) (other nil) (keys nil))
                      (cond ((zl-sys::%loop-keyword-p kind '("HASH-KEY" "HASH-KEYS")) (setq keys t))
                            ((zl-sys::%loop-keyword-p kind '("HASH-VALUE" "HASH-VALUES")) (setq keys nil))
                            (t (zl-sys::%unimplemented-error "LOOP の being のこの種類は未実装です" kind)))
                      (if (at "OF" "IN") (next) (zl-sys::%macro-form-error "LOOP の being には of が必要です" (peek)))
                      (bind pairs `(zl-sys::%hash-pairs ,(need-form "OF")))
                      (if (at "USING")
                          (progn
                            (next)
                            (let ((u (next)))
                              (if (not (and (consp u) (consp (cdr u))))
                                  (zl-sys::%macro-form-error "LOOP の using の形が正しくありません" u))
                              (setq other (car (cdr u))))))
                      (bind-pattern var)
                      (if other (bind-pattern other))
                      (let ((sets (append (assign var (if keys `(car (car ,pairs)) `(cdr (car ,pairs))))
                                          (if other (assign other (if keys `(cdr (car ,pairs)) `(car (car ,pairs))))))))
                        (add-first (cons `(if (endp ,pairs) (go zl-sys::%loop-end)) sets))
                        (add-step (cons `(setq ,pairs (cdr ,pairs))
                                        (cons `(if (endp ,pairs) (go zl-sys::%loop-end)) sets))))))
                   ((at "FROM" "UPFROM" "DOWNFROM" "TO" "UPTO" "BELOW" "DOWNTO" "ABOVE" "BY")
                    (parse-arithmetic var))
                   (t (zl-sys::%macro-form-error "LOOP の for の形が正しくありません" (peek))))
                 (no-and "FOR")))
             (parse-arithmetic (var)
               (let ((start 0) (limit nil) (has-limit nil) (inclusive t) (down nil) (by nil))
                 (if (not (and var (symbolp var)))
                     (zl-sys::%macro-form-error "LOOP の for の数の変数はシンボルでなければなりません" var))
                 (tagbody
                  next
                    (cond ((at "FROM") (next) (setq start (need-form "FROM")))
                          ((at "UPFROM") (next) (setq start (need-form "UPFROM")))
                          ((at "DOWNFROM") (next) (setq start (need-form "DOWNFROM")) (setq down t))
                          ((at "TO" "UPTO") (next) (setq limit (need-form "TO")) (setq has-limit t) (setq inclusive t))
                          ((at "BELOW") (next) (setq limit (need-form "BELOW")) (setq has-limit t) (setq inclusive nil))
                          ((at "DOWNTO") (next) (setq limit (need-form "DOWNTO")) (setq has-limit t) (setq inclusive t) (setq down t))
                          ((at "ABOVE") (next) (setq limit (need-form "ABOVE")) (setq has-limit t) (setq inclusive nil) (setq down t))
                          ((at "BY") (next) (setq by (need-form "BY")))
                          (t (go done)))
                    (go next)
                  done)
                 (bind var start)
                 (let ((lim (gensym "LIMIT")) (stp (gensym "STEP")) (test nil))
                   (if has-limit (bind lim limit))
                   (bind stp (if by by 1))
                   (if has-limit
                       (setq test `(if ,(if down
                                            (if inclusive `(< ,var ,lim) `(<= ,var ,lim))
                                            (if inclusive `(> ,var ,lim) `(>= ,var ,lim)))
                                       (go zl-sys::%loop-end))))
                   (add-first (if test (list test) nil))
                   (add-step (cons `(setq ,var ,(if down `(- ,var ,stp) `(+ ,var ,stp)))
                                   (if test (list test) nil))))))
             ;; 集める句：集める変数（into がなければ既定の結果の変数）と、リストの末尾の変数
             (accumulator (kind into)
               (let ((var into) (tail nil) (entry nil))
                 (if (null var)
                     (progn
                       (if (null result-var) (setq result-var (gensym "RESULT")))
                       (setq var result-var)
                       (setq default-return result-var)))
                 (dolist (e bound-accumulators)
                   (if (eq (car e) var) (setq entry e)))
                 (if (null entry)
                     (progn
                       (setq entry (list var (gensym "TAIL")))
                       (setq bound-accumulators (cons entry bound-accumulators))
                       (bind var (if (zl-sys::%loop-keyword-p kind '("SUM" "SUMMING" "COUNT" "COUNTING")) 0 nil))
                       (bind (car (cdr entry)) nil)))
                 (setq tail (car (cdr entry)))
                 (list var tail)))
             (parse-form-or-it (what)
               (if (and it-var (at "IT")) (progn (next) it-var) (need-form what)))
             (parse-accumulation (kind)
               (let* ((form (parse-form-or-it kind))
                      (into (if (at "INTO") (progn (next) (next)) nil))
                      (acc (accumulator kind into))
                      (var (car acc))
                      (tail (car (cdr acc)))
                      (c (gensym)))
                 (skip-type)
                 (cond
                   ((zl-sys::%loop-keyword-p kind '("COLLECT" "COLLECTING"))
                    `(let ((,c (list ,form)))
                       (if ,tail (rplacd ,tail ,c) (setq ,var ,c))
                       (setq ,tail ,c)))
                   ((zl-sys::%loop-keyword-p kind '("APPEND" "APPENDING" "NCONC" "NCONCING"))
                    `(let ((,c ,(if (zl-sys::%loop-keyword-p kind '("APPEND" "APPENDING")) `(copy-list ,form) form)))
                       (if ,c
                           (progn
                             (if ,tail (rplacd ,tail ,c) (setq ,var ,c))
                             (setq ,tail (last ,c))))))
                   ((zl-sys::%loop-keyword-p kind '("SUM" "SUMMING"))
                    `(setq ,var (+ ,var ,form)))
                   ((zl-sys::%loop-keyword-p kind '("COUNT" "COUNTING"))
                    `(if ,form (setq ,var (1+ ,var))))
                   ((zl-sys::%loop-keyword-p kind '("MAXIMIZE" "MAXIMIZING"))
                    `(let ((,c ,form)) (setq ,var (if ,var (max ,var ,c) ,c))))
                   (t
                    `(let ((,c ,form)) (setq ,var (if ,var (min ,var ,c) ,c)))))))
             ;; 本体の句（条件の中に置けるもの）。フォームのリストを返す
             (parse-selectable ()
               (cond
                 ((at "DO" "DOING")
                  (next)
                  (let ((fs nil))
                    (if (not (consp (peek))) (zl-sys::%macro-form-error "LOOP の do の後ろに複合フォームがありません" (peek)))
                    (tagbody
                     next
                       (if (consp (peek)) (progn (setq fs (cons (next) fs)) (go next))))
                    (reverse fs)))
                 ((at "COLLECT" "COLLECTING" "APPEND" "APPENDING" "NCONC" "NCONCING" "SUM" "SUMMING"
                      "COUNT" "COUNTING" "MAXIMIZE" "MAXIMIZING" "MINIMIZE" "MINIMIZING")
                  (list (parse-accumulation (next))))
                 ((at "RETURN")
                  (next)
                  (list `(return-from ,name ,(parse-form-or-it "RETURN"))))
                 ((at "WHEN" "IF" "UNLESS")
                  (list (parse-conditional (next))))
                 (t (zl-sys::%macro-form-error "LOOP の条件の中に置けない句です" (peek)))))
             (parse-clause-group ()
               (let ((forms (parse-selectable)))
                 (tagbody
                  next
                    (if (at "AND")
                        (progn (next) (setq forms (append forms (parse-selectable))) (go next))))
                 forms))
             (parse-conditional (kw)
               (let ((test (need-form kw)) (saved it-var) (then nil) (else nil) (it (gensym "IT")))
                 (setq it-var it)
                 (bind it nil)
                 (setq then (parse-clause-group))
                 (if (at "ELSE") (progn (next) (setq else (parse-clause-group))))
                 (if (at "END") (next))
                 (setq it-var saved)
                 (let ((cond-form (if (zl-sys::%loop-keyword-p kw '("UNLESS")) `(not (setq ,it ,test)) `(setq ,it ,test))))
                   `(if ,cond-form (progn ,@then) (progn ,@else)))))
             (add-body (forms) (setq body (append (reverse forms) body))))
      (if (at "NAMED")
          (progn (next) (setq name (next))))
      (tagbody
       next
         (if (null rest) (go done))
         (cond
           ((at "FOR" "AS") (next) (parse-for))
           ((at "WITH")
            (next)
            (let ((var (next)))
              (skip-type)
              (if (at "=") (progn (next) (bind var (need-form "WITH"))) (bind var nil))
              (no-and "WITH")))
           ((at "REPEAT")
            (next)
            (let ((c (gensym "COUNT")))
              (bind c (need-form "REPEAT"))
              (add-first (list `(if (<= ,c 0) (go zl-sys::%loop-end))))
              (add-step (list `(setq ,c (1- ,c)) `(if (<= ,c 0) (go zl-sys::%loop-end))))))
           ((at "INITIALLY")
            (next)
            (tagbody
             more
               (if (consp (peek)) (progn (setq prologue (cons (next) prologue)) (go more)))))
           ((at "FINALLY")
            (next)
            (tagbody
             more
               (if (consp (peek)) (progn (setq epilogue (cons (next) epilogue)) (go more)))))
           ((at "WHILE") (next) (add-body (list `(if (not ,(need-form "WHILE")) (go zl-sys::%loop-end)))))
           ((at "UNTIL") (next) (add-body (list `(if ,(need-form "UNTIL") (go zl-sys::%loop-end)))))
           ((at "ALWAYS")
            (next)
            (setq default-return t)
            (add-body (list `(if (not ,(need-form "ALWAYS")) (return-from ,name nil)))))
           ((at "NEVER")
            (next)
            (setq default-return t)
            (add-body (list `(if ,(need-form "NEVER") (return-from ,name nil)))))
           ((at "THEREIS")
            (next)
            (let ((g (gensym)))
              (add-body (list `(let ((,g ,(need-form "THEREIS"))) (if ,g (return-from ,name ,g)))))))
           ((at "DO" "DOING" "COLLECT" "COLLECTING" "APPEND" "APPENDING" "NCONC" "NCONCING" "SUM" "SUMMING"
                "COUNT" "COUNTING" "MAXIMIZE" "MAXIMIZING" "MINIMIZE" "MINIMIZING" "RETURN" "WHEN" "IF" "UNLESS")
            (add-body (parse-selectable)))
           ((and (symbolp (peek)) (peek))
            (zl-sys::%unimplemented-error "この LOOP の句は未実装です" (peek)))
           (t (zl-sys::%macro-form-error "LOOP の句が正しくありません" (peek))))
         (go next)
       done)
      `(block ,name
         (let* ,(reverse bindings)
           (tagbody
              ,@(reverse prologue)
              ,@(reverse first-code)
            ,body-tag
              ,@(reverse body)
              ,@(reverse step-code)
              (go ,body-tag)
            zl-sys::%loop-end
              ,@(reverse epilogue)
              (return-from ,name ,default-return)))))))
