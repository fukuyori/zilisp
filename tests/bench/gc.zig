//! GC の停止時間（Phase 07。詳細設計 §3.7）。
//! 生きている cons の数を変えて、1 回の GC（マークと、大きいオブジェクト・内部資源の処理。小さいページの
//! 掃除は遅延して確保の時に行うので含まない）にかかる時間を測る。
//! 1 回の実行で `iterations` 回の GC を行う（生きているデータを作る時間も含むが、回数で割ると小さい）。
//!   gc/collect-100k-live ：生きている cons が 10 万個
//!   gc/collect-1m-live   ：生きている cons が 100 万個
//!   gc/alloc-churn       ：寿命の短い cons を確保し続ける（GC は確保量の閾値で起きる）。1 回あたり＝cons 1 個

const std = @import("std");
const zl = @import("zilisp");
const Value = zl.value.Value;
const Runtime = zl.runtime.Runtime;

// 走査の上端は、値を扱う関数自身の @frameAddress() にしない（最適化ありのビルドでは、その関数の
// ローカル変数が @frameAddress() より高い位置に置かれることがある。詳細設計 §3.4）。
// 外側の関数で上端を記録し、値を扱う本体は inline 展開しない別の関数で行う。

fn collectWithLive(comptime live: usize) fn (u64) void {
    return struct {
        fn run(iterations: u64) void {
            const rt = Runtime.create(std.heap.smp_allocator) catch unreachable;
            defer rt.destroy();
            rt.stack_top = @frameAddress();
            @call(.never_inline, body, .{ rt, iterations });
        }
        fn body(rt: *Runtime, iterations: u64) void {
            // 作る途中で GC が起きても消えないよう、先にルートに登録して先頭を更新していく
            const root = rt.roots.register(Value.nil) catch unreachable;
            for (0..live) |i| {
                const c = rt.cons(Value.fromFixnum(@intCast(i)), rt.roots.get(root).?) catch unreachable;
                _ = rt.roots.set(root, c);
            }
            var i: u64 = 0;
            while (i < iterations) : (i += 1) rt.collect();
            // 生きている数が意図どおりか確かめる
            if (rt.heap.stats.live_objects < live) @panic("gc bench: live objects were collected");
        }
    }.run;
}

fn allocChurn(iterations: u64) void {
    const rt = Runtime.create(std.heap.smp_allocator) catch unreachable;
    defer rt.destroy();
    rt.stack_top = @frameAddress();
    @call(.never_inline, allocChurnBody, .{ rt, iterations });
}

fn allocChurnBody(rt: *Runtime, iterations: u64) void {
    var keep = Value.nil;
    var i: u64 = 0;
    while (i < iterations) : (i += 1) {
        const c = rt.cons(Value.fromFixnum(@intCast(i & 0xFFFF)), Value.nil) catch unreachable;
        // 1000 個に 1 個だけを短い間保持する
        if (i % 1000 == 0) keep = c;
    }
    std.mem.doNotOptimizeAway(&keep);
}

pub const collect_benchmarks = .{
    .{ "gc/collect-100k-live", collectWithLive(100_000) },
    .{ "gc/collect-1m-live", collectWithLive(1_000_000) },
};

pub const churn_benchmarks = .{
    .{ "gc/alloc-churn", allocChurn },
};
