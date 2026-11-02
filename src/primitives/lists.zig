//! リストと述語（Phase 08 の範囲）：cons car cdr first rest list list* null not atom consp listp
//! symbolp numberp functionp eq eql。
//! 残りの列・リストの関数は Phase 21 で実装する。

const std = @import("std");
const Value = @import("../values/value.zig").Value;
const Thread = @import("../runtime/thread.zig").Thread;
const Runtime = @import("../runtime/runtime.zig").Runtime;
const numbers = @import("numbers.zig");

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

/// eql：eq であるか、同じ型の数で値が同じ（浮動小数は表現が同じ。(eql 0.0 -0.0) は偽）
pub fn eql2(a: Value, b: Value) bool {
    if (a == b) return true;
    if (a.isOther() and b.isOther() and Runtime.kindOf(a) == .double_float and Runtime.kindOf(b) == .double_float) {
        return @as(u64, @bitCast(Runtime.doubleValue(a))) == @as(u64, @bitCast(Runtime.doubleValue(b)));
    }
    return false;
}

pub fn eql(th: *Thread, args: []const Value) Value {
    return th.rt.boolean(eql2(args[0], args[1]));
}
