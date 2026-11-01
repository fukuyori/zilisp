//! 確保の速さ（Phase 06。詳細設計 §3.1）。
//!   alloc/heap-cons      ：ページ単位のヒープで cons を確保する
//!   alloc/heap-symbol64  ：ページ単位のヒープで 64 バイトのオブジェクト（シンボルの大きさ）を確保する
//!   alloc/arena-cons     ：比較用。ArenaAllocator で 16 バイトを 16 バイト境界に確保する（Phase 05 の仮のヒープの方式）
//! 1 回の実行で `iterations` 個を確保する（ヒープの初期化と解放の時間も含む）。

const std = @import("std");
const zl = @import("zilisp");
const Value = zl.value.Value;

fn heapCons(iterations: u64) void {
    var h = zl.heap.Heap.init(std.heap.smp_allocator);
    defer h.deinit();
    var last = Value.nil;
    var i: u64 = 0;
    while (i < iterations) : (i += 1) {
        last = h.cons(Value.fromFixnum(@intCast(i & 0xFFFF)), last) catch unreachable;
    }
    std.mem.doNotOptimizeAway(last);
}

fn heapSymbol64(iterations: u64) void {
    var h = zl.heap.Heap.init(std.heap.smp_allocator);
    defer h.deinit();
    var i: u64 = 0;
    while (i < iterations) : (i += 1) {
        const s = h.create(zl.object.Symbol, 0) catch unreachable;
        s.header = .{ .kind = .symbol };
        std.mem.doNotOptimizeAway(s);
    }
}

fn arenaCons(iterations: u64) void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    var last = Value.nil;
    var i: u64 = 0;
    while (i < iterations) : (i += 1) {
        const m = arena.allocator().alignedAlloc(zl.object.Cons, .@"16", 1) catch unreachable;
        m[0] = .{ .car = Value.fromFixnum(@intCast(i & 0xFFFF)), .cdr = last };
        last = Value.fromPointer(&m[0], .cons);
    }
    std.mem.doNotOptimizeAway(last);
}

pub const benchmarks = .{
    .{ "alloc/heap-cons", heapCons },
    .{ "alloc/heap-symbol64", heapSymbol64 },
    .{ "alloc/arena-cons", arenaCons },
};
