;; Reader の拡張（Phase 24）：readtable、ユーザー定義の reader macro、#.、#n= と #n#、readtable-case、*read-base*、
;; *read-default-float-format*、*read-suppress*、read-delimited-list。期待値は SBCL 2.6.7 と同じ出力。
;; 後ろのフォームの読み方を変える定義は eval-when で囲む（ネイティブのコンパイルは compile-file と同じ意味のため）
(setq *print-pretty* nil)

;; #. と *read-eval*
(print (list '#.(+ 1 2) (read-from-string "#.(list 'a (* 2 3))")))
(print (let ((*read-eval* t)) (read-from-string "(x #.(length \"abc\"))")))

;; #n= と #n#
(print (let ((*print-circle* t)) (prin1-to-string (read-from-string "#1=(a . #1#)"))))
(print (let ((*print-circle* t)) (prin1-to-string (read-from-string "(#1=(x y) #1# #2=\"s\" #2#)"))))
(print (let ((x (read-from-string "(#1=(a) #1# #1#)"))) (list (eq (first x) (second x)) (eq (second x) (third x)))))
(print (let ((*print-circle* t)) (prin1-to-string (read-from-string "#1=#(1 #1# (#1#))"))))
(print (let ((*print-circle* t)) (prin1-to-string (read-from-string "#1=(#2=(1 #2#) #1#)"))))
(print (let ((v (read-from-string "#(#1=(p) #1#)"))) (eq (aref v 0) (aref v 1))))
(print (read-from-string "(#1=10 #1# #2=foo #2#)"))
(print (let ((x '#1=(p q . #1#))) (list (first x) (second x) (eq x (cddr x)))))

;; *read-base*・*read-default-float-format*・*read-suppress*
(print (list (let ((*read-base* 16)) (read-from-string "ff")) (let ((*read-base* 2)) (read-from-string "101"))
             (let ((*read-base* 16)) (read-from-string "10.")) (let ((*read-base* 36)) (read-from-string "zz"))
             (let ((*read-base* 16)) (symbol-name (read-from-string "fg")))))
(print (list (let ((*read-default-float-format* 'double-float)) (eql (read-from-string "1.5") 1.5d0))
             (let ((*read-default-float-format* 'double-float)) (eql (read-from-string "1.5f0") 1.5))
             (eql (read-from-string "1.5") 1.5)))
(print (list (let ((*read-suppress* t)) (read-from-string "(a b foo:bar #\\nosuch 1.2.3)"))
             (let ((*read-suppress* t)) (read-from-string "nosuchpkg::x"))))

;; readtable：標準の readtable の写し、readtablep、readtable-case
(print (list (readtablep *readtable*) (readtablep 'x) (eq *readtable* (copy-readtable)) (readtablep (copy-readtable nil))
             (readtable-case *readtable*) (readtable-case (copy-readtable nil))))
(defun read-with-case (case text)
  (let ((*readtable* (copy-readtable nil)))
    (setf (readtable-case *readtable*) case)
    (symbol-name (read-from-string text))))
(print (list (read-with-case :upcase "Foo") (read-with-case :downcase "FoO") (read-with-case :preserve "FoO")
             (read-with-case :invert "foo") (read-with-case :invert "FOO") (read-with-case :invert "Foo")
             (read-with-case :invert "|foo|x") (read-with-case :downcase "\\Foo")))
(print (let ((*readtable* (copy-readtable nil))) (setf (readtable-case *readtable*) :preserve) (read-from-string "(1E5 1e5 #x1f)")))

;; マクロ文字の関数
(print (multiple-value-list (get-macro-character #\a)))
(print (list (functionp (get-macro-character #\()) (nth-value 1 (get-macro-character #\()) (nth-value 1 (get-macro-character #\#))
             (functionp (get-dispatch-macro-character #\# #\()) (get-dispatch-macro-character #\# #\0)))

;; ユーザー定義のマクロ文字
(eval-when (:compile-toplevel :load-toplevel :execute)
  (setq *readtable* (copy-readtable))
  (set-macro-character #\[ (lambda (stream char) (declare (ignore char)) (read-delimited-list #\] stream t)))
  (set-macro-character #\] (get-macro-character #\)))
  (set-macro-character #\! (lambda (stream char) (declare (ignore char)) (list 'not (read stream t nil t))))
  (set-macro-character #\% (lambda (stream char) (declare (ignore char)) (read-line stream) (values)))
  (set-macro-character #\$ (lambda (stream char) (declare (ignore char)) (list 'dollar (read stream t nil t))) t))
(print '[1 2 [3 4] 5])
(print '(a !b !(c d)))
(print '(1 % this is a comment
         2))
(print '(a$b $c))
(print (read-from-string "[x [y] z]"))
(print (with-input-from-string (s "[1 2] !x rest") (list (read s) (read s) (read s))))
(print (read-from-string "(a!b)"))

;; dispatch のマクロ文字
(eval-when (:compile-toplevel :load-toplevel :execute)
  (set-dispatch-macro-character #\# #\{ (lambda (stream sub arg) (declare (ignore sub)) (list 'braces arg (read-delimited-list #\} stream t))))
  (set-macro-character #\} (get-macro-character #\)))
  (make-dispatch-macro-character #\@)
  (set-dispatch-macro-character #\@ #\v (lambda (stream sub arg) (list 'at sub arg (read stream t nil t)))))
(print '(#{1 2} #3{x}))
(print '(@v1 @7V2))
(print (list (functionp (get-dispatch-macro-character #\@ #\v)) (get-dispatch-macro-character #\@ #\w)))

;; set-syntax-from-char
(eval-when (:compile-toplevel :load-toplevel :execute)
  (set-syntax-from-char #\~ #\')
  (set-syntax-from-char #\_ #\Space))
(print '(~x a_b))
(print (read-from-string "~(1 2)"))

;; reader macro の中で読む：peek-char・read-char・unread-char、#n= の共有（recursive-p）
(eval-when (:compile-toplevel :load-toplevel :execute)
  (set-macro-character #\^ (lambda (stream char)
                             (declare (ignore char))
                             (let ((c (read-char stream)))
                               (if (char= c #\^)
                                   (list 'double (read stream t nil t))
                                   (progn (unread-char c stream) (list 'single (read stream t nil t))))))))
(print '(^x ^^y ^(1 2)))
(print (let ((*print-circle* t)) (prin1-to-string (read-from-string "#1=(a ^#1#)"))))

;; 標準の readtable に戻す
(setq *readtable* (copy-readtable nil))
(print (read-from-string "(a!b [c])"))

;; with-standard-io-syntax
(print (let ((*print-case* :downcase) (*print-base* 16) (*read-base* 16))
         (with-standard-io-syntax (list (prin1-to-string 'abc) (prin1-to-string 255) (read-from-string "10") *print-readably*))))

;; 印字：readtable-case と *print-case* の組み合わせ、標準でない readtable のマクロ文字のエスケープ
(dolist (rc '(:upcase :downcase :preserve :invert))
  (dolist (pc '(:upcase :downcase :capitalize))
    (let ((*readtable* (copy-readtable nil)) (*print-case* pc))
      (setf (readtable-case *readtable*) rc)
      (print (list rc pc (prin1-to-string '|FOO|) (prin1-to-string '|foo|) (prin1-to-string '|Foo|) (prin1-to-string '|FOO-bar|)
                   (prin1-to-string :kw) (prin1-to-string 'cl:car) (princ-to-string '|Foo|) (princ-to-string '|FOO|) (princ-to-string '|foo|)
                   (prin1-to-string '|A1b|))))))
(let ((*readtable* (copy-readtable nil)))
  (set-macro-character #\! (lambda (s c) (declare (ignore s c)) 'bang))
  (set-syntax-from-char #\_ #\Space)
  (print (list (prin1-to-string '|A!B|) (prin1-to-string '|A_B|) (prin1-to-string '|A$B|))))
