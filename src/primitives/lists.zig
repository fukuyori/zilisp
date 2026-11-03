//! リストと述語（Phase 08 の範囲）：cons car cdr first rest list list* null not atom consp listp
//! symbolp numberp functionp eq eql。
//! 残りの列・リストの関数は Phase 21 で実装する。

const std = @import("std");
const Value = @import("../values/value.zig").Value;
const Thread = @import("../runtime/thread.zig").Thread;
const Runtime = @import("../runtime/runtime.zig").Runtime;
const numbers = @import("numbers.zig");
const arrays = @import("arrays.zig");

pub fn cons(th: *Thread, args: []const Value) Value {
    return th.rt.cons(args[0], args[1]) catch th.outOfMemory();
}

pub fn car1(th: *Thread, x: Value) Value {
    if (x.isCons()) return Runtime.consPtr(x).car;
    if (x == Value.nil) return Value.nil;
    return th.typeError(x, th.rt.syms.list);
}

pub fn cdr1(th: *Thread, x: Value) Value {
    if (x.isCons()) return Runtime.consPtr(x).cdr;
    if (x == Value.nil) return Value.nil;
    return th.typeError(x, th.rt.syms.list);
}

pub fn car(th: *Thread, args: []const Value) Value {
    return car1(th, args[0]);
}

pub fn cdr(th: *Thread, args: []const Value) Value {
    return cdr1(th, args[0]);
}

/// 引数の並びからリストを作る。tail を最後の cdr にする。
/// 作っている途中のリストは、ネイティブのスタックにある変数 head が保持する（§3.4）
fn listFrom(th: *Thread, items: []const Value, tail: Value) Value {
    var head = tail;
    var i = items.len;
    while (i > 0) : (i -= 1) {
        head = th.rt.cons(items[i - 1], head) catch return th.outOfMemory();
    }
    return head;
}

pub fn list(th: *Thread, args: []const Value) Value {
    return listFrom(th, args, Value.nil);
}

pub fn listStar(th: *Thread, args: []const Value) Value {
    return listFrom(th, args[0 .. args.len - 1], args[args.len - 1]);
}

pub fn null_(th: *Thread, args: []const Value) Value {
    return th.rt.boolean(args[0] == Value.nil);
}

pub fn atom(th: *Thread, args: []const Value) Value {
    return th.rt.boolean(!args[0].isCons());
}

pub fn consp(th: *Thread, args: []const Value) Value {
    return th.rt.boolean(args[0].isCons());
}

pub fn listp(th: *Thread, args: []const Value) Value {
    return th.rt.boolean(args[0].isList());
}

pub fn symbolp(th: *Thread, args: []const Value) Value {
    const x = args[0];
    return th.rt.boolean(x == Value.nil or (x.isOther() and Runtime.kindOf(x) == .symbol));
}

pub fn numberp(th: *Thread, args: []const Value) Value {
    return th.rt.boolean(numbers.isNumber(args[0]));
}

pub fn functionp(th: *Thread, args: []const Value) Value {
    return th.rt.boolean(args[0].isFunctionPointer());
}

pub fn eq(th: *Thread, args: []const Value) Value {
    return th.rt.boolean(args[0] == args[1]);
}

/// eql：eq であるか、同じ型の数で値が同じ（浮動小数は表現が同じ。(eql 0.0 -0.0) は偽）。bignum・比は値で比べる（Phase 20）
pub fn eql2(a: Value, b: Value) bool {
    if (a == b) return true;
    if (!(a.isOther() and b.isOther())) return false;
    const ka = Runtime.kindOf(a);
    if (ka != Runtime.kindOf(b)) return false;
    return switch (ka.?) {
        .double_float => @as(u64, @bitCast(Runtime.doubleValue(a))) == @as(u64, @bitCast(Runtime.doubleValue(b))),
        .bignum => Runtime.bignumConst(a).eql(Runtime.bignumConst(b)),
        .ratio => eql2(Runtime.ratioPtr(a).numerator, Runtime.ratioPtr(b).numerator) and
            eql2(Runtime.ratioPtr(a).denominator, Runtime.ratioPtr(b).denominator),
        else => false,
    };
}

pub fn eql(th: *Thread, args: []const Value) Value {
    return th.rt.boolean(eql2(args[0], args[1]));
}

/// append：最後以外のリストを写してつなぐ（最後のリストは共有する。CLHS append）
pub fn append(th: *Thread, args: []const Value) Value {
    if (args.len == 0) return Value.nil;
    var head = Value.nil;
    var tail = Value.nil;
    for (args[0 .. args.len - 1]) |l| {
        var x = l;
        while (x.isCons()) : (x = Runtime.consPtr(x).cdr) {
            const c = th.rt.cons(Runtime.consPtr(x).car, Value.nil) catch return th.outOfMemory();
            if (tail == Value.nil) head = c else Runtime.consPtr(tail).cdr = c;
            tail = c;
        }
        if (x != Value.nil) return th.typeError(l, th.rt.syms.list);
    }
    const last = args[args.len - 1];
    if (tail == Value.nil) return last;
    Runtime.consPtr(tail).cdr = last;
    return head;
}

/// vector：引数を要素とする単純ベクタ
pub fn vector(th: *Thread, args: []const Value) Value {
    return th.rt.makeVector(args) catch th.outOfMemory();
}

/// equal：eql か、cons なら car と cdr が equal、文字列なら同じ文字の並び（CLHS equal）
pub fn equal2(a: Value, b: Value) bool {
    // パス名は欄ごとに equal（Phase 23。CLHS equal）
    if (a.isOther() and b.isOther() and Runtime.kindOf(a) == .pathname and Runtime.kindOf(b) == .pathname)
        return @import("pathnames.zig").equalPathnames(a, b);
    var x = a;
    var y = b;
    while (true) {
        if (eql2(x, y)) return true;
        if (x.isCons() and y.isCons()) {
            if (!equal2(Runtime.consPtr(x).car, Runtime.consPtr(y).car)) return false;
            x = Runtime.consPtr(x).cdr;
            y = Runtime.consPtr(y).cdr;
            continue;
        }
        // 文字列（単純でないものも。有効な部分を比べる：Phase 21）
        if (arrays.isStringLike(x) and arrays.isStringLike(y)) {
            const vx = arrays.vectorView(x).?;
            const vy = arrays.vectorView(y).?;
            if (vx.len != vy.len) return false;
            const s = Runtime.stringPtr(vx.data);
            const t = Runtime.stringPtr(vy.data);
            for (0..vx.len) |i| if (s.charAt(i) != t.charAt(i)) return false;
            return true;
        }
        return false;
    }
}

pub fn equal(th: *Thread, args: []const Value) Value {
    return th.rt.boolean(equal2(args[0], args[1]));
}

pub fn rplaca(th: *Thread, args: []const Value) Value {
    if (!args[0].isCons()) return th.typeError(args[0], th.rt.syms.cons);
    Runtime.consPtr(args[0]).car = args[1];
    return args[0];
}

pub fn rplacd(th: *Thread, args: []const Value) Value {
    if (!args[0].isCons()) return th.typeError(args[0], th.rt.syms.cons);
    Runtime.consPtr(args[0]).cdr = args[1];
    return args[0];
}

/// ZILISP-SYSTEM::%SET-CAR・%SET-CDR：(setf (car x) v) の展開先。値を返す
pub fn sysSetCar(th: *Thread, args: []const Value) Value {
    if (!args[0].isCons()) return th.typeError(args[0], th.rt.syms.cons);
    Runtime.consPtr(args[0]).car = args[1];
    return args[1];
}

pub fn sysSetCdr(th: *Thread, args: []const Value) Value {
    if (!args[0].isCons()) return th.typeError(args[0], th.rt.syms.cons);
    Runtime.consPtr(args[0]).cdr = args[1];
    return args[1];
}

fn indexArg(th: *Thread, v: Value) ?usize {
    if (v.isFixnum() and v.asFixnum() >= 0) return @intCast(v.asFixnum());
    _ = th.typeError(v, th.rt.syms.integer);
    return null;
}

pub fn nthcdr1(th: *Thread, n: usize, lst: Value) Value {
    var x = lst;
    var i: usize = 0;
    while (i < n) : (i += 1) {
        if (x == Value.nil) return Value.nil;
        if (!x.isCons()) return th.typeError(lst, th.rt.syms.list);
        x = Runtime.consPtr(x).cdr;
    }
    return x;
}

pub fn nthcdr(th: *Thread, args: []const Value) Value {
    return nthcdr1(th, indexArg(th, args[0]) orelse return Value.unwind, args[1]);
}

pub fn nth(th: *Thread, args: []const Value) Value {
    const x = nthcdr1(th, indexArg(th, args[0]) orelse return Value.unwind, args[1]);
    if (x == Value.unwind) return x;
    return car1(th, x);
}

/// c[ad]+r：path の文字を右から順に適用する（"ad" は (car (cdr x))）
fn cxr(th: *Thread, comptime path: []const u8, x0: Value) Value {
    var x = x0;
    comptime var i = path.len;
    inline while (i > 0) : (i -= 1) {
        x = if (path[i - 1] == 'a') car1(th, x) else cdr1(th, x);
        if (x == Value.unwind) return x;
    }
    return x;
}

pub fn makeCxr(comptime path: []const u8) fn (*Thread, []const Value) Value {
    return struct {
        fn f(th: *Thread, args: []const Value) Value {
            return cxr(th, path, args[0]);
        }
    }.f;
}

/// second〜tenth
pub fn makeNth(comptime n: usize) fn (*Thread, []const Value) Value {
    return struct {
        fn f(th: *Thread, args: []const Value) Value {
            const x = nthcdr1(th, n, args[0]);
            if (x == Value.unwind) return x;
            return car1(th, x);
        }
    }.f;
}

/// getf 属性リスト 指示子 [既定値]
pub fn getf(th: *Thread, args: []const Value) Value {
    var x = args[0];
    while (x.isCons()) {
        const c = Runtime.consPtr(x);
        if (!c.cdr.isCons()) return th.typeError(args[0], th.rt.syms.list);
        if (c.car == args[1]) return Runtime.consPtr(c.cdr).car;
        x = Runtime.consPtr(c.cdr).cdr;
    }
    if (x != Value.nil) return th.typeError(args[0], th.rt.syms.list);
    return if (args.len > 2) args[2] else Value.nil;
}

/// ZILISP-SYSTEM::%PUTF 属性リスト 指示子 値：指示子があれば値を書き換えて同じリストを、なければ先頭に足したリストを返す
/// （(setf (getf 場所 指示子) 値) の展開先。CLHS getf：新しい組は先頭に足してよい。SBCL 2.6.7 も先頭に足す）
pub fn sysPutf(th: *Thread, args: []const Value) Value {
    var x = args[0];
    while (x.isCons()) {
        const c = Runtime.consPtr(x);
        if (!c.cdr.isCons()) return th.typeError(args[0], th.rt.syms.list);
        if (c.car == args[1]) {
            Runtime.consPtr(c.cdr).car = args[2];
            return args[0];
        }
        x = Runtime.consPtr(c.cdr).cdr;
    }
    const tail = th.rt.cons(args[2], args[0]) catch return th.outOfMemory();
    return th.rt.cons(args[1], tail) catch th.outOfMemory();
}
