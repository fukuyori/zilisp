# P29 メソッド結合・初期化・再定義（2026-11-12）

対象はtque #321・#534・#535。既存rack方式とLispディスパッチャを拡張する。

- standardのaround/before/primary/after順序、次メソッド、afterの多値保存。
- allocate-instance、make-instance、initialize-instance、shared-initialize、reinitialize-instanceと、メソッドが宣言する有効な初期化引数。
- 標準クラス再定義、子孫のCPL・スロット再計算、make-instances-obsolete、遅延rack更新とupdate-instance-for-redefined-class、change-classとupdate-instance-for-different-class。
- 上位クラスの前方参照（未確定クラスは生成不可）、find-classの名前登録・解除とクラス同一性。
- クラス別に利用キャッシュを登録し、旧stampのエントリだけを失効する。アクセサの生成メソッドも再定義時に更新する。
- 受入は教材canonical commit 639544cのLevel 21完成コードと、各CLOS機能のSBCL比較・VM/ネイティブ・GC stress。
- メタクラスの変更と独自メソッド結合は非対応として明示的に拒否する。with-slots/with-accessorsはsymbol-macroletを扱うP30、深い再帰の資源改善は#541。

実装・受け入れをそろえてClaude Codeに読み取り専用レビューを依頼し、指摘を一括で再現・修正する。再確認は通常1回、修正と回帰に限定する。重いネイティブ全体試験はレビュー修正後の固定ソースで行う。

参照: [CLHSクラス再定義](https://www.lispworks.com/documentation/HyperSpec/Body/04_cf.htm)、[ローカル・共有スロット](https://www.lispworks.com/documentation/HyperSpec/Body/04_cfa.htm)、[shared-initialize](https://www.lispworks.com/documentation/HyperSpec/Body/f_shared.htm)、[change-class](https://www.lispworks.com/documentation/HyperSpec/Body/f_chg_cl.htm)、[find-class](https://www.lispworks.com/documentation/HyperSpec/Body/f_find_c.htm)。設計書の「両方localだけ保持」はshared→localの値も保持するよう原文に合わせる。

## 実装と受け入れの補足

標準クラス記述はP27/P28の0〜8に加え、9=self、10=直接のdefault-initargs、11=上位クラスの実体、12=CPLの実体、13=利用キャッシュ、14=予約、15=生成アクセサメソッドを持つ。名前と継承を切り離し、再定義では候補となる子孫の記述を先に計算し、整合性確認後に公開する。旧instanceは旧layoutからselfをたどれる。共有→localの値も保持し、local→共有は廃止スロットとplistに含める。

クラスごとのキャッシュ一覧から旧stampを含むエントリだけを削除する。標準クラスの旧layoutはグローバルな記述対応表に蓄積しない。標準クラスの依存関係は強参照のレジストリで保持する（弱参照による回収は本Phaseでは扱わない）。

教材Level21-BのL700完成コードは、DEFCOMMANDのlambdaに名前付きblockがないのにTAKE/DROP/USE/TALKがreturn-fromを使う。SBCLもコンパイルエラーを報告する。`clos-castle.lisp`はDEFCOMMANDだけを、declareを残して名前付きblockを加える形に補正する。そのほかの完成コードはcanonical commitのまま。ゲーム生成、部屋移動、入力解析、オブジェクト印字を比較する。Level21-Aの修飾子と初期化の例も別途連続実行する。

`clos-lifecycle.lisp`はmethod combination・多値・初期化・再定義・継承・前方参照・別名・change-classをSBCLと比較する。SBCLが共通の未束縛スロットもaddedとしてフックに渡すため、その名前を比較ログから除く。CLHS 4.3.6.1に従う未束縛保持と、CLHS 4.3.6の旧アクセサ生成メソッド実体だけを削除する検査は単体試験に分離する（SBCLは外部で同じsignatureを置き換えたメソッドも削除する）。


レビュー後はproper nameに限って既存クラスを再定義する。失敗した定義は新規の前方参照クラスを解除し、元の別名登録を復元する。condition/構造体のCPLも定義時に実体で保存し、元名の解除・再登録に影響されない。`clos-lifecycle-review.lisp`は別名定義、失敗後の状態、構造体の名前交換、conditionの元名解除と親名再使用をSBCLと比較する。修正原文と対応は `clos-phase29-claude-review.md`・`clos-phase29-claude-review.ja.md`。


限定再確認後の動作：standard defclassは別名に新しいクラスを定義する。同種のcondition/structureはSBCL実測に合わせて別名先の実体を更新し元のproper nameを保持する。親CPLは直接の親実体から凍結し、旧来の定義処理だけ動的に祖先記述を参照する。元名解除後の親別名からのcondition定義はSBCL2.6.10.168自体も失敗したため、reader・reportと合わせてZilisp単体試験に置いた。成功した入れ子定義が使うplaceholderは外側の失敗後も保持する。


## 教材全体の比較

canonical commitの1107ブロック（SBCL2.6.10.168で分類済み）の候補Aは955件。Readerはboth-ok 1079、both-error 23、Zilispのみエラー5、SBCLのみエラー0でP28と同じ。

eval-checkは一致566、both-error 362、出力差1、Zilispのみエラー26、SBCLのみエラー0、timeout 0。同じSBCL版のP28比較から変わった8件はすべて一致への改善（前方参照5件、メソッド修飾子3件）。一致から失敗への変更はない。出力差は従来と同じLevel13 L455。各件の結果は `compatibility/eval-check-sbcl-2.6.10-p29.tsv` に保存した。2.6.7およびP28の結果は維持する。ツールの生成Markdownは版を2.6.7と固定表示する既存実装のため、その見出しは今回のSBCL版の証拠としない。


## 最終検証（Linux、Zig 0.17.1）

| 対象 | 結果 |
| --- | --- |
| 単体 | Debug・ReleaseSafe・ReleaseFast成功 |
| 言語 | 91/91成功（新規4本と同名のGC stress版を含む） |
| ネイティブReleaseFast | 全49/49成功、各ファイル通常・GC stress |
| ネイティブDebug | clos-lifecycle・clos-lifecycle-reviewの2/2成功、通常・GC stress |
| クロスビルド | Windows x86_64 GNU、Linux x86_64/aarch64 musl、macOS x86_64/aarch64の5種成功 |
| 書式・差分 | zig fmt成功。期待値の末尾空白・TSVの空の最終列を除くdiff check成功。新規ファイルの末尾空白とfixture複製・TSV列数も検査 |

ネイティブDebug全49件とWindows/macOSの実機実行は未実施。最終の重い試験はレビュー修正後の固定ソースで実施し、実行中に処理系を変更していない。GC stressは新規メソッド・class guardのクロージャ、rack移行、共有循環値、conditionの別名とreader/reportも含む。

レビューは初回1回・限定再確認1回。着手・受け入れとも2026-11-12（作業日1日、厳密な実働時間は未測定）。残る深い再帰の資源改善は#541。weak registry・独自メタクラス・独自メソッド結合は未実装であり、with-slots/with-accessorsはP30。
