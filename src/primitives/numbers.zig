//! 数の演算（Phase 08 の範囲）：fixnum・single-float・double-float の
//! + - * / 1+ 1- = /= < > <= >=。
//!
//! - 浮動小数の伝播（CLHS 12.1.4.1）：double-float があれば double-float、single-float があれば single-float。
//! - 比較（CLHS 12.1.4.1.1）：有理数と浮動小数の比較は、浮動小数を有理数とみなして正確に行う。
//! - 未実装（明示的なエラーにする。黙って別の値を返さない：基本設計 §3.1）
//!     fixnum の範囲（±2^61）を超える結果：bignum（Phase 20）
//!     割り切れない整数の割り算：ratio（Phase 20）
//! - 浮動小数の溢れ・不正な演算・0 での割り算は、SBCL 2.6.7 の既定（トラップが有効）と同じくエラーにする。

const std = @import("std");
const Value = @import("../values/value.zig").Value;
const Thread = @import("../runtime/thread.zig").Thread;
const Runtime = @import("../runtime/runtime.zig").Runtime;

pub const Num = union(enum) {
    fix: i64,
    single: f32,
    double: f64,
};

pub fn toNum(v: Value) ?Num {
    if (v.isFixnum()) return .{ .fix = v.asFixnum() };
    if (v.isSingleFloat()) return .{ .single = v.asSingle() };
    if (v.isOther() and Runtime.kindOf(v) == .double_float) return .{ .double = Runtime.doubleValue(v) };
    return null;
}

pub fn isNumber(v: Value) bool {
    return toNum(v) != null;
}

fn bignumError(th: *Thread) Value {
    return th.signal(.unimplemented, "fixnum の範囲を超える整数は未実装です（bignum は Phase 20 で実装予定）", Value.unbound, Value.unbound);
}

fn fixnum(th: *Thread, i: i64) Value {
    if (!Value.fixnumFits(i)) return bignumError(th);
    return Value.fromFixnum(i);
}

fn single(th: *Thread, f: f32) Value {
    if (std.math.isNan(f)) return th.signal(.floating_point_invalid_operation, "浮動小数の不正な演算です", Value.unbound, Value.unbound);
    if (std.math.isInf(f)) return th.signal(.floating_point_overflow, "浮動小数の演算が溢れました", Value.unbound, Value.unbound);
    return Value.fromSingle(f);
}

fn double(th: *Thread, f: f64) Value {
    if (std.math.isNan(f)) return th.signal(.floating_point_invalid_operation, "浮動小数の不正な演算です", Value.unbound, Value.unbound);
    if (std.math.isInf(f)) return th.signal(.floating_point_overflow, "浮動小数の演算が溢れました", Value.unbound, Value.unbound);
    return th.rt.makeDouble(f) catch th.outOfMemory();
}

fn asF64(n: Num) f64 {
    return switch (n) {
        .fix => |i| @floatFromInt(i),
        .single => |f| f,
        .double => |f| f,
    };
}

fn asF32(n: Num) f32 {
    return switch (n) {
        .fix => |i| @floatFromInt(i),
        .single => |f| f,
        .double => |f| @floatCast(f),
    };
}

const Format = enum { fix, single, double };

fn formatOf(a: Num, b: Num) Format {
    if (a == .double or b == .double) return .double;
    if (a == .single or b == .single) return .single;
    return .fix;
}

const Op = enum { add, sub, mul };

fn arith(th: *Thread, comptime op: Op, a: Num, b: Num) Value {
    switch (formatOf(a, b)) {
        .fix => {
            const x = a.fix;
            const y = b.fix;
            const r = switch (op) {
                .add => @addWithOverflow(x, y),
                .sub => @subWithOverflow(x, y),
                .mul => @mulWithOverflow(x, y),
            };
            if (r[1] != 0) return bignumError(th);
            return fixnum(th, r[0]);
        },
        .single => {
            const x = asF32(a);
            const y = asF32(b);
            return single(th, switch (op) {
                .add => x + y,
                .sub => x - y,
                .mul => x * y,
            });
        },
        .double => {
            const x = asF64(a);
            const y = asF64(b);
            return double(th, switch (op) {
                .add => x + y,
                .sub => x - y,
                .mul => x * y,
            });
        },
    }
}

fn numArg(th: *Thread, v: Value) ?Num {
    if (toNum(v)) |n| return n;
    _ = th.typeError(v, th.rt.syms.number);
    return null;
}

fn realArg(th: *Thread, v: Value) ?Num {
    if (toNum(v)) |n| return n;
    _ = th.typeError(v, th.rt.syms.real);
    return null;
}

// ---------------------------------------------------------------------------
// 2 引数の演算（VM の高速経路の後ろ盾にもする）

pub fn add2(th: *Thread, a: Value, b: Value) Value {
    if (a.isFixnum() and b.isFixnum()) return fixnum(th, a.asFixnum() + b.asFixnum());
    const x = numArg(th, a) orelse return Value.unwind;
    const y = numArg(th, b) orelse return Value.unwind;
    return arith(th, .add, x, y);
}

pub fn sub2(th: *Thread, a: Value, b: Value) Value {
    if (a.isFixnum() and b.isFixnum()) return fixnum(th, a.asFixnum() - b.asFixnum());
    const x = numArg(th, a) orelse return Value.unwind;
    const y = numArg(th, b) orelse return Value.unwind;
    return arith(th, .sub, x, y);
}

pub fn mul2(th: *Thread, a: Value, b: Value) Value {
    const x = numArg(th, a) orelse return Value.unwind;
    const y = numArg(th, b) orelse return Value.unwind;
    return arith(th, .mul, x, y);
}

pub fn div2(th: *Thread, a: Value, b: Value) Value {
    const x = numArg(th, a) orelse return Value.unwind;
    const y = numArg(th, b) orelse return Value.unwind;
    switch (formatOf(x, y)) {
        .fix => {
            if (y.fix == 0) return th.signal(.division_by_zero, "0 で割りました", Value.unbound, Value.unbound);
            if (@rem(x.fix, y.fix) != 0)
                return th.signal(.unimplemented, "割り切れない整数の割り算（ratio）は未実装です（Phase 20 で実装予定）", Value.unbound, Value.unbound);
            return fixnum(th, @divExact(x.fix, y.fix));
        },
        .single => {
            const d = asF32(y);
            if (d == 0) return th.signal(.division_by_zero, "0 で割りました", Value.unbound, Value.unbound);
            return single(th, asF32(x) / d);
        },
        .double => {
            const d = asF64(y);
            if (d == 0) return th.signal(.division_by_zero, "0 で割りました", Value.unbound, Value.unbound);
            return double(th, asF64(x) / d);
        },
    }
}

/// 整数と浮動小数を正確に比べる（浮動小数を有理数とみなす。CLHS 12.1.4.1.1）
fn cmpIntFloat(i: i64, f: f64) std.math.Order {
    std.debug.assert(!std.math.isNan(f));
    // fixnum は ±2^61 に収まるので、±2^62 の外の浮動小数とは大小が決まる
    if (f >= 0x1p62) return .lt;
    if (f <= -0x1p62) return .gt;
    const fl = @floor(f);
    const t: i64 = @intFromFloat(fl);
    if (i < t) return .lt;
    if (i > t) return .gt;
    return if (f > fl) .lt else .eq;
}

fn compareNum(a: Num, b: Num) std.math.Order {
    switch (a) {
        .fix => |x| switch (b) {
            .fix => |y| return std.math.order(x, y),
            else => return cmpIntFloat(x, asF64(b)),
        },
        else => switch (b) {
            .fix => |y| return cmpIntFloat(y, asF64(a)).invert(),
            // single と double の比較も、値をそのまま（f64 は f32 を正確に表せる）比べる
            else => return std.math.order(asF64(a), asF64(b)),
        },
    }
}

pub const Cmp = enum { eq, lt, gt, le, ge };

fn holds(comptime c: Cmp, o: std.math.Order) bool {
    return switch (c) {
        .eq => o == .eq,
        .lt => o == .lt,
        .gt => o == .gt,
        .le => o != .gt,
        .ge => o != .lt,
    };
}

pub fn compare2(th: *Thread, comptime c: Cmp, a: Value, b: Value) Value {
    if (a.isFixnum() and b.isFixnum()) {
        return th.rt.boolean(holds(c, std.math.order(a.asFixnum(), b.asFixnum())));
    }
    const x = (if (c == .eq) numArg(th, a) else realArg(th, a)) orelse return Value.unwind;
    const y = (if (c == .eq) numArg(th, b) else realArg(th, b)) orelse return Value.unwind;
    return th.rt.boolean(holds(c, compareNum(x, y)));
}

// ---------------------------------------------------------------------------
// プリミティブ（引数の個数は呼び出し側で検査済み）

pub fn plus(th: *Thread, args: []const Value) Value {
    if (args.len == 0) return Value.fromFixnum(0);
    if (args.len == 1) {
        _ = numArg(th, args[0]) orelse return Value.unwind;
        return args[0];
    }
    var acc = args[0];
    for (args[1..]) |x| {
        acc = add2(th, acc, x);
        if (acc == Value.unwind) return acc;
    }
    return acc;
}

pub fn times(th: *Thread, args: []const Value) Value {
    if (args.len == 0) return Value.fromFixnum(1);
    if (args.len == 1) {
        _ = numArg(th, args[0]) orelse return Value.unwind;
        return args[0];
    }
    var acc = args[0];
    for (args[1..]) |x| {
        acc = mul2(th, acc, x);
        if (acc == Value.unwind) return acc;
    }
    return acc;
}

/// 符号を反転する（(- 0.0) は -0.0。0 からの引き算とは違う）
fn negate(th: *Thread, v: Value) Value {
    const x = numArg(th, v) orelse return Value.unwind;
    return switch (x) {
        .fix => |i| fixnum(th, -i),
        .single => |f| Value.fromSingle(-f),
        .double => |f| double(th, -f),
    };
}

pub fn minus(th: *Thread, args: []const Value) Value {
    if (args.len == 1) return negate(th, args[0]);
    var acc = args[0];
    for (args[1..]) |x| {
        acc = sub2(th, acc, x);
        if (acc == Value.unwind) return acc;
    }
    return acc;
}

pub fn divide(th: *Thread, args: []const Value) Value {
    if (args.len == 1) return div2(th, Value.fromFixnum(1), args[0]);
    var acc = args[0];
    for (args[1..]) |x| {
        acc = div2(th, acc, x);
        if (acc == Value.unwind) return acc;
    }
    return acc;
}

pub fn onePlus(th: *Thread, args: []const Value) Value {
    return add2(th, args[0], Value.fromFixnum(1));
}

pub fn oneMinus(th: *Thread, args: []const Value) Value {
    return sub2(th, args[0], Value.fromFixnum(1));
}

/// = < > <= >=：隣り合う組がすべて成り立つか。すべての引数の型を検査する
fn chain(th: *Thread, comptime c: Cmp, args: []const Value) Value {
    if (args.len == 1) {
        _ = (if (c == .eq) numArg(th, args[0]) else realArg(th, args[0])) orelse return Value.unwind;
        return th.rt.t;
    }
    var result = true;
    for (args[0 .. args.len - 1], args[1..]) |a, b| {
        const r = compare2(th, c, a, b);
        if (r == Value.unwind) return r;
        if (r == Value.nil) result = false;
    }
    return th.rt.boolean(result);
}

pub fn numEq(th: *Thread, args: []const Value) Value {
    return chain(th, .eq, args);
}
pub fn lessThan(th: *Thread, args: []const Value) Value {
    return chain(th, .lt, args);
}
pub fn greaterThan(th: *Thread, args: []const Value) Value {
    return chain(th, .gt, args);
}
pub fn lessEq(th: *Thread, args: []const Value) Value {
    return chain(th, .le, args);
}
pub fn greaterEq(th: *Thread, args: []const Value) Value {
    return chain(th, .ge, args);
}

/// /=：すべての組が異なるか
pub fn numNe(th: *Thread, args: []const Value) Value {
    for (args) |a| _ = numArg(th, a) orelse return Value.unwind;
    for (args, 0..) |a, i| {
        for (args[i + 1 ..]) |b| {
            if (compareNum(toNum(a).?, toNum(b).?) == .eq) return Value.nil;
        }
    }
    return th.rt.t;
}

test "exact comparison of integers and floats" {
    try std.testing.expectEqual(std.math.Order.eq, cmpIntFloat(1, 1.0));
    try std.testing.expectEqual(std.math.Order.lt, cmpIntFloat(1, 1.5));
    try std.testing.expectEqual(std.math.Order.gt, cmpIntFloat(2, 1.5));
    try std.testing.expectEqual(std.math.Order.gt, cmpIntFloat(-1, -1.5));
    try std.testing.expectEqual(std.math.Order.lt, cmpIntFloat(-2, -1.5));
    // 2^53 + 1 は double で表せないが、正確に比べる
    try std.testing.expectEqual(std.math.Order.gt, cmpIntFloat((1 << 53) + 1, 0x1p53));
    try std.testing.expectEqual(std.math.Order.lt, cmpIntFloat((1 << 61) - 1, 0x1p61));
}
