;;; src/unicode/testdata/sbcl-2.6.7-chars.txt を作るスクリプト（Phase 21.5）。SBCL 2.6.7 で実行する：
;;;   sbcl --script tools/gen_unicode/sbcl-chars.lisp > src/unicode/testdata/sbcl-2.6.7-chars.txt
;;; 全符号位置について、CL の文字の関数の結果を書き出す。同じ結果が続く範囲ごとに 1 行：
;;;   start end alpha alnum upper lower both graphic digit36 up down
;;; （start・end は 16 進。真偽は 1・0、digit36 は基数 36 の digit-char-p（数字でなければ -1）、
;;;  up・down は char-upcase・char-downcase の符号から自分の符号を引いた値）
(defun tuple (cp)
  (let ((c (code-char cp)))
    (list (if (alpha-char-p c) 1 0)
          (if (alphanumericp c) 1 0)
          (if (upper-case-p c) 1 0)
          (if (lower-case-p c) 1 0)
          (if (both-case-p c) 1 0)
          (if (graphic-char-p c) 1 0)
          (or (digit-char-p c 36) -1)
          (- (char-code (char-upcase c)) cp)
          (- (char-code (char-downcase c)) cp))))

(format t "# SBCL ~A: start end alpha alnum upper lower both graphic digit36 up down~%"
        (lisp-implementation-version))
(let ((start 0) (prev (tuple 0)))
  (loop for cp from 1 below char-code-limit
        for tp = (tuple cp)
        unless (equal tp prev)
          do (format t "~X ~X~{ ~D~}~%" start (1- cp) prev)
             (setf start cp prev tp))
  (format t "~X ~X~{ ~D~}~%" start (1- char-code-limit) prev))
