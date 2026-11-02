;; エラーで止まるときも、unwind-protect の cleanup を実行してから止まる（終了コード 1）
(print 'before)
(unwind-protect (car 1) (print 'cleanup))
(print 'after)
