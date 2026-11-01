//! NIL の表現の比較（詳細設計 §2.2 の A・B・C。Phase 05 で計測して決める）。
//!
//!   A：NIL は即値（0x07）。car / cdr は「cons のタグか」「NIL か」の 2 つの判定
//!   B：NIL は cons のタグを持つ静的な cons（car・cdr が NIL 自身）。car / cdr は「cons のタグか」の判定 1 つ
//!   C：NIL は cons のタグを持つ固定の値（0x01、ECL の方式）。car / cdr は「NIL か」「cons のタグか」の 2 つ
//!
//! 計測する処理（CL の car / cdr は NIL に対して NIL を返す）
//!   length    ：1000 要素のリストを endp で終わりまでたどる
//!   safe-cadr ：長さ 0〜3 のリストに (car (cdr x)) を適用する（second のような、NIL に当たり得る操作）

const std = @import("std");

const Cell = extern struct { car: u64, cdr: u64 };

var b_nil_cell: Cell align(16) = undefined;

fn Repr(comptime kind: enum { a, b, c }) type {
    return struct {
        pub inline fn nil() u64 {
            return switch (kind) {
                .a => 0x07,
                .b => @intFromPtr(&b_nil_cell) | 1,
                .c => 0x01,
            };
        }
        /// CL の consp。B と C では NIL も cons のタグを持つので、NIL を除く判定が要る
        pub inline fn isCons(x: u64) bool {
            return x & 7 == 1 and (kind == .a or x != nil());
        }
        inline fn cell(x: u64) *const Cell {
            return @ptrFromInt(x & ~@as(u64, 7));
        }
        /// CL の cdr（引数がリストでなければ型エラーとして 0 を返す）
        pub inline fn cdr(x: u64) u64 {
            switch (kind) {
                .a => {
                    if (x & 7 == 1) return cell(x).cdr;
                    if (x == nil()) return nil();
                    return 0;
                },
                .b => {
                    if (x & 7 == 1) return cell(x).cdr;
                    return 0;
                },
                .c => {
                    if (x == nil()) return nil();
                    if (x & 7 == 1) return cell(x).cdr;
                    return 0;
                },
            }
        }
        pub inline fn car(x: u64) u64 {
            switch (kind) {
                .a => {
                    if (x & 7 == 1) return cell(x).car;
                    if (x == nil()) return nil();
                    return 0;
                },
                .b => {
                    if (x & 7 == 1) return cell(x).car;
                    return 0;
                },
                .c => {
                    if (x == nil()) return nil();
                    if (x & 7 == 1) return cell(x).car;
                    return 0;
                },
            }
        }
    };
}

/// 長さ n のリストを cells の中に作る（要素は fixnum の i）
fn buildList(comptime R: type, cells: []Cell, n: usize) u64 {
    var head = R.nil();
    var i: usize = n;
    while (i > 0) : (i -= 1) {
        cells[i - 1] = .{ .car = @as(u64, i) << 2, .cdr = head };
        head = @intFromPtr(&cells[i - 1]) | 1;
    }
    return head;
}

var list_cells: [1000]Cell align(16) = undefined;
var small_cells: [1024 * 3]Cell align(16) = undefined;
var small_lists: [1024]u64 = undefined;

fn lengthBench(comptime R: type) fn (u64) void {
    return struct {
        fn run(iterations: u64) void {
            b_nil_cell = .{ .car = R.nil(), .cdr = R.nil() };
            const head = buildList(R, &list_cells, list_cells.len);
            var total: u64 = 0;
            var rep: u64 = 0;
            const reps = @max(iterations / list_cells.len, 1);
            while (rep < reps) : (rep += 1) {
                var x = head;
                std.mem.doNotOptimizeAway(&x);
                while (x != R.nil()) {
                    x = R.cdr(x);
                    total += 1;
                }
            }
            std.mem.doNotOptimizeAway(total);
        }
    }.run;
}

fn safeCadrBench(comptime R: type) fn (u64) void {
    return struct {
        fn run(iterations: u64) void {
            b_nil_cell = .{ .car = R.nil(), .cdr = R.nil() };
            for (&small_lists, 0..) |*l, i| {
                l.* = buildList(R, small_cells[i * 3 .. i * 3 + 3], i % 4);
            }
            var acc: u64 = 0;
            var i: u64 = 0;
            while (i < iterations) : (i += 1) {
                var x = small_lists[i & 1023];
                std.mem.doNotOptimizeAway(&x);
                acc +%= R.car(R.cdr(x));
            }
            std.mem.doNotOptimizeAway(acc);
        }
    }.run;
}

pub const benchmarks = .{
    .{ "nil-repr/A-immediate/length", lengthBench(Repr(.a)) },
    .{ "nil-repr/B-static-cons/length", lengthBench(Repr(.b)) },
    .{ "nil-repr/C-cons-tagged-constant/length", lengthBench(Repr(.c)) },
    .{ "nil-repr/A-immediate/safe-cadr", safeCadrBench(Repr(.a)) },
    .{ "nil-repr/B-static-cons/safe-cadr", safeCadrBench(Repr(.b)) },
    .{ "nil-repr/C-cons-tagged-constant/safe-cadr", safeCadrBench(Repr(.c)) },
};

test "representations agree" {
    inline for (.{ Repr(.a), Repr(.b), Repr(.c) }) |R| {
        b_nil_cell = .{ .car = R.nil(), .cdr = R.nil() };
        var cells: [3]Cell align(16) = undefined;
        const l = buildList(R, &cells, 3);
        try std.testing.expectEqual(@as(u64, 2 << 2), R.car(R.cdr(l)));
        try std.testing.expectEqual(R.nil(), R.car(R.nil()));
        try std.testing.expectEqual(R.nil(), R.cdr(R.cdr(R.cdr(l))));
        try std.testing.expect(R.isCons(l) and !R.isCons(R.nil()));
    }
}
