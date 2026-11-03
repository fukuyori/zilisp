;; 複数のファイルの名前の解決（Phase 22 の受入）：load したファイルの defpackage・in-package と、パッケージ修飾。
;; 期待値は SBCL 2.6.7 と同じ出力。作業ディレクトリはリポジトリの直下。
;; load を eval-when で囲むのは、ファイル全体を先にコンパイルするとき（ネイティブ・compile-file）にも、後のフォームを
;; 読む前にパッケージを作るため（CL の書き方。囲まなければ compile-file では読み取りのエラーになる）
(setq *print-pretty* nil)
(eval-when (:compile-toplevel :load-toplevel :execute)
  (print (load "tests/language/load-files/utils.lsp")))
;; load の中の in-package は、load が終われば元に戻る
(print (package-name *package*))
(eval-when (:compile-toplevel :load-toplevel :execute)
  (print (load "tests/language/load-files/app.lsp")))
(print (package-name *package*))
(print (mf.app:run 21))
(print (list (mf.utils:double 4) mf.utils:*base* (mf.utils::helper)))
(print (list (multiple-value-list (find-symbol "DOUBLE" :mf.app)) (multiple-value-list (find-symbol "RUN" :mf.app))
             (multiple-value-list (find-symbol "HELPER" :mf.app))))
(print (list (package-name (symbol-package 'mf.app:run)) (package-name (symbol-package 'mf.app::double))))
(print (load "tests/language/load-files/nope.lsp" :if-does-not-exist nil))
;; 同じファイルをもう一度読み込んでも（defpackage が既にあるパッケージに足すだけ）同じ結果
(print (load "tests/language/load-files/utils.lsp"))
(print (mf.app:run 5))
