//! 列・文字列の関数の一部（Phase 19。反復の教材と loop の展開が使うもの）：
//! reverse・nreverse・copy-list・last・endp、symbol-name・string=・string-upcase・string-downcase。
//! 列の関数の全体（:test・:key を取る関数、subseq など）は Phase 21 で実装する。
//! 大文字・小文字の変換は ASCII の文字だけを対象にする（Reader の変換と同じ。SBCL 2.6.7 は Unicode の文字も変換する）。

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
fn isSymbol(v: Value) bool {
    return v == Value.nil or (v.isOther() and Runtime.kindOf(v) == .symbol);
}

fn cl(th: *Thread, name: []const u8) Value {
    return (th.rt.findSymbol(th.rt.cl, name) orelse unreachable).symbol;
}

fn properListError(th: *Thread, v: Value) Value {
    return th.typeError(v, th.rt.syms.list);
}

/// (reverse 列)：新しい列を返す
pub fn reverse(th: *Thread, args: []const Value) Value {
    const seq = args[0];
    if (seq.isList()) {
        var out = Value.nil;
        var x = seq;
        while (x.isCons()) : (x = Runtime.consPtr(x).cdr) out = th.rt.cons(Runtime.consPtr(x).car, out) catch return th.outOfMemory();
        if (x != Value.nil) return properListError(th, seq);
        return out;
    }
    if (isVector(seq)) {
        const n = Runtime.vectorPtr(seq).items().len;
        const v = th.rt.makeVectorFilled(n, Value.nil) catch return th.outOfMemory();
        const src = Runtime.vectorPtr(seq).items();
        const dst = Runtime.vectorPtr(v).items();
        for (0..n) |i| dst[i] = src[n - 1 - i];
        return v;
    }
    if (isString(seq)) {
        const n = Runtime.stringPtr(seq).length();
        const s = th.rt.makeStringFilled(n, ' ') catch return th.outOfMemory();
        for (0..n) |i| th.rt.stringSetChar(s, i, Runtime.stringPtr(seq).charAt(n - 1 - i)) catch return th.outOfMemory();
        return s;
    }
    return th.typeError(seq, cl(th, "SEQUENCE"));
}

/// (nreverse 列)：リストはつなぎ替え、ベクタ・文字列はその場で並べ替える
pub fn nreverse(th: *Thread, args: []const Value) Value {
    const seq = args[0];
    if (seq.isList()) {
        var prev = Value.nil;
        var x = seq;
        while (x.isCons()) {
            const c = Runtime.consPtr(x);
            const next = c.cdr;
            c.cdr = prev;
            prev = x;
            x = next;
        }
        if (x != Value.nil) return properListError(th, seq);
        return prev;
    }
    if (isVector(seq)) {
        std.mem.reverse(Value, Runtime.vectorPtr(seq).items());
        return seq;
    }
    if (isString(seq)) {
        const s = Runtime.stringPtr(seq);
        const n = s.length();
        var i: usize = 0;
        while (i < n / 2) : (i += 1) {
            const a = s.charAt(i);
            const b = s.charAt(n - 1 - i);
            th.rt.stringSetChar(seq, i, b) catch return th.outOfMemory();
            th.rt.stringSetChar(seq, n - 1 - i, a) catch return th.outOfMemory();
        }
        return seq;
    }
    return th.typeError(seq, cl(th, "SEQUENCE"));
}

/// (copy-list リスト)：最上位の cons を写す（ドット対の終わりもそのまま）
pub fn copyList(th: *Thread, args: []const Value) Value {
    const list = args[0];
    if (!list.isList()) return properListError(th, list);
    if (list == Value.nil) return Value.nil;
    const head = th.rt.cons(Runtime.consPtr(list).car, Value.nil) catch return th.outOfMemory();
    var tail = head;
    var x = Runtime.consPtr(list).cdr;
    while (x.isCons()) : (x = Runtime.consPtr(x).cdr) {
        const c = th.rt.cons(Runtime.consPtr(x).car, Value.nil) catch return th.outOfMemory();
        Runtime.consPtr(tail).cdr = c;
        tail = c;
    }
    Runtime.consPtr(tail).cdr = x;
    return head;
}

/// (last リスト &optional (n 1))：最後の n 個の cons
pub fn last(th: *Thread, args: []const Value) Value {
    const list = args[0];
    if (!list.isList()) return properListError(th, list);
    var n: usize = 1;
    if (args.len > 1) {
        const c = args[1];
        // 正の bignum はリストより長い個数として扱う（Codex のレビュー P20 #12）
        if (c.isOther() and Runtime.kindOf(c) == .bignum and Runtime.bignumPtr(c).positive()) {
            n = std.math.maxInt(usize);
        } else {
            if (!c.isFixnum() or c.asFixnum() < 0) return th.typeError(c, cl(th, "UNSIGNED-BYTE"));
            n = @intCast(c.asFixnum());
        }
    }
    var len: usize = 0;
    var x = list;
    while (x.isCons()) : (x = Runtime.consPtr(x).cdr) len += 1;
    var skip = if (len > n) len - n else 0;
    x = list;
    while (skip > 0) : (skip -= 1) x = Runtime.consPtr(x).cdr;
    return x;
}

/// (endp リスト)
pub fn endp(th: *Thread, args: []const Value) Value {
    const x = args[0];
    if (x == Value.nil) return th.rt.t;
    if (x.isCons()) return Value.nil;
    return properListError(th, x);
}

/// (symbol-name シンボル)
pub fn symbolName(th: *Thread, args: []const Value) Value {
    const s = args[0];
    if (!isSymbol(s)) return th.typeError(s, th.rt.syms.symbol);
    if (s == Value.nil) return th.rt.nil_symbol.name;
    return th.rt.symbolPtr(s).name;
}

/// 文字列指定子（文字列・シンボル・文字）を文字列にする。文字なら1文字の文字列を作る
fn stringDesignator(th: *Thread, v: Value) Value {
    if (isString(v)) return v;
    if (isSymbol(v)) return if (v == Value.nil) th.rt.nil_symbol.name else th.rt.symbolPtr(v).name;
    if (v.isChar()) return th.rt.makeStringFilled(1, v.asChar()) catch th.outOfMemory();
    return th.typeError(v, cl(th, "STRING"));
}

/// :start・:end を [start, end) にする（end が NIL なら長さ）。範囲が正しくなければ null（エラーを記録済み）
fn bounds(th: *Thread, start: ?Value, end: ?Value, len: usize) ?[2]usize {
    var s: usize = 0;
    var e: usize = len;
    if (start) |v| {
        if (!v.isFixnum() or v.asFixnum() < 0) {
            _ = th.typeError(v, cl(th, "UNSIGNED-BYTE"));
            return null;
        }
        s = @intCast(v.asFixnum());
    }
    if (end) |v| if (v != Value.nil) {
        if (!v.isFixnum() or v.asFixnum() < 0) {
            _ = th.typeError(v, cl(th, "UNSIGNED-BYTE"));
            return null;
        }
        e = @intCast(v.asFixnum());
    };
    if (s > e or e > len) {
        _ = th.signal(.program_error, "列の範囲（:start・:end）が正しくありません", Value.fromFixnum(@intCast(s)), Value.unbound);
        return null;
    }
    return .{ s, e };
}

/// (string= a b &key start1 end1 start2 end2)
pub fn stringEq(th: *Thread, args: []const Value) Value {
    var kv: [4]?Value = undefined;
    if (!keyargs.parse(th, args[2..], &.{ "START1", "END1", "START2", "END2" }, &kv)) return Value.unwind;
    const a = stringDesignator(th, args[0]);
    if (a == Value.unwind) return a;
    const b = stringDesignator(th, args[1]);
    if (b == Value.unwind) return b;
    const sa = Runtime.stringPtr(a);
    const sb = Runtime.stringPtr(b);
    const ra = bounds(th, kv[0], kv[1], sa.length()) orelse return Value.unwind;
    const rb = bounds(th, kv[2], kv[3], sb.length()) orelse return Value.unwind;
    if (ra[1] - ra[0] != rb[1] - rb[0]) return Value.nil;
    for (0..ra[1] - ra[0]) |i| {
        if (sa.charAt(ra[0] + i) != sb.charAt(rb[0] + i)) return Value.nil;
    }
    return th.rt.t;
}

fn convertCase(th: *Thread, args: []const Value, comptime upper: bool) Value {
    var kv: [2]?Value = undefined;
    if (!keyargs.parse(th, args[1..], &.{ "START", "END" }, &kv)) return Value.unwind;
    const src = stringDesignator(th, args[0]);
    if (src == Value.unwind) return src;
    const n = Runtime.stringPtr(src).length();
    const r = bounds(th, kv[0], kv[1], n) orelse return Value.unwind;
    const out = th.rt.makeStringFilled(n, ' ') catch return th.outOfMemory();
    for (0..n) |i| {
        var cp = Runtime.stringPtr(src).charAt(i);
        if (i >= r[0] and i < r[1] and cp < 0x80) {
            const c: u8 = @intCast(cp);
            cp = if (upper) std.ascii.toUpper(c) else std.ascii.toLower(c);
        }
        th.rt.stringSetChar(out, i, cp) catch return th.outOfMemory();
    }
    return out;
}

pub fn stringUpcase(th: *Thread, args: []const Value) Value {
    return convertCase(th, args, true);
}

pub fn stringDowncase(th: *Thread, args: []const Value) Value {
    return convertCase(th, args, false);
}

/// (char= 文字 ...)（Phase 19）
pub fn charEq(th: *Thread, args: []const Value) Value {
    for (args) |a| if (!a.isChar()) return th.typeError(a, cl(th, "CHARACTER"));
    for (args[1..]) |a| if (a.asChar() != args[0].asChar()) return Value.nil;
    return th.rt.t;
}
