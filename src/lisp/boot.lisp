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


;; 場所の一時変数を束縛し、value の値で格納の変数を束縛して body を評価するフォーム。格納の変数がちょうど 1 個でなければ
;; （(values) は 0 個、(values a b) は 2 個）value の多値で束縛する（足りない値は NIL。CLHS 5.1.2.3。Codex のレビュー P25 5回目 #1・#2）
(defun zl-sys::%bind-stores (temps vals stores value body)
  (if (and stores (null (cdr stores)))
      `(let* (,@(zl-sys::%zip temps vals) (,(car stores) ,value)) ,@body)
      `(let* ,(zl-sys::%zip temps vals)
         (multiple-value-bind ,stores ,value ,@body))))

(defun zl-sys::%expand-setf (place value)
  (if (symbolp place)
      `(setq ,place ,value)
      (destructuring-bind (temps vals stores store-form access) (zl-sys::%setf-expansion place)
        (declare (ignore access))
        (zl-sys::%bind-stores temps vals stores value (list store-form)))))

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
                            ;; Codex のレビュー P25 6回目 #1：内側の格納の変数をすべて束縛し、足りない値は NIL にする
                            (zl-sys::%bind-stores nil nil stores `(zl-sys::%putf ,access ,itemp ,store)
                                                  (list store-form store))
                            `(getf ,access ,itemp ,dtemp)))))))

;; 場所を更新するマクロ（CLHS 5.1.2：場所の部分のフォームは1回だけ、左から順に評価する）
;; incf・decf の展開。増やす量は場所の部分の後、場所の値を読む前に評価する（増やす量が場所を書き換えても、書き換えた後の
;; 値に足す。SBCL 2.6.7 と同じ。Codex のレビュー P25 7回目 #1）。増やす量が数なら一時変数を使わない
(defun zl-sys::%expand-incf (op place delta)
  (let ((d (if (numberp delta) delta (gensym "DELTA"))))
    (if (symbolp place)
        (if (numberp delta)
            `(setq ,place (,op ,place ,d))
            `(let ((,d ,delta)) (setq ,place (,op ,place ,d))))
        (destructuring-bind (temps vals stores store-form access) (zl-sys::%setf-expansion place)
          (if (numberp delta)
              (zl-sys::%bind-stores temps vals stores `(,op ,access ,d) (list store-form))
              (zl-sys::%bind-stores (append temps (list d)) (append vals (list delta)) stores `(,op ,access ,d)
                                    (list store-form)))))))

(defmacro incf (place &optional (delta 1))
  (zl-sys::%expand-incf '+ place delta))

(defmacro decf (place &optional (delta 1))
  (zl-sys::%expand-incf '- place delta))

;; push：item は場所の部分より先に評価する（CLHS push）
(defmacro push (item place)
  (if (symbolp place)
      `(setq ,place (cons ,item ,place))
      (let ((g (gensym)))
        (destructuring-bind (temps vals stores store-form access) (zl-sys::%setf-expansion place)
          (zl-sys::%bind-stores (cons g temps) (cons item vals) stores `(cons ,g ,access) (list store-form))))))

(defmacro pop (place)
  (let ((g (gensym)))
    (if (symbolp place)
        `(let ((,g ,place))
           (setq ,place (cdr ,g))
           (car ,g))
        (destructuring-bind (temps vals stores store-form access) (zl-sys::%setf-expansion place)
          (zl-sys::%bind-stores (append temps (list g)) (append vals (list access)) stores `(cdr ,g)
                                (list store-form `(car ,g)))))))

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
       (if (null (cdr p)) (zl-sys::%macro-simple-error "PSETQ の引数は変数と値の組です" pairs))
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
        (zl-sys::%macro-simple-error "DO の終了の節はリストでなければなりません" end-clause))
    (dolist (s specs)
      (cond ((symbolp s) (setq bindings (cons s bindings)))
            ;; (変数 [初期値 [更新]])：変数はシンボル、長さ 1〜3 の真のリスト（SBCL と同じくそれ以外はエラー）
            ((and (consp s)
                  (or (not (symbolp (car s)))
                      (not (listp (cdr s)))
                      (and (cdr s) (not (listp (cdr (cdr s)))))
                      (and (cdr s) (cdr (cdr s)) (cdr (cdr (cdr s))))))
             (zl-sys::%macro-simple-error "DO の変数の指定が正しくありません" s))
            ((consp s)
             (setq bindings (cons (if (cdr s) (list (car s) (car (cdr s))) (list (car s))) bindings))
             (if (cdr (cdr s))
                 (setq steps (cons (car (cdr (cdr s))) (cons (car s) steps)))))
            (t (zl-sys::%macro-simple-error "DO の変数の指定が正しくありません" s))))
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

;; (setf (values 場所 …) 値)：各場所に多値の各値を入れ、入れた値を多値で返す（CLHS 5.1.2.3。Codex のレビュー P25 4回目 #5）。
;; 場所の格納の変数の2つ目以降は NIL にする。dolist・mapcar を使うので、それらの定義の後ろに置く
(define-setf-expander values (&rest places)
  (let ((temps nil) (vals nil) (stores nil) (sets nil) (gets nil) (results nil))
    (dolist (p places)
      (destructuring-bind (ts vs ss sf af) (zl-sys::%setf-expansion p)
        (setq temps (append temps ts)
              vals (append vals vs)
              ;; Codex のレビュー P25 6回目 #2：格納の変数がなければ値を消費せず、その位置には NIL を返す
              stores (append stores (if ss (list (car ss)) nil))
              results (append results (list (car ss)))
              sets (append sets (list (if (cdr ss)
                                          `(let ,(mapcar (lambda (s) (list s nil)) (cdr ss)) ,sf)
                                          sf)))
              gets (append gets (list af)))))
    (values temps vals stores `(progn ,@sets (values ,@results)) `(values ,@gets))))

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
             ;; 初期値のない with：パターンの変数ごとに、型（パターンと同じ形の型のリストか、全体に1つの型）の既定値
             (bind-defaults (pat type)
               (cond ((null pat))
                     ((symbolp pat) (bind pat (type-default type)))
                     ((consp pat)
                      (bind-defaults (car pat) (if (consp type) (car type) type))
                      (bind-defaults (cdr pat) (if (consp type) (cdr type) type)))
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
                            ;; CLHS 6.1.2.1.7 の symbol の種類と SBCL 2.6.7 の拡張の elements は未実装。それ以外の名前は形の誤り
                            ;; （Codex のレビュー P25 5回目 #6）
                            ((zl-sys::%loop-keyword-p kind '("SYMBOL" "SYMBOLS" "PRESENT-SYMBOL" "PRESENT-SYMBOLS"
                                                              "EXTERNAL-SYMBOL" "EXTERNAL-SYMBOLS" "ELEMENT" "ELEMENTS"))
                             (zl-sys::%unimplemented-error "LOOP の being のこの種類は未実装です" kind))
                            (t (zl-sys::%macro-form-error "LOOP の being の種類が正しくありません" kind)))
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
                     (start (gensym "START")) (lim (gensym "LIMIT")) (stp (gensym "STEP")) (down nil) (test nil))
                 (if (not (and var (symbolp var)))
                     (zl-sys::%macro-form-error "LOOP の for の数の変数はシンボルでなければなりません" var))
                 (tagbody
                  next
                    (cond ((at "FROM" "UPFROM" "DOWNFROM")
                           (if has-start (zl-sys::%macro-form-error "LOOP の for の開始の値が2つあります" (peek)))
                           (setq start-dir (cond ((at "UPFROM") :up) ((at "DOWNFROM") :down) (t nil)))
                           (next) (setq has-start t) (bind start (need-form "FROM")))
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
                 ;; ループの変数は、部分節の式をすべて評価した後で束縛する（to・by の式は外側の同じ名前の変数を見る。
                 ;; SBCL と同じ。Codex のレビュー 0.3 修正の修正 #1）
                 (bind var (if has-start start 0))
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
             (parse-clause-group (it)
               (setq it-var it)
               (let ((forms (parse-selectable)))
                 ;; 入れ子の条件の and・else の後ろでも、外側の条件の it は使えない（SBCL と同じ。Codex のレビュー 0.3
                 ;; 修正の修正 #2）
                 (setq it-var nil)
                 (tagbody
                  next
                    (if (at "AND")
                        (progn (next) (setq forms (append forms (parse-selectable))) (go next))))
                 forms))
             (parse-conditional (kw)
               ;; 条件の式も、外側の条件の直後の最初の句なら it を使える（SBCL と同じ。Codex のレビュー 0.3 修正 #5）
               (let ((test (parse-form-or-it kw)) (saved it-var) (then nil) (else nil) (it (gensym "IT")))
                 (bind it nil)
                 (setq then (parse-clause-group it))
                 (if (at "ELSE") (progn (next) (setq else (parse-clause-group nil))))
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
                 (let* ((var (next)) (type (skip-type)))
                   (if (at "=")
                       (progn (next) (setq group (cons (list var (need-form "WITH") (gensym "WITH")) group)))
                       ;; 初期値がなければ、パターンの変数ごとに型による既定値（(a b) of-type fixnum は 0 と 0。
                       ;; SBCL の loop-make-var と同じ。Codex のレビュー 0.3 修正 #4）
                       (setq group (cons (list var nil nil type) group))))
                 (if (at "AND") (progn (next) (go more))))
              (setq group (reverse group))
              (if (cdr group)
                  (progn
                    (dolist (g group) (if (car (cdr (cdr g))) (bind (car (cdr (cdr g))) (car (cdr g)))))
                    (dolist (g group)
                      (if (car (cdr (cdr g)))
                          (bind-destructuring (car g) (car (cdr (cdr g))))
                          (bind-defaults (car g) (car (cdr (cdr (cdr g))))))))
                  (if (car (cdr (cdr (car group))))
                      (bind-destructuring (car (car group)) (car (cdr (car group))))
                      (bind-defaults (car (car group)) (car (cdr (cdr (cdr (car group))))))))))
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
           ;; CLHS の句はすべて上で扱う。ここに来るのは書き間違いか位置の誤り（先頭でない named など）で、SBCL と同じ
           ;; program-error（Codex のレビュー P25 4回目 #3・5回目 #6）
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
    ;; 指定の誤り（未実装ではない）。SBCL 2.6.7 と同じ simple-error（Codex のレビュー P25 4回目 #3）
    (zl-sys::%macro-simple-error "PPRINT-LOGICAL-BLOCK に :prefix と :per-line-prefix の両方は指定できません" prefix))
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

;;; ---------------------------------------------------------------------------
;;; Phase 25：condition・handler・restart（CLHS 9 章。詳細設計 §9）
;;; condition と restart は record（Zig の zl-sys::%make-record。src/primitives/conditions.zig）で表し、CLOS（Phase 27）で
;;; instance にまとめる。クラスの記述は simple-vector で、クラスの名前のシンボルの属性 zl-sys::%class に置く：
;;;   #(名前 CPL 直接の上位 スロット report 既定の initarg 直接のスロット)
;;;   CPL は自身を含む上位のクラスの名前のリスト（具体的な方から。位置 0・1 は Zig の typep と印字が読む）、
;;;   スロットは (名前 initarg のリスト initform の関数か NIL) のリスト（上位のクラスのスロットを含む。値のベクタの順）、
;;;   report は文字列・関数・NIL、既定の initarg は (initarg 関数 …)。
;;; handler：zl-sys::*handler-clusters* は cluster（((型 . 関数) …)）のリスト（新しい順）。handler-bind が動的に束縛する。
;;; restart：zl-sys::*restart-clusters* は cluster（restart のリスト）のリスト。restart-bind が動的に束縛する。
;;; どちらも動的束縛なので、非局所脱出で抜けると一緒に戻る。
;;; Zig で見つけたエラー（th.signal）は、handler・restart があるときだけ zl-sys::%signal-zig-error で condition にして通知する
;;; （受け止められなければ、Zig の側でトップレベルへ戻る。報告の文面は今までと同じ）。
;;; 標準の condition の report の文面は SBCL 2.6.7 に合わせる。

(defvar zl-sys::*handler-clusters* nil)
(defvar zl-sys::*restart-clusters* nil)
(defvar *debugger-hook* nil)
(defvar *break-on-signals* nil)

(export (intern "UNIMPLEMENTED" "ZILISP") "ZILISP")

;; クラスの記述。なければ（errorp が真なら）simple-type-error（SBCL 2.6.7 と同じ文面）
(defun zl-sys::%find-class (name &optional (errorp t))
  (let ((class (if (and name (symbolp name)) (get name 'zl-sys::%class) nil)))
    (cond (class class)
          (errorp (error 'simple-type-error
                         :datum name :expected-type '(satisfies zl-sys::%condition-class-name-p)
                         :format-control "~S does not designate a condition class."
                         :format-arguments (list name)))
          (t nil))))

(defun zl-sys::%condition-class-name-p (name)
  (let ((class (zl-sys::%find-class name nil)))
    (if (and class (member 'condition (svref class 1))) t nil)))

;; CPL：深さ優先・左から右に並べ、重なりは最後のものを残す（菱形の継承で共通の上位を後ろに置く）
(defun zl-sys::%compute-cpl (name supers)
  (let ((all (cons name (mapcan (lambda (s) (copy-list (svref (zl-sys::%find-class s) 1))) supers)))
        (result nil))
    (do ((x all (cdr x)))
        ((null x) (nreverse result))
      (unless (member (car x) (cdr x)) (push (car x) result)))))

;; 上位のクラスから順に、スロットを名前でまとめる（initarg は合わせ、initform は具体的なクラスのものを使う）
(defun zl-sys::%effective-slots (cpl)
  (let ((slots nil))
    (dolist (cname (reverse cpl))
      (dolist (d (svref (zl-sys::%find-class cname) 6))
        (let ((e (assoc (car d) slots)))
          (if e
              (progn
                (dolist (a (cadr d)) (unless (member a (cadr e)) (setf (cadr e) (append (cadr e) (list a)))))
                (if (caddr d) (setf (caddr e) (caddr d))))
              (setq slots (append slots (list (list (car d) (copy-list (cadr d)) (caddr d)))))))))
    slots))

(defun zl-sys::%effective-default-initargs (cpl)
  (let ((result nil))
    (dolist (cname cpl)
      (do ((x (svref (zl-sys::%find-class cname) 5) (cddr x)))
          ((null x))
        (unless (zl-sys::%plist-has result (car x))
          (setq result (append result (list (car x) (cadr x)))))))
    result))

(defun zl-sys::%plist-has (plist key)
  (do ((x plist (cddr x)))
      ((null x) nil)
    (if (eq (car x) key) (return t))))

;; クラスを定義する（define-condition の展開先）。direct-slots は (名前 initarg のリスト initform の関数か NIL) のリスト
(defun zl-sys::%define-condition-class (name parents direct-slots report default-initargs)
  (let* ((supers (cond (parents parents) ((member name '(condition restart)) nil) (t '(condition))))
         (class (vector name nil supers nil report default-initargs direct-slots)))
    (dolist (s supers) (zl-sys::%find-class s))
    (setf (get name 'zl-sys::%class) class)
    (setf (svref class 1) (zl-sys::%compute-cpl name supers))
    (setf (svref class 3) (zl-sys::%effective-slots (svref class 1)))
    (setf (svref class 5) (zl-sys::%effective-default-initargs (svref class 1)))
    name))

;; initarg のリスト keys のどれかの値（最初に現れたもの）。なければ zl-sys::%missing
(defun zl-sys::%initarg-value (initargs keys)
  (do ((x initargs (cddr x)))
      ((null x) 'zl-sys::%missing)
    (if (member (car x) keys) (return (cadr x)))))

(defun make-condition (type &rest initargs)
  (let* ((class (zl-sys::%find-class type))
         (slots (svref class 3))
         (defaults (svref class 5))
         (slot-values (make-array (length slots) :initial-element 'zl-sys::%unbound-slot))
         (i 0))
    (unless (member 'condition (svref class 1))
      (error 'simple-type-error
             :datum type :expected-type '(satisfies zl-sys::%condition-class-name-p)
             :format-control "~S does not designate a condition class." :format-arguments (list type)))
    (dolist (s slots)
      (let ((v (zl-sys::%initarg-value initargs (cadr s))))
        (if (eq v 'zl-sys::%missing)
            (let ((d (zl-sys::%initarg-value defaults (cadr s))))
              (cond ((not (eq d 'zl-sys::%missing)) (setf (svref slot-values i) (funcall d)))
                    ((caddr s) (setf (svref slot-values i) (funcall (caddr s))))))
            (setf (svref slot-values i) v)))
      (setq i (1+ i)))
    (zl-sys::%make-record class slot-values)))

(defun zl-sys::%slot-index (class name)
  (let ((i 0))
    (dolist (s (svref class 3) nil)
      (if (eq (car s) name) (return i))
      (setq i (1+ i)))))

;; condition のスロットの値（スロットの reader・accessor の展開先）。type はスロットを持つクラスの名前
(defun zl-sys::%condition-slot (c name type)
  (unless (typep c type) (error 'type-error :datum c :expected-type type))
  (let ((v (svref (zl-sys::%record-slots c) (zl-sys::%slot-index (zl-sys::%record-class c) name))))
    (if (eq v 'zl-sys::%unbound-slot)
        (error 'unbound-slot :name name :instance c)
        v)))

(defun zl-sys::%set-condition-slot (value c name type)
  (unless (typep c type) (error 'type-error :datum c :expected-type type))
  (setf (svref (zl-sys::%record-slots c) (zl-sys::%slot-index (zl-sys::%record-class c) name)) value))

;; スロットの値。値がなければ default（印字に使う）
(defun zl-sys::%slot-or (c name default)
  (let ((i (zl-sys::%slot-index (zl-sys::%record-class c) name)))
    (if i
        (let ((v (svref (zl-sys::%record-slots c) i)))
          (if (eq v 'zl-sys::%unbound-slot) default v))
        default)))

;; (define-condition 名前 (上位 …) (スロット …) オプション …)：スロットのオプションは :initarg・:initform・:reader・
;; :writer・:accessor（:type・:documentation・:allocation は受け付けて使わない）。オプションは :report・:default-initargs・
;; :documentation
(defmacro define-condition (name parent-types slot-specs &rest options)
  (let ((slots nil) (functions nil) (report nil) (defaults nil))
    (dolist (spec slot-specs)
      (let ((sname (if (consp spec) (car spec) spec))
            (initargs nil) (initform nil) (has-initform nil))
        (do ((o (if (consp spec) (cdr spec) nil) (cddr o)))
            ((null o))
          (let ((key (car o)) (val (cadr o)))
            (cond ((eq key :initarg) (push val initargs))
                  ((eq key :initform) (setq initform val has-initform t))
                  ((eq key :reader)
                   (push `(defun ,val (condition) (zl-sys::%condition-slot condition ',sname ',name)) functions))
                  ((eq key :writer)
                   (push `(defun ,val (value condition) (zl-sys::%set-condition-slot value condition ',sname ',name)) functions))
                  ((eq key :accessor)
                   (push `(defun ,val (condition) (zl-sys::%condition-slot condition ',sname ',name)) functions)
                   (push `(defun (setf ,val) (value condition) (zl-sys::%set-condition-slot value condition ',sname ',name))
                         functions))
                  ((member key '(:type :documentation :allocation)))
                  (t (zl-sys::%macro-form-error "DEFINE-CONDITION のスロットのオプションが正しくありません" spec)))))
        (push `(list ',sname ',(reverse initargs) ,(if has-initform `(lambda () ,initform) nil)) slots)))
    (dolist (o options)
      (cond ((not (consp o)) (zl-sys::%macro-form-error "DEFINE-CONDITION のオプションが正しくありません" o))
            ((eq (car o) :report)
             (let ((r (cadr o)))
               (setq report (cond ((stringp r) r)
                                  ((symbolp r) `',r)
                                  (t `(function ,r))))))
            ((eq (car o) :default-initargs)
             (do ((x (cdr o) (cddr x)))
                 ((null x))
               (setq defaults (append defaults (list `',(car x) `(lambda () ,(cadr x)))))))
            ((eq (car o) :documentation))
            (t (zl-sys::%macro-form-error "DEFINE-CONDITION のオプションが正しくありません" o))))
    `(progn
       (zl-sys::%define-condition-class ',name ',parent-types (list ,@(reverse slots)) ,report (list ,@defaults))
       ,@(reverse functions)
       ',name)))

;;; 標準の condition 型（CLHS 9.2）。report の文面は SBCL 2.6.7 と同じ

(zl-sys::%define-condition-class 'condition nil nil nil nil)
(define-condition serious-condition (condition) ())
(define-condition error (serious-condition) ())
(define-condition warning (condition) ())
(define-condition style-warning (warning) ())
(define-condition storage-condition (serious-condition) ())

(define-condition simple-condition (condition)
  ((format-control :initarg :format-control :initform nil :reader simple-condition-format-control)
   (format-arguments :initarg :format-arguments :initform nil :reader simple-condition-format-arguments))
  (:report (lambda (condition stream)
             (let ((control (simple-condition-format-control condition)))
               (if control
                   (apply #'format stream control (simple-condition-format-arguments condition)))))))

(define-condition simple-error (simple-condition error) ())
(define-condition simple-warning (simple-condition warning) ())

(define-condition type-error (error)
  ((datum :initarg :datum :reader type-error-datum)
   (expected-type :initarg :expected-type :reader type-error-expected-type))
  (:report (lambda (condition stream)
             (format stream "~@<The value ~@:_~2@T~S ~@:_is not of type ~@:_~2@T~S~:@>"
                     (type-error-datum condition) (type-error-expected-type condition)))))

(define-condition simple-type-error (simple-condition type-error) ())
(define-condition program-error (error) ())
(define-condition control-error (error) ())
(define-condition parse-error (error) ())

(define-condition cell-error (error)
  ((name :initarg :name :reader cell-error-name)))

;; 名前をパッケージ付きで書く（SBCL の print-symbol-with-prefix）
(defun zl-sys::%prin1-with-prefix (name stream)
  (let ((*package* (find-package "KEYWORD")))
    (prin1 name stream)))

(define-condition unbound-variable (cell-error) ()
  (:report (lambda (condition stream)
             (format stream "The variable ~S is unbound." (cell-error-name condition)))))

(define-condition undefined-function (cell-error) ()
  (:report (lambda (condition stream)
             (write-string "The function " stream)
             (zl-sys::%prin1-with-prefix (cell-error-name condition) stream)
             (write-string " is undefined." stream))))

(define-condition unbound-slot (cell-error)
  ((instance :initarg :instance :reader unbound-slot-instance))
  (:report (lambda (condition stream)
             (write-string "The slot " stream)
             (zl-sys::%prin1-with-prefix (cell-error-name condition) stream)
             (format stream " is unbound in the object ~S." (unbound-slot-instance condition)))))

(define-condition arithmetic-error (error)
  ((operation :initarg :operation :initform nil :reader arithmetic-error-operation)
   (operands :initarg :operands :initform nil :reader arithmetic-error-operands))
  (:report (lambda (condition stream)
             (format stream "arithmetic error ~S signalled" (zl-sys::%condition-type condition))
             (if (arithmetic-error-operation condition)
                 (format stream "~%Operation was (~S~{ ~S~})."
                         (arithmetic-error-operation condition) (arithmetic-error-operands condition))))))

(define-condition division-by-zero (arithmetic-error) ())
(define-condition floating-point-overflow (arithmetic-error) ())
(define-condition floating-point-underflow (arithmetic-error) ())
(define-condition floating-point-inexact (arithmetic-error) ())
(define-condition floating-point-invalid-operation (arithmetic-error) ())

(define-condition package-error (error)
  ((package :initarg :package :reader package-error-package)))

(define-condition stream-error (error)
  ((stream :initarg :stream :reader stream-error-stream)))

(define-condition end-of-file (stream-error) ()
  (:report (lambda (condition stream)
             (format stream "end of file on ~S" (stream-error-stream condition)))))

(define-condition reader-error (parse-error stream-error) ())

(define-condition file-error (error)
  ((pathname :initarg :pathname :reader file-error-pathname))
  (:report (lambda (condition stream)
             (format stream "error on file ~S" (file-error-pathname condition)))))

(define-condition print-not-readable (error)
  ((object :initarg :object :reader print-not-readable-object))
  (:report (lambda (condition stream)
             (let ((*print-readably* nil))
               (format stream "~S cannot be printed readably." (print-not-readable-object condition))))))

;; Zilisp の condition 型（Zig で見つけたエラーの説明の文を持つもの。SBCL の SB-INT:SIMPLE-PROGRAM-ERROR などに当たる）
(define-condition zl-sys::simple-program-error (simple-condition program-error) ())
(define-condition zl-sys::simple-control-error (simple-condition control-error) ())
(define-condition zl-sys::simple-parse-error (simple-condition parse-error) ())
(define-condition zl-sys::simple-reader-error (simple-condition reader-error) ())
(define-condition zl-sys::simple-package-error (simple-condition package-error) ())
(define-condition zl-sys::simple-stream-error (simple-condition stream-error) ())
(define-condition zl-sys::simple-end-of-file (simple-condition end-of-file) ())
(define-condition zl-sys::simple-file-error (simple-condition file-error) ())
(define-condition zl-sys::simple-storage-condition (simple-condition storage-condition) ())
(define-condition zl-sys::simple-print-not-readable (simple-condition print-not-readable) ())
(define-condition zl-sys::simple-arithmetic-error (simple-condition arithmetic-error) ())
;; 未実装の機能（基本設計 §3.1）
;; error の下位にしない（ignore-errors・(handler-case … (error …)) が未実装を黙って受け止めないように。基本設計 §3.1
;; 「黙って別の値を返さない」。2026-11-05 の決定）。serious-condition なので、handler がなければトップレベルまで届く
(define-condition zilisp:unimplemented (simple-condition serious-condition) ())

;; ecase・etypecase などの漏れ（SBCL の SB-KERNEL:CASE-FAILURE と同じ文面）
(define-condition zl-sys::case-failure (type-error)
  ((name :initarg :name :reader zl-sys::case-failure-name)
   (possibilities :initarg :possibilities :reader zl-sys::case-failure-possibilities))
  (:report (lambda (condition stream)
             (format stream "~@<~S fell through ~S expression. ~:_Wanted one of ~:S.~:>"
                     (type-error-datum condition) (zl-sys::case-failure-name condition)
                     (zl-sys::case-failure-possibilities condition)))))

;;; report と印字

(defun zl-sys::%condition-type (c)
  (svref (zl-sys::%record-class c) 0))

;; CPL の具体的な方から、最初に report を持つクラスの report を使う
(defun zl-sys::%report-condition (c stream)
  (let ((report nil))
    (dolist (name (svref (zl-sys::%record-class c) 1))
      (let ((r (svref (zl-sys::%find-class name) 4)))
        (when r
          (setq report r)
          (return))))
    (cond ((stringp report) (write-string report stream))
          (report (funcall report c stream))
          (t (let ((*package* (find-package "COMMON-LISP")))
               (format stream "Condition ~S was signalled." (zl-sys::%condition-type c)))))))

;; #<…> の形（SBCL 2.6.7 と同じ形。アドレスは Zilisp のもの）
(defun zl-sys::%print-condition-unreadably (c stream)
  (let ((name (zl-sys::%condition-type c))
        (address (zl-sys::%object-address c)))
    (cond ((typep c 'type-error)
           (format stream "#<~S expected-type: ~S datum: ~S>" name
                   (zl-sys::%slot-or c 'expected-type nil) (zl-sys::%slot-or c 'datum nil)))
          ((typep c 'simple-condition)
           (format stream "#<~S ~S {~X}>" name (zl-sys::%slot-or c 'format-control nil) address))
          ((typep c 'cell-error)
           (format stream "#<~S ~S {~X}>" name (zl-sys::%slot-or c 'name nil) address))
          (t (format stream "#<~S {~X}>" name address)))))

;; record（condition・restart）の印字（Zig の印字の入口が呼ぶ：src/printer/pprint.zig の outputUgly）
(defun zl-sys::%print-record (object stream)
  (cond (*print-readably* (error 'print-not-readable :object object))
        ((typep object 'restart)
         (if *print-escape*
             (format stream "#<RESTART ~S {~X}>" (restart-name object) (zl-sys::%object-address object))
             (zl-sys::%report-restart object stream)))
        (*print-escape* (zl-sys::%print-condition-unreadably object stream))
        (t (zl-sys::%report-condition object stream))))

;;; restart（CLHS 9.1.4.2）。スロットは 名前・関数・report の関数・interactive の関数・test の関数・関連付けた condition

(zl-sys::%define-condition-class 'restart nil nil nil nil)

(defun zl-sys::%make-restart (name function report interactive test)
  (zl-sys::%make-record (get 'restart 'zl-sys::%class) (vector name function report interactive test nil)))

(defun zl-sys::%restart-slots (restart)
  (unless (typep restart 'restart) (error 'type-error :datum restart :expected-type 'restart))
  (zl-sys::%record-slots restart))

(defun restart-name (restart)
  (svref (zl-sys::%restart-slots restart) 0))

(defun zl-sys::%report-restart (restart stream)
  (let ((report (svref (zl-sys::%restart-slots restart) 2)))
    (if report
        (funcall report stream)
        (format stream "~A" (restart-name restart)))))

;; (restart-bind ((名前 関数 &key :interactive-function :report-function :test-function) …) 本体 …)
(defmacro restart-bind (bindings &body forms)
  `(let ((zl-sys::*restart-clusters*
           (cons (list ,@(mapcar (lambda (b)
                                   (destructuring-bind (name function &key interactive-function report-function test-function) b
                                     `(zl-sys::%make-restart ',name ,function ,report-function ,interactive-function
                                                             ,test-function)))
                                 bindings))
                 zl-sys::*restart-clusters*)))
     ,@forms))

;; condition に関連付けた restart は、その condition を指定したときだけ見える（CLHS 9.1.4.2.4）
(defun zl-sys::%restart-applicable-p (restart condition)
  (let* ((s (zl-sys::%record-slots restart))
         (associated (svref s 5))
         (test (svref s 4)))
    (and (or (null condition) (null associated) (member condition associated))
         (or (null test) (funcall test condition)))))

(defun compute-restarts (&optional condition)
  (let ((result nil))
    (dolist (cluster zl-sys::*restart-clusters*)
      (dolist (r cluster)
        (if (zl-sys::%restart-applicable-p r condition) (push r result))))
    (nreverse result)))

(defun find-restart (identifier &optional condition)
  (if (typep identifier 'restart)
      (if (member identifier (compute-restarts condition)) identifier nil)
      (dolist (r (compute-restarts condition) nil)
        (if (eq (restart-name r) identifier) (return r)))))

;; restart のオブジェクトは、いま有効か（束縛の中にあるか）だけを見る。:test を condition なしで呼び直すと、
;; condition を指定して見つけた restart を拒否してしまう（Codex のレビュー P25 10回目。SBCL 2.6.7 と同じ）
(defun zl-sys::%restart-active-p (restart)
  (dolist (cluster zl-sys::*restart-clusters* nil)
    (if (member restart cluster) (return t))))

(defun zl-sys::%find-restart-or-lose (identifier &optional condition)
  (or (if (typep identifier 'restart)
          (if (zl-sys::%restart-active-p identifier) identifier nil)
          (find-restart identifier condition))
      (error 'zl-sys::simple-control-error :format-control "No restart ~S is active." :format-arguments (list identifier))))

(defun invoke-restart (restart &rest arguments)
  (apply (svref (zl-sys::%record-slots (zl-sys::%find-restart-or-lose restart)) 1) arguments))

(defun invoke-restart-interactively (restart)
  (let* ((s (zl-sys::%record-slots (zl-sys::%find-restart-or-lose restart)))
         (interactive (svref s 3)))
    (apply (svref s 1) (if interactive (funcall interactive) nil))))

(defmacro with-condition-restarts (condition-form restarts-form &body body)
  (let ((c (gensym "CONDITION")) (rs (gensym "RESTARTS")))
    `(let ((,c ,condition-form) (,rs ,restarts-form))
       (unwind-protect
            (progn
              (dolist (r ,rs) (push ,c (svref (zl-sys::%record-slots r) 5)))
              ,@body)
         (dolist (r ,rs) (setf (svref (zl-sys::%record-slots r) 5) (remove ,c (svref (zl-sys::%record-slots r) 5) :count 1)))))))

;; restart-case の節の :report・:interactive・:test の値を関数にする
(defun zl-sys::%restart-case-option (key value)
  (cond ((and (eq key :report) (stringp value)) `(lambda (stream) (write-string ,value stream)))
        (t `(function ,value))))

;; (restart-case フォーム (名前 ラムダリスト [:report r] [:interactive i] [:test t] 本体 …) …)。
;; フォームが error・cerror・signal・warn の呼び出しなら、通知する condition に restart を関連付ける（CLHS restart-case）
(defmacro restart-case (restartable-form &rest clauses)
  (let ((block (gensym "BLOCK")) (args (gensym "ARGS")) (bindings nil) (bodies nil))
    (dolist (clause clauses)
      (let ((tag (gensym "TAG")) (temp (gensym "TEMP"))
            (name (car clause)) (lambda-list (cadr clause)) (rest (cddr clause))
            (options nil))
        (do () ((not (and (consp rest) (member (car rest) '(:report :interactive :test)) (consp (cdr rest)))))
          (setq options (append options
                                (list (cdr (assoc (car rest) '((:report . :report-function)
                                                               (:interactive . :interactive-function)
                                                               (:test . :test-function))))
                                      (zl-sys::%restart-case-option (car rest) (cadr rest)))))
          (setq rest (cddr rest)))
        (push `(,name (lambda (&rest ,temp) (setq ,args ,temp) (go ,tag)) ,@options) bindings)
        (push tag bodies)
        (push `(return-from ,block (apply (lambda ,lambda-list ,@rest) ,args)) bodies)))
    ;; フォームはマクロを展開してから調べる（CLHS restart-case。字句的なマクロはないので、大域のマクロだけを展開する）
    (let* ((expanded (macroexpand restartable-form))
           (form (if (and (consp expanded) (member (car expanded) '(error cerror signal warn)))
                     (zl-sys::%restart-case-signaling-form expanded)
                     restartable-form)))
      `(block ,block
         (let ((,args nil))
           (declare (ignorable ,args))
           (tagbody
              (restart-bind ,(reverse bindings)
                (return-from ,block ,form))
              ,@(reverse bodies)))))))

;; (error 指定子 引数 …) などを、condition を作ってから restart を関連付けて通知する形にする。
;; 引数は書いた順に評価する（cerror の継続の制御文字列が先）
(defun zl-sys::%restart-case-signaling-form (form)
  (let ((op (car form)) (c (gensym "CONDITION")) (control (gensym "CONTROL")))
    (if (eq op 'cerror)
        `(let* ((,control ,(cadr form))
                (,c (zl-sys::%coerce-to-condition ,(caddr form) (list ,@(cdddr form)) 'simple-error)))
           (with-condition-restarts ,c (car zl-sys::*restart-clusters*)
             (cerror ,control ,c)))
        `(let ((,c (zl-sys::%coerce-to-condition ,(cadr form) (list ,@(cddr form))
                                                ',(cdr (assoc op '((error . simple-error) (signal . simple-condition)
                                                                   (warn . simple-warning)))))))
           (with-condition-restarts ,c (car zl-sys::*restart-clusters*)
             (,op ,c))))))

(defmacro with-simple-restart ((restart-name format-control &rest format-arguments) &body forms)
  (let ((stream (gensym "STREAM")))
    `(restart-case (progn ,@forms)
       (,restart-name ()
         :report (lambda (,stream) (format ,stream ,format-control ,@format-arguments))
         (values nil t)))))

;; 標準の restart の関数（CLHS 9.2）。abort・muffle-warning は restart がなければ control-error、
;; continue・store-value・use-value は restart がなければ NIL を返す
;; abort の restart が戻ってきたら control-error（CLHS abort。文面は SBCL 2.6.7 と同じ）
(defun abort (&optional condition)
  (invoke-restart (zl-sys::%find-restart-or-lose 'abort condition))
  (error 'zl-sys::simple-control-error
         :format-control "An ABORT restart was found that failed to transfer control dynamically."))

;; muffle-warning の restart が戻ってきても control-error（SBCL 2.6.7 と同じ種類。SBCL の文面は型宣言によるもの）
(defun muffle-warning (&optional condition)
  (invoke-restart (zl-sys::%find-restart-or-lose 'muffle-warning condition))
  (error 'zl-sys::simple-control-error
         :format-control "A MUFFLE-WARNING restart was found that failed to transfer control dynamically."))

(defun continue (&optional condition)
  (let ((r (find-restart 'continue condition)))
    (if r (invoke-restart r) nil)))

(defun store-value (value &optional condition)
  (let ((r (find-restart 'store-value condition)))
    (if r (invoke-restart r value) nil)))

(defun use-value (value &optional condition)
  (let ((r (find-restart 'use-value condition)))
    (if r (invoke-restart r value) nil)))

;;; handler（CLHS 9.1.4.1）

;; (handler-bind ((型 handler) …) 本体 …)：型は評価しない。handler は評価する
(defmacro handler-bind (bindings &body forms)
  `(let ((zl-sys::*handler-clusters*
           (cons (list ,@(mapcar (lambda (b) `(cons ',(car b) ,(cadr b))) bindings))
                 zl-sys::*handler-clusters*)))
     ,@forms))

;; (handler-case フォーム (型 ([変数]) 本体 …) … [(:no-error ラムダリスト 本体 …)])
(defmacro handler-case (form &rest clauses)
  (let ((no-error (assoc :no-error clauses)))
    (if no-error
        (let ((normal-return (gensym "NORMAL-RETURN")) (error-return (gensym "ERROR-RETURN")))
          `(block ,error-return
             (multiple-value-call (lambda ,(cadr no-error) ,@(cddr no-error))
               (block ,normal-return
                 (return-from ,error-return
                   (handler-case (return-from ,normal-return ,form)
                     ,@(remove no-error clauses)))))))
        (let ((block (gensym "BLOCK")) (var (gensym "CONDITION"))
              (bindings nil) (bodies nil))
          (dolist (clause clauses)
            (let ((tag (gensym "TAG")) (temp (gensym "TEMP")))
              (push `(,(car clause) (lambda (,temp) (setq ,var ,temp) (go ,tag))) bindings)
              (push tag bodies)
              (push `(return-from ,block
                       ,(if (cadr clause)
                            `(let ((,(car (cadr clause)) ,var)) ,@(cddr clause))
                            `(let () ,@(cddr clause))))
                    bodies)))
          `(block ,block
             (let ((,var nil))
               (declare (ignorable ,var))
               (tagbody
                  (handler-bind ,(reverse bindings)
                    (return-from ,block ,form))
                  ,@(reverse bodies))))))))

(defmacro ignore-errors (&body forms)
  (let ((c (gensym "CONDITION")))
    `(handler-case (progn ,@forms)
       (error (,c) (values nil ,c)))))

;;; 通知（CLHS 9.1.4）

;; condition の指定子（condition・型の名前と initarg・format の制御文字列と引数）を condition にする
(defun zl-sys::%coerce-to-condition (datum arguments default-type)
  (cond ((typep datum 'condition) datum)
        ((symbolp datum) (apply #'make-condition datum arguments))
        ((or (stringp datum) (functionp datum))
         (make-condition default-type :format-control datum :format-arguments arguments))
        (t (error 'simple-type-error
                  :datum datum :expected-type '(or string function symbol condition)
                  :format-control "~S is not a condition designator." :format-arguments (list datum)))))

;; handler を新しい順に探して呼ぶ。handler を呼ぶ間は、その cluster より外側の handler だけを有効にする（CLHS 9.1.4.1）
(defun zl-sys::%signal (condition)
  (let ((clusters zl-sys::*handler-clusters*))
    (do () ((null clusters))
      (let ((cluster (car clusters)))
        (setq clusters (cdr clusters))
        (dolist (h cluster)
          (when (typep condition (car h))
            (let ((zl-sys::*handler-clusters* clusters))
              (funcall (cdr h) condition))))))))

(defun signal (datum &rest arguments)
  (zl-sys::%signal (zl-sys::%coerce-to-condition datum arguments 'simple-condition))
  nil)

(defun error (datum &rest arguments)
  (let ((condition (zl-sys::%coerce-to-condition datum arguments 'simple-error)))
    (zl-sys::%signal condition)
    (invoke-debugger condition)))

(defun cerror (continue-format-control datum &rest arguments)
  (let ((condition (zl-sys::%coerce-to-condition datum arguments 'simple-error)))
    (restart-case (with-condition-restarts condition (car zl-sys::*restart-clusters*)
                    (error condition))
      (continue ()
        :report (lambda (stream) (apply #'format stream continue-format-control arguments))
        nil))))

(defun warn (datum &rest arguments)
  (let ((condition (zl-sys::%coerce-to-condition datum arguments 'simple-warning)))
    (unless (typep condition 'warning)
      (error 'type-error :datum condition :expected-type 'warning))
    (restart-case (with-condition-restarts condition (car zl-sys::*restart-clusters*)
                    (zl-sys::%signal condition)
                    (format *error-output* "~&WARNING: ~A~%" condition))
      (muffle-warning ()
        :report "Skip warning."
        nil))
    nil))

;; handler が受け止めなかった：*debugger-hook* を呼び、トップレベルへ戻る（対話的なデバッガはない。
;; 報告に restart の一覧を書く）
(defun invoke-debugger (condition)
  (let ((hook *debugger-hook*))
    (when hook
      (let ((*debugger-hook* nil))
        (funcall hook condition hook))))
  (zl-sys::%unhandled-condition condition (zl-sys::%safe-report condition) (zl-sys::%restart-descriptions condition)))

;; report の文字列（report の中でエラーが起きても報告を続ける）
(defun zl-sys::%safe-report (condition)
  (handler-case (princ-to-string condition)
    (error () (format nil "（~S の report でエラーが起きました）" (zl-sys::%condition-type condition)))))

;; 使える restart の説明（"[名前] report" のリスト）
(defun zl-sys::%restart-descriptions (condition)
  (mapcar (lambda (r)
            (handler-case (format nil "[~A] ~A" (restart-name r) (princ-to-string r))
              (error () (format nil "[~A]" (restart-name r)))))
          (compute-restarts condition)))

;; Zig で見つけたエラーを condition にして handler に通知する（src/runtime/thread.zig の callSignalHook が呼ぶ）。
;; kind はエラーの種類のキーワード、message は説明、datum・expected は値（なければ zl-sys::%missing）。
;; 受け止められなければ、使える restart の説明を返す（Zig の側でエラーを記録してトップレベルへ戻る）
(defun zl-sys::%signal-zig-error (kind message datum expected)
  (let ((condition (zl-sys::%zig-condition kind message datum expected)))
    (zl-sys::%signal condition)
    (let ((hook *debugger-hook*))
      (when hook
        (let ((*debugger-hook* nil))
          (funcall hook condition hook))))
    (zl-sys::%restart-descriptions condition)))

(defun zl-sys::%zig-condition (kind message datum expected)
  (let* ((has-datum (not (eq datum 'zl-sys::%missing)))
         (has-expected (not (eq expected 'zl-sys::%missing)))
         (control (if has-datum "~A: ~S" "~A"))
         (arguments (if has-datum (list message datum) (list message))))
    (flet ((simple (type &rest initargs)
             (apply #'make-condition type :format-control control :format-arguments arguments initargs)))
      (case kind
        (:type-error
         (if (and (equal message "") has-expected)
             (make-condition 'type-error :datum datum :expected-type expected)
             (simple 'simple-type-error :datum (if has-datum datum nil) :expected-type (if has-expected expected t))))
        (:unbound-variable (make-condition 'unbound-variable :name datum))
        (:undefined-function (make-condition 'undefined-function :name datum))
        (:division-by-zero
         (make-condition 'division-by-zero :operation (if has-expected (car expected) nil)
                                           :operands (if has-expected (cdr expected) nil)))
        (:floating-point-overflow (make-condition 'floating-point-overflow))
        (:floating-point-invalid-operation (make-condition 'floating-point-invalid-operation))
        (:program-error (simple 'zl-sys::simple-program-error))
        (:control-error (simple 'zl-sys::simple-control-error))
        (:parse-error (simple 'zl-sys::simple-parse-error))
        (:reader-error (simple 'zl-sys::simple-reader-error :stream (if (and has-datum (streamp datum)) datum nil)))
        (:package-error (simple 'zl-sys::simple-package-error :package (if has-datum datum nil)))
        (:stream-error (simple 'zl-sys::simple-stream-error :stream (if (and has-datum (streamp datum)) datum nil)))
        (:end-of-file
         (if (and has-datum (streamp datum))
             (make-condition 'end-of-file :stream datum)
             (simple 'zl-sys::simple-end-of-file :stream nil)))
        (:file-error (simple 'zl-sys::simple-file-error :pathname (if has-datum datum nil)))
        (:print-not-readable (make-condition 'print-not-readable :object (if has-datum datum nil)))
        (:storage-condition (simple 'zl-sys::simple-storage-condition))
        (:unimplemented (simple 'zilisp:unimplemented))
        ;; COMMON-LISP パッケージの未実装の関数・変数（Zig の callSignalHook が分ける）
        (:unimplemented-function
         (make-condition 'zilisp:unimplemented :format-control "関数 ~S は未実装です" :format-arguments (list datum)))
        (:unimplemented-variable
         (make-condition 'zilisp:unimplemented :format-control "変数 ~S は未実装です" :format-arguments (list datum)))
        (t (simple 'simple-error))))))

;;; 型の分岐と検査（CLHS 5.3・9.2）

(defun zl-sys::%case-failure (name datum expected-type possibilities)
  (error 'zl-sys::case-failure :name name :datum datum :expected-type expected-type :possibilities possibilities))

;; case の節のキーを並べる（ecase の報告に使う）
(defun zl-sys::%case-keys (clauses)
  (mapcan (lambda (c) (if (listp (car c)) (copy-list (car c)) (list (car c)))) clauses))

(defmacro ecase (keyform &rest clauses)
  (let ((v (gensym "KEY")) (keys (zl-sys::%case-keys clauses)))
    `(let ((,v ,keyform))
       (case ,v ,@clauses
         (otherwise (zl-sys::%case-failure 'ecase ,v '(member ,@keys) ',keys))))))

;; otherwise を「どれにも当たらない」節にするのは typecase だけ（otherwise-p）。etypecase・ctypecase では otherwise も
;; 型指定子として扱う（CLHS。SBCL 2.6.7 と同じ。Codex のレビュー P25 4回目 #4）。t は型として常に真なので同じ
(defun zl-sys::%typecase-clauses (v clauses &optional (otherwise-p t))
  (mapcar (lambda (c)
            (if (or (eq (car c) t) (and otherwise-p (eq (car c) 'otherwise)))
                `(t ,@(or (cdr c) '(nil)))
                `((typep ,v ',(car c)) ,@(or (cdr c) '(nil)))))
          clauses))

(defmacro typecase (keyform &rest clauses)
  (let ((v (gensym "KEY")))
    `(let ((,v ,keyform))
       (cond ,@(zl-sys::%typecase-clauses v clauses)))))

(defmacro etypecase (keyform &rest clauses)
  (let ((v (gensym "KEY")) (types (mapcar #'car clauses)))
    `(let ((,v ,keyform))
       (cond ,@(zl-sys::%typecase-clauses v clauses nil)
             (t (zl-sys::%case-failure 'etypecase ,v '(or ,@types) ',types))))))

;; 新しい値を読む（store-value の :interactive）
(defun zl-sys::%read-new-value ()
  (format *query-io* "~&Enter a form to be evaluated: ")
  (force-output *query-io*)
  (list (eval (read *query-io*))))

;; ccase・ctypecase：漏れたら store-value の restart で場所に新しい値を入れて、もう一度分岐する。
;; 場所の部分式（添字など）は、setf の展開で最初に1回だけ評価し、やり直しでも同じ場所を読み書きする。場所を読むのも最初の
;; 1回だけで、store-value の後は格納のフォームの値で分岐をやり直す。格納の変数が複数あれば、足りない値は NIL
;; （どれも SBCL 2.6.7 と同じ。Codex のレビュー P25 2回目 #3・3回目 #1・#2）
(defun zl-sys::%correctable-case (keyplace dispatch)
  (destructuring-bind (temps vals stores store-form access) (zl-sys::%setf-expansion keyplace)
    (let ((block (gensym "BLOCK")) (again (gensym "AGAIN")) (v (gensym "KEY")) (value (gensym "VALUE")))
      `(let* ,(zl-sys::%zip temps vals)
         (let ((,v ,access))
           (block ,block
             (tagbody
                ,again
                (return-from ,block
                  ,(funcall dispatch v
                            `(restart-case ,(funcall dispatch v nil)
                               (store-value (,value)
                                 :report (lambda (stream) (format stream "Supply a new value for ~S." ',keyplace))
                                 :interactive zl-sys::%read-new-value
                                 (setq ,v (multiple-value-bind ,stores (values ,value) ,store-form))
                                 (go ,again))))))))))))

(defmacro ccase (keyplace &rest clauses)
  (let ((keys (zl-sys::%case-keys clauses)))
    ;; dispatch：漏れたときのフォーム fallback が NIL なら、漏れの通知そのもの
    (zl-sys::%correctable-case
     keyplace
     (lambda (v fallback)
       (if fallback
           `(case ,v ,@clauses (otherwise ,fallback))
           `(zl-sys::%case-failure 'ccase ,v '(member ,@keys) ',keys))))))

(defmacro ctypecase (keyplace &rest clauses)
  (let ((types (mapcar #'car clauses)))
    (zl-sys::%correctable-case
     keyplace
     (lambda (v fallback)
       (if fallback
           `(cond ,@(zl-sys::%typecase-clauses v clauses nil) (t ,fallback))
           `(zl-sys::%case-failure 'ctypecase ,v '(or ,@types) ',types))))))

;; (check-type 場所 型 [型の説明])：型でなければ store-value の restart のある simple-type-error（SBCL と同じ文面）
(defun zl-sys::%check-type-error (place value type type-string)
  (restart-case
      (error 'simple-type-error
             :datum value :expected-type type
             :format-control (if type-string
                                 "The value of ~S is ~S, which is not ~A."
                                 "The value of ~S is ~S, which is not of type ~S.")
             :format-arguments (list place value (or type-string type)))
    (store-value (new-value)
      :report (lambda (stream) (format stream "Supply a new value for ~S." place))
      :interactive zl-sys::%read-new-value
      new-value)))

;; 場所は確かめるたびに1回読む（SBCL 2.6.7 と同じく、store-value の後は部分式を評価し直す。CLHS check-type）
(defmacro check-type (place type &optional type-string)
  (let ((v (gensym "VALUE")))
    `(do ((,v ,place ,place)) ((typep ,v ',type) nil)
       (setf ,place (zl-sys::%check-type-error ',place ,v ',type ,type-string)))))

;; (assert テスト [場所のリスト [指定子 引数 …]])：偽なら continue の restart のあるエラー（場所の値を尋ねることはしない）。
;; テストが関数の呼び出しなら、定数でない引数の値を報告に含める（SBCL 2.6.7 と同じ文面：failed with X = 3.）
(defun zl-sys::%assert-error (assertion values datum arguments)
  (restart-case
      (if datum
          (apply #'error datum arguments)
          (error 'simple-error
                 :format-control "The assertion ~S failed~:[.~:; with ~:*~{~S = ~S~^, ~}.~]"
                 :format-arguments (list assertion values)))
    (continue ()
      :report "Retry assertion."
      nil)))

(defun zl-sys::%constant-form-p (form)
  (or (keywordp form) (member form '(t nil)) (numberp form) (stringp form) (characterp form)
      (and (consp form) (eq (car form) 'quote))))

(defmacro assert (test-form &optional places datum &rest arguments)
  (declare (ignore places))
  ;; 引数を先に評価して表示するのは関数の呼び出しだけ。特殊演算子（if・let など）はそのまま評価する（Codex のレビュー P25 11回目）
  (if (and (consp test-form) (symbolp (car test-form)) (fboundp (car test-form)) (not (macro-function (car test-form)))
           (not (special-operator-p (car test-form))))
      (let* ((temps (mapcar (lambda (a) (declare (ignore a)) (gensym "ARG")) (cdr test-form)))
             (shown (mapcan (lambda (a temp) (if (zl-sys::%constant-form-p a) nil (list `',a temp)))
                            (cdr test-form) temps)))
        `(do () (nil)
           (let ,(mapcar #'list temps (cdr test-form))
             (if (,(car test-form) ,@temps) (return nil))
             (zl-sys::%assert-error ',test-form (list ,@shown) ,datum (list ,@arguments)))))
      `(do () (,test-form nil)
         (zl-sys::%assert-error ',test-form nil ,datum (list ,@arguments)))))
