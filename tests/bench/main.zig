//! ベンチマークの実行器（詳細設計 §13.2）。
//! `zig build bench` で ReleaseFast でビルドして実行する。
//! 結果は 1 行 1 項目のタブ区切り（名前、反復回数、合計 ns、1 回あたり ns）で標準出力に出す。
//! 記録するときは scripts/run-bench.ps1 で bench-results/ に保存する。
//!
//! Phase 01 時点では処理系本体がないため、計測の仕組みを確かめるための基準となる処理だけを置く。
//! 処理系の機能ができるたびに、詳細設計 §13.2 の対象（算術、リスト、再帰、クロージャ、
//! ハッシュ表、文字列、CLOS、I/O、起動時間）を追加する。

const std = @import("std");
const Io = std.Io;

const Benchmark = struct {
    name: []const u8,
    /// 指定回数だけ処理を繰り返す
    run: *const fn (iterations: u64) void,
    iterations: u64,
};

const nil_repr = @import("nil_repr.zig");
const alloc = @import("alloc.zig");

const benchmarks = [_]Benchmark{
    .{ .name = "baseline/empty-loop", .run = emptyLoop, .iterations = 100_000_000 },
    .{ .name = "prototype/tagged-fixnum-add", .run = taggedFixnumAdd, .iterations = 100_000_000 },
} ++ group(nil_repr.benchmarks, 200_000_000) ++ group(alloc.benchmarks, 10_000_000);

fn group(comptime list: anytype, comptime iterations: u64) [list.len]Benchmark {
    var out: [list.len]Benchmark = undefined;
    for (list, 0..) |b, i| {
        out[i] = .{ .name = b[0], .run = b[1], .iterations = iterations };
    }
    return out;
}

test {
    _ = nil_repr;
}

fn emptyLoop(iterations: u64) void {
    var i: u64 = 0;
    while (i < iterations) : (i += 1) {
        std.mem.doNotOptimizeAway(i);
    }
}

/// 詳細設計 §2.2 の fixnum の加算（タグ付きのまま加算し、溢れを検査する）の試作。
fn taggedFixnumAdd(iterations: u64) void {
    const one: i64 = 1 << 2;
    var acc: i64 = 0;
    var i: u64 = 0;
    while (i < iterations) : (i += 1) {
        const r = @addWithOverflow(acc, one);
        if (r[1] != 0) {
            acc = 0; // 本来は bignum へ切り替える
        } else {
            acc = r[0];
        }
        std.mem.doNotOptimizeAway(acc);
    }
}

pub fn main(init: std.process.Init) !void {
    const io = init.io;
    const args = try init.minimal.args.toSlice(init.arena.allocator());
    const filter: ?[]const u8 = if (args.len > 1) args[1] else null;

    var buf: [4096]u8 = undefined;
    var fw: Io.File.Writer = .init(.stdout(), io, &buf);
    const out = &fw.interface;

    try out.writeAll("# name\titerations\ttotal_ns\tns_per_op\n");
    for (benchmarks) |b| {
        if (filter) |f| {
            if (std.mem.indexOf(u8, b.name, f) == null) continue;
        }
        // 1 回目は温め（キャッシュ・分岐予測の影響を減らす）
        b.run(b.iterations / 10);
        const start = Io.Timestamp.now(io, .awake);
        b.run(b.iterations);
        const elapsed = start.untilNow(io, .awake).nanoseconds;
        const per_op = @as(f64, @floatFromInt(elapsed)) / @as(f64, @floatFromInt(b.iterations));
        try out.print("{s}\t{d}\t{d}\t{d:.3}\n", .{ b.name, b.iterations, elapsed, per_op });
    }
    try out.flush();
}
