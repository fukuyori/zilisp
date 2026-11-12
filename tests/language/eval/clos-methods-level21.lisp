;; CommonLispBasicMaster 639544c, Level21-A qualifier/init examples.
;; Fence L86
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
;; Fence L122
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
;; Fence L142
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
;; Fence L175
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
;; Fence L199
;;; プライマリメソッドの前に実行
(defmethod greet :before ((p person))
  (format t "[挨拶開始]~%"))

;;; プライマリメソッドの後に実行
(defmethod greet :after ((p person))
  (format t "[挨拶終了]~%"))

;;; 全体をラップ（call-next-method で次を呼ぶ）
(defmethod greet :around ((e employee))
  (format t "【従業員の挨拶】~%")
  (call-next-method))  ; プライマリメソッドを呼び出す
;; Fence L223
;;; インスタンス作成時に自動で呼ばれる
(defmethod initialize-instance :after ((p person) &key)
  (format t "新しい person を作成: ~A~%" (person-name p)))

(make-instance 'person :name "Charlie")
; 出力: 新しい person を作成: Charlie
;; Fence L236
(defmethod print-object ((p person) stream)
  (print-unreadable-object (p stream :type t)
    (format stream "~A (age ~A)" (person-name p) (person-age p))))

;; REPL での表示
*alice*  ; => #<PERSON Alice (age 26)>
(print (list (greet *alice*) (greet *bob*)))
(print (person-name (make-instance 'person :name "Delta")))
