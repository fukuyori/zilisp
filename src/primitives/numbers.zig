//! 数の演算（詳細設計 §2.2・§2.4。Phase 20 で数の階層を実装）。
//!
//! 数の種類：fixnum（62 ビット）、bignum（limb 列。src/values/object.zig）、比（約分済み、分母は 2 以上）、
//! single-float、double-float。複素数は未実装（必要になる演算は明示的なエラー）。
//! 規則（CLHS 12.1.4）：
//!   - 整数と比どうしの演算は正確（結果の比は約分し、分母が 1 なら整数、整数は収まれば fixnum）
//!   - 浮動小数が混ざれば浮動小数（double-float が混ざれば double-float、そうでなければ single-float）
//!   - 比較は正確（浮動小数を有理数とみなす。CLHS 12.1.4.1.1）
//! 多倍長の演算は std.math.big.int を使う。途中の値は Zig のヒープ（gpa）に置き、結果だけを Lisp のヒープに作る。

const std = @import("std");
const big = std.math.big.int;
const Managed = big.Managed;
const Value = @import("../values/value.zig").Value;
const Thread = @import("../runtime/thread.zig").Thread;
const Runtime = @import("../runtime/runtime.zig").Runtime;

pub const Num = union(enum) {
    fix: i64,
    big: Value,
    ratio: Value,
    single: f32,
    double: f64,
};

pub fn toNum(v: Value) ?Num {
    if (v.isFixnum()) return .{ .fix = v.asFixnum() };
    if (v.isSingleFloat()) return .{ .single = v.asSingle() };
    if (v.isOther()) switch (Runtime.kindOf(v).?) {
        .double_float => return .{ .double = Runtime.doubleValue(v) },
        .bignum => return .{ .big = v },
        .ratio => return .{ .ratio = v },
        else => {},
    };
    return null;
}

pub fn isNumber(v: Value) bool {
    return toNum(v) != null;
}

fn isInteger(n: Num) bool {
    return n == .fix or n == .big;
}

fn isExact(n: Num) bool {
    return n == .fix or n == .big or n == .ratio;
}

fn cl(th: *Thread, name: []const u8) Value {
    return (th.rt.findSymbol(th.rt.cl, name) orelse unreachable).symbol;
}

// ---------------------------------------------------------------------------
// エラー

fn divisionByZero(th: *Thread) Value {
    return th.signal(.division_by_zero, "0 で割りました", Value.unbound, Value.unbound);
}

fn complexError(th: *Thread) Value {
    return th.signal(.unimplemented, "結果が複素数になる演算は未実装です（複素数は後の Phase で実装予定）", Value.unbound, Value.unbound);
}

fn numArg(th: *Thread, v: Value) ?Num {
    if (toNum(v)) |n| return n;
    _ = th.typeError(v, th.rt.syms.number);
    return null;
}

/// 実数（複素数は未実装なので、数ならすべて実数）
fn realArg(th: *Thread, v: Value) ?Num {
    if (toNum(v)) |n| return n;
    _ = th.typeError(v, th.rt.syms.real);
    return null;
}

fn integerArg(th: *Thread, v: Value) ?Num {
    if (toNum(v)) |n| if (isInteger(n)) return n;
    _ = th.typeError(v, th.rt.syms.integer);
    return null;
}

fn rationalArg(th: *Thread, v: Value) ?Num {
    if (toNum(v)) |n| if (isExact(n)) return n;
    _ = th.typeError(v, cl(th, "RATIONAL"));
    return null;
}

// ---------------------------------------------------------------------------
// 浮動小数を作る（溢れ・NaN はエラー）

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

// ---------------------------------------------------------------------------
// 整数（fixnum・bignum の Value）の演算

/// 整数の値を big.Const にする（fixnum は buf に置く。bignum の limb は、GC が起こり得る処理をまたいで使わないこと）
fn intConst(v: Value, buf: *[2]usize) big.Const {
    if (v.isFixnum()) return big.Mutable.init(buf, v.asFixnum()).toConst();
    return Runtime.bignumConst(v);
}

fn fromI128(th: *Thread, x: i128) Value {
    if (x >= std.math.minInt(i64) and x <= std.math.maxInt(i64)) {
        const i: i64 = @intCast(x);
        if (Value.fixnumFits(i)) return Value.fromFixnum(i);
    }
    var m = Managed.initSet(th.rt.gpa, x) catch return th.outOfMemory();
    defer m.deinit();
    return th.rt.makeInteger(m.toConst()) catch th.outOfMemory();
}

/// Managed の値を整数の Value にして、Managed を解放する
fn finish(th: *Thread, m: *Managed) Value {
    defer m.deinit();
    return th.rt.makeInteger(m.toConst()) catch th.outOfMemory();
}

fn toManaged(th: *Thread, v: Value) ?Managed {
    var buf: [2]usize = undefined;
    const m = intConst(v, &buf).toManaged(th.rt.gpa) catch {
        _ = th.outOfMemory();
        return null;
    };
    return m;
}

const IntOp = enum { add, sub, mul };

fn intArith(th: *Thread, comptime op: IntOp, a: Value, b: Value) Value {
    if (a.isFixnum() and b.isFixnum()) {
        const x: i128 = a.asFixnum();
        const y: i128 = b.asFixnum();
        return fromI128(th, switch (op) {
            .add => x + y,
            .sub => x - y,
            .mul => x * y,
        });
    }
    var x = toManaged(th, a) orelse return Value.unwind;
    defer x.deinit();
    var y = toManaged(th, b) orelse return Value.unwind;
    defer y.deinit();
    var r = Managed.init(th.rt.gpa) catch return th.outOfMemory();
    (switch (op) {
        .add => r.add(&x, &y),
        .sub => r.sub(&x, &y),
        .mul => r.mul(&x, &y),
    }) catch {
        r.deinit();
        return th.outOfMemory();
    };
    return finish(th, &r);
}

fn intNeg(th: *Thread, a: Value) Value {
    return intArith(th, .sub, Value.fromFixnum(0), a);
}

fn intOrder(a: Value, b: Value) std.math.Order {
    if (a.isFixnum() and b.isFixnum()) return std.math.order(a.asFixnum(), b.asFixnum());
    var ba: [2]usize = undefined;
    var bb: [2]usize = undefined;
    return intConst(a, &ba).order(intConst(b, &bb));
}

fn intSign(a: Value) i2 {
    if (a.isFixnum()) {
        const i = a.asFixnum();
        return if (i > 0) 1 else if (i < 0) -1 else 0;
    }
    return if (Runtime.bignumPtr(a).positive()) 1 else -1;
}

fn intIsOdd(a: Value) bool {
    if (a.isFixnum()) return @mod(a.asFixnum(), 2) != 0;
    return Runtime.bignumConst(a).isOdd();
}

const DivMode = enum { floor, ceiling, truncate, round };

const QR = struct { q: Value, r: Value };

/// 整数の割り算（b は 0 でないこと）。q は整数、r = a - q*b
fn intDivMod(th: *Thread, a: Value, b: Value, mode: DivMode) ?QR {
    if (a.isFixnum() and b.isFixnum()) {
        const x = a.asFixnum();
        const y = b.asFixnum();
        var q: i64 = undefined;
        var r: i64 = undefined;
        switch (mode) {
            .truncate => {
                q = @divTrunc(x, y);
                r = @rem(x, y);
            },
            else => {
                q = @divFloor(x, y);
                r = @mod(x, y);
                if (mode == .ceiling and r != 0) {
                    q += 1;
                    r -= y;
                } else if (mode == .round and r != 0) {
                    // 2r と y を比べ、半分なら偶数へ（y > 0 なら 0 ≦ r < y、y < 0 なら y < r ≦ 0）
                    const twice: i128 = @as(i128, r) * 2;
                    const c = std.math.order(twice, @as(i128, y));
                    const up = if (y > 0) (c == .gt or (c == .eq and @mod(q, 2) != 0)) else (c == .lt or (c == .eq and @mod(q, 2) != 0));
                    if (up) {
                        q += 1;
                        r -= y;
                    }
                }
            },
        }
        const qv = fromI128(th, q);
        if (qv == Value.unwind) return null;
        return .{ .q = qv, .r = Value.fromFixnum(r) };
    }
    var x = toManaged(th, a) orelse return null;
    defer x.deinit();
    var y = toManaged(th, b) orelse return null;
    defer y.deinit();
    var q = Managed.init(th.rt.gpa) catch {
        _ = th.outOfMemory();
        return null;
    };
    var r = Managed.init(th.rt.gpa) catch {
        q.deinit();
        _ = th.outOfMemory();
        return null;
    };
    (if (mode == .truncate) q.divTrunc(&r, &x, &y) else q.divFloor(&r, &x, &y)) catch {
        q.deinit();
        r.deinit();
        _ = th.outOfMemory();
        return null;
    };
    var qv = finish(th, &q);
    if (qv == Value.unwind) {
        r.deinit();
        return null;
    }
    var rv = finish(th, &r);
    if (rv == Value.unwind) return null;
    if ((mode == .ceiling or mode == .round) and intSign(rv) != 0) {
        var up = mode == .ceiling;
        if (mode == .round) {
            const twice = intArith(th, .add, rv, rv);
            if (twice == Value.unwind) return null;
            const c = intOrder(twice, b);
            up = if (intSign(b) > 0) (c == .gt or (c == .eq and intIsOdd(qv))) else (c == .lt or (c == .eq and intIsOdd(qv)));
        }
        if (up) {
            qv = intArith(th, .add, qv, Value.fromFixnum(1));
            if (qv == Value.unwind) return null;
            rv = intArith(th, .sub, rv, b);
            if (rv == Value.unwind) return null;
        }
    }
    return .{ .q = qv, .r = rv };
}

fn intGcd(th: *Thread, a: Value, b: Value) Value {
    if (a.isFixnum() and b.isFixnum()) {
        // 絶対値は fixnum に収まらないことがある（most-negative-fixnum。Codex のレビュー P20 #1）
        const x: u64 = @abs(a.asFixnum());
        const y: u64 = @abs(b.asFixnum());
        if (x == 0) return fromI128(th, y);
        if (y == 0) return fromI128(th, x);
        return fromI128(th, std.math.gcd(x, y));
    }
    var x = toManaged(th, a) orelse return Value.unwind;
    defer x.deinit();
    var y = toManaged(th, b) orelse return Value.unwind;
    defer y.deinit();
    x.abs();
    y.abs();
    if (x.eqlZero()) return th.rt.makeInteger(y.toConst()) catch th.outOfMemory();
    if (y.eqlZero()) return th.rt.makeInteger(x.toConst()) catch th.outOfMemory();
    var r = Managed.init(th.rt.gpa) catch return th.outOfMemory();
    r.gcd(&x, &y) catch {
        r.deinit();
        return th.outOfMemory();
    };
    return finish(th, &r);
}

/// 整数の値を浮動小数にする（最も近い値。表せなければ無限大）
fn intToFloat(comptime F: type, v: Value) F {
    if (v.isFixnum()) return @floatFromInt(v.asFixnum());
    return Runtime.bignumConst(v).toFloat(F, .nearest_even)[0];
}

fn bitLength(v: Value) usize {
    var buf: [2]usize = undefined;
    const c = intConst(v, &buf);
    return c.bitCountAbs();
}

// ---------------------------------------------------------------------------
// 有理数（整数と比）

const Parts = struct { num: Value, den: Value };

fn parts(v: Value) Parts {
    if (v.isOther() and Runtime.kindOf(v) == .ratio) {
        const r = Runtime.ratioPtr(v);
        return .{ .num = r.numerator, .den = r.denominator };
    }
    return .{ .num = v, .den = Value.fromFixnum(1) };
}

/// n/d を約分して有理数にする（d は 0 でないこと）
fn makeRational(th: *Thread, n0: Value, d0: Value) Value {
    var n = n0;
    var d = d0;
    if (intSign(d) < 0) {
        n = intNeg(th, n);
        if (n == Value.unwind) return n;
        d = intNeg(th, d);
        if (d == Value.unwind) return d;
    }
    const g = intGcd(th, n, d);
    if (g == Value.unwind) return g;
    if (!(g.isFixnum() and g.asFixnum() == 1)) {
        n = (intDivMod(th, n, g, .truncate) orelse return Value.unwind).q;
        d = (intDivMod(th, d, g, .truncate) orelse return Value.unwind).q;
    }
    if (d.isFixnum() and d.asFixnum() == 1) return n;
    return th.rt.makeRatioRaw(n, d) catch th.outOfMemory();
}

fn ratArith(th: *Thread, comptime op: enum { add, sub, mul, div }, a: Value, b: Value) Value {
    const x = parts(a);
    const y = parts(b);
    switch (op) {
        .add, .sub => {
            const p = intArith(th, .mul, x.num, y.den);
            if (p == Value.unwind) return p;
            const q = intArith(th, .mul, y.num, x.den);
            if (q == Value.unwind) return q;
            const n = intArith(th, if (op == .add) .add else .sub, p, q);
            if (n == Value.unwind) return n;
            const d = intArith(th, .mul, x.den, y.den);
            if (d == Value.unwind) return d;
            return makeRational(th, n, d);
        },
        .mul => {
            const n = intArith(th, .mul, x.num, y.num);
            if (n == Value.unwind) return n;
            const d = intArith(th, .mul, x.den, y.den);
            if (d == Value.unwind) return d;
            return makeRational(th, n, d);
        },
        .div => {
            if (intSign(y.num) == 0) return divisionByZero(th);
            const n = intArith(th, .mul, x.num, y.den);
            if (n == Value.unwind) return n;
            const d = intArith(th, .mul, x.den, y.num);
            if (d == Value.unwind) return d;
            return makeRational(th, n, d);
        },
    }
}

/// 有理数どうしの比較（分母は正なので、交差して掛けた値を比べる）
fn ratOrder(th: *Thread, a: Value, b: Value) ?std.math.Order {
    const x = parts(a);
    const y = parts(b);
    if (x.den.isFixnum() and x.den.asFixnum() == 1 and y.den.isFixnum() and y.den.asFixnum() == 1) return intOrder(x.num, y.num);
    const p = intArith(th, .mul, x.num, y.den);
    if (p == Value.unwind) return null;
    const q = intArith(th, .mul, y.num, x.den);
    if (q == Value.unwind) return null;
    return intOrder(p, q);
}

/// 有理数 n/d を浮動小数にする（最も近い値）。
/// 64 ビット以上の商を求め、余りがあれば最下位のビットを立てて（sticky）から丸めるので、丸めは1回で正しい
fn ratToFloat(comptime F: type, th: *Thread, n: Value, d: Value) ?F {
    const nb = bitLength(n);
    const db = bitLength(d);
    const mant_bits = std.math.floatMantissaBits(F) + 1;
    if (nb <= mant_bits and db <= mant_bits) return intToFloat(F, n) / intToFloat(F, d);
    const shift: isize = 66 + @as(isize, @intCast(db)) - @as(isize, @intCast(nb));
    var x = toManaged(th, n) orelse return null;
    defer x.deinit();
    var y = toManaged(th, d) orelse return null;
    defer y.deinit();
    const negative = !x.isPositive();
    x.abs();
    (if (shift >= 0) x.shiftLeft(&x, @intCast(shift)) else y.shiftLeft(&y, @intCast(-shift))) catch {
        _ = th.outOfMemory();
        return null;
    };
    var q = Managed.init(th.rt.gpa) catch {
        _ = th.outOfMemory();
        return null;
    };
    defer q.deinit();
    var r = Managed.init(th.rt.gpa) catch {
        _ = th.outOfMemory();
        return null;
    };
    defer r.deinit();
    q.divTrunc(&r, &x, &y) catch {
        _ = th.outOfMemory();
        return null;
    };
    if (!r.eqlZero()) {
        // 余りがあれば、最下位のビットを立てる（q は 64 ビット以上あるので、立てたビットは丸めの判断にだけ使われる）
        q.limbs[0] |= 1;
    }
    // 値は q × 2^-shift。q を、結果の形式で使える精度（非正規化数の範囲では少なくなる）のビットに、ここで1回だけ丸める
    // （浮動小数にしてから ldexp で非正規化数にすると、丸めが2回になる：Codex のレビュー P20 #5）
    const qc = q.toConst();
    const len: isize = @intCast(qc.bitCountAbs());
    const top = len - shift; // 値 < 2^top、値 ≧ 2^(top-1)
    const emin: isize = std.math.floatExponentMin(F); // 最小の正規化数は 2^emin
    const emax: isize = std.math.floatExponentMax(F);
    if (top - 1 > emax) return if (negative) -std.math.inf(F) else std.math.inf(F);
    var prec: isize = mant_bits;
    if (top - 1 < emin) prec -= emin - (top - 1);
    const drop = len - prec; // 捨てるビットの数（q は 66 ビット以上あるので正）
    var kept: u64 = 0;
    if (drop < len) {
        var k = q.toConst().toManaged(th.rt.gpa) catch {
            _ = th.outOfMemory();
            return null;
        };
        defer k.deinit();
        k.shiftRight(&k, @intCast(drop)) catch {
            _ = th.outOfMemory();
            return null;
        };
        kept = k.toConst().toInt(u64) catch unreachable; // prec ≦ 53 ビット
    }
    const round_bit = bitAt(qc, drop - 1);
    const sticky = anyBitBelow(qc, drop - 1);
    if (round_bit and (sticky or kept & 1 != 0)) kept += 1;
    const result = std.math.ldexp(@as(F, @floatFromInt(kept)), @intCast(drop - shift));
    return if (negative) -result else result;
}

/// 非負の整数の i 番目のビット（i < 0 なら偽）
fn bitAt(c: big.Const, i: isize) bool {
    if (i < 0) return false;
    const idx: usize = @intCast(i);
    const limb = idx / @bitSizeOf(usize);
    if (limb >= c.limbs.len) return false;
    return (c.limbs[limb] >> @intCast(idx % @bitSizeOf(usize))) & 1 != 0;
}

/// 非負の整数の、i 番目より下のビットに 1 があるか
fn anyBitBelow(c: big.Const, i: isize) bool {
    if (i <= 0) return false;
    const n: usize = @intCast(i);
    const full = n / @bitSizeOf(usize);
    for (c.limbs[0..@min(full, c.limbs.len)]) |l| if (l != 0) return true;
    if (full >= c.limbs.len) return false;
    const rest: usize = n % @bitSizeOf(usize);
    if (rest == 0) return false;
    const mask = (@as(usize, 1) << @intCast(rest)) - 1;
    return c.limbs[full] & mask != 0;
}

fn exactToFloat(comptime F: type, th: *Thread, v: Value) ?F {
    if (v.isFixnum()) return @floatFromInt(v.asFixnum());
    if (Runtime.kindOf(v) == .bignum) return intToFloat(F, v);
    const p = parts(v);
    return ratToFloat(F, th, p.num, p.den);
}

/// 浮動小数を、正確に同じ値の有理数にする（CLHS rational）
fn floatToRational(th: *Thread, f: f64) Value {
    if (f == 0) return Value.fromFixnum(0);
    const fr = std.math.frexp(f); // f = m × 2^e、0.5 ≦ |m| < 1
    const mant: i64 = @intFromFloat(std.math.ldexp(fr.significand, 53));
    const e2: i32 = fr.exponent - 53;
    var m = Managed.initSet(th.rt.gpa, mant) catch return th.outOfMemory();
    if (e2 >= 0) {
        m.shiftLeft(&m, @intCast(e2)) catch {
            m.deinit();
            return th.outOfMemory();
        };
        return finish(th, &m);
    }
    const n = finish(th, &m);
    if (n == Value.unwind) return n;
    var d = Managed.initSet(th.rt.gpa, @as(i64, 1)) catch return th.outOfMemory();
    d.shiftLeft(&d, @intCast(-e2)) catch {
        d.deinit();
        return th.outOfMemory();
    };
    const dv = finish(th, &d);
    if (dv == Value.unwind) return dv;
    return makeRational(th, n, dv);
}

// ---------------------------------------------------------------------------
// 数の種類をそろえる

const Kind = enum { exact, single, double };

fn kindOf2(a: Num, b: Num) Kind {
    if (a == .double or b == .double) return .double;
    if (a == .single or b == .single) return .single;
    return .exact;
}

fn exactValue(n: Num) Value {
    return switch (n) {
        .fix => |i| Value.fromFixnum(i),
        .big => |v| v,
        .ratio => |v| v,
        else => unreachable,
    };
}

fn toF64(th: *Thread, n: Num) ?f64 {
    return switch (n) {
        .single => |f| f,
        .double => |f| f,
        else => exactToFloat(f64, th, exactValue(n)),
    };
}

fn toF32(th: *Thread, n: Num) ?f32 {
    return switch (n) {
        .single => |f| f,
        .double => |f| @floatCast(f),
        else => exactToFloat(f32, th, exactValue(n)),
    };
}

// ---------------------------------------------------------------------------
// 2 引数の演算（VM・ネイティブの高速経路の後ろ盾にもする）

const Arith = enum { add, sub, mul };

fn arith(th: *Thread, comptime op: Arith, a: Value, b: Value) Value {
    const x = numArg(th, a) orelse return Value.unwind;
    const y = numArg(th, b) orelse return Value.unwind;
    switch (kindOf2(x, y)) {
        .exact => {
            if (isInteger(x) and isInteger(y)) return intArith(th, switch (op) {
                .add => .add,
                .sub => .sub,
                .mul => .mul,
            }, a, b);
            return ratArith(th, switch (op) {
                .add => .add,
                .sub => .sub,
                .mul => .mul,
            }, a, b);
        },
        .single => {
            const p = toF32(th, x) orelse return Value.unwind;
            const q = toF32(th, y) orelse return Value.unwind;
            return single(th, switch (op) {
                .add => p + q,
                .sub => p - q,
                .mul => p * q,
            });
        },
        .double => {
            const p = toF64(th, x) orelse return Value.unwind;
            const q = toF64(th, y) orelse return Value.unwind;
            return double(th, switch (op) {
                .add => p + q,
                .sub => p - q,
                .mul => p * q,
            });
        },
    }
}

pub fn add2(th: *Thread, a: Value, b: Value) Value {
    if (a.isFixnum() and b.isFixnum()) return fromI128(th, @as(i128, a.asFixnum()) + b.asFixnum());
    return arith(th, .add, a, b);
}

pub fn sub2(th: *Thread, a: Value, b: Value) Value {
    if (a.isFixnum() and b.isFixnum()) return fromI128(th, @as(i128, a.asFixnum()) - b.asFixnum());
    return arith(th, .sub, a, b);
}

pub fn mul2(th: *Thread, a: Value, b: Value) Value {
    return arith(th, .mul, a, b);
}

pub fn div2(th: *Thread, a: Value, b: Value) Value {
    const x = numArg(th, a) orelse return Value.unwind;
    const y = numArg(th, b) orelse return Value.unwind;
    switch (kindOf2(x, y)) {
        .exact => {
            if (isInteger(y) and intSign(b) == 0) return divisionByZero(th);
            if (isInteger(x) and isInteger(y)) return makeRational(th, a, b);
            return ratArith(th, .div, a, b);
        },
        .single => {
            const p = toF32(th, x) orelse return Value.unwind;
            const q = toF32(th, y) orelse return Value.unwind;
            if (q == 0) return divisionByZero(th);
            return single(th, p / q);
        },
        .double => {
            const p = toF64(th, x) orelse return Value.unwind;
            const q = toF64(th, y) orelse return Value.unwind;
            if (q == 0) return divisionByZero(th);
            return double(th, p / q);
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

/// 正確な数と浮動小数の比較（浮動小数を正確な有理数にして比べる）
fn cmpExactFloat(th: *Thread, v: Value, f: f64) ?std.math.Order {
    if (v.isFixnum()) return cmpIntFloat(v.asFixnum(), f);
    if (std.math.isInf(f)) return if (f > 0) .lt else .gt;
    const r = floatToRational(th, f);
    if (r == Value.unwind) return null;
    return ratOrder(th, v, r);
}

fn compareNum(th: *Thread, a: Num, b: Num) ?std.math.Order {
    if (isExact(a) and isExact(b)) {
        if (a == .fix and b == .fix) return std.math.order(a.fix, b.fix);
        return ratOrder(th, exactValue(a), exactValue(b));
    }
    if (isExact(a)) return cmpExactFloat(th, exactValue(a), toF64(th, b).?);
    if (isExact(b)) return (cmpExactFloat(th, exactValue(b), toF64(th, a).?) orelse return null).invert();
    // single と double の比較も、値をそのまま（f64 は f32 を正確に表せる）比べる
    return std.math.order(toF64(th, a).?, toF64(th, b).?);
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
    const o = compareNum(th, x, y) orelse return Value.unwind;
    return th.rt.boolean(holds(c, o));
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
        .fix, .big => intNeg(th, v),
        .ratio => blk: {
            const p = parts(v);
            const n = intNeg(th, p.num);
            if (n == Value.unwind) break :blk n;
            break :blk th.rt.makeRatioRaw(n, p.den) catch th.outOfMemory();
        },
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
            const o = compareNum(th, toNum(a).?, toNum(b).?) orelse return Value.unwind;
            if (o == .eq) return Value.nil;
        }
    }
    return th.rt.t;
}

// ---------------------------------------------------------------------------
// 述語・max・min・abs（Phase 19、Phase 20 で数の階層に広げた）

fn sign(n: Num) i2 {
    return switch (n) {
        .fix, .big => intSign(exactValue(n)),
        .ratio => |v| intSign(parts(v).num),
        .single => |f| if (f > 0) 1 else if (f < 0) -1 else 0,
        .double => |f| if (f > 0) 1 else if (f < 0) -1 else 0,
    };
}

pub fn evenp(th: *Thread, args: []const Value) Value {
    _ = integerArg(th, args[0]) orelse return Value.unwind;
    return th.rt.boolean(!intIsOdd(args[0]));
}

pub fn oddp(th: *Thread, args: []const Value) Value {
    _ = integerArg(th, args[0]) orelse return Value.unwind;
    return th.rt.boolean(intIsOdd(args[0]));
}

pub fn zerop(th: *Thread, args: []const Value) Value {
    const n = numArg(th, args[0]) orelse return Value.unwind;
    return th.rt.boolean(sign(n) == 0);
}

pub fn plusp(th: *Thread, args: []const Value) Value {
    const n = realArg(th, args[0]) orelse return Value.unwind;
    return th.rt.boolean(sign(n) > 0);
}

pub fn minusp(th: *Thread, args: []const Value) Value {
    const n = realArg(th, args[0]) orelse return Value.unwind;
    return th.rt.boolean(sign(n) < 0);
}

/// max・min：引数のうち最大（最小）のものを返す（SBCL 2.6.7 と同じく、引数そのものを返す。浮動小数への変換はしない）
fn extremum(th: *Thread, comptime c: Cmp, args: []const Value) Value {
    var best = args[0];
    _ = realArg(th, best) orelse return Value.unwind;
    for (args[1..]) |a| {
        _ = realArg(th, a) orelse return Value.unwind;
        const r = compare2(th, c, a, best);
        if (r == Value.unwind) return r;
        if (r != Value.nil) best = a;
    }
    return best;
}

pub fn max(th: *Thread, args: []const Value) Value {
    return extremum(th, .gt, args);
}

pub fn min(th: *Thread, args: []const Value) Value {
    return extremum(th, .lt, args);
}

pub fn abs(th: *Thread, args: []const Value) Value {
    const n = numArg(th, args[0]) orelse return Value.unwind;
    return switch (n) {
        .single => |f| single(th, @abs(f)),
        .double => |f| double(th, @abs(f)),
        else => if (sign(n) < 0) negate(th, args[0]) else args[0],
    };
}

// ---------------------------------------------------------------------------
// 整数の割り算：floor・ceiling・truncate・round（2つの値：商と余り）、mod・rem（Phase 20）

/// x を y で割った商（整数）と余り（x - 商×y）。y が省略されたら 1
fn quotient(th: *Thread, xv: Value, yv: Value, mode: DivMode) ?QR {
    const x = realArg(th, xv) orelse return null;
    const y = realArg(th, yv) orelse return null;
    switch (kindOf2(x, y)) {
        .exact => {
            if (sign(y) == 0) {
                _ = divisionByZero(th);
                return null;
            }
            if (isInteger(x) and isInteger(y)) return intDivMod(th, xv, yv, mode);
            // 有理数：(xn/xd) / (yn/yd) の商は (xn*yd) / (xd*yn) を整数で割ったもの。余りは x - 商×y
            const px = parts(xv);
            const py = parts(yv);
            var n = intArith(th, .mul, px.num, py.den);
            if (n == Value.unwind) return null;
            var d = intArith(th, .mul, px.den, py.num);
            if (d == Value.unwind) return null;
            if (intSign(d) < 0) {
                n = intNeg(th, n);
                if (n == Value.unwind) return null;
                d = intNeg(th, d);
                if (d == Value.unwind) return null;
            }
            const qr = intDivMod(th, n, d, mode) orelse return null;
            const qy = ratArith(th, .mul, qr.q, yv);
            if (qy == Value.unwind) return null;
            const r = ratArith(th, .sub, xv, qy);
            if (r == Value.unwind) return null;
            return .{ .q = qr.q, .r = r };
        },
        inline .single, .double => |k| {
            const F = if (k == .single) f32 else f64;
            const p: F = (if (k == .single) toF32(th, x) else toF64(th, x)) orelse return null;
            const q: F = (if (k == .single) toF32(th, y) else toF64(th, y)) orelse return null;
            if (q == 0) {
                _ = divisionByZero(th);
                return null;
            }
            const t = p / q;
            // 商が浮動小数で表せなければ、浮動小数の溢れ（SBCL 2.6.7 と同じ。Codex のレビュー P20 #2）
            if (std.math.isInf(t) or std.math.isNan(t)) {
                _ = th.signal(.floating_point_overflow, "浮動小数の演算が溢れました", Value.unbound, Value.unbound);
                return null;
            }
            const qf: F = switch (mode) {
                .floor => @floor(t),
                .ceiling => @ceil(t),
                .truncate => @trunc(t),
                .round => roundEven(F, t),
            };
            const qi = floatToRational(th, qf);
            if (qi == Value.unwind) return null;
            const r = if (k == .single) single(th, p - qf * q) else double(th, p - qf * q);
            if (r == Value.unwind) return null;
            return .{ .q = qi, .r = r };
        },
    }
}

/// 最も近い整数（ちょうど半分なら偶数）
fn roundEven(comptime F: type, t: F) F {
    const r = @round(t); // 半分は 0 から遠い方
    if (@abs(t - @trunc(t)) == 0.5 and @mod(r, 2) != 0) return r - std.math.sign(t);
    return r;
}

fn divisionFn(th: *Thread, args: []const Value, mode: DivMode) Value {
    const y = if (args.len > 1) args[1] else Value.fromFixnum(1);
    const qr = quotient(th, args[0], y, mode) orelse return Value.unwind;
    th.mv[1] = qr.r;
    th.mv_count = 2;
    return qr.q;
}

pub fn floor(th: *Thread, args: []const Value) Value {
    return divisionFn(th, args, .floor);
}
pub fn ceiling(th: *Thread, args: []const Value) Value {
    return divisionFn(th, args, .ceiling);
}
pub fn truncate(th: *Thread, args: []const Value) Value {
    return divisionFn(th, args, .truncate);
}
pub fn round(th: *Thread, args: []const Value) Value {
    return divisionFn(th, args, .round);
}

/// mod（floor の余り）・rem（truncate の余り）
pub fn mod(th: *Thread, args: []const Value) Value {
    return (quotient(th, args[0], args[1], .floor) orelse return Value.unwind).r;
}

pub fn rem(th: *Thread, args: []const Value) Value {
    return (quotient(th, args[0], args[1], .truncate) orelse return Value.unwind).r;
}

// ---------------------------------------------------------------------------
// gcd・lcm・numerator・denominator・rational・float と型の述語（Phase 20）

pub fn gcd(th: *Thread, args: []const Value) Value {
    var acc = Value.fromFixnum(0);
    for (args) |a| {
        _ = integerArg(th, a) orelse return Value.unwind;
        acc = intGcd(th, acc, a);
        if (acc == Value.unwind) return acc;
    }
    return acc;
}

pub fn lcm(th: *Thread, args: []const Value) Value {
    var acc = Value.fromFixnum(1);
    for (args) |a| {
        _ = integerArg(th, a) orelse return Value.unwind;
        if (intSign(a) == 0) {
            acc = Value.fromFixnum(0);
            continue;
        }
        if (intSign(acc) == 0) continue;
        const g = intGcd(th, acc, a);
        if (g == Value.unwind) return g;
        const p = intArith(th, .mul, acc, a);
        if (p == Value.unwind) return p;
        acc = (intDivMod(th, p, g, .truncate) orelse return Value.unwind).q;
        if (intSign(acc) < 0) acc = intNeg(th, acc);
        if (acc == Value.unwind) return acc;
    }
    if (args.len == 1 and intSign(acc) < 0) return intNeg(th, acc);
    return acc;
}

pub fn numerator(th: *Thread, args: []const Value) Value {
    _ = rationalArg(th, args[0]) orelse return Value.unwind;
    return parts(args[0]).num;
}

pub fn denominator(th: *Thread, args: []const Value) Value {
    _ = rationalArg(th, args[0]) orelse return Value.unwind;
    return parts(args[0]).den;
}

pub fn rational(th: *Thread, args: []const Value) Value {
    const n = realArg(th, args[0]) orelse return Value.unwind;
    return switch (n) {
        .single => |f| floatToRational(th, f),
        .double => |f| floatToRational(th, f),
        else => args[0],
    };
}

/// (float 数 [見本])：見本がなければ single-float（既に浮動小数ならそのまま）、あれば見本と同じ形式
pub fn float(th: *Thread, args: []const Value) Value {
    const n = realArg(th, args[0]) orelse return Value.unwind;
    var to_double = n == .double;
    if (args.len > 1) {
        const p = toNum(args[1]);
        if (p == null or !(p.? == .single or p.? == .double)) return th.typeError(args[1], cl(th, "FLOAT"));
        to_double = p.? == .double;
    } else if (n == .single or n == .double) return args[0];
    if (to_double) return double(th, toF64(th, n) orelse return Value.unwind);
    return single(th, toF32(th, n) orelse return Value.unwind);
}

pub fn integerp(th: *Thread, args: []const Value) Value {
    const n = toNum(args[0]);
    return th.rt.boolean(n != null and isInteger(n.?));
}

pub fn rationalp(th: *Thread, args: []const Value) Value {
    const n = toNum(args[0]);
    return th.rt.boolean(n != null and isExact(n.?));
}

pub fn floatp(th: *Thread, args: []const Value) Value {
    const n = toNum(args[0]);
    return th.rt.boolean(n != null and (n.? == .single or n.? == .double));
}

pub fn realp(th: *Thread, args: []const Value) Value {
    return th.rt.boolean(isNumber(args[0]));
}

/// 複素数は未実装なので、いつも NIL
pub fn complexp(th: *Thread, args: []const Value) Value {
    _ = args;
    _ = th;
    return Value.nil;
}

// ---------------------------------------------------------------------------
// expt・sqrt・isqrt・exp・log・三角関数（Phase 20）

/// 浮動小数の関数の結果の形式：引数に double-float があれば double-float、そうでなければ single-float
fn floatResult(th: *Thread, is_double: bool, f: f64) Value {
    if (is_double) return double(th, f);
    return single(th, @floatCast(f));
}

/// 正確な数の、正の整数乗（2乗を繰り返す）
fn exactPow(th: *Thread, base: Value, n: u64) Value {
    if (base.isFixnum() or Runtime.kindOf(base) == .bignum) {
        if (n <= std.math.maxInt(u32)) {
            var b = toManaged(th, base) orelse return Value.unwind;
            defer b.deinit();
            var r = Managed.init(th.rt.gpa) catch return th.outOfMemory();
            r.pow(&b, @intCast(n)) catch {
                r.deinit();
                return th.outOfMemory();
            };
            return finish(th, &r);
        }
    }
    var result = Value.fromFixnum(1);
    var b = base;
    var e = n;
    while (e > 0) : (e >>= 1) {
        if (e & 1 != 0) {
            result = mul2(th, result, b);
            if (result == Value.unwind) return result;
        }
        if (e > 1) {
            b = mul2(th, b, b);
            if (b == Value.unwind) return b;
        }
    }
    return result;
}

pub fn expt(th: *Thread, args: []const Value) Value {
    const b = numArg(th, args[0]) orelse return Value.unwind;
    const p = numArg(th, args[1]) orelse return Value.unwind;
    if (isInteger(p)) {
        if (p == .big) {
            // 底が 0・1・-1 でなければ、結果は表せないほど大きい（または小さい）
            if (isExact(b) and (sign(b) == 0 or (b == .fix and (b.fix == 1 or b.fix == -1)))) {
                if (b == .fix and b.fix == -1) return Value.fromFixnum(if (intIsOdd(args[1])) -1 else 1);
                if (sign(b) == 0 and intSign(args[1]) < 0) return divisionByZero(th);
                return args[0];
            }
            if (b == .single or b == .double) return floatResult(th, b == .double, std.math.pow(f64, toF64(th, b).?, intToFloat(f64, args[1])));
            return th.signal(.storage_condition, "EXPT の結果が大きすぎます", args[1], Value.unbound);
        }
        const n = p.fix;
        if (isExact(b)) {
            if (n == 0) return Value.fromFixnum(1);
            if (n > 0) return exactPow(th, args[0], @intCast(n));
            if (sign(b) == 0) return divisionByZero(th);
            const d = exactPow(th, args[0], @intCast(-n));
            if (d == Value.unwind) return d;
            return div2(th, Value.fromFixnum(1), d);
        }
        // 浮動小数の整数乗（(expt x 0) は x の形式の 1）
        return floatResult(th, b == .double, std.math.pow(f64, toF64(th, b).?, @floatFromInt(n)));
    }
    // 指数が比・浮動小数：結果は浮動小数。指数が 0 なら 1、底が 0 なら指数の正負で 0 か 0 除算、負の底は複素数になる
    // （SBCL 2.6.7 と同じ。Codex のレビュー P20 #3）
    const is_double = b == .double or p == .double;
    if (sign(p) == 0) return floatResult(th, is_double, 1);
    if (sign(b) == 0) {
        if (sign(p) < 0) return divisionByZero(th);
        return floatResult(th, is_double, 0);
    }
    if (sign(b) < 0) return complexError(th);
    const bf = toF64(th, b) orelse return Value.unwind;
    const pf = toF64(th, p) orelse return Value.unwind;
    return floatResult(th, is_double, std.math.pow(f64, bf, pf));
}

pub fn sqrt(th: *Thread, args: []const Value) Value {
    const n = numArg(th, args[0]) orelse return Value.unwind;
    if (sign(n) < 0) return complexError(th);
    const f = toF64(th, n) orelse return Value.unwind;
    return floatResult(th, n == .double, @sqrt(f));
}

pub fn isqrt(th: *Thread, args: []const Value) Value {
    const n = integerArg(th, args[0]) orelse return Value.unwind;
    if (sign(n) < 0) return th.typeError(args[0], cl(th, "UNSIGNED-BYTE"));
    if (n == .fix) return Value.fromFixnum(@intCast(std.math.sqrt(@as(u64, @intCast(n.fix)))));
    var x = toManaged(th, args[0]) orelse return Value.unwind;
    defer x.deinit();
    var r = Managed.init(th.rt.gpa) catch return th.outOfMemory();
    r.sqrt(&x) catch {
        r.deinit();
        return th.outOfMemory();
    };
    return finish(th, &r);
}

/// 実数1つを取り、浮動小数を返す関数
fn floatFn(th: *Thread, v: Value, comptime f: fn (f64) f64) Value {
    const n = numArg(th, v) orelse return Value.unwind;
    const x = toF64(th, n) orelse return Value.unwind;
    return floatResult(th, n == .double, f(x));
}

fn expF(x: f64) f64 {
    return @exp(x);
}
fn sinF(x: f64) f64 {
    return @sin(x);
}
fn cosF(x: f64) f64 {
    return @cos(x);
}
fn tanF(x: f64) f64 {
    return @tan(x);
}
fn asinF(x: f64) f64 {
    return std.math.asin(x);
}
fn acosF(x: f64) f64 {
    return std.math.acos(x);
}

pub fn exp(th: *Thread, args: []const Value) Value {
    return floatFn(th, args[0], expF);
}
pub fn sin(th: *Thread, args: []const Value) Value {
    return floatFn(th, args[0], sinF);
}
pub fn cos(th: *Thread, args: []const Value) Value {
    return floatFn(th, args[0], cosF);
}
pub fn tan(th: *Thread, args: []const Value) Value {
    return floatFn(th, args[0], tanF);
}

fn arcFn(th: *Thread, v: Value, comptime f: fn (f64) f64) Value {
    const n = numArg(th, v) orelse return Value.unwind;
    const x = toF64(th, n) orelse return Value.unwind;
    if (x > 1 or x < -1) return complexError(th);
    return floatResult(th, n == .double, f(x));
}

pub fn asin(th: *Thread, args: []const Value) Value {
    return arcFn(th, args[0], asinF);
}
pub fn acos(th: *Thread, args: []const Value) Value {
    return arcFn(th, args[0], acosF);
}

/// (atan y [x])
pub fn atan(th: *Thread, args: []const Value) Value {
    const y = realArg(th, args[0]) orelse return Value.unwind;
    const yf = toF64(th, y) orelse return Value.unwind;
    if (args.len == 1) return floatResult(th, y == .double, std.math.atan(yf));
    const x = realArg(th, args[1]) orelse return Value.unwind;
    const xf = toF64(th, x) orelse return Value.unwind;
    return floatResult(th, y == .double or x == .double, std.math.atan2(yf, xf));
}

/// 正の整数の自然対数。浮動小数で表せない大きさの整数も、仮数と2進の指数に分けて求める（Codex のレビュー P20 #7）
fn intLog(th: *Thread, v: Value) ?f64 {
    if (v.isFixnum()) return @log(@as(f64, @floatFromInt(v.asFixnum())));
    const len = bitLength(v);
    if (len <= 1000) return @log(intToFloat(f64, v));
    var m = toManaged(th, v) orelse return null;
    defer m.deinit();
    const sh = len - 64;
    m.shiftRight(&m, sh) catch {
        _ = th.outOfMemory();
        return null;
    };
    return @log(m.toConst().toFloat(f64, .nearest_even)[0]) + @as(f64, @floatFromInt(sh)) * std.math.ln2;
}

/// 正の数の自然対数（正確な数は、分子と分母を別に求めて、途中の溢れを避ける）
fn positiveLog(th: *Thread, n: Num) ?f64 {
    return switch (n) {
        .fix, .big => intLog(th, exactValue(n)),
        .ratio => |v| blk: {
            const p = parts(v);
            const a = intLog(th, p.num) orelse break :blk null;
            const b = intLog(th, p.den) orelse break :blk null;
            break :blk a - b;
        },
        .single => |f| @log(@as(f64, f)),
        .double => |f| @log(f),
    };
}

/// (log 数 [底])：0 は division-by-zero、負の数は複素数（未実装）
pub fn log(th: *Thread, args: []const Value) Value {
    const n = numArg(th, args[0]) orelse return Value.unwind;
    if (sign(n) < 0) return complexError(th);
    if (sign(n) == 0) return divisionByZero(th);
    const x = positiveLog(th, n) orelse return Value.unwind;
    if (args.len == 1) return floatResult(th, n == .double, x);
    const b = numArg(th, args[1]) orelse return Value.unwind;
    if (sign(b) < 0) return complexError(th);
    if (sign(b) == 0) return floatResult(th, n == .double or b == .double, 0);
    const lb = positiveLog(th, b) orelse return Value.unwind;
    return floatResult(th, n == .double or b == .double, x / lb);
}

// ---------------------------------------------------------------------------
// ビット演算（2の補数の意味。Phase 20）

const BitOp = enum { @"and", @"or", xor };

fn bitOp2(th: *Thread, comptime op: BitOp, a: Value, b: Value) Value {
    if (a.isFixnum() and b.isFixnum()) {
        const x = a.asFixnum();
        const y = b.asFixnum();
        return Value.fromFixnum(switch (op) {
            .@"and" => x & y,
            .@"or" => x | y,
            .xor => x ^ y,
        });
    }
    var x = toManaged(th, a) orelse return Value.unwind;
    defer x.deinit();
    var y = toManaged(th, b) orelse return Value.unwind;
    defer y.deinit();
    var r = Managed.init(th.rt.gpa) catch return th.outOfMemory();
    (switch (op) {
        .@"and" => r.bitAnd(&x, &y),
        .@"or" => r.bitOr(&x, &y),
        .xor => r.bitXor(&x, &y),
    }) catch {
        r.deinit();
        return th.outOfMemory();
    };
    return finish(th, &r);
}

fn bitFold(th: *Thread, comptime op: BitOp, args: []const Value) Value {
    var acc = Value.fromFixnum(if (op == .@"and") -1 else 0);
    for (args) |a| {
        _ = integerArg(th, a) orelse return Value.unwind;
        acc = bitOp2(th, op, acc, a);
        if (acc == Value.unwind) return acc;
    }
    return acc;
}

pub fn logand(th: *Thread, args: []const Value) Value {
    return bitFold(th, .@"and", args);
}
pub fn logior(th: *Thread, args: []const Value) Value {
    return bitFold(th, .@"or", args);
}
pub fn logxor(th: *Thread, args: []const Value) Value {
    return bitFold(th, .xor, args);
}

/// lognot：-x - 1
pub fn lognot(th: *Thread, args: []const Value) Value {
    _ = integerArg(th, args[0]) orelse return Value.unwind;
    return intArith(th, .sub, Value.fromFixnum(-1), args[0]);
}

/// (ash 整数 数)：左へ数ビット（負なら右へ。右は floor の意味）
pub fn ash(th: *Thread, args: []const Value) Value {
    _ = integerArg(th, args[0]) orelse return Value.unwind;
    const c = integerArg(th, args[1]) orelse return Value.unwind;
    if (intSign(args[0]) == 0) return args[0];
    if (c == .big) {
        if (intSign(args[1]) < 0) return Value.fromFixnum(if (intSign(args[0]) < 0) -1 else 0);
        return th.signal(.storage_condition, "ASH の結果が大きすぎます", args[1], Value.unbound);
    }
    const count = c.fix;
    if (count >= 0) {
        if (args[0].isFixnum() and count < 62) {
            const r = @as(i128, args[0].asFixnum()) << @intCast(count);
            return fromI128(th, r);
        }
        var x = toManaged(th, args[0]) orelse return Value.unwind;
        x.shiftLeft(&x, @intCast(count)) catch {
            x.deinit();
            return th.outOfMemory();
        };
        return finish(th, &x);
    }
    if (args[0].isFixnum()) {
        const sh: u6 = @intCast(@min(-count, 63));
        return Value.fromFixnum(args[0].asFixnum() >> sh);
    }
    // ビットの長さ以上の右シフトは 0 か -1（2^(-count) を作らない。Codex のレビュー P20 #6）
    if (-count >= bitLength(args[0])) return Value.fromFixnum(if (intSign(args[0]) < 0) -1 else 0);
    // bignum の右シフト：2^(-count) で floor の割り算をする
    var p = Managed.initSet(th.rt.gpa, @as(i64, 1)) catch return th.outOfMemory();
    p.shiftLeft(&p, @intCast(-count)) catch {
        p.deinit();
        return th.outOfMemory();
    };
    const pv = finish(th, &p);
    if (pv == Value.unwind) return pv;
    return (intDivMod(th, args[0], pv, .floor) orelse return Value.unwind).q;
}

/// integer-length：負なら lognot のビットの長さ
pub fn integerLength(th: *Thread, args: []const Value) Value {
    _ = integerArg(th, args[0]) orelse return Value.unwind;
    var v = args[0];
    if (intSign(v) < 0) {
        v = intArith(th, .sub, Value.fromFixnum(-1), v);
        if (v == Value.unwind) return v;
    }
    if (intSign(v) == 0) return Value.fromFixnum(0);
    return Value.fromFixnum(@intCast(bitLength(v)));
}

/// logcount：負なら lognot の 1 のビットの数
pub fn logcount(th: *Thread, args: []const Value) Value {
    _ = integerArg(th, args[0]) orelse return Value.unwind;
    var v = args[0];
    if (intSign(v) < 0) {
        v = intArith(th, .sub, Value.fromFixnum(-1), v);
        if (v == Value.unwind) return v;
    }
    if (v.isFixnum()) return Value.fromFixnum(@popCount(@as(u64, @intCast(v.asFixnum()))));
    var n: i64 = 0;
    for (Runtime.bignumPtr(v).limbs()) |l| n += @popCount(l);
    return Value.fromFixnum(n);
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

test "round half to even" {
    try std.testing.expectEqual(@as(f64, 2), roundEven(f64, 2.5));
    try std.testing.expectEqual(@as(f64, 4), roundEven(f64, 3.5));
    try std.testing.expectEqual(@as(f64, -2), roundEven(f64, -2.5));
    try std.testing.expectEqual(@as(f64, 3), roundEven(f64, 2.6));
}
