# Changelog

## Unreleased

### Added
- 企画・基本設計書（v0.3）と詳細設計書（v0.2）
- MIT ライセンス
- Phase 01：`build.zig` / `build.zig.zon`（Zig 0.17.0）、CLI の骨組み（`--version` / `--help`）、
  ベンチマークの実行器（`zig build bench`、`scripts/run-bench.ps1`）、
  リリースビルドのスクリプト（`scripts/build-release.ps1`）、
  バージョン更新チェックリスト、Zig 0.17.0 の std・言語機能の照合結果（`docs/zig-std-usage.md`）
- Phase 02：言語試験の実行器（`zig build lang-test`）、教材のコードブロックの抽出（`zig build extract-samples`）、
  SBCL による読み込みだけの分類（`tools/classify_samples/classify.lisp`）、
  `scripts/curriculum-inventory.ps1`、`compatibility/curriculum-inventory.md`、`compatibility/manifest.toml`（初期版）
- Phase 03：Reader の基本（`src/reader/`）。空白、コメント（`;`・`#| |#` の入れ子）、整数・比・浮動小数
  （`*read-base*`・`*read-default-float-format*`・指数の記号）、シンボル（エスケープ、パッケージ修飾、
  大文字への変換）、位置情報（行・列）。値を作る処理は Builder として差し替え可能（Value との接続は Phase 05）。
  SBCL との処理系依存の違いを `tests/differential/impl-dependent.toml` に記録
- Phase 04：Reader のマクロ文字。quote、文字列、リスト（ドット対）、`#'`、`#(`（`#n(` を含む）、`#\`（標準・準標準の名前、`U+XXXX`）、
  `#:`、`#b #o #x #nR`、backquote（`zl-sys:quasiquote` など）、`#+` / `#-`（`*read-suppress*`、`*features*`）。
  `#P #S #C #A #. #= ##` は後の Phase まで明示的な reader-error。
  教材のブロックを Zilisp の Reader で読み SBCL と比べる道具（`zig build reader-check`）
- Phase 05：8 バイトの Value（`enum(u64)`、下位ビットのタグ。`src/values/`）、オブジェクトの形（シンボル 64 バイト、
  cons 16 バイト、文字列、単純ベクタ、double-float、パッケージ）、仮のヒープ（Phase 06 で置き換え）、
  パッケージと intern（CL・CL-USER・KEYWORD・ZILISP・ZILISP-SYSTEM。CL の 978 シンボルは SBCL から生成：
  `tools/gen_cl_symbols/gen.lisp`）、Reader を Value につなぐ Builder、印字（prin1 相当。SBCL 2.6.7 と同じ形）、
  `zilisp --read FILE`、言語試験 `tests/language/reader/`（SBCL の出力と一致）、NIL の表現 A/B/C の計測（A を採用）
- Phase 06：ページ単位のヒープ（`src/runtime/heap.zig`）。4 MiB のチャンク（4 MiB 境界）、32 KiB のページ、
  cons 専用のページ、28 のサイズクラス、大きいオブジェクトの連続ページ、ページ外の使用中ビット・マークビット、
  アドレスからオブジェクトの先頭を求める処理（途中を指すポインタを含む）、確保の統計。
  明示的なルートと FFI handle（世代番号つき。`src/runtime/roots.zig`）。
  Windows で大きな境界にそろえた確保を行う `src/support/os_memory.zig`（Zig 0.17.0 の page_allocator の問題の回避）。
  確保のベンチマーク（`tests/bench/alloc.zig`）
- Phase 07：mark-and-sweep GC（`src/runtime/gc.zig`）。マークスタック、正確なルート（パッケージ・NIL・明示的ルート・
  FFI handle）と保守的なルート（ネイティブのスタックとレジスタ）、finalize 待ちの一覧（文字列のバッファの解放）、
  大きいオブジェクトの即時回収、小さいページの遅延スイープ、空になったページの再利用、GC の契機
  （max(8 MiB, 生存量 × 2)）、`--gc-stress`、回収した領域を 0xAA で埋める（Debug）、統計と `--gc-stats`。
  言語試験 `tests/language/gc-stress/`、GC の停止時間のベンチマーク（`tests/bench/gc.zig`）
- Phase 08：最小のコンパイラと VM、REPL。
  Resolver（`src/compiler/resolver.zig`。`quote` `if` `progn` `let` `setq` `function` `lambda`、捕捉と代入の解析）、
  Core IR（`ir.zig`）、バイトコードの生成（`codegen.zig`。捕捉され代入される変数は value_cell に入れる）と検証器（`src/vm/verify.zig`）、
  スタック型の VM（`src/vm/vm.zig`。VM の closure どうしの呼び出しは同じ実行ループの中でフレームを積む、fixnum の高速経路、`WIDE`）、
  関数オブジェクト（`src/runtime/function.zig`：code・closure・native_function）、スレッドの状態（`src/runtime/thread.zig`）、
  プリミティブ（`src/primitives/`：`+ - * / 1+ 1- = /= < > <= >=`、`cons car cdr first rest list list* null not atom consp listp
  symbolp numberp functionp eq eql`、`funcall apply`、`print prin1 terpri`）、
  CLI（`zilisp`＝REPL、`zilisp FILE`・`--script FILE`、`--eval TEXT`、`--load FILE`）。
  condition（Phase 25）ができるまでは、Lisp のエラーを型の名前と説明で報告する。
  言語試験 `tests/language/eval/`（SBCL の出力と一致）、VM のベンチマーク（`tests/bench/vm.zig`）
- Phase 09：`let*`（束縛を順に行う。同じ名前を2回束縛してよい。SBCL 2.6.7 と同じ）。
  `let`・`let*` の束縛と shadowing の試験（SBCL 2.6.7 の結果と比べる20通り。GC stress でも実行）、
  言語試験 `tests/language/eval/let.lisp`（と gc-stress 版）
- Phase 10：`defun`（Zig で書いたブートストラップ用のマクロ。`zl-sys::%defun` に展開する。名前の付いた関数は
  `#<FUNCTION 名前>` と印字する。COMMON-LISP パッケージのシンボルの関数の定義は package-error）、`fboundp`、`symbol-function`。
  VM のフレームの上限を値スタックの 1/4（既定 262144）に。再帰・相互再帰・再定義・高階関数の試験（SBCL 2.6.7 の結果と比べる）、
  言語試験 `tests/language/eval/functions.lisp`（と gc-stress 版）

### Changed
- VM の命令の分岐を、ラベル付き `switch` と `continue` に書き換えた（詳細設計 §7.1）。
  fib(25) が 5.08 ms から 2.97 ms に（約41%短縮）。実行ループと関係のない変更で速さが揺れる問題もなくなった

### Fixed
- Codex による Phase 07 のレビューの指摘10件
  - `readAll` が読んだ値を GC が走査しない Zig の配列に溜めていた（Lisp のリストで返し、読んでいる間は明示的なルートに登録する）
  - ベクタを作るときに要素を Zig の配列に写していた（ベクタを確保してからリストから直接埋める）
  - レジスタの退避をコンパイラ任せにしていた（callee-saved レジスタの値を直接読み、現在のスタックポインタから走査する）。
    レジスタにだけ参照がある場合の試験を追加
  - シンボルの表への登録とパッケージの作成で、確保に失敗すると表・一覧が壊れていた（確保を先に済ませる）。
    確保をすべての位置で失敗させる試験を追加
  - 大きいオブジェクトの大きさを u32 で持っていたため、4 GiB を超えると途中のポインタを認識できなかった
  - 大きいオブジェクトの再利用で、空きページの一覧に同じページが重なって増え続けた
  - `1||` が整数に、`:||` がエラーになっていた（空のエスケープ `||` もエスケープとして扱う。SBCL 2.6.7 と同じ）
  - 読み飛ばしの最中の `#n=` が、続くオブジェクトを読み飛ばしていなかった
  - GC のベンチマークが、値を持つ関数自身の `@frameAddress()` を走査の上端にしていた
- Codex による Phase 08 のレビューの指摘6件
  - Zig の関数どうしの呼び出し（apply から apply など）が、入れ子の深さの上限を通らなかった（プリミティブの呼び出しも Thread.call で数える）
  - VM の値スタックの使い終わった枠に残った値まで GC のルートにしていた（[0, sp) だけを走査する）
  - REPL で、フォームの途中で入力が終わっても何も報告せず、終了コード 0 で終わっていた（END-OF-FILE を報告し、終了コード 1）
  - `notinline` の宣言を無視して、高速経路の命令にしていた
  - 本体の先頭の説明文字列を何個でも読み飛ばしていた（1つまで。2つ目の文字列の後の declare はエラー）
  - 検証器が、到達しない命令のジャンプ先が命令の途中を指すものを見逃していた
