;; Unicode の文字の種類と大文字・小文字（Phase 21.5。Unicode 15.0.0）
;; 期待値は SBCL 2.6.7 と同じ。違う行は、tests/differential/impl-dependent.toml に記録した違い（行の前の注釈）。
(setq *print-pretty* nil)
(defun c (x) (if (characterp x) (char-code x) x))

;; Reader は ASCII 以外の小文字も大文字にする。Printer は小文字を含む名前を囲む
(print 'λx)
(print (list 'é '|λ| 'あいう '|Ab|))
(print (format nil "~a ~s ~s ~s" 'αβ 'αβ '|Ab| '|αβ|))

;; 文字の種類
(print (list (alpha-char-p #\あ) (alpha-char-p #\é) (alphanumericp #\٣) (alphanumericp #\Ⅻ) (alpha-char-p #\Ⅻ)))
(print (list (digit-char-p #\٣) (digit-char-p #\٠) (digit-char-p #\７) (digit-char-p #\Ａ 16) (parse-integer "١٢")))
(print (list (upper-case-p #\Σ) (lower-case-p #\ς) (c (char-upcase #\ς)) (c (char-downcase #\Σ)) (both-case-p #\ς)))

;; 大文字・小文字（1 文字から 1 文字への対応で、往復するものだけ）
(print (list (string-upcase "straße ﬁ αβγ") (string-capitalize "élan ΑΒΓ δ") (string-capitalize "あab 1a١b")))
(print (list (c (char-downcase #\İ)) (c (char-upcase #\ı)) (c (char-upcase #\ÿ)) (c (char-downcase #\Ÿ))))
(print (list (char-equal #\K #\k) (char-equal (code-char #x212A) #\k) (both-case-p (code-char #x212A))
             (c (char-downcase (code-char #x212A))) (char-equal #\µ #\Μ)))
(print (list (nstring-upcase (copy-seq "ωmega")) (nstring-downcase (copy-seq "ΩMEGA"))
             (nstring-capitalize (copy-seq "ωμέγα όμικρον"))))

;; 大文字・小文字を区別しない比較・equalp・ハッシュ表
(print (list (char-equal #\Α #\α) (char-lessp #\α #\Β) (string-equal "ÀÉÎ" "àéî") (string-lessp "αβ" "ΑΓ")
             (equalp "Straße" "STRAßE")))
(print (gethash "ÉCOLE" (let ((h (make-hash-table :test 'equalp))) (setf (gethash "école" h) 1) h)))
(print (list (c (find #\É "café" :test #'char-equal)) (position #\Ω "αβω" :test #'char-equal)
             (count-if #'upper-case-p "AÀαΒ")))

;; impl-dependent.toml の char-case-titlecase：SBCL 2.6.7 は (452 T T T T) と (T T T 454)
(print (list (c (char-upcase #\ǅ)) (both-case-p #\ǅ) (char-equal #\ǆ #\Ǆ) (string-equal "ǆ" "Ǆ") (upper-case-p #\Ǆ)))
(print (list (equalp #\ǅ #\ǆ) (equalp "ǅ" "ǆ") (char-equal #\ǅ #\ǆ) (c (char-downcase #\ǅ))))
;; impl-dependent.toml の reader-symbol-normalization：SBCL 2.6.7 は |ǅ| と囲む
(print '|ǅ|)
