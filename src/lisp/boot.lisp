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
