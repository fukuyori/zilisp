;; Canonical CommonLispBasicMaster 639544c, Level 21-B fence L700.
;; Adapter: DEFCOMMAND supplies its missing named BLOCK (SBCL also reports errors without it).
;;;; ============================================================
;;;; テキストアドベンチャーエンジン + 「古城の秘密」
;;;; ============================================================

;;; ==================== グローバル変数 ====================
;;; ゲーム全体で共有される状態

(defvar *world* nil "現在のゲームワールド（game-world インスタンス）")
(defvar *commands* (make-hash-table :test 'equal) "コマンド名→関数のマッピング")
(defvar *synonyms* (make-hash-table :test 'equal) "同義語→正規形のマッピング")

;;; ==================== クラス定義 ====================
;;; CLOS によるゲームオブジェクトの階層構造

;; 基底クラス（全オブジェクト共通の属性）
(defclass game-object ()
  ((id :initarg :id :reader object-id)           ; 一意識別子
   (name :initarg :name :accessor object-name)   ; 表示名
   (description :initarg :description :accessor object-description :initform "")))

;; REPL での表示をカスタマイズ
(defmethod print-object ((obj game-object) stream)
  (print-unreadable-object (obj stream :type t)
    (format stream "~A" (object-name obj))))

;; 部屋クラス（場所を表す）
(defclass game-room (game-object)
  ((exits :initarg :exits :accessor game-room-exits :initform '())      ; 出口リスト
   (items :initarg :items :accessor game-room-items :initform '())      ; アイテムID
   (npcs :initarg :npcs :accessor game-room-npcs :initform '())         ; NPC ID
   (visited :initarg :visited :accessor game-room-visited :initform nil))) ; 訪問済み?

;; 部屋の説明を表示するメソッド
(defmethod describe-game-room ((r game-room) &key (verbose t))
  (format t "~%【~A】~%" (object-name r))
  (when (or verbose (not (game-room-visited r)))
    (format t "~A~%" (object-description r)))
  (when (game-room-items r)
    (format t "~%アイテム: ~{~A~^, ~}~%"
            (mapcar #'get-item-name (game-room-items r))))
  (when (game-room-npcs r)
    (format t "人物: ~{~A~^, ~}~%"
            (mapcar #'get-npc-name (game-room-npcs r))))
  (format t "出口: ~{~A~^, ~}~%"
          (mapcar (lambda (x) (string-downcase (symbol-name (car x))))
                  (game-room-exits r))))

;; アイテムクラス（持ち物・道具）
(defclass item (game-object)
  ((portable :initarg :portable :accessor item-portable :initform t)     ; 持てるか
   (usable :initarg :usable :accessor item-usable :initform nil)         ; 使えるか
   (use-action :initarg :use-action :accessor item-use-action :initform nil) ; 使用関数
   (examine-text :initarg :examine-text :accessor item-examine-text :initform nil))) ; 調査テキスト

;; コンテナクラス（箱・引き出しなど）
(defclass container (item)
  ((contents :initarg :contents :accessor container-contents :initform '()) ; 中身
   (locked :initarg :locked :accessor container-locked :initform nil)       ; 施錠状態
   (key-id :initarg :key-id :accessor container-key-id :initform nil)))     ; 開錠に必要な鍵

;; NPCクラス（会話可能キャラクター）
(defclass npc (game-object)
  ((dialogue :initarg :dialogue :accessor npc-dialogue :initform '())       ; セリフリスト
   (inventory :initarg :inventory :accessor npc-inventory :initform '())    ; 所持品
   (talk-count :initarg :talk-count :accessor npc-talk-count :initform 0))) ; 会話回数

;; NPCとの会話メソッド
(defmethod talk-to ((n npc))
  (let ((dialogue (npc-dialogue n)))
    (if dialogue
        (let* ((count (npc-talk-count n))
               (text (or (nth count dialogue) (car (last dialogue)))))
          (incf (npc-talk-count n))
          (format t "~%~A: 「~A」~%" (object-name n) text))
        (format t "~%~A は何も言わない。~%" (object-name n)))))

;; プレイヤークラス（主人公の状態）
(defclass player ()
  ((current-room :initarg :current-room :accessor player-current-room) ; 現在地
   (inventory :initarg :inventory :accessor player-inventory :initform '()) ; 所持品
   (max-inventory :initarg :max-inventory :accessor player-max-inventory :initform 10)
   (score :initarg :score :accessor player-score :initform 0)
   (turns :initarg :turns :accessor player-turns :initform 0)))        ; ターン数

;; ワールドクラス（ゲーム全体の状態）
(defclass game-world ()
  ((rooms :initarg :rooms :accessor world-rooms :initform (make-hash-table))
   (items :initarg :items :accessor world-items :initform (make-hash-table))
   (npcs :initarg :npcs :accessor world-npcs :initform (make-hash-table))
   (player :initarg :player :accessor world-player)
   (flags :initarg :flags :accessor world-flags :initform (make-hash-table))
   (game-over :initarg :game-over :accessor world-game-over :initform nil)
   (win :initarg :win :accessor world-win :initform nil)))

;;; ==================== ユーティリティ ====================
;;; オブジェクト取得と状態確認のヘルパー関数

(defun get-room (id) (gethash id (world-rooms *world*)))   ; ID→部屋
(defun get-item (id) (gethash id (world-items *world*)))   ; ID→アイテム
(defun get-npc (id) (gethash id (world-npcs *world*)))     ; ID→NPC

;; ID から表示名を取得（見つからなければ "???"）
(defun get-item-name (id)
  (let ((item (get-item id))) (if item (object-name item) "???")))

(defun get-npc-name (id)
  (let ((npc (get-npc id))) (if npc (object-name npc) "???")))

;; 現在の部屋オブジェクトを取得
(defun current-room ()
  (get-room (player-current-room (world-player *world*))))

;; フラグ操作（イベント管理用）
(defun get-flag (name) (gethash name (world-flags *world*)))
(defun set-flag (name value) (setf (gethash name (world-flags *world*)) value))

;; 所持判定
(defun has-item-p (item-id)
  (member item-id (player-inventory (world-player *world*))))

(defun game-room-has-item-p (item-id &optional (room (current-room)))
  (member item-id (game-room-items room)))

;;; ==================== パーサー ====================
;;; ユーザー入力を解析してコマンドに変換

;; 文字列を空白（半角・全角）で分割してリストに変換
(defun split-string (str)
  (let ((result '()) (current ""))
    (loop for c across str
          do (if (member c '(#\Space #\Tab #\　))
                 (progn (when (> (length current) 0) (push current result))
                        (setf current ""))
                 (setf current (concatenate 'string current (string c)))))
    (when (> (length current) 0) (push current result))
    (nreverse result)))

;; 文字列置換（すべての出現を置換）
(defun replace-all (str old new)
  "文字列内のすべてのoldをnewに置換"
  (let ((result "") (pos 0) (old-len (length old)))
    (loop
      (let ((found (search old str :start2 pos)))
        (if found
            (progn
              (setf result (concatenate 'string result (subseq str pos found) new))
              (setf pos (+ found old-len)))
            (progn
              (setf result (concatenate 'string result (subseq str pos)))
              (return result)))))))

;; 助詞の前後に空白を挿入（「鍵を取る」→「鍵 を 取る」）
(defun expand-particles (str)
  "助詞の前後に空白を挿入して分割可能にする"
  (let ((result str))
    (dolist (p '("を" "に" "へ" "で" "と" "から" "まで"))
      (setf result (replace-all result p (format nil " ~A " p))))
    result))

;; 助詞・冠詞などの不要語を判定
(defun noise-word-p (word)
  (member (string-downcase word)
          '("を" "に" "へ" "の" "と" "で" "から" "まで"
            "a" "an" "the" "to" "at" "in" "on")
          :test #'string=))

;; 同義語を登録
(defun add-synonym (word syn)
  (setf (gethash (string-downcase syn) *synonyms*) (string-downcase word)))

;; 同義語を解決（登録されていなければそのまま返す）
(defun resolve-synonym (word)
  (or (gethash (string-downcase word) *synonyms*) (string-downcase word)))

;; 日本語の語順を変換（「鍵 取る」→「取る 鍵」）
(defun reorder-japanese (words)
  "動詞が最後にある場合、先頭に移動する"
  (if (and words (> (length words) 1))
      (let ((last-word (car (last words))))
        (if (find-command last-word)
            (cons last-word (butlast words))
            words))
      words))

;; 入力を解析: 助詞展開 → 分割 → 不要語除去 → 同義語解決 → 語順変換
(defun parse-input (input)
  (let* ((input (expand-particles input))       ; 「鍵を取る」→「鍵 を 取る」
         (words (split-string input))           ; → ("鍵" "を" "取る")
         (words (remove-if #'noise-word-p words)) ; → ("鍵" "取る")
         (words (mapcar #'resolve-synonym words)) ; → ("鍵" "take")
         (words (reorder-japanese words)))        ; → ("take" "鍵")
    words))

;; コマンド関数を検索
(defun find-command (name) (gethash (resolve-synonym name) *commands*))

;;; ==================== コマンドシステム ====================
;;; コマンド定義マクロと同義語設定

;; コマンドを定義するマクロ（名前→関数をテーブルに登録）
(defmacro defcommand (name args &body body)
  (let ((declarations nil))
    (loop while (and (consp (car body)) (eq (caar body) 'declare))
          do (push (pop body) declarations))
    `(setf (gethash ,(string-downcase (string name)) *commands*)
           (lambda ,args ,@(nreverse declarations) (block ,name ,@body)))))

;; 同義語を設定（日本語⇔英語、略語など）
(defun setup-synonyms ()
  ;; 移動
  (add-synonym "go" "行く") (add-synonym "go" "いく") (add-synonym "go" "move")
  ;; 方向
  (add-synonym "north" "北") (add-synonym "south" "南")
  (add-synonym "east" "東") (add-synonym "west" "西")
  (add-synonym "up" "上") (add-synonym "down" "下")
  ;; アイテム
  (add-synonym "take" "取る") (add-synonym "take" "とる") (add-synonym "take" "get")
  (add-synonym "drop" "置く") (add-synonym "drop" "おく") (add-synonym "drop" "put")
  (add-synonym "look" "見る") (add-synonym "look" "みる") (add-synonym "look" "x")
  (add-synonym "use" "使う") (add-synonym "use" "つかう")
  (add-synonym "talk" "話す") (add-synonym "talk" "はなす")
  ;; システム
  (add-synonym "inventory" "持ち物") (add-synonym "inventory" "i")
  (add-synonym "help" "ヘルプ") (add-synonym "quit" "終了")
  (add-synonym "save" "セーブ") (add-synonym "load" "ロード"))

;;; ==================== 検索関数 ====================
;;; 名前（部分一致）からオブジェクトを検索

;; アイテムを名前で検索（インベントリ優先）
(defun find-item-by-name (name)
  (let ((name-down (string-downcase name)))
    (or (find-if (lambda (id)
                   (search name-down (string-downcase (object-name (get-item id)))))
                 (player-inventory (world-player *world*)))
        (find-if (lambda (id)
                   (search name-down (string-downcase (object-name (get-item id)))))
                 (game-room-items (current-room))))))

;; NPCを名前で検索（現在の部屋のみ）
(defun find-npc-by-name (name)
  (let ((name-down (string-downcase name)))
    (find-if (lambda (id)
               (search name-down (string-downcase (object-name (get-npc id)))))
             (game-room-npcs (current-room)))))

;;; ==================== 基本コマンド ====================
;;; 移動、観察、アイテム操作など

;; 移動コマンド
(defcommand go (direction &rest args)
  (declare (ignore args))
  (let* ((room (current-room))
         (exit (assoc (intern (string-upcase direction) :keyword) (game-room-exits room))))
    (if exit
        (progn
          (setf (player-current-room (world-player *world*)) (cdr exit))
          (setf (game-room-visited (current-room)) t)
          (describe-game-room (current-room)))
        (format t "~%その方向には行けない。~%"))))

;; 見るコマンド（引数なしで部屋全体、ありで特定のアイテム）
(defcommand look (&optional target &rest args)
  (declare (ignore args))
  (if target
      (let ((item-id (find-item-by-name target)))
        (if item-id
            (let ((item (get-item item-id)))
              (format t "~%~A~%" (object-description item))
              (when (item-examine-text item)
                (format t "~A~%" (item-examine-text item))))
            (format t "~%~A は見当たらない。~%" target)))
      (describe-game-room (current-room) :verbose t)))

;; 取るコマンド
(defcommand take (item-name &rest args)
  (declare (ignore args))
  (unless item-name (format t "~%何を取る？~%") (return-from take))
  (let ((item-id (find-item-by-name item-name)))
    (cond
      ((null item-id) (format t "~%~A は見当たらない。~%" item-name))
      ((has-item-p item-id) (format t "~%すでに持っている。~%"))
      ((not (game-room-has-item-p item-id)) (format t "~%ここにはない。~%"))
      ((not (item-portable (get-item item-id))) (format t "~%それは持ち運べない。~%"))
      ((>= (length (player-inventory (world-player *world*)))
           (player-max-inventory (world-player *world*)))
       (format t "~%これ以上持てない。~%"))
      (t (let ((item (get-item item-id)))
           (setf (game-room-items (current-room))
                 (remove item-id (game-room-items (current-room))))
           (push item-id (player-inventory (world-player *world*)))
           (format t "~%~A を手に入れた。~%" (object-name item)))))))

(defcommand drop (item-name &rest args)
  (declare (ignore args))
  (unless item-name (format t "~%何を置く？~%") (return-from drop))
  (let ((item-id (find-item-by-name item-name)))
    (cond
      ((null item-id) (format t "~%~A は見当たらない。~%" item-name))
      ((not (has-item-p item-id)) (format t "~%それは持っていない。~%"))
      (t (let ((item (get-item item-id)))
           (setf (player-inventory (world-player *world*))
                 (remove item-id (player-inventory (world-player *world*))))
           (push item-id (game-room-items (current-room)))
           (format t "~%~A を置いた。~%" (object-name item)))))))

;; 持ち物コマンド
(defcommand inventory (&rest args)
  (declare (ignore args))
  (let ((inv (player-inventory (world-player *world*))))
    (if inv
        (progn (format t "~%所持品:~%")
               (dolist (id inv) (format t "- ~A~%" (get-item-name id))))
        (format t "~%何も持っていない。~%"))))

;; 使うコマンド（アイテムの use-action を呼び出す）
(defcommand use (item-name &rest args)
  (unless item-name (format t "~%何を使う？~%") (return-from use))
  (let ((item-id (find-item-by-name item-name)))
    (cond
      ((null item-id) (format t "~%~A は見当たらない。~%" item-name))
      ((not (has-item-p item-id)) (format t "~%それは持っていない。~%"))
      (t (let ((item (get-item item-id)))
           (if (item-use-action item)
               (funcall (item-use-action item) item args)
               (format t "~%~A の使い方がわからない。~%" (object-name item))))))))

;; 話すコマンド
(defcommand talk (npc-name &rest args)
  (declare (ignore args))
  (unless npc-name (format t "~%誰と話す？~%") (return-from talk))
  (let ((npc-id (find-npc-by-name npc-name)))
    (if npc-id
        (talk-to (get-npc npc-id))
        (format t "~%~A はここにいない。~%" npc-name))))

;; ヘルプコマンド
(defcommand help (&rest args)
  (declare (ignore args))
  (format t "~%========== コマンド一覧 ==========~%")
  (format t "移動: 北/南/東/西/上/下 (n/s/e/w)~%")
  (format t "見る: 見る, 見る <対象>~%")
  (format t "取る: 取る <アイテム>~%")
  (format t "置く: 置く <アイテム>~%")
  (format t "使う: 使う <アイテム>~%")
  (format t "話す: 話す <人物>~%")
  (format t "持ち物: 持ち物, i~%")
  (format t "セーブ/ロード: セーブ, ロード~%")
  (format t "終了: 終了~%")
  (format t "==================================~%"))

;; 終了コマンド
(defcommand quit (&rest args)
  (declare (ignore args))
  (format t "~%ゲームを終了しますか？ (y/n): ")
  (force-output)
  (let ((answer (read-line)))
    (when (member (string-downcase answer) '("y" "yes" "はい") :test #'string=)
      (setf (world-game-over *world*) t)
      (format t "~%ゲームを終了します。~%"))))

;; 方向ショートカット（go コマンドへのエイリアス）
(defcommand north (&rest args) (declare (ignore args)) (funcall (find-command "go") "north"))
(defcommand south (&rest args) (declare (ignore args)) (funcall (find-command "go") "south"))
(defcommand east (&rest args) (declare (ignore args)) (funcall (find-command "go") "east"))
(defcommand west (&rest args) (declare (ignore args)) (funcall (find-command "go") "west"))
(defcommand up (&rest args) (declare (ignore args)) (funcall (find-command "go") "up"))
(defcommand down (&rest args) (declare (ignore args)) (funcall (find-command "go") "down"))
;; 1文字略語（伝統的なテキストアドベンチャーの慣習）
(defcommand n (&rest args) (declare (ignore args)) (funcall (find-command "go") "north"))
(defcommand s (&rest args) (declare (ignore args)) (funcall (find-command "go") "south"))
(defcommand e (&rest args) (declare (ignore args)) (funcall (find-command "go") "east"))
(defcommand w (&rest args) (declare (ignore args)) (funcall (find-command "go") "west"))
(defcommand u (&rest args) (declare (ignore args)) (funcall (find-command "go") "up"))
(defcommand d (&rest args) (declare (ignore args)) (funcall (find-command "go") "down"))

;;; ==================== セーブ/ロード ====================
;;; ゲーム状態の永続化（S式によるシリアライズ）

;; ハッシュテーブルを連想リストに変換
(defun hash-table-to-alist (ht)
  (let ((result '()))
    (maphash (lambda (k v) (push (cons k v) result)) ht)
    result))

(defun serialize-world (world)
  (list :player-room (player-current-room (world-player world))
        :player-inventory (player-inventory (world-player world))
        :player-score (player-score (world-player world))
        :player-turns (player-turns (world-player world))
        :game-room-items (let ((r '()))
                      (maphash (lambda (id room) (push (cons id (game-room-items room)) r))
                               (world-rooms world)) r)
        :game-room-visited (let ((r '()))
                        (maphash (lambda (id room)
                                   (when (game-room-visited room) (push id r)))
                                 (world-rooms world)) r)
        :flags (hash-table-to-alist (world-flags world))
        :npc-talk-counts (let ((r '()))
                           (maphash (lambda (id npc)
                                      (push (cons id (npc-talk-count npc)) r))
                                    (world-npcs world)) r)
        :container-states (let ((r '()))
                            (maphash (lambda (id item)
                                       (when (typep item 'container)
                                         (push (list id
                                                     :locked (container-locked item)
                                                     :contents (container-contents item))
                                               r)))
                                     (world-items world)) r)))

(defun deserialize-world (world data)
  (let ((player (world-player world)))
    (setf (player-current-room player) (getf data :player-room))
    (setf (player-inventory player) (getf data :player-inventory))
    (setf (player-score player) (getf data :player-score))
    (setf (player-turns player) (getf data :player-turns))
    ;; 部屋のアイテム
    (dolist (pair (getf data :game-room-items))
      (let ((room (get-room (car pair))))
        (when room (setf (game-room-items room) (cdr pair)))))
    ;; 訪問済み
    (maphash (lambda (id room) (declare (ignore id)) (setf (game-room-visited room) nil))
             (world-rooms world))
    (dolist (id (getf data :game-room-visited))
      (let ((room (get-room id))) (when room (setf (game-room-visited room) t))))
    ;; フラグ
    (clrhash (world-flags world))
    (dolist (pair (getf data :flags))
      (setf (gethash (car pair) (world-flags world)) (cdr pair)))
    ;; NPC会話
    (dolist (pair (getf data :npc-talk-counts))
      (let ((npc (get-npc (car pair))))
        (when npc (setf (npc-talk-count npc) (cdr pair)))))
    ;; コンテナ状態
    (dolist (entry (getf data :container-states))
      (let ((container (get-item (first entry))))
        (when (and container (typep container 'container))
          (setf (container-locked container) (getf (cdr entry) :locked))
          (setf (container-contents container) (getf (cdr entry) :contents)))))))

(defcommand save (filename &rest args)
  (declare (ignore args))
  (unless filename (setf filename "save.dat"))
  (with-open-file (out filename :direction :output :if-exists :supersede)
    (print (serialize-world *world*) out))
  (format t "~%ゲームを ~A に保存しました。~%" filename))

(defcommand load (filename &rest args)
  (declare (ignore args))
  (unless filename (setf filename "save.dat"))
  (if (probe-file filename)
      (progn
        (with-open-file (in filename :direction :input)
          (deserialize-world *world* (read in)))
        (format t "~%ゲームを ~A から読み込みました。~%" filename)
        (describe-game-room (current-room)))
      (format t "~%セーブファイルが見つかりません。~%")))

;;; ==================== アイテム使用関数 ====================

(defun use-rusty-key (item args)
  (declare (ignore item args))
  (let ((room (current-room)))
    (cond
      ((member :locked-drawer (game-room-items room))
       (let ((drawer (get-item :locked-drawer)))
         (if (container-locked drawer)
             (progn
               (setf (container-locked drawer) nil)
               (format t "~%錆びた鍵で引き出しを開けた！~%")
               (format t "中に銀の鍵が入っている！~%")
               (dolist (id (container-contents drawer))
                 (push id (game-room-items room)))
               (setf (container-contents drawer) nil)
               (setf (player-inventory (world-player *world*))
                     (remove :rusty-key (player-inventory (world-player *world*)))))
             (format t "~%引き出しはすでに開いている。~%"))))
      (t (format t "~%ここでは使えない。~%")))))

(defun use-silver-key (item args)
  (declare (ignore item args))
  (let ((room (current-room)))
    (cond
      ((member :treasure-chest (game-room-items room))
       (let ((chest (get-item :treasure-chest)))
         (if (container-locked chest)
             (progn
               (setf (container-locked chest) nil)
               (format t "~%銀の鍵で宝箱を開けた！~%")
               (format t "中に輝く王冠がある！~%")
               (dolist (id (container-contents chest))
                 (push id (game-room-items room)))
               (setf (container-contents chest) nil)
               (setf (player-inventory (world-player *world*))
                     (remove :silver-key (player-inventory (world-player *world*)))))
             (format t "~%宝箱はすでに開いている。~%"))))
      (t (format t "~%ここでは使えない。~%")))))

(defun use-golden-goblet (item args)
  (declare (ignore item args))
  (if (has-item-p :crown)
      (progn
        (format t "~%杯を掲げると、王冠が輝きを増す。~%")
        (format t "あなたは真の宝を手に入れた！~%")
        (format t "~%========================================~%")
        (format t "    ゲームクリア！おめでとうございます！~%")
        (format t "========================================~%")
        (setf (world-game-over *world*) t)
        (setf (world-win *world*) t))
      (format t "~%杯を見つめると、自分の顔が映っている。
何かが足りないようだ...~%")))

;;; ==================== ゲームデータ ====================

(defun create-castle-world ()
  (let ((world (make-instance 'game-world)))
    (setf (world-player world) (make-instance 'player :current-room :entrance))
    ;; 部屋
    (let ((rooms (world-rooms world)))
      (setf (gethash :entrance rooms)
            (make-instance 'game-room :id :entrance :name "城の入口"
                           :description "古びた城の入口に立っている。重厚な木の扉が北に見える。"
                           :exits '((:north . :hall))))
      (setf (gethash :hall rooms)
            (make-instance 'game-room :id :hall :name "大広間"
                           :description "埃っぽい大広間だ。シャンデリアが天井からぶら下がっている。"
                           :exits '((:south . :entrance) (:east . :corridor)
                                    (:west . :dining) (:up . :upper-hall))
                           :items '(:rusty-key)))
      (setf (gethash :corridor rooms)
            (make-instance 'game-room :id :corridor :name "廊下"
                           :description "薄暗い廊下だ。壁には古い肖像画が並んでいる。"
                           :exits '((:west . :hall) (:north . :library))
                           :npcs '(:ghost)))
      (setf (gethash :library rooms)
            (make-instance 'game-room :id :library :name "図書室"
                           :description "本棚が壁一面に並んでいる。一冊だけ綺麗な本がある。"
                           :exits '((:south . :corridor))
                           :items '(:old-book)))
      (setf (gethash :dining rooms)
            (make-instance 'game-room :id :dining :name "食堂"
                           :description "長いテーブルがある食堂だ。暖炉の前に何かが光っている。"
                           :exits '((:east . :hall))
                           :items '(:golden-goblet)))
      (setf (gethash :upper-hall rooms)
            (make-instance 'game-room :id :upper-hall :name "上階の広間"
                           :description "二階の広間だ。赤い絨毯が敷かれている。"
                           :exits '((:down . :hall) (:north . :master-room) (:east . :tower))))
      (setf (gethash :master-room rooms)
            (make-instance 'game-room :id :master-room :name "主人の部屋"
                           :description "かつての城主の部屋だ。机の引き出しには鍵がかかっている。"
                           :exits '((:south . :upper-hall))
                           :items '(:locked-drawer)))
      (setf (gethash :tower rooms)
            (make-instance 'game-room :id :tower :name "塔の頂上"
                           :description "塔の頂上だ。部屋の中央に豪華な宝箱がある。"
                           :exits '((:west . :upper-hall))
                           :items '(:treasure-chest))))
    ;; アイテム
    (let ((items (world-items world)))
      (setf (gethash :rusty-key items)
            (make-instance 'item :id :rusty-key :name "錆びた鍵"
                           :description "古くて錆びた鍵。" :portable t :usable t
                           :use-action #'use-rusty-key))
      (setf (gethash :old-book items)
            (make-instance 'item :id :old-book :name "古い本"
                           :description "「城の秘密」というタイトルの本。"
                           :examine-text "「真の宝は、黄金の杯に映る者のみが手に入れられる」"
                           :portable t))
      (setf (gethash :golden-goblet items)
            (make-instance 'item :id :golden-goblet :name "黄金の杯"
                           :description "美しく輝く黄金の杯。"
                           :examine-text "杯を覗き込むと、自分の顔が映っている。"
                           :portable t :usable t :use-action #'use-golden-goblet))
      (setf (gethash :locked-drawer items)
            (make-instance 'container :id :locked-drawer :name "鍵のかかった引き出し"
                           :description "机の引き出し。鍵がかかっている。"
                           :examine-text "古い錆びた鍵穴がある。"
                           :portable nil :locked t :key-id :rusty-key
                           :contents '(:silver-key)))
      (setf (gethash :silver-key items)
            (make-instance 'item :id :silver-key :name "銀の鍵"
                           :description "美しい銀の鍵。" :portable t :usable t
                           :use-action #'use-silver-key))
      (setf (gethash :treasure-chest items)
            (make-instance 'container :id :treasure-chest :name "宝箱"
                           :description "豪華な宝箱。鍵がかかっている。"
                           :examine-text "銀色の鍵穴が付いている。"
                           :portable nil :locked t :key-id :silver-key
                           :contents '(:crown)))
      (setf (gethash :crown items)
            (make-instance 'item :id :crown :name "輝く王冠"
                           :description "宝石がちりばめられた美しい王冠。"
                           :examine-text "これこそが城の秘宝だ！" :portable t)))
    ;; NPC
    (let ((npcs (world-npcs world)))
      (setf (gethash :ghost npcs)
            (make-instance 'npc :id :ghost :name "幽霊"
                           :description "青白く光る幽霊。"
                           :dialogue '("私は...この城で...長い間..."
                                       "図書室の本を...読むのだ..."
                                       "黄金の杯が...全てを教えてくれる..."))))
    world))

;;; ==================== ゲームループ ====================

(defun game-loop ()
  (loop
    (when (world-game-over *world*) (return))
    (format t "~%> ") (force-output)
    (let ((input (read-line *standard-input* nil)))
      (when (null input) (return))
      (let ((words (parse-input input)))
        (when words
          (incf (player-turns (world-player *world*)))
          (let* ((verb (first words)) (args (rest words))
                 (cmd (find-command verb)))
            (if cmd
                (apply cmd args)
                (format t "~%「~A」は理解できない。「ヘルプ」でコマンド一覧を確認。~%"
                        verb))))))))

(defun start-game ()
  (setup-synonyms)
  (format t "~%========================================~%")
  (format t "    古城の秘密 - テキストアドベンチャー~%")
  (format t "========================================~%~%")
  (format t "あなたは謎めいた古城を探索することになった。~%")
  (format t "この城には秘宝が眠っているという噂だ。~%~%")
  (format t "（「ヘルプ」でコマンド一覧を表示）~%")
  (describe-game-room (current-room) :verbose t)
  (game-loop)
  (if (world-win *world*)
      (format t "~%ターン数: ~A~%またのプレイをお待ちしています。~%"
              (player-turns (world-player *world*)))
      (format t "~%またの挑戦をお待ちしています。~%")))

(defun play-castle ()
  "「古城の秘密」をプレイする。"
  (setf *world* (create-castle-world))
  (start-game))

;;; 起動: (play-castle)

;; Deterministic completion-code acceptance: initialize, navigate and inspect.
(setf *world* (create-castle-world))
(setup-synonyms)
(print (list (hash-table-count (world-rooms *world*)) (hash-table-count (world-items *world*))
             (object-name (current-room)) (player-current-room (world-player *world*))))
(funcall (find-command "go") "north")
(print (list (player-current-room (world-player *world*)) (game-room-visited (current-room))))
(print (parse-input "北"))
(print (write-to-string (get-item :rusty-key)))
