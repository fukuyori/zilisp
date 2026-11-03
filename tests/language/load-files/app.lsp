;; 読み込まれる側のファイル：別のファイルのパッケージを use する
(defpackage :mf.app (:use :cl :mf.utils) (:export :run))
(in-package :mf.app)
(defun run (n) (list (double n) *base* (mf.utils::helper) 'done))
