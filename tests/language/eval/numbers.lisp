;; 数の階層（Phase 20）：bignum・比・浮動小数の混在、整数の割り算、累乗、ビット演算
;; 階乗（fixnum の範囲を超えると bignum になる）
(defun factorial (n)
  (if (< n 2) 1 (* n (factorial (- n 1)))))
(print (factorial 20))
(print (factorial 30))
(print (length (format nil "~D" (factorial 100))))

;; フィボナッチ数（大きな数どうしの足し算）
(defun fib (n)
  (let ((a 0) (b 1))
    (dotimes (i n a)
      (psetq a b b (+ a b)))))
(print (fib 100))

;; 比は約分され、分母が 1 なら整数になる
(print (/ 6 4))
(print (+ 1/3 1/6))
(print (* 2/3 3/2))
(print (loop for i from 1 to 10 sum (/ 1 i)))
(print (list (numerator 6/8) (denominator 6/8)))

;; 浮動小数が混ざると浮動小数になる。比較は正確
(print (+ 1/2 0.25))
(print (float 1/3 1d0))
(print (list (= 1/2 0.5) (< 1/3 0.3333) (> (expt 2 100) 1e30)))

;; 整数の割り算は商と余りの2つの値
(print (multiple-value-list (floor 17 5)))
(print (multiple-value-list (round 7 2)))
(print (multiple-value-list (truncate -7.5)))
(print (mod (expt 2 100) 1000007))

;; 累乗・平方根・gcd
(print (expt 2 128))
(print (expt 2/3 -3))
(print (sqrt 2d0))
(print (isqrt (expt 10 30)))
(print (gcd (expt 2 60) (expt 6 30)))

;; ビット演算（2 の補数の意味）
(print (list (logand 12 10) (logior 12 10) (logxor 12 10) (lognot 5)))
(print (ash 1 100))
(print (ash (- (expt 2 100)) -98))
(print (integer-length (expt 2 100)))
(terpri)
