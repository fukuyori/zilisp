//! 列の関数のうち Zig で書くもの（Phase 19・21）：reverse・nreverse・copy-list・last・endp・symbol-name、
//! elt・subseq・make-list・vector-pop・fill・replace・concatenate・coerce の一部（Phase 21）。
//! :test・:key を取る列の関数（find・position・remove など）は boot.lisp に書く。
//! 文字・文字列の関数は strings.zig。

const std = @import("std");
const Value = @import("../values/value.zig").Value;
const Thread = @import("../runtime/thread.zig").Thread;
const Runtime = @import("../runtime/runtime.zig").Runtime;
const keyargs = @import("keyargs.zig");
const arrays = @import("arrays.zig");

fn isSymbol(v: Value) bool {
    return v == Value.nil or (v.isOther() and Runtime.kindOf(v) == .symbol);
}

fn cl(th: *Thread, name: []const u8) Value {
    return (th.rt.findSymbol(th.rt.cl, name) orelse unreachable).symbol;
}

fn properListError(th: *Thread, v: Value) Value {
    return th.typeError(v, th.rt.syms.list);
}

/// (reverse 列)：新しい列を返す（ベクタは有効な部分を、単純なベクタ・文字列に逆順に写す）
pub fn reverse(th: *Thread, args: []const Value) Value {
    const seq = args[0];
    if (seq.isList()) {
        var out = Value.nil;
        var x = seq;
        while (x.isCons()) : (x = Runtime.consPtr(x).cdr) out = th.rt.cons(Runtime.consPtr(x).car, out) catch return th.outOfMemory();
        if (x != Value.nil) return properListError(th, seq);
        return out;
    }
    const view = arrays.vectorView(seq) orelse return th.typeError(seq, cl(th, "SEQUENCE"));
    const out = arrays.makeLike(th, view.data, view.len);
    if (out == Value.unwind) return out;
    const src = arrays.dataOf(seq);
    for (0..view.len) |i| if (arrays.storageSet(th, out, i, arrays.storageGet(src, view.len - 1 - i)) == Value.unwind) return Value.unwind;
    return out;
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
    const view = arrays.vectorView(seq) orelse return th.typeError(seq, cl(th, "SEQUENCE"));
    if (arrays.isSimpleVector(view.data)) {
        std.mem.reverse(Value, Runtime.vectorPtr(view.data).items()[0..view.len]);
        return seq;
    }
    const n = view.len;
    var i: usize = 0;
    while (i < n / 2) : (i += 1) {
        const a = arrays.storageGet(view.data, i);
        const b = arrays.storageGet(view.data, n - 1 - i);
        if (arrays.storageSet(th, view.data, i, b) == Value.unwind) return Value.unwind;
        if (arrays.storageSet(th, view.data, n - 1 - i, a) == Value.unwind) return Value.unwind;
    }
    return seq;
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
