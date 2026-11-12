# P27 Claude Codeレビューと対応

2026-11-12。Claude Code 2.1.322のCLIで、読み取り専用レビューを依頼した。
初回はP27の範囲全体、2回目は修正した6件に限定して確認した。
ClaudeにはRead・Grep・Globだけを許可し、再現実行と修正・検証はこちらで行った。

| 指摘 | 対応 |
|---|---|
| 重複スロットを受理し、LISTというスロットを拒否 | マクロ展開フォームと名前を別リストで管理 |
| adjustable vector/stringのclass-ofがARRAY | 次元と文字列の判定でVECTOR・STRING・ARRAYに分類 |
| スロットの:typeを未実装として拒否 | 宣言を受理する。P27では実行時の型検査には使わない |
| 異種クラスへの再定義と公開クラスのキャッシュ | 異種への変更をP29まで拒否し、同種の記述変更では公開クラスの同一性を保って更新 |
| slot-exists-pが任意オブジェクト・構造体でエラー | 非スロットオブジェクトはNIL、構造体のスロットは定義から判定 |
| restartのメタクラスがstandard-class | structure-classに分類 |

SBCLの文字列の具体的なクラス名は内部のCHARACTER-STRINGになる場合がある。
Zilispは公開のSTRINGを返すため、回帰試験ではその差を許容する。
SBCLが警告付きで許す異種メタクラスへの変更も、P27ではP29の範囲として明示的に拒否する。

`tests/language/eval/clos-review.lisp` とGC stress版に回帰例を追加した。
異種クラスの拒否とキャッシュの記述更新は `src/compiler/eval_test.zig` で確認する。
ガードの追加で同じRuntimeへのThread再作成が失敗する例も見つかったため、同種のrestart再初期化を許すよう修正した。
Runtime再利用と異種restart再定義の拒否はP27限定の単体試験で確認した（importの確認3件と実試験2件、計5件成功）。

修正後の単体試験Debug、言語77本、影響するネイティブ4ケース（conditions・defstruct・clos・clos-review、通常とGC stress）が成功した。
最後の再初期化条件の修正後は、P27限定単体試験とclos-reviewのVM通常・GC stressを再実行して成功した。
全ネイティブ42本の再実行はしていない。Claudeの確認は静的レビューで、再現と試験の実行はこちらで行った。

以下はClaude Codeの原文。初回の「未検証」はレビュー実行時点を指す。

<details>
<summary>初回レビュー</summary>

# Phase 27 CLOS レビュー結果

実行できるツールがないため、以下の再現例はすべて**未検証**です（コードを読んで導いたものです）。対象ファイルは指定の新規4ファイルと差分、および関連する `boot.lisp` / `types.zig` / `gc.zig` / `printer.zig` / `thread.zig` を読みました。

GC のルート登録・トレース、condition／restart の instance+rack 化、VM／ネイティブの共有には、スコープ内の不具合は見つかりませんでした。見つかったのはクラス・スロットの意味論の問題が中心で、独立した不具合は6件です。

## 1. [Medium] `defclass` のスロット名の重複検査が効かず、`list` という名前のスロットを誤って拒否する

- **場所**: `src/lisp/clos.lisp:121`（検査）と `:135`（`parsed` への追加）
- **原因**: `parsed` の要素は `(list 'n '(keys) …)` というフォームなので、`(assoc n parsed)` はスロット名ではなくシンボル `LIST` と比較しています。
- **再現 A**: `(defclass p27-dup () (a a))`
  - 期待: 重複スロットのエラー（CLHS defclass は program-error）。
  - 現状: 受理され、`%clos-effective-slots` が2つを黙って1つにまとめます。
- **再現 B**: `(defclass p27-l () (a list))`
  - 期待: 正常に定義される。
  - 現状: 2番目以降に `list` があると "Invalid or duplicate slot" になります。
- **直し方の方向**: スロット名を別のリストに集めて検査する。

## 2. [Medium] 単純でないベクタ・文字列の `class-of` が `ARRAY` になる

- **場所**: `src/primitives/clos.zig:101`（`.array => "ARRAY"`）
- **原因**: fill-pointer 付きや adjustable の1次元配列は `.array` 種別（`arrays.zig:87-103`）ですが、次元も要素型も見ていません。
- **再現**:
  - `(class-name (class-of (make-array 3 :fill-pointer 0)))`
  - `(class-name (class-of (make-array 3 :element-type 'character :fill-pointer 0)))`
- **期待**: それぞれ `VECTOR`、`STRING`。
- **現状**: どちらも `ARRAY`。
- **影響**: `ARRAY` の CPL は `(array t)` なので、`vector`／`string`／`sequence` の下位クラスになりません。#536 とは別の問題で、P28 で `vector`／`string`／`sequence` に特化したメソッドが当たらなくなります。
- **直し方の方向**: `vectorView` と `isStringLike` で分ける。

## 3. [Medium] スロットオプション `:type` が「未実装 (P28)」で拒否される

- **場所**: `src/lisp/clos.lisp:134`
- **再現**: `(defclass p27-typed () ((x :type integer :initarg :x)))`
- **期待**: 受理して無視する（`define-condition` は `:type` を受け付けて使わない実装です）。
- **現状**: マクロ展開時に `zilisp:unimplemented "DEFCLASS slot option (P28)"`。
- **補足**: `:type` はアクセサではないので、P28 送りの対象（`:reader`／`:writer`／`:accessor`）には当たらないと判断しました。意図的な先送りなら無視してください。

## 4. [Low–Medium] 既存の `defclass` 名を `defstruct`／`define-condition` が黙って上書きでき、公開クラスのキャッシュが古いまま残る

- **場所**: `src/lisp/clos.lisp:13-19`（`%public-class` のキャッシュ）、`src/lisp/boot.lisp:1429` と `:2285`（`%class` の無条件上書き）
- **原因**: `defclass` は既存の `%class` を拒否しますが、逆方向の検査がありません。`find-class` は一度作ったクラスオブジェクト（古い記述と古い種別）を返し続けます。
- **再現**:
  ```lisp
  (defclass p27-k () ((a :initform 1)))
  (define-condition p27-k (error) ())
  (list (typep (find-class 'p27-k) 'standard-class)
        (slot-value (make-instance 'p27-k) 'a)
        (class-name (class-of (make-condition 'p27-k))))
  ```
- **期待**: 2番目の定義がエラーになるか、少なくとも `find-class` が新しい定義を反映する。
- **現状**: `(T 1 P27-K)`。標準クラスのオブジェクトが残り、`make-instance` は古い記述でインスタンスを作ります。
- **同じ原因の症状**:
  - `(defstruct s a)` → `(find-class 's)` → `(define-condition s …)` で、種別が `structure-class` のまま残ります。
  - `(define-condition c (p27-point) ())` が通り、condition でない「condition クラス」が登録されます。
- **直し方の方向**: `%class` を書き換える2か所で、種別が違えばエラーにし、`%public-class` を無効化する。

## 5. [Low] `slot-exists-p` が標準インスタンス・condition 以外で `type-error` になる

- **場所**: `src/lisp/clos.lisp:182`
- **再現**: `(slot-exists-p 5 'x)`、`(slot-exists-p (make-p27-structure) 'x)`
- **期待**: 前者は `NIL`（CLHS は任意のオブジェクトを受ける）。後者は SBCL では `T` です。
- **現状**: どちらも `type-error`（期待型 `standard-object`）。

## 6. [Low] `(find-class 'restart)` が `standard-class` になる

- **場所**: `src/lisp/clos.lisp:15-19`
- **原因**: `restart` の CPL には `condition` も `structure-object` もないので、種別 0 に落ちます。
- **再現**: `(typep (find-class 'restart) 'standard-class)`
- **期待**: `NIL`（SBCL では `restart` は構造体クラスです）。
- **現状**: `T`。一方で `(make-instance 'restart)` は "Not an instantiable standard class." で失敗し、矛盾します。

## 確認して問題なしと判断した点

- **GC**: `makeInstance` は rack をルートに登録してから instance を確保しています。`gc.zig` の `.class`／`.instance`／`.rack` のマークは、`flags & 1` の分岐もスロット0個の場合も含めて正しいです。
- **既存の Record 読み出し**: `Instance` と `Record` は `class` が同じ位置にあるので、`thread.zig:400`、`printer.zig:360`、`%record-class` は安全です。
- **CPL**: CLHS 4.3.5 の pie／apple／cinnamon の例を手で追い、正しい順になりました。菱形継承、矛盾の検出、共有スロットのセルの継承、default-initargs のマージ順も正しいです。
- **`typep`**: クラスオブジェクトを型指定子にする経路、`standard-object`／`class`／各メタクラスの判定、複合型指定子の中のクラスオブジェクトに問題はありません。

</details>

<details>
<summary>修正確認</summary>

6件の修正を読み終えました。残っている具体的な不具合はなく、6件とも対処済みと判断します（指示どおりテストは実行しておらず、コードを読んだ結果です）。

1. **スロット名の重複検査**: `names` に名前だけを集めて `member` で検査しており（`src/lisp/clos.lisp:122-124`）、`(a a)` は拒否、`list` という名前のスロットは受理されます。
2. **単純でない配列の `class-of`**: `isStringLike` → `STRING`、`vectorView` が非 null → `VECTOR`、それ以外 → `ARRAY` の順で分かれています（`src/primitives/clos.zig:109`）。多次元配列は `vectorView` が null を返すので `ARRAY` のままです。
3. **`:type`**: `:documentation` と同じ分岐で受理して無視します（`src/lisp/clos.lisp:135`）。同じオプションの重複検査も引き続き効きます。
4. **種別をまたぐ再定義**: 最初のレポートで挙げた3つの症状はすべて塞がっています。
   - `%define-condition-class`（`src/lisp/boot.lisp:1426-1429`）と `%define-structure`（`:2290-2293`）が、`%class` を書き換える前に組み込みクラス名と別種別の既存クラスを拒否します。
   - 親クラスの検査も `%class` の書き換えより前にあるので、`(define-condition c (標準クラス) ())` は何も登録せずに失敗します。
   - 同じ種別の再定義では、`find-class` が `%refresh-class` でキャッシュ済みクラスの記述を差し替え、同一性を保ちます。
5. **`slot-exists-p`**: 標準インスタンスと condition は記述のスロット一覧、構造体は `%structure-class-of` のスロット一覧を `assoc` で調べ、それ以外は `NIL` を返します（`src/lisp/clos.lisp:182-188`）。
6. **`restart`**: `find-class` が `restart` を種別 2 にするので `structure-class` になり（`src/lisp/clos.lisp:16`）、`make-instance` が拒否することとも矛盾しません。

不具合ではない補足が1点あります。記述の差し替えは次に `find-class` か `class-of` を呼んだ時点で行われるため、再定義の直後に保持しているクラスオブジェクトは一時的に古い記述を指します。`typep` と `class-name` は名前だけを使い、同じ種別の再定義で名前は変わらないので、P27 の範囲では外から観測できません。P29 でクラスオブジェクトから記述を直接読む経路を足すときは、定義時に差し替える形にする必要があります。

テストは、`tests/language/eval/clos-review.lisp` と `.expected` が項目 1・2・3・5・6 を、`src/compiler/eval_test.zig:34` の P27 テストが項目 4 を押さえており、期待値はコードの挙動と一致しています。

</details>
