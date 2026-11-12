;; CommonLispBasicMaster 639544c, Level 21-A basic blocks.
;; Level 21-A fence line 86
;;; 基本的なクラス定義
(defclass person ()
  ((name :initarg :name
         :accessor person-name
         :documentation "人物の名前")
   (age :initarg :age
        :accessor person-age
        :initform 0
        :documentation "年齢"))
  (:documentation "人物を表すクラス"))

;; Level 21-A fence line 122
;;; インスタンス作成
(defvar *alice* (make-instance 'person :name "Alice" :age 25))

;;; アクセサでスロットにアクセス
(person-name *alice*)  ; => "Alice"
(person-age *alice*)   ; => 25

;;; setf で値を変更
(setf (person-age *alice*) 26)
(person-age *alice*)  ; => 26

;;; slot-value で直接アクセス（あまり推奨されない）
(slot-value *alice* 'name)  ; => "Alice"

;; Level 21-A fence line 142
;;; employee は person を継承
(defclass employee (person)
  ((department :initarg :department
               :accessor employee-department)
   (salary :initarg :salary
           :accessor employee-salary
           :initform 0))
  (:documentation "従業員クラス"))

;;; 子クラスは親クラスのスロットを持つ
(defvar *bob* (make-instance 'employee
                             :name "Bob"
                             :age 30
                             :department "Engineering"
                             :salary 50000))

(person-name *bob*)         ; => "Bob"（親のアクセサ）
(employee-department *bob*) ; => "Engineering"

;; Level 21-A fence line 175
;;; 総称関数を宣言（省略可能）
(defgeneric greet (person)
  (:documentation "挨拶をする"))

;;; person クラス用のメソッド
(defmethod greet ((p person))
  (format nil "こんにちは、~A です。" (person-name p)))

;;; employee クラス用のメソッド（オーバーライド）
(defmethod greet ((e employee))
  (format nil "~A 部の ~A です。"
          (employee-department e)
          (person-name e)))

;;; 呼び出し（引数の型でメソッドが選択される）
(greet *alice*)  ; => "こんにちは、Alice です。"
(greet *bob*)    ; => "Engineering 部の Bob です。"

;; Level 21-A fence line 236
(defmethod print-object ((p person) stream)
  (print-unreadable-object (p stream :type t)
    (format stream "~A (age ~A)" (person-name p) (person-age p))))

;; REPL での表示
*alice*  ; => #<PERSON Alice (age 26)>

(print (list (greet *alice*) (greet *bob*) (person-age *alice*) (write-to-string *alice*)))
