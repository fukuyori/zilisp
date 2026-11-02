//! VM の実行速度（Phase 08。詳細設計 §13.2）。
//!   vm/fib-25        ：(funcall fib 25)。1 回あたり＝fib 25 の計算 1 回（関数呼び出し約 24 万回）
//!   vm/closure-calls ：捕捉した変数を更新する closure を、再帰の中から 1 万回呼ぶ。1 回あたり＝その 1 万回
//! 比較の基準は Phase 12 のネイティブバックエンド（同じ式の Zig 生成コード）。

const std = @import("std");
const zl = @import("zilisp");
const Value = zl.value.Value;
const Runtime = zl.runtime.Runtime;
const Thread = zl.thread.Thread;

var discard_buf: [256]u8 = undefined;

fn evalAll(th: *Thread, text: []const u8) Value {
    var src = zl.reader.Source.init(text, 0);
    var b: zl.value_builder.ValueBuilder = .{ .rt = th.rt };
    var r = zl.reader.Reader(zl.value_builder.ValueBuilder).init(std.heap.smp_allocator, &src, &b, .{});
    defer r.deinit();
    var last = Value.nil;
    while (r.read() catch @panic("read")) |form| {
        last = zl.eval.eval(th, form);
        if (last == Value.unwind) @panic("eval");
    }
    return last;
}

fn benchText(comptime setup: []const u8, comptime body: []const u8) fn (u64) void {
    return struct {
        fn run(iterations: u64) void {
            const rt = Runtime.create(std.heap.smp_allocator) catch unreachable;
            defer rt.destroy();
            rt.stack_top = @frameAddress();
            @call(.never_inline, inner, .{ rt, iterations });
        }
        fn inner(rt: *Runtime, iterations: u64) void {
            var w: std.Io.Writer = .fixed(&discard_buf);
            const th = Thread.create(rt, &w, .{}) catch unreachable;
            defer th.destroy();
            _ = evalAll(th, setup);
            var i: u64 = 0;
            while (i < iterations) : (i += 1) std.mem.doNotOptimizeAway(evalAll(th, body));
        }
    }.run;
}

pub const benchmarks = .{
    .{ "vm/fib-25", benchText("(setq fib (lambda (n) (if (< n 2) n (+ (funcall fib (- n 1)) (funcall fib (- n 2))))))", "(funcall fib 25)") },
    .{ "vm/closure-calls", benchText(
        "(setq c (let ((n 0)) (lambda () (setq n (1+ n))))) (setq loop (lambda (k) (if (= k 0) nil (progn (funcall c) (funcall loop (1- k))))))",
        "(funcall loop 1000) (funcall loop 1000) (funcall loop 1000) (funcall loop 1000) (funcall loop 1000) (funcall loop 1000) (funcall loop 1000) (funcall loop 1000) (funcall loop 1000) (funcall loop 1000)",
    ) },
};
