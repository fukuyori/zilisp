//! 非局所脱出の方式の比較（詳細設計 §6.4。Phase 18、tque #339）。
//!
//!   方式1：特別な戻り値（Value.unwind）で1段ずつ返す。呼び出しのたびに戻り値を比べる（Zilisp の今の方式）
//!   方式2：setjmp/longjmp に相当する方式。脱出先でレジスタとスタックの位置を保存し、脱出するときに直接そこへ戻る
//!
//! 方式2の試作：Zig 0.17.0 には「2回戻る関数」（returns_twice）を扱う仕組みがないため、setjmp そのものではなく、
//! 「保存してから関数を呼ぶ」までを1つのアセンブリの関数 catchCall にした。catchCall は、呼んだ関数が普通に戻れば
//! その値を、jumpTo で脱出すればその値を返す。コンパイラから見ると catchCall は1回だけ戻る普通の呼び出しなので、
//! 呼び出し側のレジスタの扱いは正しい（callee-saved のレジスタは jumpTo が catchCall に入った時点の値に戻す）。
//! x86_64（Windows・System V）だけ。それ以外のアーキテクチャでは方式2の計測を省く。
//!
//! 計測する処理（1回 = 脱出先を作る → 深さ D の呼び出し → 脱出、または普通に戻る）
//!   enter-only    ：D = 0。脱出先を作る費用
//!   call-D        ：深さ D まで呼んで普通に戻る（方式1は呼び出しのたびの検査の費用を含む）
//!   exit-D        ：深さ D まで呼んで、いちばん深いところから脱出する
//! どちらの方式も、制御スタックへのエントリの出し入れ（throw がタグを探すため。実際の処理系では両方式で要る）を含める。

const std = @import("std");
const builtin = @import("builtin");

const UNWIND: u64 = 0x2F; // Value.unwind に相当する値
const supported = builtin.cpu.arch == .x86_64;
const windows = builtin.os.tag == .windows;

// ---------------------------------------------------------------------------
// 制御スタック（両方式で共通の部分）

const Entry = struct { tag: u64, ctx: ?*Ctx };
var control: [256]Entry = undefined;
var control_depth: usize = 0;
var pending_value: u64 = 0;

inline fn pushEntry(tag: u64, ctx: ?*Ctx) void {
    control[control_depth] = .{ .tag = tag, .ctx = ctx };
    control_depth += 1;
}

// ---------------------------------------------------------------------------
// 方式2：レジスタの保存と復元（x86_64）

/// 保存する内容：rbx rbp rdi rsi r12 r13 r14 r15 rsp（Windows は xmm6〜xmm15 も callee-saved）
const Ctx = extern struct {
    gpr: [10]u64 = @splat(0),
    xmm: [10][2]u64 = @splat(@splat(0)),
};

const Callee = *const fn (arg: u64) callconv(.c) u64;
const CatchCallFn = *const fn (ctx: *Ctx, f: Callee, arg: u64) callconv(.c) u64;
const JumpToFn = *const fn (ctx: *Ctx, v: u64) callconv(.c) noreturn;

/// catchCall(ctx, f, arg)：レジスタとスタックの位置を ctx に保存し、f(arg) を呼ぶ
fn catchCallWin() callconv(.naked) noreturn {
    // rcx = ctx, rdx = f, r8 = arg（Windows x64）
    asm volatile (
        \\movq %%rbx, 0(%%rcx)
        \\movq %%rbp, 8(%%rcx)
        \\movq %%rdi, 16(%%rcx)
        \\movq %%rsi, 24(%%rcx)
        \\movq %%r12, 32(%%rcx)
        \\movq %%r13, 40(%%rcx)
        \\movq %%r14, 48(%%rcx)
        \\movq %%r15, 56(%%rcx)
        \\movdqu %%xmm6, 80(%%rcx)
        \\movdqu %%xmm7, 96(%%rcx)
        \\movdqu %%xmm8, 112(%%rcx)
        \\movdqu %%xmm9, 128(%%rcx)
        \\movdqu %%xmm10, 144(%%rcx)
        \\movdqu %%xmm11, 160(%%rcx)
        \\movdqu %%xmm12, 176(%%rcx)
        \\movdqu %%xmm13, 192(%%rcx)
        \\movdqu %%xmm14, 208(%%rcx)
        \\movdqu %%xmm15, 224(%%rcx)
        \\subq $40, %%rsp
        \\movq %%rsp, 64(%%rcx)
        \\movq %%rdx, %%rax
        \\movq %%r8, %%rcx
        \\callq *%%rax
        \\addq $40, %%rsp
        \\retq
    );
}

/// jumpTo(ctx, v)：ctx を保存した catchCall から、値 v で戻る
fn jumpToWin() callconv(.naked) noreturn {
    // rcx = ctx, rdx = v
    asm volatile (
        \\movq 0(%%rcx), %%rbx
        \\movq 8(%%rcx), %%rbp
        \\movq 16(%%rcx), %%rdi
        \\movq 24(%%rcx), %%rsi
        \\movq 32(%%rcx), %%r12
        \\movq 40(%%rcx), %%r13
        \\movq 48(%%rcx), %%r14
        \\movq 56(%%rcx), %%r15
        \\movdqu 80(%%rcx), %%xmm6
        \\movdqu 96(%%rcx), %%xmm7
        \\movdqu 112(%%rcx), %%xmm8
        \\movdqu 128(%%rcx), %%xmm9
        \\movdqu 144(%%rcx), %%xmm10
        \\movdqu 160(%%rcx), %%xmm11
        \\movdqu 176(%%rcx), %%xmm12
        \\movdqu 192(%%rcx), %%xmm13
        \\movdqu 208(%%rcx), %%xmm14
        \\movdqu 224(%%rcx), %%xmm15
        \\movq 64(%%rcx), %%rsp
        \\movq %%rdx, %%rax
        \\addq $40, %%rsp
        \\retq
    );
}

fn catchCallSysV() callconv(.naked) noreturn {
    // rdi = ctx, rsi = f, rdx = arg（System V）
    asm volatile (
        \\movq %%rbx, 0(%%rdi)
        \\movq %%rbp, 8(%%rdi)
        \\movq %%r12, 32(%%rdi)
        \\movq %%r13, 40(%%rdi)
        \\movq %%r14, 48(%%rdi)
        \\movq %%r15, 56(%%rdi)
        \\subq $8, %%rsp
        \\movq %%rsp, 64(%%rdi)
        \\movq %%rsi, %%rax
        \\movq %%rdx, %%rdi
        \\callq *%%rax
        \\addq $8, %%rsp
        \\retq
    );
}

fn jumpToSysV() callconv(.naked) noreturn {
    // rdi = ctx, rsi = v
    asm volatile (
        \\movq 0(%%rdi), %%rbx
        \\movq 8(%%rdi), %%rbp
        \\movq 32(%%rdi), %%r12
        \\movq 40(%%rdi), %%r13
        \\movq 48(%%rdi), %%r14
        \\movq 56(%%rdi), %%r15
        \\movq 64(%%rdi), %%rsp
        \\movq %%rsi, %%rax
        \\addq $8, %%rsp
        \\retq
    );
}

// アセンブリの関数は Zig の宣言では noreturn（naked の関数の本体はアセンブリだけ）なので、そのまま呼ぶと、
// 最適化が「catchCall からは戻らない」とみなして後ろのコードを消す。関数ポインタを volatile で読み、
// 呼び出し先を最適化から隠す（ReleaseSafe・ReleaseFast で確認した。Debug では起きない）
var catch_call_ptr: CatchCallFn = if (!supported) undefined else if (windows) @ptrCast(&catchCallWin) else @ptrCast(&catchCallSysV);
var jump_to_ptr: JumpToFn = if (!supported) undefined else if (windows) @ptrCast(&jumpToWin) else @ptrCast(&jumpToSysV);

inline fn catchCall(ctx: *Ctx, f: Callee, arg: u64) u64 {
    const p = @as(*volatile CatchCallFn, &catch_call_ptr).*;
    return p(ctx, f, arg);
}

inline fn jumpTo(ctx: *Ctx, v: u64) noreturn {
    const p = @as(*volatile JumpToFn, &jump_to_ptr).*;
    p(ctx, v);
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
            // throw：タグを探して値を記録し、Value.unwind を返す
            var i = control_depth;
            while (i > 0) : (i -= 1) if (control[i - 1].tag == 1) break;
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
        if (exit_at_bottom) {
            var i = control_depth;
            while (i > 0) : (i -= 1) if (control[i - 1].tag == 1) break;
            jumpTo(control[i - 1].ctx.?, 7);
        }
        return 1;
    }
    return load(@TypeOf(m2_fn), &m2_fn)(n - 1) + 1;
}
var m2_fn: *const fn (u64) callconv(.c) u64 = &m2Down;

/// 方式1の catch：エントリを積んで本体を呼び、Value.unwind なら自分が脱出先かを確かめる
fn m1Catch(depth: u64) u64 {
    pushEntry(1, null);
    var r = load(@TypeOf(m1_fn), &m1_fn)(depth);
    control_depth -= 1;
    if (r == UNWIND) r = pending_value;
    return r;
}

/// 方式2の catch：エントリ（保存したレジスタの場所を含む）を積んで、catchCall で本体を呼ぶ
fn m2Catch(depth: u64) u64 {
    var ctx: Ctx = .{};
    pushEntry(1, &ctx);
    const r = catchCall(&ctx, load(@TypeOf(m2_fn), &m2_fn), depth);
    control_depth -= 1;
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
};

pub const deep_benchmarks = .{
    .{ "nonlocal/m1-call-100", bench(1, 100, false) },
    .{ "nonlocal/m2-call-100", bench(2, 100, false) },
    .{ "nonlocal/m1-exit-100", bench(1, 100, true) },
    .{ "nonlocal/m2-exit-100", bench(2, 100, true) },
    .{ "nonlocal/m1-exit-1000", bench(1, 1000, true) },
    .{ "nonlocal/m2-exit-1000", bench(2, 1000, true) },
};

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
}
