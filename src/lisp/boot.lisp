;;;; Zilisp の標準ライブラリ（Lisp で書く部分。詳細設計 §11.2）。
;;;; 起動時に VM で読み込む（Phase 15）。ネイティブにしてから組み込む方式（§11.3 の2段階ビルド）は後の Phase で行う。
;;;; ここで定義するのは、Zig で書いた defmacro・defun の上に作る標準マクロ。
;;;; 一般の場所（setf の場所）を扱う incf・decf・push・pop は、Phase 16 で setf と一緒に定義し直す。

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

;;; 変数の更新（場所が変数の場合だけ。一般の場所は Phase 16）
(defun zl-sys::%check-variable-place (place)
  (if (symbolp place)
      place
      (zl-sys::%unimplemented-error "変数以外の場所（setf の場所）は未実装です（Phase 16 で実装予定）" place)))

(defmacro incf (place &optional (delta 1))
  (zl-sys::%check-variable-place place)
  `(setq ,place (+ ,place ,delta)))

(defmacro decf (place &optional (delta 1))
  (zl-sys::%check-variable-place place)
  `(setq ,place (- ,place ,delta)))

(defmacro push (item place)
  (zl-sys::%check-variable-place place)
  `(setq ,place (cons ,item ,place)))

(defmacro pop (place)
  (zl-sys::%check-variable-place place)
  (let ((g (gensym)))
    `(let ((,g (car ,place)))
       (setq ,place (cdr ,place))
       ,g)))
