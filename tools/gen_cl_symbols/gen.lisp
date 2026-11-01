;;;; COMMON-LISP パッケージの外部シンボルの一覧を SBCL から取り出し、
;;;; src/runtime/cl_symbols.zig を生成する（詳細設計 §8.3）。
;;;;
;;;; 使い方:
;;;;   sbcl --script tools/gen_cl_symbols/gen.lisp src/runtime/cl_symbols.zig
;;;;
;;;; 生成するのはシンボルの名前と、SBCL での種類（特殊演算子・マクロ・関数・定数・変数・その他）だけである。
;;;; 種類は「Zilisp が何を実装すべきか」の目安であり、SBCL の実装の詳細は取り込まない。
;;;; ANSI Common Lisp の COMMON-LISP パッケージの外部シンボルは 978 個（CLHS 1.9）。件数が違えば生成を中止する。

(defun kind-of (s)
  (cond ((special-operator-p s) "special_operator")
        ((macro-function s) "macro")
        ((fboundp s) "function")
        ((constantp s) "constant")
        ((boundp s) "variable")
        (t "other")))

(defun main (out)
  (let ((syms '()))
    (do-external-symbols (s :common-lisp) (push s syms))
    (setf syms (sort syms #'string< :key #'symbol-name))
    (unless (= (length syms) 978)
      (format *error-output* "COMMON-LISP の外部シンボルが ~D 個です（978 個を期待）~%" (length syms))
      (sb-ext:exit :code 1))
    (with-open-file (o out :direction :output :if-exists :supersede :external-format :utf-8)
      (format o "//! COMMON-LISP パッケージの外部シンボルの一覧（978 個、名前の順）。~%")
      (format o "//! tools/gen_cl_symbols/gen.lisp が ~A ~A から生成した。手で編集しない。~%"
              (lisp-implementation-type) (lisp-implementation-version))
      (format o "//! kind は SBCL での種類（Zilisp が実装すべきものの目安）。~%~%")
      (format o "pub const Kind = enum { special_operator, macro, function, constant, variable, other };~%~%")
      (format o "pub const Entry = struct { name: []const u8, kind: Kind };~%~%")
      (format o "pub const symbols = [_]Entry{~%")
      (dolist (s syms)
        (format o "    .{ .name = ~S, .kind = .~A },~%" (symbol-name s) (kind-of s)))
      (format o "};~%~%")
      (format o "test \"978 symbols\" {~%    const std = @import(\"std\");~%")
      (format o "    try std.testing.expectEqual(@as(usize, 978), symbols.len);~%}~%"))
    (format t "wrote ~A (~D symbols)~%" out (length syms))
    (let ((counts (make-hash-table :test #'equal)))
      (dolist (s syms) (incf (gethash (kind-of s) counts 0)))
      (maphash (lambda (k v) (format t "  ~A: ~D~%" k v)) counts))))

(main (second sb-ext:*posix-argv*))
