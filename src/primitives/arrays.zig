//! 1次元の配列（Phase 16 の最小版）：make-array・aref・svref・char・schar と、その書き込み（%aset・%set-char）、
//! length・copy-seq・vectorp・arrayp・simple-vector-p。
//! 要素の型が T の配列は simple-vector、文字の配列は文字列で表す。
//! 多次元の配列・fill-pointer・adjustable・displaced は Phase 21（明示的なエラーにする）。

const std = @import("std");
const Value = @import("../values/value.zig").Value;
const Thread = @import("../runtime/thread.zig").Thread;
const Runtime = @import("../runtime/runtime.zig").Runtime;
const keyargs = @import("keyargs.zig");

fn isVector(v: Value) bool {
    return v.isOther() and Runtime.kindOf(v) == .simple_vector;
}
fn isString(v: Value) bool {
    return v.isOther() and Runtime.kindOf(v) == .string;
}

fn cl(th: *Thread, name: []const u8) Value {
    return (th.rt.findSymbol(th.rt.cl, name) orelse unreachable).symbol;
}

/// 要素の型が文字か（character・base-char・standard-char）
fn isCharacterType(th: *Thread, t: Value) bool {
    for ([_][]const u8{ "CHARACTER", "BASE-CHAR", "STANDARD-CHAR" }) |n| if (t == cl(th, n)) return true;
    return false;
}

/// 列（リスト・ベクタ・文字列）の要素を out に並べる。out の長さと列の長さが同じでなければ false
fn sequenceItems(th: *Thread, seq: Value, n: usize, comptime f: anytype, ctx: anytype) Value {
    _ = th;
    var i: usize = 0;
    if (seq.isList()) {
        var x = seq;
        while (x.isCons()) : (x = Runtime.consPtr(x).cdr) {
            if (i >= n) return Value.nil;
            f(ctx, i, Runtime.consPtr(x).car);
            i += 1;
        }
    } else if (isVector(seq)) {
        for (Runtime.vectorPtr(seq).items()) |e| {
            if (i >= n) return Value.nil;
            f(ctx, i, e);
            i += 1;
        }
    } else if (isString(seq)) {
        const s = Runtime.stringPtr(seq);
        for (0..s.length()) |k| {
            if (i >= n) return Value.nil;
            f(ctx, i, Value.fromChar(s.charAt(k)));
            i += 1;
        }
    } else return Value.unbound;
    return if (i == n) Value.fromFixnum(1) else Value.nil;
}

/// make-array 次元 &key element-type initial-element initial-contents adjustable fill-pointer displaced-to displaced-index-offset
pub fn makeArray(th: *Thread, args: []const Value) Value {
    var kv: [7]?Value = undefined;
    if (!keyargs.parse(th, args[1..], &.{ "ELEMENT-TYPE", "INITIAL-ELEMENT", "INITIAL-CONTENTS", "ADJUSTABLE", "FILL-POINTER", "DISPLACED-TO", "DISPLACED-INDEX-OFFSET" }, &kv)) return Value.unwind;
    var dims = args[0];
    if (dims.isCons()) {
        if (Runtime.consPtr(dims).cdr != Value.nil)
            return th.signal(.unimplemented, "多次元の配列は未実装です（Phase 21 で実装予定）", dims, Value.unbound);
        dims = Runtime.consPtr(dims).car;
    }
    if (!dims.isFixnum() or dims.asFixnum() < 0) return th.typeError(dims, th.rt.syms.integer);
    const n: usize = @intCast(dims.asFixnum());
    if ((kv[3] != null and kv[3].? != Value.nil) or (kv[4] != null and kv[4].? != Value.nil) or (kv[5] != null and kv[5].? != Value.nil))
        return th.signal(.unimplemented, "adjustable・fill-pointer・displaced の配列は未実装です（Phase 21 で実装予定）", Value.unbound, Value.unbound);
    if (kv[1] != null and kv[2] != null)
        return th.signal(.program_error, ":initial-element と :initial-contents は同時に指定できません", Value.unbound, Value.unbound);
    const chars = if (kv[0]) |t| isCharacterType(th, t) else false;
    if (chars) {
        var init: u21 = 0;
        if (kv[1]) |c| {
            if (!c.isChar()) return th.typeError(c, cl(th, "CHARACTER"));
            init = c.asChar();
        }
        const s = th.rt.makeStringFilled(n, init) catch return th.outOfMemory();
        if (kv[2]) |contents| {
            const Ctx = struct { th: *Thread, s: Value, bad: Value = Value.unbound };
            var ctx: Ctx = .{ .th = th, .s = s };
            const r = sequenceItems(th, contents, n, struct {
                fn put(c: *Ctx, i: usize, e: Value) void {
                    if (!e.isChar()) {
                        c.bad = e;
                        return;
                    }
                    c.th.rt.stringSetChar(c.s, i, e.asChar()) catch {};
                }
            }.put, &ctx);
            if (ctx.bad != Value.unbound) return th.typeError(ctx.bad, cl(th, "CHARACTER"));
            if (r != Value.fromFixnum(1)) return th.signal(.simple_error, ":initial-contents の長さが次元と違います", contents, Value.unbound);
        }
        return s;
    }
    // 要素の型が T（ほかの型も T に格上げする：CLHS 15.1.2.1 upgraded-array-element-type）。既定の初期値は 0（SBCL 2.6.7 と同じ）
    const v = th.rt.makeVectorFilled(n, kv[1] orelse Value.fromFixnum(0)) catch return th.outOfMemory();
    if (kv[2]) |contents| {
        const items = Runtime.vectorPtr(v).items();
        const r = sequenceItems(th, contents, n, struct {
            fn put(it: []Value, i: usize, e: Value) void {
                it[i] = e;
            }
        }.put, items);
        if (r != Value.fromFixnum(1)) return th.signal(.simple_error, ":initial-contents の長さが次元と違います", contents, Value.unbound);
    }
    return v;
}

/// 添字を確かめる。範囲外なら type-error（期待する型は (INTEGER 0 (n))）
fn index(th: *Thread, i: Value, n: usize) ?usize {
    if (i.isFixnum() and i.asFixnum() >= 0 and @as(usize, @intCast(i.asFixnum())) < n) return @intCast(i.asFixnum());
    const rt = th.rt;
    const bound = rt.cons(Value.fromFixnum(@intCast(n)), Value.nil) catch {
        _ = th.outOfMemory();
        return null;
    };
    var t = rt.cons(bound, Value.nil) catch {
        _ = th.outOfMemory();
        return null;
    };
    t = rt.cons(Value.fromFixnum(0), t) catch {
        _ = th.outOfMemory();
        return null;
    };
    t = rt.cons(rt.syms.integer, t) catch {
        _ = th.outOfMemory();
        return null;
    };
    _ = th.typeError(i, t);
    return null;
}

fn oneSubscript(th: *Thread, args: []const Value) ?Value {
    if (args.len != 2) {
        _ = th.signal(.unimplemented, "多次元の配列は未実装です（Phase 21 で実装予定）", Value.unbound, Value.unbound);
        return null;
    }
    return args[1];
}

pub fn aref(th: *Thread, args: []const Value) Value {
    const a = args[0];
    const sub = oneSubscript(th, args) orelse return Value.unwind;
    if (isVector(a)) {
        const items = Runtime.vectorPtr(a).items();
        return items[index(th, sub, items.len) orelse return Value.unwind];
    }
    if (isString(a)) {
        const s = Runtime.stringPtr(a);
        return Value.fromChar(s.charAt(index(th, sub, s.length()) orelse return Value.unwind));
    }
    return th.typeError(a, cl(th, "ARRAY"));
}

/// ZILISP-SYSTEM::%ASET 配列 添字 値：(setf (aref 配列 添字) 値) の展開先。値を返す
pub fn sysAset(th: *Thread, args: []const Value) Value {
    const a = args[0];
    const v = args[args.len - 1];
    if (args.len != 3) return th.signal(.unimplemented, "多次元の配列は未実装です（Phase 21 で実装予定）", Value.unbound, Value.unbound);
    if (isVector(a)) {
        const items = Runtime.vectorPtr(a).items();
        items[index(th, args[1], items.len) orelse return Value.unwind] = v;
        return v;
    }
    if (isString(a)) {
        const s = Runtime.stringPtr(a);
        const i = index(th, args[1], s.length()) orelse return Value.unwind;
        if (!v.isChar()) return th.typeError(v, cl(th, "CHARACTER"));
        th.rt.stringSetChar(a, i, v.asChar()) catch return th.outOfMemory();
        return v;
    }
    return th.typeError(a, cl(th, "ARRAY"));
}

pub fn svref(th: *Thread, args: []const Value) Value {
    if (!isVector(args[0])) return th.typeError(args[0], cl(th, "SIMPLE-VECTOR"));
    return aref(th, args);
}

pub fn sysSvset(th: *Thread, args: []const Value) Value {
    if (!isVector(args[0])) return th.typeError(args[0], cl(th, "SIMPLE-VECTOR"));
    return sysAset(th, args);
}

pub fn char(th: *Thread, args: []const Value) Value {
    if (!isString(args[0])) return th.typeError(args[0], cl(th, "STRING"));
    return aref(th, args);
}

pub fn sysSetChar(th: *Thread, args: []const Value) Value {
    if (!isString(args[0])) return th.typeError(args[0], cl(th, "STRING"));
    return sysAset(th, args);
}

/// length：リスト（真リスト）・ベクタ・文字列の長さ
pub fn length(th: *Thread, args: []const Value) Value {
    const x = args[0];
    if (x.isList()) {
        var n: i64 = 0;
        var p = x;
        while (p.isCons()) : (p = Runtime.consPtr(p).cdr) n += 1;
        if (p != Value.nil) return th.typeError(x, th.rt.syms.list);
        return Value.fromFixnum(n);
    }
    if (isVector(x)) return Value.fromFixnum(@intCast(Runtime.vectorPtr(x).items().len));
    if (isString(x)) return Value.fromFixnum(@intCast(Runtime.stringPtr(x).length()));
    return th.typeError(x, cl(th, "SEQUENCE"));
}

/// copy-seq：リスト・ベクタ・文字列を写す
pub fn copySeq(th: *Thread, args: []const Value) Value {
    const x = args[0];
    const rt = th.rt;
    if (x.isList()) {
        var head = Value.nil;
        var tail = Value.nil;
        var p = x;
        while (p.isCons()) : (p = Runtime.consPtr(p).cdr) {
            const c = rt.cons(Runtime.consPtr(p).car, Value.nil) catch return th.outOfMemory();
            if (tail == Value.nil) head = c else Runtime.consPtr(tail).cdr = c;
            tail = c;
        }
        if (p != Value.nil) return th.typeError(x, rt.syms.list);
        return head;
    }
    if (isVector(x)) return rt.makeVector(Runtime.vectorPtr(x).items()) catch th.outOfMemory();
    if (isString(x)) {
        const s = Runtime.stringPtr(x);
        const n = s.length();
        const out = rt.makeStringFilled(n, 0) catch return th.outOfMemory();
        for (0..n) |i| rt.stringSetChar(out, i, Runtime.stringPtr(x).charAt(i)) catch return th.outOfMemory();
        return out;
    }
    return th.typeError(x, cl(th, "SEQUENCE"));
}

pub fn vectorp(th: *Thread, args: []const Value) Value {
    return th.rt.boolean(isVector(args[0]) or isString(args[0]));
}

pub fn arrayp(th: *Thread, args: []const Value) Value {
    return th.rt.boolean(isVector(args[0]) or isString(args[0]));
}

pub fn simpleVectorP(th: *Thread, args: []const Value) Value {
    return th.rt.boolean(isVector(args[0]));
}
