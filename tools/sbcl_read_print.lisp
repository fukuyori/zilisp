;;;; SBCL で、ファイルのデータを読み、1つずつ prin1 で印字する（zilisp --read と同じ処理）。
;;;; 言語試験 tests/language/reader/ の期待値（*.expected）を作るのに使う。
;;;;
;;;; 使い方:
;;;;   sbcl --script tools/sbcl_read_print.lisp FILE > FILE.expected
;;;;
;;;; *print-pretty* は偽、*package* は CL-USER、*read-default-float-format* は single-float とする。

(let ((path (second sb-ext:*posix-argv*))
      (*package* (find-package "COMMON-LISP-USER"))
      (*print-pretty* nil)
      (*read-default-float-format* 'single-float))
  (with-open-file (in path :external-format :utf-8)
    (loop for form = (read in nil in)
          until (eq form in)
          do (prin1 form)
             (terpri))))
