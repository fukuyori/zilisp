;;;; 教材のコードブロックを SBCL で「読み込むだけ」で調べ、分類の候補を出す（詳細設計 §12 の手順 3）。
;;;;
;;;; 使い方:
;;;;   sbcl --script tools/classify_samples/classify.lisp <samples-dir> <source-commit>
;;;;
;;;; <samples-dir> は extract-samples の出力ディレクトリ（index.tsv と blocks/ を含む）。
;;;; 出力（<samples-dir> の下）:
;;;;   classify.tsv     seq, id, status, candidate, forms, packages, note
;;;;   symbols.tsv      symbol, blocks（CL のシンボルを使っているブロックの数）
;;;;   inventory.md     集計（compatibility/curriculum-inventory.md の元）
;;;;   manifest.toml    全ブロックの一覧（compatibility/manifest.toml の元）
;;;;
;;;; 安全のため、フォームは評価しない。*read-eval* を NIL にして #. を禁止する。
;;;; 分類はあくまで候補であり、A〜E の確定は手作業で行う（基本設計 §2.2）。

(defpackage #:zilisp-classify
  (:use #:common-lisp))
(in-package #:zilisp-classify)

(defparameter *external-markers*
  '("QL" "QUICKLISP" "ASDF" "UIOP" "DEXADOR" "DEX" "HUNCHENTOOT" "CL-WHO" "WHO"
    "CL-JSON" "JSON" "JONATHAN" "YASON" "IRONCLAD" "BABEL" "LTK" "BT" "BORDEAUX-THREADS"
    "CL-PPCRE" "PPCRE" "ALEXANDRIA" "SPLIT-SEQUENCE" "LOCAL-TIME" "USOCKET" "FLEXI-STREAMS"
    "DRAKMA" "CLACK" "NINGLE" "SB-EXT" "SB-ALIEN" "SB-THREAD" "SB-IMPL" "SB-POSIX")
  "外部ライブラリ・処理系固有のパッケージ名（候補 C の目安）。")

(defun split-tab (line)
  (loop with start = 0
        for pos = (position #\Tab line :start start)
        collect (subseq line start pos)
        while pos
        do (setf start (1+ pos))))

(defun read-lines (path)
  (with-open-file (in path :external-format :utf-8)
    (loop for line = (read-line in nil) while line
          collect (string-right-trim '(#\Return) line))))

(defun read-file-string (path)
  (with-open-file (in path :external-format :utf-8)
    (let ((s (make-string (file-length in))))
      (subseq s 0 (read-sequence s in)))))

(defvar *cl-symbols* nil "このブロックで使われた CL のシンボル（ハッシュ表）")

(defvar *curriculum-packages* '()
  "教材のどこかの defpackage で定義されているパッケージ名（1 回目の走査で集める）。")

(defun defpackage-names (text)
  "評価せずに読み、(defpackage name ...) の name を集める。読めないところで打ち切る。"
  (let ((*read-eval* nil) (*package* (scratch-package)) (names '()))
    (with-input-from-string (in text)
      (loop (handler-case
                (let ((form (read in nil in)))
                  (when (eq form in) (return))
                  (when (and (consp form) (eq (car form) 'defpackage))
                    (push (string-upcase (string (second form))) names)))
              (error () (return)))))
    names))

(defun short-message (c)
  (let ((s (substitute #\Space #\Tab (substitute #\Space #\Newline (princ-to-string c)))))
    (subseq s 0 (min 120 (length s)))))

(defun note-symbols (form)
  "フォームの中の CL のシンボルを集める（循環構造に備えて訪問済みを記録する）。"
  (let ((seen (make-hash-table :test #'eq)))
    (labels ((walk (x)
               (cond ((symbolp x)
                      (when (and x (eq (symbol-package x) (find-package "COMMON-LISP")))
                        (setf (gethash x *cl-symbols*) t)))
                     ((consp x)
                      (unless (gethash x seen)
                        (setf (gethash x seen) t)
                        (walk (car x))
                        (walk (cdr x))))
                     ((and (vectorp x) (not (stringp x)))
                      (map nil #'walk x)))))
      (walk form))))

(defun scratch-package ()
  "ブロックごとに新しいパッケージで読む（ブロックどうしのシンボルの干渉を避ける）。"
  (let ((name "ZILISP-CLASSIFY-SCRATCH"))
    (when (find-package name) (delete-package name))
    (make-package name :use '("COMMON-LISP"))))

(defun classify-block (text)
  "返り値: status forms packages note"
  (let ((*read-eval* nil)
        (*package* (scratch-package))
        (forms 0)
        (packages '())
        (status "ok")
        (note ""))
    (with-input-from-string (in text)
      (loop
        (handler-case
            (let ((form (read in nil in)))
              (when (eq form in) (return))
              (incf forms)
              (note-symbols form)
              ;; (in-package :foo) / (defpackage :foo ...) は評価しないが、記録する
              (when (and (consp form) (member (car form) '(in-package defpackage)))
                (pushnew (format nil "~A:~A" (car form) (second form)) packages :test #'string=)))
          (sb-int:simple-reader-package-error (c)
            ;; 存在しないパッケージの修飾（foo:bar）。その場所の後ろは読み直せないので打ち切る
            (let* ((p (package-error-package c))
                   (name (string-upcase (if (stringp p) p (princ-to-string p)))))
              (pushnew name packages :test #'string=)
              (setf status (if (member name *curriculum-packages* :test #'string=)
                               "curriculum-package"
                               "package-ref")))
            (return))
          (reader-error (c)
            (setf status "reader-error" note (short-message c))
            (return))
          (end-of-file ()
            (setf status "incomplete")
            (return))
          (error (c)
            (setf status "error" note (short-message c))
            (return)))))
    (values status forms (reverse packages) note)))

(defun mentions-external-p (packages text)
  (or (some (lambda (p) (member p *external-markers* :test #'string=)) packages)
      (search "quickload" text :test #'char-equal)
      (search "asdf:" text :test #'char-equal)))

(defun candidate (status packages text)
  (cond ((mentions-external-p packages text) "C")
        ((string= status "ok") "A")
        ;; 教材の中で定義したパッケージを参照している（複数のブロックをまとめて読み込む必要がある）
        ((string= status "curriculum-package") "A")
        ((string= status "package-ref") "U")   ; 教材の中で定義したパッケージか、外部か、手作業で判断
        (t "D")))

(defun toml-string (s)
  (with-output-to-string (o)
    (write-char #\" o)
    (loop for ch across s
          do (case ch
               (#\" (write-string "\\\"" o))
               (#\\ (write-string "\\\\" o))
               (t (write-char ch o))))
    (write-char #\" o)))

(defun main (samples-dir commit)
  (let* ((dir (pathname (concatenate 'string (string-right-trim "/\\" samples-dir) "/")))
         (rows (rest (read-lines (merge-pathnames "index.tsv" dir))))
         (symbol-counts (make-hash-table :test #'eq))
         (results '()))
    ;; 1 回目の走査：教材の中で定義されているパッケージ名を集める
    (dolist (row rows)
      (let ((seq (first (split-tab row))))
        (dolist (n (defpackage-names
                    (read-file-string (merge-pathnames (format nil "blocks/~A.lisp" seq) dir))))
          (pushnew n *curriculum-packages* :test #'string=))))
    (dolist (row rows)
      (destructuring-bind (seq id path start end lang bytes) (split-tab row)
        (declare (ignore start end lang bytes))
        (let* ((text (read-file-string (merge-pathnames (format nil "blocks/~A.lisp" seq) dir)))
               (*cl-symbols* (make-hash-table :test #'eq)))
          (multiple-value-bind (status forms packages note) (classify-block text)
            (maphash (lambda (k v) (declare (ignore v)) (incf (gethash k symbol-counts 0))) *cl-symbols*)
            (push (list seq id path status (candidate status packages text) forms packages note) results)))))
    (setf results (nreverse results))
    ;; classify.tsv
    (with-open-file (o (merge-pathnames "classify.tsv" dir) :direction :output :if-exists :supersede
                                                           :external-format :utf-8)
      (format o "seq	id	status	candidate	forms	packages	note~%")
      (dolist (r results)
        (destructuring-bind (seq id path status cand forms packages note) r
          (declare (ignore path))
          (format o "~A	~A	~A	~A	~D	~{~A~^,~}	~A~%" seq id status cand forms packages note))))
    ;; symbols.tsv
    (let ((syms '()))
      (maphash (lambda (k v) (push (cons k v) syms)) symbol-counts)
      (setf syms (sort syms (lambda (a b) (or (> (cdr a) (cdr b))
                                              (and (= (cdr a) (cdr b))
                                                   (string< (symbol-name (car a)) (symbol-name (car b))))))))
      (with-open-file (o (merge-pathnames "symbols.tsv" dir) :direction :output :if-exists :supersede
                                                            :external-format :utf-8)
        (format o "symbol	blocks~%")
        (dolist (s syms) (format o "~(~A~)	~D~%" (symbol-name (car s)) (cdr s))))
      ;; inventory.md
      (with-open-file (o (merge-pathnames "inventory.md" dir) :direction :output :if-exists :supersede
                                                             :external-format :utf-8)
        (format o "# 教材サンプルの一覧（自動収集）~%~%")
        (format o "このファイルは `scripts/curriculum-inventory.ps1` が生成する。手で編集しない。~%~%")
        (format o "| 項目 | 値 |~%|---|---|~%")
        (format o "| 教材 | https://github.com/fukuyori/CommonLispBasicMaster |~%")
        (format o "| コミット | `~A` |~%" commit)
        (format o "| 読み込みに使った処理系 | ~A ~A |~%" (lisp-implementation-type) (lisp-implementation-version))
        (format o "| Lisp のブロック | ~D |~%" (length results))
        (format o "| 使われている CL のシンボル | ~D 種類 |~%~%" (length syms))
        (format o "## 分類の候補~%~%")
        (format o "候補は読み込みの結果だけから機械的に決めたものであり、A〜E の確定は手作業で行う（基本設計 §2.2）。~%~%")
        (format o "| 候補 | 意味 | ブロック数 |~%|---|---|---|~%")
        (dolist (c '(("A" "読み込めた（または教材の中で定義したパッケージを参照している）。外部ライブラリの参照なし（A の候補）")
                     ("C" "外部ライブラリ・処理系固有のパッケージへの参照あり（C の候補）")
                     ("U" "存在しないパッケージの修飾あり（教材内で定義したものか外部かを手作業で判断）")
                     ("D" "読み込みに失敗（断片・説明用のコードの候補）")))
          (format o "| ~A | ~A | ~D |~%" (first c) (second c)
                  (count (first c) results :key #'fifth :test #'string=)))
        (format o "~%## 章ごとのブロック数~%~%| 章 | A | C | U | D | 計 |~%|---|---|---|---|---|---|~%")
        (let ((chapters (remove-duplicates (mapcar #'third results) :test #'string= :from-end t)))
          (dolist (ch chapters)
            (let ((rs (remove ch results :key #'third :test-not #'string=)))
              (format o "| ~A | ~{~D~^ | ~} | ~D |~%" ch
                      (mapcar (lambda (c) (count c rs :key #'fifth :test #'string=)) '("A" "C" "U" "D"))
                      (length rs)))))
        (format o "~%## 参照されているパッケージ（in-package・defpackage・修飾）~%~%| パッケージ | ブロック数 |~%|---|---|~%")
        (let ((pk (make-hash-table :test #'equal)))
          (dolist (r results) (dolist (p (seventh r)) (incf (gethash p pk 0))))
          (let ((l '())) (maphash (lambda (k v) (push (cons k v) l)) pk)
            (dolist (e (sort l #'> :key #'cdr)) (format o "| `~A` | ~D |~%" (car e) (cdr e)))))
        (format o "~%## よく使われている CL のシンボル（上位 100）~%~%| シンボル | ブロック数 |~%|---|---|~%")
        (loop for s in syms repeat 100
              do (format o "| `~(~A~)` | ~D |~%" (symbol-name (car s)) (cdr s)))))
    ;; manifest.toml
    (with-open-file (o (merge-pathnames "manifest.toml" dir) :direction :output :if-exists :supersede
                                                            :external-format :utf-8)
      (format o "# 教材サンプルの互換性マニフェスト（基本設計 §21）~%")
      (format o "# scripts/curriculum-inventory.ps1 が生成した初期版。category と status は手作業で更新する。~%")
      (format o "source_repo = \"https://github.com/fukuyori/CommonLispBasicMaster\"~%")
      (format o "source_commit = ~A~%" (toml-string commit))
      (format o "reference_implementation = \"SBCL\"~%")
      (dolist (r results)
        (destructuring-bind (seq id path status cand forms packages note) r
          (declare (ignore seq note forms))
          (format o "~%[[cases]]~%id = ~A~%source = ~A~%candidate = ~A~%category = \"?\"~%read_status = ~A~%"
                  (toml-string id) (toml-string path) (toml-string cand) (toml-string status))
          (when packages
            (format o "packages = [~{~A~^, ~}]~%" (mapcar #'toml-string packages)))
          (format o "status = \"unreviewed\"~%"))))
    (format t "blocks: ~D~%" (length results))
    (dolist (c '("A" "C" "U" "D"))
      (format t "candidate ~A: ~D~%" c (count c results :key #'fifth :test #'string=)))))

(let ((args (rest sb-ext:*posix-argv*)))
  (unless (= (length args) 2)
    (format *error-output* "usage: sbcl --script classify.lisp <samples-dir> <source-commit>~%")
    (sb-ext:exit :code 2))
  (main (first args) (second args)))
