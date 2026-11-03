;; 読み込まれる側のファイル（tests/language/eval/multi-file.lisp が load する。拡張子が .lisp でないのは、
;; 言語試験の実行器がこのファイルを試験として扱わないようにするため）
(defpackage :mf.utils (:use :cl) (:export :double :*base*))
(in-package :mf.utils)
(defparameter *base* 10)
(defun double (x) (* 2 x))
(defun helper () :hidden)
