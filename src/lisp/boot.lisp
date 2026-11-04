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
(defsetf row-major-aref zl-sys::%set-row-major-aref)
(defsetf fill-pointer zl-sys::%set-fill-pointer)
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
       ;; 結果の式の束縛にも、本体の宣言を付ける（special 宣言などが結果の式にも効くように。Codex のレビュー P19 #8）
       (let ((,var nil))
         (declare (ignorable ,var))
         ,@(zl-sys::%body-declarations body)
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
            ;; (変数 [初期値 [更新]])：変数はシンボル、長さ 1〜3 の真のリスト（SBCL と同じくそれ以外はエラー）
            ((and (consp s)
                  (or (not (symbolp (car s)))
                      (not (listp (cdr s)))
                      (and (cdr s) (not (listp (cdr (cdr s)))))
                      (and (cdr s) (cdr (cdr s)) (cdr (cdr (cdr s))))))
             (zl-sys::%macro-form-error "DO の変数の指定が正しくありません" s))
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

;; 結果のリストを nconc でつなぐ（apply を使うと、要素の数が call-arguments-limit を超えられない。agy のレビュー 0.3 #6）
(defun mapcan (function list &rest more-lists)
  (let ((head nil) (tail nil))
    (do ((rs (apply #'mapcar function list more-lists) (cdr rs)))
        ((null rs) head)
      (let ((l (car rs)))
        (cond ((null (cdr rs)) (if tail (rplacd tail l) (setq head l)))
              ((null l))
              (t (if tail (rplacd tail l) (setq head l))
                 (setq tail (last l))))))))

;; 列の start〜end の要素のリスト。範囲と型は subseq が確かめる（SBCL と同じ type-error。agy のレビュー 0.3 #2）
(defun zl-sys::%sequence-list (seq start end)
  (let ((s (subseq seq start end)))
    (if (listp s) s (coerce s 'list))))

(defun reduce (function sequence &key key from-end (start 0) end (initial-value nil initial-value-p))
  (let ((items (zl-sys::%sequence-list sequence start end)))
    ;; :from-end では、:key も後ろの要素から順に呼ぶ（SBCL 2.6.7 と同じ。Codex のレビュー P19 #9）
    (if from-end (setq items (reverse items)))
    (if key (setq items (mapcar key items)))
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
             ;; 分解して束縛する（with。パターンの変数を、初期値の一時変数の car・cdr で束縛する）
             (bind-destructuring (pat init)
               (cond ((null pat) (bind (gensym "IGNORE") init))
                     ((symbolp pat) (bind pat init))
                     ((consp pat)
                      (let ((g (gensym "WITH")))
                        (bind g init)
                        (labels ((walk (p e)
                                   (cond ((null p))
                                         ((symbolp p) (bind p e))
                                         ((consp p) (walk (car p) `(car ,e)) (walk (cdr p) `(cdr ,e)))
                                         (t (zl-sys::%macro-form-error "LOOP の変数が正しくありません" p)))))
                          (walk pat g))))
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
             ;; 型の指定を読み飛ばし、型（なければ NIL）を返す
             (skip-type ()
               (cond ((at "OF-TYPE") (next) (next))
                     ((at "FIXNUM" "FLOAT" "INTEGER" "NUMBER" "REAL" "SINGLE-FLOAT" "DOUBLE-FLOAT") (next))
                     (t nil)))
             ;; with の変数の、型による既定の初期値（数の型なら 0。CLHS 6.1.2.2。Codex のレビュー P19 #10）
             (type-default (type)
               (cond ((zl-sys::%loop-keyword-p type '("FIXNUM" "INTEGER" "NUMBER" "REAL" "RATIONAL" "BIT")) 0)
                     ((zl-sys::%loop-keyword-p type '("FLOAT" "SINGLE-FLOAT" "SHORT-FLOAT")) 0.0)
                     ((zl-sys::%loop-keyword-p type '("DOUBLE-FLOAT" "LONG-FLOAT")) 0.0d0)
                     (t nil)))
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
                      (bind tail list-form)
                      ;; by の関数は初めに一度だけ評価する（SBCL と同じ。Codex のレビュー 0.3 #9）
                      (if (at "BY") (let ((f (gensym "BY"))) (next) (bind f (need-form "BY")) (setq by f)))
                      (bind-pattern var)
                      (let ((test `(if (endp ,tail) (go zl-sys::%loop-end))))
                        (add-first (cons test (assign var `(car ,tail))))
                        (add-step (cons `(setq ,tail ,(if by `(funcall ,by ,tail) `(cdr ,tail)))
                                        (cons test (assign var `(car ,tail))))))))
                   ((at "ON")
                    (next)
                    (let ((tail (gensym "TAIL")) (list-form (need-form "ON")) (by nil))
                      (bind tail list-form)
                      ;; by の関数は初めに一度だけ評価する（SBCL と同じ。Codex のレビュー 0.3 #9）
                      (if (at "BY") (let ((f (gensym "BY"))) (next) (bind f (need-form "BY")) (setq by f)))
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
                              ;; hash-keys には (hash-value 変数)、hash-values には (hash-key 変数)（SBCL と同じ）
                              (if (not (and (consp u) (consp (cdr u)) (null (cdr (cdr u)))
                                            (zl-sys::%loop-keyword-p (car u) (if keys '("HASH-VALUE" "HASH-VALUES") '("HASH-KEY" "HASH-KEYS")))))
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
             ;; 部分節は書いた順に評価する（CLHS 6.1.2.1.1）。上り・下りの向きが矛盾すればエラー、by は正の数（SBCL と同じ。
             ;; agy のレビュー 0.3 #4）
             (parse-arithmetic (var)
               (let ((has-start nil) (has-limit nil) (has-by nil) (inclusive t) (start-dir nil) (limit-dir nil)
                     (lim (gensym "LIMIT")) (stp (gensym "STEP")) (down nil) (test nil))
                 (if (not (and var (symbolp var)))
                     (zl-sys::%macro-form-error "LOOP の for の数の変数はシンボルでなければなりません" var))
                 (tagbody
                  next
                    (cond ((at "FROM" "UPFROM" "DOWNFROM")
                           (if has-start (zl-sys::%macro-form-error "LOOP の for の開始の値が2つあります" (peek)))
                           (setq start-dir (cond ((at "UPFROM") :up) ((at "DOWNFROM") :down) (t nil)))
                           (next) (setq has-start t) (bind var (need-form "FROM")))
                          ((at "TO" "UPTO" "BELOW" "DOWNTO" "ABOVE")
                           (if has-limit (zl-sys::%macro-form-error "LOOP の for の終わりの値が2つあります" (peek)))
                           (setq limit-dir (cond ((at "UPTO" "BELOW") :up) ((at "DOWNTO" "ABOVE") :down) (t nil)))
                           (setq inclusive (not (at "BELOW" "ABOVE")))
                           (next) (setq has-limit t) (bind lim (need-form "TO")))
                          ((at "BY")
                           (if has-by (zl-sys::%macro-form-error "LOOP の for の by が2つあります" (peek)))
                           (next) (setq has-by t) (bind stp (need-form "BY")))
                          (t (go done)))
                    (go next)
                  done)
                 (if (and start-dir limit-dir (not (eq start-dir limit-dir)))
                     (zl-sys::%macro-form-error "LOOP の for の上り・下りの向きが矛盾しています" var))
                 (setq down (or (eq start-dir :down) (eq limit-dir :down)))
                 (if (not has-start) (bind var 0))
                 (if has-by
                     (add-first (list `(if (not (plusp ,stp)) (zl-sys::%type-error ,stp '(and real (satisfies plusp))))))
                     (bind stp 1))
                 (progn
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
                 ;; 同じ変数に、種類の違う集め方（リスト・数の和と数・最大と最小）は混ぜられない（SBCL と同じ。agy のレビュー 0.3 #5）
                 (let ((category (cond ((zl-sys::%loop-keyword-p kind '("SUM" "SUMMING" "COUNT" "COUNTING")) :sum)
                                       ((zl-sys::%loop-keyword-p kind '("MAXIMIZE" "MAXIMIZING" "MINIMIZE" "MINIMIZING")) :minmax)
                                       (t :list))))
                   (if (and entry (not (eq (car (cdr (cdr entry))) category)))
                       (zl-sys::%macro-form-error "LOOP で種類の違う集め方を同じ変数に使っています" kind))
                   (if (null entry) (setq entry (list var (gensym "TAIL") category))))
                 (if (not (member entry bound-accumulators))
                     (progn
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
             ;; it は、条件の直後の最初の句の中でだけ使える（CLHS 6.1.6.2。and の後ろと else の後ろでは使えない。
             ;; agy のレビュー 0.3 #5）
             (parse-clause-group (it outer)
               (setq it-var it)
               (let ((forms (parse-selectable)))
                 (setq it-var outer)
                 (tagbody
                  next
                    (if (at "AND")
                        (progn (next) (setq forms (append forms (parse-selectable))) (go next))))
                 forms))
             (parse-conditional (kw)
               (let ((test (need-form kw)) (saved it-var) (then nil) (else nil) (it (gensym "IT")))
                 (bind it nil)
                 (setq then (parse-clause-group it saved))
                 (if (at "ELSE") (progn (next) (setq else (parse-clause-group saved saved))))
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
           ;; with 変数 [型] [= 初期値] {and …}：分解（(a b)・(a . b)・nil）と、and による並列の束縛（初期値をすべて
           ;; 一時変数に入れてから変数を束縛する。CLHS 6.1.2.2。agy のレビュー 0.3 #3）
           ((at "WITH")
            (next)
            (let ((group nil))
              (tagbody
               more
                 (let* ((var (next)) (type (skip-type)) (init (if (at "=") (progn (next) (need-form "WITH")) (type-default type))))
                   (setq group (cons (list var init (gensym "WITH")) group)))
                 (if (at "AND") (progn (next) (go more))))
              (setq group (reverse group))
              (if (cdr group)
                  (progn
                    (dolist (g group) (bind (car (cdr (cdr g))) (car (cdr g))))
                    (dolist (g group) (bind-destructuring (car g) (car (cdr (cdr g))))))
                  (bind-destructuring (car (car group)) (car (cdr (car group)))))))
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


;;; ---------------------------------------------------------------------------
;;; 列・リスト・集合（Phase 21。CLHS 14 章・17 章）
;;; find・position・remove・sort などの列の関数は Zig（seqfns.zig）。ここには、リスト・集合・木の関数と、
;;; それらを使うマクロ（pushnew・remf）、列の場所（elt・subseq）を書く。
;;; 集合の関数の結果の順序は、SBCL 2.6.7 と同じにする（CLHS では処理系依存）。

(defsetf elt zl-sys::%set-elt)
(defsetf subseq (sequence start &optional end) (new)
  `(progn (replace ,sequence ,new :start1 ,start :end1 ,end) ,new))

(defun identity (object) object)

(defun complement (function)
  (lambda (&rest arguments) (not (apply function arguments))))

(defun constantly (value)
  (lambda (&rest arguments) (declare (ignore arguments)) value))

(defun acons (key datum alist) (cons (cons key datum) alist))

(defun pairlis (keys data &optional alist)
  ;; SBCL 2.6.7 と同じく、前の組から順に alist の前に積む（結果は逆順）
  (do ((k keys (cdr k)) (d data (cdr d)) (result alist))
      ((or (endp k) (endp d))
       (if (or k d) (zl-sys::%macro-form-error "PAIRLIS のキーと値の数が違います" (list keys data)))
       result)
    (setq result (acons (car k) (car d) result))))

(defun copy-alist (alist)
  (mapcar (lambda (x) (if (consp x) (cons (car x) (cdr x)) x)) alist))

(defun copy-tree (tree)
  (if (consp tree) (cons (copy-tree (car tree)) (copy-tree (cdr tree))) tree))

(defun revappend (list tail)
  (do ((x list (cdr x)) (result tail (cons (car x) result)))
      ((endp x) result)))

(defun nreconc (list tail)
  (nconc (nreverse list) tail))

;; butlast・nbutlast はドット対で終わるリストも受け付ける（cons の数で数える。CLHS butlast。Codex のレビュー P21 #7）
(defun zl-sys::%cons-count (list)
  (do ((x list (cdr x)) (n 0 (1+ n)))
      ((atom x) n)))

;; n は負でない整数。0 ならドット対の末尾も保つ（SBCL と同じ。Codex のレビュー 0.3 #7・#10）
(defun butlast (list &optional (n 1))
  (if (not (and (integerp n) (>= n 0))) (zl-sys::%type-error n 'unsigned-byte))
  (if (eql n 0) (return-from butlast (copy-list list)))
  (let ((len (zl-sys::%cons-count list)))
    (if (<= len n)
        nil
        (let ((head nil) (tail nil) (x list))
          (dotimes (i (- len n) head)
            (let ((c (cons (car x) nil)))
              (if tail (rplacd tail c) (setq head c))
              (setq tail c x (cdr x))))))))

(defun nbutlast (list &optional (n 1))
  (if (not (and (integerp n) (>= n 0))) (zl-sys::%type-error n 'unsigned-byte))
  (if (eql n 0) (return-from nbutlast list))
  (let ((len (zl-sys::%cons-count list)))
    (if (<= len n)
        nil
        (progn (rplacd (nthcdr (- len n 1) list) nil) list))))

(defun tailp (object list)
  (do ((x list (cdr x)))
      ((atom x) (eql x object))
    (if (eql x object) (return t))))

(defun ldiff (list object)
  (let ((head nil) (tail nil))
    (do ((x list (cdr x)))
        ((atom x)
         ;; ドット対の終わりが object でなければ、それも残す
         (if (and x (not (eql x object)))
             (if tail (rplacd tail x) (setq head x)))
         head)
      (if (eql x object) (return head))
      (let ((c (cons (car x) nil)))
        (if tail (rplacd tail c) (setq head c))
        (setq tail c)))))

;; 写像（CLHS mapl・maplist・mapcon）：関数にリストの残りの部分を渡す
(defun mapl (function list &rest more-lists)
  (do ((lists (cons list more-lists) (zl-sys::%cdrs lists)))
      ((zl-sys::%any-endp lists) list)
    (apply function lists)))

(defun maplist (function list &rest more-lists)
  (let ((head nil) (tail nil))
    (do ((lists (cons list more-lists) (zl-sys::%cdrs lists)))
        ((zl-sys::%any-endp lists) head)
      (let ((c (cons (apply function lists) nil)))
        (if tail (rplacd tail c) (setq head c))
        (setq tail c)))))

(defun mapcon (function list &rest more-lists)
  (apply #'nconc (apply #'maplist function list more-lists)))

;; 木（CLHS subst・sublis・tree-equal）。変わらない部分は元の木を共有する
(defun zl-sys::%subst (new pred tree key)
  (cond ((funcall pred (if key (funcall key tree) tree)) new)
        ((atom tree) tree)
        (t (let ((a (zl-sys::%subst new pred (car tree) key))
                 (d (zl-sys::%subst new pred (cdr tree) key)))
             (if (and (eq a (car tree)) (eq d (cdr tree))) tree (cons a d))))))

(defun zl-sys::%test-function (test test-not)
  (cond ((and test test-not) (zl-sys::%macro-form-error ":test と :test-not は同時に指定できません" (list test test-not)))
        (test-not (lambda (a b) (not (funcall test-not a b))))
        (test test)
        (t #'eql)))

(defun subst (new old tree &key key test test-not)
  (let ((f (zl-sys::%test-function test test-not)))
    (zl-sys::%subst new (lambda (x) (funcall f old x)) tree key)))

(defun subst-if (new predicate tree &key key)
  (zl-sys::%subst new predicate tree key))

(defun subst-if-not (new predicate tree &key key)
  (zl-sys::%subst new (complement predicate) tree key))

;; nsubst の仲間は、木の car・cdr を書き換える（根そのものを置き換えるときは new を返す。CLHS nsubst。
;; Codex のレビュー P21 #3）。cdr の向きは繰り返しでたどる（長いリストでも深い再帰にしない）
(defun zl-sys::%nsubst (new pred tree key)
  (cond ((funcall pred (if key (funcall key tree) tree)) new)
        ((atom tree) tree)
        (t (let ((x tree))
             (loop
               (rplaca x (zl-sys::%nsubst new pred (car x) key))
               (let ((d (cdr x)))
                 (cond ((funcall pred (if key (funcall key d) d)) (rplacd x new) (return))
                       ((atom d) (return))
                       (t (setq x d))))))
           tree)))

(defun nsubst (new old tree &key key test test-not)
  (let ((f (zl-sys::%test-function test test-not)))
    (zl-sys::%nsubst new (lambda (x) (funcall f old x)) tree key)))

(defun nsubst-if (new predicate tree &key key)
  (zl-sys::%nsubst new predicate tree key))

(defun nsubst-if-not (new predicate tree &key key)
  (zl-sys::%nsubst new (complement predicate) tree key))

(defun sublis (alist tree &key key test test-not)
  (let ((f (zl-sys::%test-function test test-not)))
    (labels ((walk (x)
               (let ((pair (assoc (if key (funcall key x) x) alist :test f)))
                 (cond (pair (cdr pair))
                       ((atom x) x)
                       (t (let ((a (walk (car x))) (d (walk (cdr x))))
                            (if (and (eq a (car x)) (eq d (cdr x))) x (cons a d))))))))
      (walk tree))))

;; nsublis は木の car・cdr を書き換える（CLHS nsublis）
(defun nsublis (alist tree &key key test test-not)
  (let ((f (zl-sys::%test-function test test-not)))
    (labels ((lookup (x) (assoc (if key (funcall key x) x) alist :test f))
             (walk (x)
               (let ((pair (lookup x)))
                 (cond (pair (cdr pair))
                       ((atom x) x)
                       (t (let ((y x))
                            (loop
                              (rplaca y (walk (car y)))
                              (let* ((d (cdr y)) (dp (lookup d)))
                                (cond (dp (rplacd y (cdr dp)) (return))
                                      ((atom d) (return))
                                      (t (setq y d))))))
                          x)))))
      (walk tree))))

(defun tree-equal (tree-1 tree-2 &key test test-not)
  (let ((f (zl-sys::%test-function test test-not)))
    (labels ((walk (a b)
               (cond ((and (consp a) (consp b)) (and (walk (car a) (car b)) (walk (cdr a) (cdr b))))
                     ((or (consp a) (consp b)) nil)
                     ;; 比較の関数の多値を漏らさない（Codex のレビュー P21 #8）
                     (t (if (funcall f a b) t nil)))))
      (walk tree-1 tree-2))))

;; 集合（CLHS 14.1.2）。要素の比較は (funcall test (key x) (key y))
(defun zl-sys::%set-member (item list key test test-not)
  (if key
      (member (funcall key item) list :key key :test (zl-sys::%test-function test test-not))
      (member item list :test (zl-sys::%test-function test test-not))))

(defun adjoin (item list &key key test test-not)
  (if (zl-sys::%set-member item list key test test-not) list (cons item list)))

;; list-2 の要素 item が list-1 にあるか（比較の引数は list-1 の要素が先：CLHS 17.2.1）
(defun zl-sys::%set-member-flipped (item list key test test-not)
  (let ((f (zl-sys::%test-function test test-not)))
    (member (if key (funcall key item) item) list :key key :test (lambda (a b) (funcall f b a)))))

;; 短い方のリストの要素で調べ、長い方のリストの前に積む（長さが同じなら list-2 の要素を list-1 の前に。SBCL 2.6.7 と同じ順序）
(defun union (list-1 list-2 &key key test test-not)
  (cond ((null list-1) list-2)
        ((null list-2) list-1)
        ((< (length list-2) (length list-1))
         (let ((result list-2))
           (dolist (x list-1 result)
             (unless (zl-sys::%set-member x list-2 key test test-not) (setq result (cons x result))))))
        (t
         (let ((result list-1))
           (dolist (x list-2 result)
             (unless (zl-sys::%set-member-flipped x list-1 key test test-not) (setq result (cons x result))))))))

(defun nunion (list-1 list-2 &key key test test-not)
  (union list-1 list-2 :key key :test test :test-not test-not))

(defun intersection (list-1 list-2 &key key test test-not)
  (let ((result nil))
    (if list-2
        (dolist (x list-1)
          (if (zl-sys::%set-member x list-2 key test test-not) (setq result (cons x result)))))
    result))

(defun nintersection (list-1 list-2 &key key test test-not)
  (intersection list-1 list-2 :key key :test test :test-not test-not))

(defun set-difference (list-1 list-2 &key key test test-not)
  (if (null list-2)
      list-1
      (let ((result nil))
        (dolist (x list-1 result)
          (unless (zl-sys::%set-member x list-2 key test test-not) (setq result (cons x result)))))))

(defun nset-difference (list-1 list-2 &key key test test-not)
  (set-difference list-1 list-2 :key key :test test :test-not test-not))

(defun set-exclusive-or (list-1 list-2 &key key test test-not)
  (let ((result nil))
    (dolist (x list-1)
      (unless (zl-sys::%set-member x list-2 key test test-not) (setq result (cons x result))))
    (dolist (x list-2)
      (unless (zl-sys::%set-member-flipped x list-1 key test test-not) (setq result (cons x result))))
    result))

(defun nset-exclusive-or (list-1 list-2 &key key test test-not)
  (set-exclusive-or list-1 list-2 :key key :test test :test-not test-not))

(defun subsetp (list-1 list-2 &key key test test-not)
  (dolist (x list-1 t)
    (unless (zl-sys::%set-member x list-2 key test test-not) (return nil))))

;; (pushnew 要素 場所 &key key test test-not)：場所のリストになければ前に加える
(defmacro pushnew (item place &rest keys)
  (let ((g (gensym)))
    (if (symbolp place)
        `(let ((,g ,item)) (setq ,place (adjoin ,g ,place ,@keys)))
        (destructuring-bind (temps vals stores store-form access) (zl-sys::%setf-expansion place)
          `(let* ((,g ,item) ,@(zl-sys::%zip temps vals) (,(car stores) (adjoin ,g ,access ,@keys)))
             ,store-form)))))

;; (remf 場所 指示子)：属性リストから指示子の組を除く。除いたら T
(defun zl-sys::%remf (plist indicator)
  ;; 新しい属性リストと、除いたかどうか
  (do ((x plist (cddr x)) (prev nil x))
      ((atom x) (values plist nil))
    (when (eq (car x) indicator)
      (if prev
          (progn (rplacd (cdr prev) (cddr x)) (return (values plist t)))
          (return (values (cddr x) t))))))

;; 評価の順序：場所の部分のフォーム、指示子、場所の読み出し（CLHS 5.1.1.1。Codex のレビュー P21 #4）
(defmacro remf (place indicator)
  (destructuring-bind (temps vals stores store-form access) (zl-sys::%setf-expansion place)
    (let ((removed (gensym)) (ind (gensym)))
      `(let* (,@(zl-sys::%zip temps vals) (,ind ,indicator))
         (multiple-value-bind (,(car stores) ,removed) (zl-sys::%remf ,access ,ind)
           ,store-form
           ,removed)))))

;; (merge 型 列1 列2 述語 &key key)：安定に併合する（同じなら列1 の要素が先）
(defun merge (result-type sequence-1 sequence-2 predicate &key key)
  (let ((a (coerce sequence-1 'list)) (b (coerce sequence-2 'list)) (result nil))
    (loop
      (cond ((null a) (return))
            ((null b) (return))
            ((funcall predicate (if key (funcall key (car b)) (car b)) (if key (funcall key (car a)) (car a)))
             (setq result (cons (car b) result) b (cdr b)))
            (t (setq result (cons (car a) result) a (cdr a)))))
    (coerce (nreconc result (if a a b)) result-type)))

;;; ---------------------------------------------------------------------------
;;; Phase 22：パッケージ（CLHS 11 章。関数は src/primitives/packages.zig）

;; (in-package 名前)：*package* を名前のパッケージにする。コンパイル時にも評価する（後のフォームの読み方が変わる）
(defmacro in-package (name)
  `(eval-when (:compile-toplevel :load-toplevel :execute)
     (setq *package* (zl-sys::%find-package-or-lose ,(string name)))))

;; defpackage のオプションの名前（文字列指定子）を文字列にする
(defun zl-sys::%defpackage-names (option)
  (mapcar #'string (cdr option)))

;; 名前の集まりが互いに重ならないことを確かめる（CLHS defpackage）
(defun zl-sys::%defpackage-disjoint (what-a a what-b b)
  (dolist (x a)
    (when (member x b :test #'string=)
      (zl-sys::%macro-form-error
       (concatenate 'string "DEFPACKAGE の " what-a " と " what-b " に同じ名前があります") x))))

;; (defpackage 名前 オプション...)：:nicknames :use :shadow :shadowing-import-from :import-from :intern :export
;; :documentation :size、SBCL 2.6.7 の拡張 :local-nicknames。:use がなければ何も use しない（SBCL と同じ）
(defmacro defpackage (name &rest options)
  (let ((nicknames nil) (use nil) (use-p nil) (shadow nil) (shadowing-imports nil) (imports nil)
        (interns nil) (exports nil) (local-nicknames nil) (doc-p nil) (size-p nil))
    (dolist (opt options)
      (unless (and (consp opt) (keywordp (car opt)))
        (zl-sys::%macro-form-error "DEFPACKAGE のオプションが正しくありません" opt))
      (case (car opt)
        (:nicknames (setq nicknames (append nicknames (zl-sys::%defpackage-names opt))))
        (:use (setq use-p t use (append use (zl-sys::%defpackage-names opt))))
        (:shadow (setq shadow (append shadow (zl-sys::%defpackage-names opt))))
        (:shadowing-import-from
         ;; パッケージの指定がなければエラー（agy のレビュー 0.3 #13）
         (unless (consp (cdr opt)) (zl-sys::%macro-form-error "DEFPACKAGE の :shadowing-import-from にパッケージがありません" opt))
         (push (cons (string (cadr opt)) (mapcar #'string (cddr opt))) shadowing-imports))
        (:import-from
         ;; パッケージの指定がなければエラー（agy のレビュー 0.3 #13）
         (unless (consp (cdr opt)) (zl-sys::%macro-form-error "DEFPACKAGE の :import-from にパッケージがありません" opt))
         (push (cons (string (cadr opt)) (mapcar #'string (cddr opt))) imports))
        (:intern (setq interns (append interns (zl-sys::%defpackage-names opt))))
        (:export (setq exports (append exports (zl-sys::%defpackage-names opt))))
        (:local-nicknames
         (dolist (pair (cdr opt))
           (unless (and (consp pair) (consp (cdr pair)) (null (cddr pair)))
             (zl-sys::%macro-form-error "DEFPACKAGE の :local-nicknames の指定が正しくありません" pair))
           (push (cons (string (car pair)) (string (cadr pair))) local-nicknames)))
        (:documentation
         (when doc-p (zl-sys::%macro-form-error "DEFPACKAGE の :documentation は1回だけ指定できます" opt))
         ;; 引数はちょうど1つの文字列（SBCL 2.6.7：個数の誤りは program-error、文字列でなければ type-error。
         ;; Codex のレビュー P22 #6）
         (unless (and (consp (cdr opt)) (null (cddr opt)))
           (zl-sys::%macro-form-error "DEFPACKAGE の :documentation には文字列を1つ指定します" opt))
         (unless (stringp (cadr opt)) (zl-sys::%type-error (cadr opt) 'string))
         (setq doc-p t))
        (:size
         (when size-p (zl-sys::%macro-form-error "DEFPACKAGE の :size は1回だけ指定できます" opt))
         (unless (and (consp (cdr opt)) (null (cddr opt)) (integerp (cadr opt)) (>= (cadr opt) 0))
           (zl-sys::%macro-form-error "DEFPACKAGE の :size には負でない整数を1つ指定します" opt))
         (setq size-p t))
        (t (zl-sys::%macro-form-error "DEFPACKAGE の知らないオプションです" opt))))
    (let ((shadowing-names (mapcan (lambda (s) (copy-list (cdr s))) shadowing-imports))
          (import-names (mapcan (lambda (s) (copy-list (cdr s))) imports)))
      (zl-sys::%defpackage-disjoint ":shadow" shadow ":shadowing-import-from" shadowing-names)
      (zl-sys::%defpackage-disjoint ":shadow" shadow ":import-from" import-names)
      (zl-sys::%defpackage-disjoint ":shadow" shadow ":intern" interns)
      (zl-sys::%defpackage-disjoint ":shadowing-import-from" shadowing-names ":import-from" import-names)
      (zl-sys::%defpackage-disjoint ":shadowing-import-from" shadowing-names ":intern" interns)
      (zl-sys::%defpackage-disjoint ":import-from" import-names ":intern" interns)
      (zl-sys::%defpackage-disjoint ":intern" interns ":export" exports))
    `(eval-when (:compile-toplevel :load-toplevel :execute)
       (zl-sys::%defpackage ,(string name) ',nicknames ',use ',use-p ',shadow
                            ',(reverse shadowing-imports) ',(reverse imports) ',interns ',exports
                            ',(reverse local-nicknames)))))

;; (do-symbols (変数 &optional パッケージ 結果) 本体...)：アクセスできるシンボルを1つずつ
(defmacro do-symbols ((var &optional (package '*package*) result) &body body)
  `(dolist (,var (zl-sys::%package-symbols ,package :accessible) ,result) ,@body))

;; (do-external-symbols (変数 &optional パッケージ 結果) 本体...)：外部シンボルを1つずつ
(defmacro do-external-symbols ((var &optional (package '*package*) result) &body body)
  `(dolist (,var (zl-sys::%package-symbols ,package :external) ,result) ,@body))

;; (do-all-symbols (変数 &optional 結果) 本体...)：すべてのパッケージにあるシンボル（同じシンボルが何度も現れてよい）
(defmacro do-all-symbols ((var &optional result) &body body)
  `(dolist (,var (zl-sys::%all-package-symbols) ,result) ,@body))

;;; ---------------------------------------------------------------------------
;;; Phase 23：ストリーム（CLHS 21 章。関数は src/primitives/streams.zig）

;; (with-open-file (変数 ファイル オプション...) 本体...)：抜けるときに閉じる（エラー・脱出で抜けたら :abort t）
(defmacro with-open-file ((var filespec &rest options) &body body)
  (let ((abortp (gensym "ABORTP")))
    `(let ((,var (open ,filespec ,@options)) (,abortp t))
       ,@(zl-sys::%body-declarations body)
       (unwind-protect
            (multiple-value-prog1 (progn ,@(zl-sys::%body-forms body)) (setq ,abortp nil))
         (when ,var (close ,var :abort ,abortp))))))

;; (with-open-stream (変数 ストリーム) 本体...)
(defmacro with-open-stream ((var stream) &body body)
  (let ((abortp (gensym "ABORTP")))
    `(let ((,var ,stream) (,abortp t))
       ,@(zl-sys::%body-declarations body)
       (unwind-protect
            (multiple-value-prog1 (progn ,@(zl-sys::%body-forms body)) (setq ,abortp nil))
         (when ,var (close ,var :abort ,abortp))))))

;; (with-output-to-string (変数 &optional 文字列 &key element-type) 本体...)：書いた文字列を返す。
;; 文字列（fill-pointer のある文字列に書き足す形）は未実装
(defmacro with-output-to-string ((var &optional string &key element-type) &body body)
  (declare (ignore element-type))
  (when string
    (zl-sys::%unimplemented-error "WITH-OUTPUT-TO-STRING に文字列を渡すのは未実装です" string))
  `(let ((,var (make-string-output-stream)))
     ,@(zl-sys::%body-declarations body)
     (unwind-protect
          (progn ,@(zl-sys::%body-forms body) (get-output-stream-string ,var))
       (close ,var))))

;; (with-input-from-string (変数 文字列 &key start end index) 本体...)：:index は未実装
(defmacro with-input-from-string ((var string &key (start 0) end index) &body body)
  (when index
    (zl-sys::%unimplemented-error "WITH-INPUT-FROM-STRING の :index は未実装です" index))
  `(let ((,var (make-string-input-stream ,string ,start ,end)))
     ,@(zl-sys::%body-declarations body)
     (unwind-protect
          (progn ,@(zl-sys::%body-forms body))
       (close ,var))))

;; (formatter 制御文字列)：(funcall 関数 ストリーム 引数...) で format と同じに書き、残りの引数を返す関数（CLHS formatter。Phase 24）
(defmacro formatter (control-string)
  `(function (lambda (stream &rest args)
               (zl-sys::%format-rest stream ,control-string args))))

;; (setf (readtable-case readtable) 値)（Phase 24）
(defsetf readtable-case zl-sys::%set-readtable-case)

;; (with-standard-io-syntax 本体...)：印字と読み取りの変数を標準の値に束縛する（CLHS with-standard-io-syntax。Phase 24）
(defmacro with-standard-io-syntax (&body body)
  `(let ((*package* (find-package "COMMON-LISP-USER"))
         (*print-array* t) (*print-base* 10) (*print-case* :upcase) (*print-circle* nil) (*print-escape* t)
         (*print-gensym* t) (*print-length* nil) (*print-level* nil) (*print-lines* nil) (*print-miser-width* nil)
         (*print-pprint-dispatch* zl-sys::*standard-pprint-dispatch-table*)
         (*print-pretty* nil) (*print-radix* nil) (*print-readably* t) (*print-right-margin* nil)
         (*read-base* 10) (*read-default-float-format* 'single-float) (*read-eval* t) (*read-suppress* nil)
         (*readtable* zl-sys::*standard-readtable*))
     ,@body))

;; pretty printer（Phase 24）。(pprint-logical-block (stream-symbol object &key prefix per-line-prefix suffix) 本体...)
;; 本体は (lambda (stream list state) …) にして zl-sys::%pprint-logical-block に渡す。pprint-pop と
;; pprint-exit-if-list-exhausted は、その lambda が束縛する zl-sys::%pp-list・%pp-state と block zl-sys::%pp-block を使う
;; （macrolet がないため。入れ子にしても内側の束縛が見える）。object がなければ %pp-list は zl-sys::%no-list
(defmacro pprint-logical-block ((stream-symbol object &key (prefix nil prefix-p) (per-line-prefix nil per-line-p) (suffix ""))
                                &body body)
  (when (and prefix-p per-line-p)
    (zl-sys::%unimplemented-error "PPRINT-LOGICAL-BLOCK に :prefix と :per-line-prefix の両方は指定できません" prefix))
  (let ((stream-var (cond ((null stream-symbol) '*standard-output*)
                          ((eq stream-symbol t) '*terminal-io*)
                          (t stream-symbol))))
    `(zl-sys::%pprint-logical-block
      ,stream-symbol ,(if object object ''zl-sys::%no-list)
      ,(if per-line-p per-line-prefix prefix) ,(if per-line-p t nil) ,suffix
      (lambda (,stream-var zl-sys::%pp-list zl-sys::%pp-state)
        (declare (ignorable ,stream-var zl-sys::%pp-list zl-sys::%pp-state))
        (block zl-sys::%pp-block ,@body))
      ,(if object t nil))))

(defmacro pprint-exit-if-list-exhausted ()
  '(when (or (null zl-sys::%pp-list) (eq zl-sys::%pp-list 'zl-sys::%no-list))
     (return-from zl-sys::%pp-block nil)))

(defmacro pprint-pop ()
  '(if (eq zl-sys::%pp-list 'zl-sys::%no-list)
       (if (zl-sys::%pprint-length-check* zl-sys::%pp-state) nil (return-from zl-sys::%pp-block nil))
       (if (zl-sys::%pprint-length-check zl-sys::%pp-list zl-sys::%pp-state)
           (pop zl-sys::%pp-list)
           (return-from zl-sys::%pp-block nil))))
