# P28 総称関数・メソッド（2026-11-12）

対象はtque #320と子タスク #536。P27のクラス・rackを使い、VMとネイティブで同じ呼び出しABIを持つ総称関数を追加する。

## 範囲と受け入れ

- `defgeneric`・`defmethod`、primaryメソッドの継承、多重ディスパッチ、EQL特殊化、引数優先順位。
- `call-next-method`・`next-method-p`、`no-applicable-method`・`no-next-method`、メソッドの追加・削除・検索・適用可能性。
- 総称関数としてのクラスアクセサと`print-object`、`print-unreadable-object`。
- 組み込み・condition・構造体を含むクラスの一意な正のstamp。
- 教材CommonLispBasicMaster `639544c8133fdc51ffe4c2184aad785345128419`のLevel 21-A、fence行86・122・142・175・236を連続実行しSBCLと照合する。単独では未定義のsupervisorを参照するmanagerの例と、P29の修飾子・初期化フックは対象外。
- クラス再定義、before/after/around、初期化フックはP29。with-slotsはsymbol-macroletを実装するP30。

## 実装

総称関数は関数タグを持つGC管理オブジェクト。通常のEntry ABIからLispのディスパッチャを呼ぶ。メソッドもGC管理オブジェクトで、特殊化子・クロージャ・lambda-list・所有する総称関数を保持する。

キャッシュは特殊化する引数位置のクラスstampとEQL一致の真偽列から、順序づけた適用可能メソッド列を求める。EQL対象の文字列をequalでキーにすると別オブジェクトが混同されるため、値そのものをequalキーにしない。追加・置換・削除と総称関数の再宣言でキャッシュを空にする。アクセサはstamp別にスロット位置または共有セルを保持する。クラス再定義時の旧rack更新と選択的失効はP29。

キーワードは総称関数と適用可能メソッドの和集合で検査する。各メソッドの実行lambdaにはallow-other-keysを加え、他メソッドが受け付けるキーを拒まないようにする。置換引数つきcall-next-methodは、順序を含めた適用可能メソッド列が変わるとprogram-errorにする（SBCLの標準設定で検出されない例は単体試験に分離）。

## 検証とレビュー

受け入れ試験をそろえてClaude Codeに読み取り専用レビューを依頼し、修正後の確認は指摘箇所に絞った。ネイティブ試験中はソースを固定した。最終結果は末尾に記録する。


## 既知の資源上限

Lispディスパッチャは通常の関数より中間フレームを多く使う。40段の再帰は成功、600段はstorage-conditionとなる（SBCL 2.6.10.168は600段成功）。スタック安全上限を緩める修正は行わず、VM再入と中間フレームの削減をtque #541に分離した。スタック枯渇時にhandlerを起動しない既存の制限も適用される。深い印字の上限の変化は未実測。

レビューの原文と指摘別の対応は `clos-phase28-claude-review.md`・`clos-phase28-claude-review.ja.md`。

キーワード検査は[CLHS 7.6.5](https://www.lispworks.com/documentation/HyperSpec/Body/07_fe.htm)に従い、総称関数自体が&restだけでも適用メソッドに&keyがあれば行う。SBCL 2.6.10.168が検出しない不明キーは単体試験に分離した。

## 教材全体の比較

canonical commitから1107ブロックを抽出・SBCL 2.6.10.168で再分類した。候補Aは955件。Reader比較はboth-ok 1079、both-error 23、Zilispのみエラー5、SBCLのみエラー0（保存済みの集計と同じ）。

eval-checkは一致558、both-error 362、output-diff 1、Zilispのみエラー34、SBCLのみエラー0、timeout 0。保存済みの2.6.7比較から変わった13件はすべてZilispのみエラーから一致への変更で、一致から失敗への変更はない。ただしP27を含む累積差とSBCLの版の差を含むため、13件すべてをP28だけの改善とはしない。出力差1件は従来と同じLevel 13 L455。

各ブロックの結果は `compatibility/eval-check-sbcl-2.6.10-p28.tsv` に保存した。既存の2.6.7基準の結果と期待値は維持した。eval-checkの生成MarkdownはSBCL 2.6.7と固定表示する既存の実装なので、その見出しを今回の版の証拠として使わない。実行に渡したのは `/usr/local/bin/sbcl`（2.6.10.168-29d0bbc7f）。

## 最終検証（Linux、Zig 0.17.1）

| 対象 | 結果 |
| --- | --- |
| 単体試験 | Debug・ReleaseSafe・ReleaseFast成功 |
| 言語試験 | 83/83成功（新規3本とそのGC stress版を含む） |
| ネイティブReleaseFast | 全45/45成功、各ケース通常・GC stress |
| ネイティブDebug | generic・generic-review・clos-level21の3/3成功、通常・GC stress |
| クロスビルド | Windows x86_64 GNU、Linux x86_64/aarch64 musl、macOS x86_64/aarch64の5種成功 |
| 書式・差分 | zig fmt成功、期待値の意図的な末尾空白・TSVの空の最終列を除くdiff check成功 |

ネイティブDebugの全45件再実行と、Windows/macOSの実機実行は未実施。レビュー修正前および限定再確認前のネイティブ試行は、ソース変更前に停止して結果には算入せず、上記は最終固定ソースでの結果である。

初回レビュー1回、修正箇所の再確認1回。着手・受け入れはともに2026-11-12（作業日1日、厳密な実働時間は未測定）。受け入れ例と修正の検証をまとめ、追加の全面レビューは行っていない。
