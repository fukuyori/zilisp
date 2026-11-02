//! 非局所脱出の方式の比較（詳細設計 §6.4。Phase 18、tque #339）。
//!
//!   方式1：特別な戻り値（Value.unwind）で1段ずつ返す。呼び出しのたびに戻り値を比べる（Zilisp の今の方式）
//!   方式2：setjmp/longjmp に相当する方式。脱出先でレジスタとスタックの位置を保存し、脱出するときに直接そこへ戻る
//!
//! 方式2の試作：Zig 0.17.0 には「2回戻る関数」（returns_twice）を扱う仕組みがないため、setjmp そのものではなく、
//! 「保存してから関数を呼ぶ」までを1つのアセンブリの関数 zl_catch_call にした。zl_catch_call は、呼んだ関数が普通に
//! 戻ればその値を、zl_jump_to で脱出すればその値を返す。コンパイラから見ると zl_catch_call は1回だけ戻る普通の
//! 呼び出しなので、呼び出し側のレジスタの扱いは正しい（callee-saved のレジスタと、浮動小数の制御の状態（MXCSR・
//! x87 の制御語）は、zl_jump_to が zl_catch_call に入った時点の値に戻す）。
//! アセンブリはモジュールの大域のアセンブリに書き、extern の関数として宣言して直接呼ぶ（実際の処理系でランタイムの
//! 関数を呼ぶのと同じ形。naked の関数を関数ポインタで呼ぶ形は、最適化が noreturn とみなす問題があった：
//! docs/zig-std-usage.md）。x86_64（Windows・System V）だけ。それ以外のアーキテクチャでは方式2の計測を省く。
//!
//! 計測する処理（1回 = 脱出先を作る → 深さ D の呼び出し → 脱出、または普通に戻る）
//!   enter-only    ：D = 0。脱出先を作る費用
//!   call-D        ：深さ D まで呼んで普通に戻る（方式1は呼び出しのたびの検査の費用を含む）
//!   exit-D        ：深さ D まで呼んで、いちばん深いところから脱出する
//! どちらの方式も、制御スタックへのエントリの出し入れと、throw がタグを探す処理を含める（実際の処理系では両方式で要る）。
//! 脱出先のエントリの上に別のタグのエントリを2つ積み、探す処理が1回で終わらないようにする。探した結果は、方式1では
//! 脱出先の番号として記録して着地で照合し、方式2ではジャンプ先の取得に使う（Codex のレビュー P18 #7）。

const std = @import("std");
const builtin = @import("builtin");

const UNWIND: u64 = 0x2F; // Value.unwind に相当する値
// 大域のアセンブリは、Zig 自前のコード生成器（x86_64-linux の Debug など）では出力されない（関数が未定義になる）ので、
// LLVM でコンパイルするときだけ方式2を対象にする
const supported = builtin.cpu.arch == .x86_64 and builtin.zig_backend == .stage2_llvm;
const windows = builtin.os.tag == .windows;

// ---------------------------------------------------------------------------
// 制御スタック（両方式で共通の部分）

const Entry = struct { tag: u64, ctx: ?*Ctx };
var control: [256]Entry = undefined;
var control_depth: usize = 0;
var pending_value: u64 = 0;
var pending_target: usize = 0;

inline fn pushEntry(tag: u64, ctx: ?*Ctx) void {
    control[control_depth] = .{ .tag = tag, .ctx = ctx };
    control_depth += 1;
}

/// throw のタグ（1）のエントリを上から探す
inline fn findTag() usize {
    var i = control_depth;
    while (i > 0) : (i -= 1) if (control[i - 1].tag == 1) return i - 1;
    unreachable;
}

// ---------------------------------------------------------------------------
// 方式2：レジスタの保存と復元（x86_64）

/// 保存する内容：rbx rbp rdi rsi r12 r13 r14 r15 rsp（0〜72）、xmm6〜xmm15（80〜239。Windows だけ）、
/// MXCSR（240）、x87 の制御語（244）
const Ctx = extern struct {
    gpr: [10]u64 = @splat(0),
    xmm: [10][2]u64 = @splat(@splat(0)),
    mxcsr: u32 = 0,
    x87cw: u16 = 0,
    pad: u16 = 0,
};

comptime {
    std.debug.assert(@offsetOf(Ctx, "mxcsr") == 240 and @offsetOf(Ctx, "x87cw") == 244);
}

const Callee = *const fn (arg: u64) callconv(.c) u64;

extern fn zl_catch_call(ctx: *Ctx, f: Callee, arg: u64) callconv(.c) u64;
extern fn zl_jump_to(ctx: *Ctx, v: u64) callconv(.c) noreturn;

// Windows x64：rcx = ctx, rdx = f, r8 = arg / rcx = ctx, rdx = v
const asm_windows =
    \\.text
    \\.globl zl_catch_call
    \\zl_catch_call:
    \\movq %rbx, 0(%rcx)
    \\movq %rbp, 8(%rcx)
    \\movq %rdi, 16(%rcx)
    \\movq %rsi, 24(%rcx)
    \\movq %r12, 32(%rcx)
    \\movq %r13, 40(%rcx)
    \\movq %r14, 48(%rcx)
    \\movq %r15, 56(%rcx)
    \\movdqu %xmm6, 80(%rcx)
    \\movdqu %xmm7, 96(%rcx)
    \\movdqu %xmm8, 112(%rcx)
    \\movdqu %xmm9, 128(%rcx)
    \\movdqu %xmm10, 144(%rcx)
    \\movdqu %xmm11, 160(%rcx)
    \\movdqu %xmm12, 176(%rcx)
    \\movdqu %xmm13, 192(%rcx)
    \\movdqu %xmm14, 208(%rcx)
    \\movdqu %xmm15, 224(%rcx)
    \\stmxcsr 240(%rcx)
    \\fnstcw 244(%rcx)
    \\subq $40, %rsp
    \\movq %rsp, 64(%rcx)
    \\movq %rdx, %rax
    \\movq %r8, %rcx
    \\callq *%rax
    \\addq $40, %rsp
    \\retq
    \\.globl zl_jump_to
    \\zl_jump_to:
    \\movq 0(%rcx), %rbx
    \\movq 8(%rcx), %rbp
    \\movq 16(%rcx), %rdi
    \\movq 24(%rcx), %rsi
    \\movq 32(%rcx), %r12
    \\movq 40(%rcx), %r13
    \\movq 48(%rcx), %r14
    \\movq 56(%rcx), %r15
    \\movdqu 80(%rcx), %xmm6
    \\movdqu 96(%rcx), %xmm7
    \\movdqu 112(%rcx), %xmm8
    \\movdqu 128(%rcx), %xmm9
    \\movdqu 144(%rcx), %xmm10
    \\movdqu 160(%rcx), %xmm11
    \\movdqu 176(%rcx), %xmm12
    \\movdqu 192(%rcx), %xmm13
    \\movdqu 208(%rcx), %xmm14
    \\movdqu 224(%rcx), %xmm15
    \\ldmxcsr 240(%rcx)
    \\fldcw 244(%rcx)
    \\movq 64(%rcx), %rsp
    \\movq %rdx, %rax
    \\addq $40, %rsp
    \\retq
    \\.globl zl_get_mxcsr
    \\zl_get_mxcsr:
    \\subq $8, %rsp
    \\stmxcsr (%rsp)
    \\movl (%rsp), %eax
    \\addq $8, %rsp
    \\retq
    \\.globl zl_set_mxcsr
    \\zl_set_mxcsr:
    \\subq $8, %rsp
    \\movl %ecx, (%rsp)
    \\ldmxcsr (%rsp)
    \\addq $8, %rsp
    \\retq
    \\
;

// System V：rdi = ctx, rsi = f, rdx = arg / rdi = ctx, rsi = v
const asm_sysv =
    \\.text
    \\.globl zl_catch_call
    \\zl_catch_call:
    \\movq %rbx, 0(%rdi)
    \\movq %rbp, 8(%rdi)
    \\movq %r12, 32(%rdi)
    \\movq %r13, 40(%rdi)
    \\movq %r14, 48(%rdi)
    \\movq %r15, 56(%rdi)
    \\stmxcsr 240(%rdi)
    \\fnstcw 244(%rdi)
    \\subq $8, %rsp
    \\movq %rsp, 64(%rdi)
    \\movq %rsi, %rax
    \\movq %rdx, %rdi
    \\callq *%rax
    \\addq $8, %rsp
    \\retq
    \\.globl zl_jump_to
    \\zl_jump_to:
    \\movq 0(%rdi), %rbx
    \\movq 8(%rdi), %rbp
    \\movq 32(%rdi), %r12
    \\movq 40(%rdi), %r13
    \\movq 48(%rdi), %r14
    \\movq 56(%rdi), %r15
    \\ldmxcsr 240(%rdi)
    \\fldcw 244(%rdi)
    \\movq 64(%rdi), %rsp
    \\movq %rsi, %rax
    \\addq $8, %rsp
    \\retq
    \\.globl zl_get_mxcsr
    \\zl_get_mxcsr:
    \\stmxcsr -4(%rsp)
    \\movl -4(%rsp), %eax
    \\retq
    \\.globl zl_set_mxcsr
    \\zl_set_mxcsr:
    \\movl %edi, -4(%rsp)
    \\ldmxcsr -4(%rsp)
    \\retq
    \\
;

comptime {
    if (supported) asm (if (windows) asm_windows else asm_sysv);
}

/// 呼び出しの連鎖の関数ポインタ（volatile で読み、再帰がループに変わらないようにする）
inline fn load(comptime T: type, ptr: *T) T {
    return @as(*volatile T, ptr).*;
}

// ---------------------------------------------------------------------------
// 呼び出しの連鎖。関数ポインタを通して呼び、最適化で再帰がループにならないようにする

var exit_at_bottom = false;

fn m1Down(n: u64) callconv(.c) u64 {
    if (n == 0) {
        if (exit_at_bottom) {
            // throw：タグを探して脱出先と値を記録し、Value.unwind を返す
            pending_target = findTag();
            pending_value = 7;
            return UNWIND;
        }
        return 1;
    }
    const r = load(@TypeOf(m1_fn), &m1_fn)(n - 1);
    if (r == UNWIND) return UNWIND;
    return r + 1;
}
var m1_fn: *const fn (u64) callconv(.c) u64 = &m1Down;

fn m2Down(n: u64) callconv(.c) u64 {
    if (n == 0) {
        if (exit_at_bottom) zl_jump_to(control[findTag()].ctx.?, 7);
        return 1;
    }
    return load(@TypeOf(m2_fn), &m2_fn)(n - 1) + 1;
}
var m2_fn: *const fn (u64) callconv(.c) u64 = &m2Down;

/// 脱出先のエントリの上に、別のタグのエントリを2つ積む（探す処理が1回で終わらないように）
inline fn pushOthers() void {
    pushEntry(2, null);
    pushEntry(3, null);
}

/// 方式1の catch：エントリを積んで本体を呼び、Value.unwind なら自分が脱出先かを確かめる
fn m1Catch(depth: u64) u64 {
    const me = control_depth;
    pushEntry(1, null);
    pushOthers();
    var r = load(@TypeOf(m1_fn), &m1_fn)(depth);
    control_depth = me;
    if (r == UNWIND) {
        if (pending_target != me) unreachable; // 脱出先は自分だけ
        r = pending_value;
    }
    return r;
}

/// 方式2の catch：エントリ（保存したレジスタの場所を含む）を積んで、zl_catch_call で本体を呼ぶ
fn m2Catch(depth: u64) u64 {
    var ctx: Ctx = .{};
    const me = control_depth;
    pushEntry(1, &ctx);
    pushOthers();
    const r = zl_catch_call(&ctx, load(@TypeOf(m2_fn), &m2_fn), depth);
    control_depth = me;
    return r;
}

fn runM1(comptime depth: u64, comptime exit: bool, iterations: u64) void {
    exit_at_bottom = exit;
    var sum: u64 = 0;
    var i: u64 = 0;
    while (i < iterations) : (i += 1) sum +%= m1Catch(depth);
    std.mem.doNotOptimizeAway(sum);
}

fn runM2(comptime depth: u64, comptime exit: bool, iterations: u64) void {
    if (!supported) return;
    exit_at_bottom = exit;
    var sum: u64 = 0;
    var i: u64 = 0;
    while (i < iterations) : (i += 1) sum +%= m2Catch(depth);
    std.mem.doNotOptimizeAway(sum);
}

fn bench(comptime method: u8, comptime depth: u64, comptime exit: bool) fn (u64) void {
    return struct {
        fn run(iterations: u64) void {
            if (method == 1) runM1(depth, exit, iterations) else runM2(depth, exit, iterations);
        }
    }.run;
}

pub const benchmarks = .{
    .{ "nonlocal/m1-enter-only", bench(1, 0, false) },
    .{ "nonlocal/m2-enter-only", bench(2, 0, false) },
    .{ "nonlocal/m1-call-10", bench(1, 10, false) },
    .{ "nonlocal/m2-call-10", bench(2, 10, false) },
    .{ "nonlocal/m1-exit-0", bench(1, 0, true) },
    .{ "nonlocal/m2-exit-0", bench(2, 0, true) },
    .{ "nonlocal/m1-exit-10", bench(1, 10, true) },
    .{ "nonlocal/m2-exit-10", bench(2, 10, true) },
    .{ "nonlocal/m1-exit-20", bench(1, 20, true) },
    .{ "nonlocal/m2-exit-20", bench(2, 20, true) },
};

pub const deep_benchmarks = .{
    .{ "nonlocal/m1-call-100", bench(1, 100, false) },
    .{ "nonlocal/m2-call-100", bench(2, 100, false) },
    .{ "nonlocal/m1-exit-100", bench(1, 100, true) },
    .{ "nonlocal/m2-exit-100", bench(2, 100, true) },
    .{ "nonlocal/m1-exit-1000", bench(1, 1000, true) },
    .{ "nonlocal/m2-exit-1000", bench(2, 1000, true) },
};

// MXCSR の読み書き（試験用）。インラインアセンブリのメモリのオペランドは、Zig 自前の x86_64 用コード生成器
// （x86_64-linux の Debug）で使えないため、大域のアセンブリに書く（System V はレッドゾーンを使う）
extern fn zl_get_mxcsr() callconv(.c) u32;
extern fn zl_set_mxcsr(v: u32) callconv(.c) void;

/// 丸めの方向を変えてから脱出する本体（zl_jump_to が MXCSR を戻すことの試験）
fn changeRoundingAndJump(arg: u64) callconv(.c) u64 {
    _ = arg;
    zl_set_mxcsr(zl_get_mxcsr() | 0x6000); // 0 への丸め
    zl_jump_to(control[findTag()].ctx.?, 9);
}

test "method 2 prototype returns normally and by jumping" {
    if (!supported) return;
    exit_at_bottom = false;
    try std.testing.expectEqual(@as(u64, 11), m2Catch(10));
    exit_at_bottom = true;
    try std.testing.expectEqual(@as(u64, 7), m2Catch(10));
    try std.testing.expectEqual(@as(u64, 7), m2Catch(0));
    try std.testing.expectEqual(@as(usize, 0), control_depth);
    exit_at_bottom = false;
    try std.testing.expectEqual(@as(u64, 11), m1Catch(10));
    exit_at_bottom = true;
    try std.testing.expectEqual(@as(u64, 7), m1Catch(10));
    try std.testing.expectEqual(@as(usize, 0), control_depth);
    // 本体が変えた浮動小数の制御の状態は、脱出で元に戻る（Codex のレビュー P18 #6）
    const before = zl_get_mxcsr();
    var ctx: Ctx = .{};
    pushEntry(1, &ctx);
    try std.testing.expectEqual(@as(u64, 9), zl_catch_call(&ctx, &changeRoundingAndJump, 0));
    control_depth = 0;
    try std.testing.expectEqual(before, zl_get_mxcsr());
}
