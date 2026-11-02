# Zig 0.17.0 の std・言語機能の照合結果

詳細設計書 §1.3 で「要検証」とした Zig の標準ライブラリと言語機能を、実物で照合した結果です。

| 項目 | 内容 |
|---|---|
| 照合日 | 2026-11-01 |
| Zig | 0.17.0（winget でインストール。`zig version` で確認） |
| std の場所 | `C:\Users\n_fuk\AppData\Local\Microsoft\WinGet\Packages\zig.zig_Microsoft.Winget.Source_8wekyb3d8bbwe\zig-x86_64-windows-0.17.0\lib\std` |
| 照合用の試験 | `tests/zig-probe/probe.zig`（`zig test tests/zig-probe/probe.zig`）、`tests/zig-probe/abi.zig`（アセンブリを出力して確認） |
| 照合した環境 | 実行：x86_64-windows（Debug・ReleaseFast）。コンパイルのみ：x86_64-linux-musl、aarch64-macos、x86_64-macos、aarch64-linux-musl、aarch64-windows |

Zig を更新したときは、この照合をやり直す（`docs/version-update-checklist.md` §3）。

## 1. std の API

| 用途 | 0.17.0 での名前・使い方 | 確認方法 | 備考 |
|---|---|---|---|
| `main` の形式 | `pub fn main(init: std.process.Init) !T`。`init.arena`・`init.gpa`・`init.io`・`init.minimal.args`・`init.environ_map` を持つ。`std.process.Init.Minimal` を受け取る形式もある | `lib/std/start.zig` 786〜837行目、`lib/std/process.zig` 31〜58行目、`zig init` のひな形 | 戻り値は `!void` / `!u8` など。`src/main.zig` は `!u8` で終了コードを返す |
| コマンドライン引数 | `init.minimal.args.toSlice(arena)` → `[]const [:0]const u8` | `lib/std/process/Args.zig` 479行目 | Windows では UTF-8（WTF-8）に変換される |
| 標準出力・標準エラー出力 | `var w: std.Io.File.Writer = .init(.stdout(), io, &buffer);` → `&w.interface`（`*std.Io.Writer`）。最後に `flush()` が必要 | `zig init` のひな形、`lib/std/Io/File.zig` 91・104行目 | 0.15 以降の `Writer` の新しい形式 |
| 固定バッファへの書き出し（試験用） | `std.Io.Writer.fixed(&buf)`、`buffered()` | `src/main.zig` の試験 | |
| 時刻（計測） | `std.Io.Timestamp.now(io, .awake)`、`t.untilNow(io, .awake).nanoseconds`（i96） | `lib/std/Io.zig` 836〜1100行目 | `std.time` には定数（`ns_per_s` など）だけが残っている |
| アロケータ | `std.heap.page_allocator`、`std.heap.ArenaAllocator`、`std.heap.DebugAllocator(.{})`、`std.heap.SmpAllocator`、`std.heap.SafeAllocator`、`std.heap.FixedBufferAllocator`、`std.heap.memory_pool` | `lib/std/heap.zig` 12〜35行目、`probe.zig` | 汎用アロケータの名前は `DebugAllocator`（旧 `GeneralPurposeAllocator`） |
| 可変長配列 | `std.ArrayList(T)` は unmanaged（`.empty` で初期化し、`append(gpa, x)` のようにアロケータを渡す） | `probe.zig` | |
| ハッシュ表 | `std.StringHashMapUnmanaged(V)`（`.empty`、`put(gpa, k, v)`）、`std.AutoHashMapUnmanaged` | `probe.zig` | |
| 多倍長整数 | `std.math.big.int.Managed`（`initSet`・`add`・`toConst`）。`Mutable`・`Const` もある | `probe.zig` | limb の配列を管理ヒープに置く設計（詳細設計 §1.3）は、`Mutable` / `Const` の limb 指定で実現する（Phase 20 で詳細を確認） |
| ハッシュ関数 | `std.hash.Wyhash.hash(seed, bytes)`、`std.hash.Crc32.hash(bytes)` | `probe.zig` | |
| UTF-16 | `std.unicode.utf8ToUtf16LeAllocZ(gpa, s)` | `probe.zig` | Windows API の境界で使う |
| 実行ファイルのパス | `std.process.executablePath(io, buf)`、`std.process.executablePathAlloc(io, gpa)` | `lib/std/process.zig` 742・769行目 | |
| 子プロセス | `std.process.Child` | `lib/std/process.zig` 19行目 | 使い方は Phase 12（`zig` の呼び出し）で確認する |
| 動的ライブラリ | `std.DynLib`（`lib/std/dynamic_library.zig`） | `lib/std/dynamic_library.zig` 14行目 | 使い方は Phase 39 で確認する |
| 終了 | `std.process.exit(status: u8)`、`std.process.fatal(fmt, args)` | `lib/std/process.zig` 698・865行目 | |
| 大きな境界にそろえた確保 | `std.heap.page_allocator.alignedAlloc(u8, .fromByteUnits(4 MiB), n)` は **Windows で失敗することがある**（2026-11-02 に Phase 06 で確認） | `lib/std/heap/PageAllocator.zig` 45〜108行目 | 最初の確保がたまたまそろえば成功するが、そろわない場合はプレースホルダーとして予約した領域を `NtAllocateVirtualMemory(COMMIT)` で確定しようとして失敗し、`OutOfMemory` を返す。Zilisp は Windows では予約（RESERVE）した範囲の中のそろった部分だけを確定する方式で回避する（`src/support/os_memory.zig`）。Windows 以外は `page_allocator` を使う |
| ディレクトリの走査・ファイル | `std.Io.Dir.cwd()`、`openDir(io, path, .{ .iterate = true })`、`walk(gpa)`（順序は不定）、`readFileAlloc(io, path, gpa, .limited(n))`、`writeFile(io, .{ .sub_path, .data })`、`createDirPath(io, path)` | `lib/std/Io/Dir.zig` | Phase 02 の道具で使用 |
| 子プロセス | `std.process.run(gpa, io, .{ .argv = ... })` → `.term`（`.exited => code`）、`.stdout`、`.stderr` | `lib/std/process.zig` 470〜507行目 | Phase 02 の言語試験の実行器で使用 |
| 書き出し先を確保する Writer | `std.Io.Writer.Allocating.init(gpa)`、`.writer`、`.written()`、`.toOwnedSlice()` | `lib/std/Io/Writer.zig` 2644行目 | |

## 2. 言語機能

| 機能 | 結果 | 詳細設計の箇所 |
|---|---|---|
| `@addWithOverflow` | 使える。**タグ（下位2ビット）を付けたまま i64 で加算すると、62ビットの fixnum の範囲を超えたときにちょうど溢れが立つ**（`most-positive-fixnum` のタグ付きの値 + タグ付きの 1 で溢れ、1 つ小さい値では溢れない） | §2.2 |
| ラベル付き `switch` と `continue :label` | 使える（VM の分岐の形で試験） | §7.1 |
| `@call(.always_tail, …)` | LLVM を使うビルドでは使える（x86_64-windows の Debug・ReleaseFast、全ターゲットの ReleaseFast）。**x86_64-linux の Debug ビルドではコンパイルエラーになる**（Zig 自前の x86_64 用コード生成器 `stage2_x86_64` が末尾呼び出しに対応していない）。末尾呼び出しを使うコードは、Debug ビルドでも LLVM を使う設定にするか、代わりの方式（詳細設計 §7A.3 のループ化・トランポリン）を用意する | §7A.3 |
| `@"…"` の識別子 | 使える（`@"cl-user::foo-bar?"` の関数を定義・呼び出し）。生成したシンボル名がデバッガ・リンカでどう表示されるかは未確認 | §7A.5 C1 |
| `std.mem.doNotOptimizeAway` | 使える（値・ポインタの両方） | §3.4 |
| callee-saved レジスタの退避 | 空のインラインアセンブリに clobber を指定する書き方はコンパイルできるが、退避先がローカル変数より下に置かれない保証がない。Phase 07 のレビューを受けて、**レジスタの値を直接読む方式**に変更した：`asm volatile ("" : [v] "={rbx}" (-> usize))`。制約の文字列は文字列リテラルでなければならない（`"={" ++ r ++ "}"` はコンパイルエラー。命令の文字列の方は `++` で組み立ててよい） | §3.4 手順1 |
| インラインアセンブリの制限 | (1) メモリを指す書き方 `movq %%rbx, 0(%[r])` は、Zig 自前の x86_64 用コード生成器（x86_64-linux の Debug）で `invalid memory operand` になる。(2) フレームポインタ `"={rbp}"`（ReleaseSafe・ReleaseFast）・`"={x29}"`（aarch64）は `Interference usage of base pointer/frame pointer`・`couldn't allocate output register` になるので、`movq %%rbp, %[v]` / `mov %[v], x29` と `"=r"` で読む。(3) スタックポインタは `movq %%rsp, %[sp]` / `mov %[sp], sp`。(4) clobber の名前は `std.lang.assembly.Clobbers`（x86_64 の条件コードは `.cc`、aarch64 は `.nzcv`） | §3.4 |
| `extern struct` を含む error union、`callconv(.c)` | どちらもコンパイル・実行できる | §6.2 |
| ビルドの種類 | `@import("builtin").mode` の型は `std.lang.Optimize` で、値は `.debug`・`.safe`・`.fast`・`.small`（旧 `.Debug`・`.ReleaseSafe` など） | Phase 07 |
| `@frameAddress()` | 最適化ありのビルドでは、その関数自身のローカル変数が `@frameAddress()` より高いアドレスに置かれることがある。GC の保守的走査の上端に、値を持つ関数自身のフレームの位置を使ってはならない（詳細設計 §3.4） | §3.4 |
| スタックの上端（Windows） | `std.os.windows.teb().NtTib.StackBase` | §3.4 |
| 構造体のフィールドの一覧 | `std.meta.fields` は 0.17.0 で廃止（`@compileError`）。`@typeInfo(T).@"struct".field_names`（名前の配列）と `field_types` を使う | Phase 08 |
| 1 行ずつの入力 | `std.Io.File.Reader.init(.stdin(), io, &buf)` の `interface` に `takeDelimiter('\n')`（終わりで null、行がバッファより長ければ `error.StreamTooLong`） | Phase 08 の REPL |
| 書き捨ての Writer | `std.Io.Writer.discarding` はない。`.fixed(&buf)` を使う（あふれると `error.WriteFailed`） | Phase 08 のベンチマーク |
| enum と整数の変換 | `@intFromEnum` / `@enumFromInt` は、0.17.0 では `@backingInt` / `@fromBackingInt` に置き換わっている。`zig fmt` が旧い書き方を自動で書き換える（`@enumFromInt(x)` → `@fromBackingInt(@intCast(x))`） | §2（Value を `enum(u64)` にする場合に使う） |

## 3. 戻り値の返し方（詳細設計 §6.2 の要検証項目）

`tests/zig-probe/abi.zig` を ReleaseFast でコンパイルし、出力したアセンブリで確認した。

| 戻り値の型 | x86_64-windows | x86_64-linux | aarch64-macos |
|---|---|---|---|
| `Error!Ret`（`Ret` は16バイトの `extern struct`） | メモリ | メモリ | メモリ |
| `Ret` 相当の16バイトの構造体（Zig の既定の呼び出し規約） | メモリ | メモリ | メモリ |
| `extern struct` の `Ret`、`callconv(.c)` | メモリ（Windows x64 の C ABI の規則） | **レジスタ**（`rax:rdx`） | **レジスタ**（`x0:x1`） |
| 8バイトの `extern struct` の Value（既定の呼び出し規約） | メモリ | メモリ | メモリ |
| **8バイトの `enum(u64)` の Value（既定の呼び出し規約）** | **レジスタ**（`rax`） | **レジスタ**（`rax`） | **レジスタ**（`x0`） |
| `Error!Value`（Value は `enum(u64)`） | メモリ | メモリ | メモリ |

「メモリ」は、呼び出し側が渡した隠れたポインタ（`rcx`・`rdi`・`x0`）の指す領域に書き込んで返すことを表す。

### 設計への影響（2026-11-01 に案 A で決定し、詳細設計書 §2.1・§6.2・§6.4・§6.6・§7A.2 に反映済み）

1. **`Value` は `enum(u64)` で定義する。** `extern struct` で定義すると、8バイトでもメモリ経由で返される。
2. **詳細設計 §6.2 の `Error!Ret` は、すべてのターゲットでメモリ経由になる。** 呼び出し規約は次のどちらかに変える必要がある（Phase 08 の前に決める。Phase 12 で計測して確定する）。
   - 案 A：戻り値は主値の `Value`（`enum(u64)`。レジスタで返る）だけにする。非局所脱出などのエラーは、決まった特別な即値（Lisp の値としては現れない値）を返して表し、値の個数は `Thread` の欄に書く。
   - 案 B：`callconv(.c)` の16バイトの構造体で主値と個数を返す。Linux と macOS ではレジスタで返るが、**開発の一次ターゲットである Windows ではメモリ経由になる**。
3. 高速入口（単値）の `Error!Value` もメモリ経由になるため、案 A と同じ方式（特別な即値でエラーを表す）にそろえる必要がある。

## 4. ビルド

| 項目 | 結果 |
|---|---|
| `zig init` のひな形 | `build.zig` は `b.addExecutable(.{ .root_module = b.createModule(...) })`、`b.addTest(.{ .root_module = ... })`、`run_cmd.addPassthruArgs()` の形 |
| `build.zig.zon` | `.fingerprint` が必須。初回の `zig build` が値を提示する（Zilisp は `0xedb879257924792a`） |
| クロスビルド（ReleaseFast） | x86_64-windows、x86_64-linux-musl、aarch64-macos、x86_64-macos、aarch64-linux-musl、aarch64-windows のすべてで成功（実機での動作は未確認） |
| PowerShell からの指定 | `zig build "-Dtarget=$t"` のように引用符で囲む（囲まないと変数が展開されない） |
