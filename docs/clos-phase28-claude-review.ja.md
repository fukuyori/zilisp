# P28 Claude Codeレビュー対応（2026-11-12）

Claude Code CLIにP28の差分と新規ファイル・受け入れ範囲を渡し、Read/Grep/Globだけの読み取り専用レビューを依頼した。初回は静的な指摘5件（中2・低3）。原文は `clos-phase28-claude-review.md`。再現はこの環境のSBCL 2.6.10.168とZilispで実施した。

| 指摘 | 再現と対応 |
| --- | --- |
| 1 暗黙の総称関数に最初のメソッドのキーが残る | 再現。暗黙宣言はbare &keyとし、キー名とallow-other-keysを引き継がない。異なるクラスのメソッドが別のキーを持つ例、適用されないメソッドのキーを拒む例を追加。SBCLのMOPで暗黙lambda-listも確認。 |
| 2 深い再帰でフレームを多く消費する | 再現。600段はSBCL成功、ZilispはVMスタックのstorage-conditionで終了し、クラッシュしない。40段成功と600段の制限を単体試験に記録。Lispディスパッチャの中間フレームの削減をtque #541に登録した。安全上限は緩めない。深い印字の限界がどの程度変わるかは未実測。 |
| 3 既定のprint-objectが整数までunreadableにする | 再現。通常のオブジェクトはwrite、メタオブジェクトは再ディスパッチしないZigの印字、標準インスタンスはunreadable、condition・構造体は既存の印字を使用。readablyの整数・リストも比較。 |
| 4 アクセサ失敗後にクラスだけ残る | 再現。全アクセサの通常関数との衝突、既存GFとの引数の不一致、同じ定義内のreader/writerの引数の衝突をクラス登録前に検査する。通常関数へのdefmethodはprogram-errorにした。失敗後の再定義成功も比較。 |
| 5 defgeneric内の古い:methodが残る | 再現。inlineメソッドを記録し、再宣言で取り除く。外部のdefmethodと、inlineメソッドを置き換えた外部メソッドは保持する。 |

独自確認でも、クラス・standard-method・standard-generic-functionへのprint-object特殊化を通常の印字経路が呼ばない問題を見つけた。直接・リスト内・print-pretty NILの経路を修正し、SBCLとの一致を確認した。

回帰試験は `tests/language/eval/generic-review.lisp` と同名のGC stress試験。再帰の資源上限と、SBCLが既定で検出しないcall-next-method置換引数の検査は `src/compiler/eval_test.zig` に分離した。資源上限は `tests/differential/impl-dependent.toml` にも記録した。

## 修正後の確認

Claude Codeへの再確認は修正箇所と回帰に絞って1回依頼した。修正3・4・5は問題なし、キーワード検査に追加指摘1件（低〜中）があった。原文は英語記録の末尾に保存した。

追加指摘の「SBCLではエラー」は2.6.10.168で再現せず、暗黙・明示ともNILだった。ただし[CLHS 7.6.5](https://www.lispworks.com/documentation/HyperSpec/Body/07_fe.htm)は、適用されるメソッドに&keyがある場合もキーの検査を求める。この規則に合わせ、総称関数が&restだけの場合も適用メソッドのキーを検査するよう修正した。不明キー・奇数個の引数・allow-other-keys・適用メソッドが&restだけの正常例を単体試験に追加した。SBCLとの差は処理系依存の記録にも明記した。

同じ原文照合で、[CLHS 3.4.2](https://www.lispworks.com/documentation/HyperSpec/Body/03_db.htm)が許す`&optional (x)`・`&key (x)`も受理するようにした。正常例はSBCLと一致し、言語回帰試験に追加した。追加の全面レビューは行わず、再現・原文・試験で確認した。

最終固定ソースで、単体Debug・ReleaseSafe・ReleaseFast、言語83/83、ネイティブReleaseFast全45/45、ネイティブDebug新規3/3（いずれも通常・GC stress）、クロス5種、fmtが成功した。教材比較は一致558・both-error 362・出力差1・Zilispのみエラー34。詳細と未実施範囲は `clos-phase28-plan.ja.md`。初回1回・限定再確認1回で区切った。
