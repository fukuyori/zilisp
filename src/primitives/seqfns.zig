//! 列の関数（Phase 21。CLHS 14 章・17 章）。:test・:test-not・:key を取る関数と、列を作る関数。
//!
//! リスト：member・member-if・member-if-not、assoc・assoc-if・assoc-if-not、rassoc・rassoc-if・rassoc-if-not
//! 列：find・position・count（-if・-if-not も）、remove・delete（-if・-if-not も）、substitute・nsubstitute（-if・-if-not も）、
//!   remove-duplicates・delete-duplicates、sort・stable-sort、search・mismatch、elt・subseq・fill・replace、
//!   concatenate・coerce・make-sequence・map・map-into・some・every・notany・notevery、make-list・list-length・vector-pop
//!
//! 列は、リストと1次元の配列（fill-pointer があれば有効な部分）。新しく作るベクタは単純なベクタか文字列（元と同じ要素の型）。
//! delete・delete-if などは、新しい列を返す（元の列を壊してよいが、壊さなくてもよい：CLHS 17.2）。
//! :test・:key の関数は、要素の順に呼ぶ（:from-end でも前から。呼ぶ順序は CLHS で決まっていない）。
//!
//! GC：要素を Zig の配列（gpa）に一時的に並べることがあるが、要素は元の列から届くので回収されない（非移動型の GC）。

const std = @import("std");
const Value = @import("../values/value.zig").Value;
const Thread = @import("../runtime/thread.zig").Thread;
const Runtime = @import("../runtime/runtime.zig").Runtime;
const keyargs = @import("keyargs.zig");
const arrays = @import("arrays.zig");
const lists = @import("lists.zig");
const numbers = @import("numbers.zig");

fn cl(th: *Thread, name: []const u8) Value {
    return (th.rt.findSymbol(th.rt.cl, name) orelse unreachable).symbol;
}

const Unwind = error{Unwind};

fn oom(th: *Thread) Unwind {
    _ = th.outOfMemory();
    return error.Unwind;
}

fn check(v: Value) Unwind!Value {
    if (v == Value.unwind) return error.Unwind;
    return v;
}

/// 呼び出しの結果を1つの値にして返す（:test などの関数の呼び出しが多値を残すことがある）
fn single(th: *Thread, v: Value) Value {
    if (v != Value.unwind) th.mv_count = 1;
    return v;
}

// ---------------------------------------------------------------------------
// 比較（:test・:test-not・:key と、-if・-if-not の述語）

const Fast = enum { call, eq, eql, equal };

const Matcher = struct {
    th: *Thread,
    /// item と比べる（:test）か、述語を呼ぶ（-if）か
    with_item: bool,
    item: Value = Value.nil,
    /// :test・:test-not・述語
    f: Value = Value.nil,
    fast: Fast = .eql,
    negate: bool = false,
    key: Value = Value.nil,

    fn keyOf(m: *const Matcher, x: Value) Unwind!Value {
        if (m.key == Value.nil) return x;
        return check(m.th.call(m.key, &.{x}));
    }

    /// 2つの値（item と、要素の key）を比べる
    fn compare(m: *const Matcher, a: Value, b: Value) Unwind!bool {
        const r = switch (m.fast) {
            .eq => a == b,
            .eql => lists.eql2(a, b),
            .equal => lists.equal2(a, b),
            .call => (try check(m.th.call(m.f, &.{ a, b }))) != Value.nil,
        };
        return r != m.negate;
    }

    fn matches(m: *const Matcher, elem: Value) Unwind!bool {
        const k = try m.keyOf(elem);
        if (m.with_item) return m.compare(m.item, k);
        const r = (try check(m.th.call(m.f, &.{k}))) != Value.nil;
        return r != m.negate;
    }
};

/// :test・:test-not から比較を決める（よく使う eq・eql・equal は関数を呼ばずに比べる）
fn testMatcher(th: *Thread, item: Value, test_: ?Value, test_not: ?Value, key: ?Value) Unwind!Matcher {
    var m: Matcher = .{ .th = th, .with_item = true, .item = item, .key = key orelse Value.nil };
    if (test_ != null and test_not != null) {
        _ = th.signal(.program_error, ":test と :test-not は同時に指定できません", Value.unbound, Value.unbound);
        return error.Unwind;
    }
    if (test_not) |t| {
        m.negate = true;
        m.f = t;
        m.fast = fastOf(th, t);
    } else if (test_) |t| {
        m.f = t;
        m.fast = fastOf(th, t);
    }
    return m;
}

fn fastOf(th: *Thread, f: Value) Fast {
    const rt = th.rt;
    const names = [_]struct { []const u8, Fast }{ .{ "EQ", .eq }, .{ "EQL", .eql }, .{ "EQUAL", .equal } };
    for (names) |n| {
        const sym = cl(th, n[0]);
        if (f == sym or f == rt.symbolPtr(sym).function) return n[1];
    }
    return .call;
}

fn predMatcher(th: *Thread, pred: Value, negate: bool, key: ?Value) Matcher {
    return .{ .th = th, .with_item = false, .f = pred, .negate = negate, .key = key orelse Value.nil, .fast = .call };
}

// ---------------------------------------------------------------------------
// 列の見方

const Seq = union(enum) {
    list: Value,
    vector: arrays.VectorView,
};

fn seqOf(th: *Thread, v: Value) Unwind!Seq {
    if (v.isList()) return .{ .list = v };
    if (arrays.vectorView(v)) |view| return .{ .vector = view };
    _ = th.typeError(v, cl(th, "SEQUENCE"));
    return error.Unwind;
}

fn listLength(th: *Thread, l: Value) Unwind!usize {
    var n: usize = 0;
    var x = l;
    while (x.isCons()) : (x = Runtime.consPtr(x).cdr) n += 1;
    if (x != Value.nil) {
        _ = th.typeError(l, th.rt.syms.list);
        return error.Unwind;
    }
    return n;
}

fn seqLen(th: *Thread, s: Seq) Unwind!usize {
    return switch (s) {
        .list => |l| listLength(th, l),
        .vector => |v| v.len,
    };
}

/// :start・:end
fn range(th: *Thread, start: ?Value, end: ?Value, len: usize) Unwind![2]usize {
    var s: usize = 0;
    var e: usize = len;
    if (start) |v| {
        if (!v.isFixnum() or v.asFixnum() < 0) {
            _ = th.typeError(v, cl(th, "UNSIGNED-BYTE"));
            return error.Unwind;
        }
        s = @intCast(v.asFixnum());
    }
    if (end) |v| if (v != Value.nil) {
        if (!v.isFixnum() or v.asFixnum() < 0) {
            _ = th.typeError(v, cl(th, "UNSIGNED-BYTE"));
            return error.Unwind;
        }
        e = @intCast(v.asFixnum());
    };
    // 範囲の誤りは type-error（SBCL 2.6.7 の bounding-indices-bad-error は type-error の一種）
    if (e > len) {
        _ = indexError(th, Value.fromFixnum(@intCast(e)), len + 1);
        return error.Unwind;
    }
    if (s > e) {
        _ = indexError(th, Value.fromFixnum(@intCast(s)), e + 1);
        return error.Unwind;
    }
    return .{ s, e };
}

/// 列の要素を、Zig の配列に並べる（リストは cons を順にたどる）
fn collect(th: *Thread, s: Seq, out: *std.ArrayList(Value)) Unwind!void {
    const gpa = th.rt.gpa;
    switch (s) {
        .list => |l| {
            var x = l;
            while (x.isCons()) : (x = Runtime.consPtr(x).cdr) out.append(gpa, Runtime.consPtr(x).car) catch return oom(th);
            if (x != Value.nil) {
                _ = th.typeError(l, th.rt.syms.list);
                return error.Unwind;
            }
        },
        .vector => |v| {
            out.ensureTotalCapacity(gpa, v.len) catch return oom(th);
            for (0..v.len) |i| out.appendAssumeCapacity(arrays.storageGet(v.data, i));
        },
    }
}

fn isTrue(v: ?Value) bool {
    return v != null and v.? != Value.nil;
}

/// 要素の並びから、元の列と同じ種類の列を作る（リストか、元と同じ要素の型の単純なベクタ・文字列）
fn buildLike(th: *Thread, like: Value, items: []const Value) Unwind!Value {
    if (like.isList()) return buildList(th, items, Value.nil);
    const view = arrays.vectorView(like).?;
    return buildVector(th, arrays.isSimpleString(view.data), items);
}

fn buildList(th: *Thread, items: []const Value, tail: Value) Unwind!Value {
    var out = tail;
    var i = items.len;
    while (i > 0) : (i -= 1) out = th.rt.cons(items[i - 1], out) catch return oom(th);
    return out;
}

fn buildVector(th: *Thread, chars: bool, items: []const Value) Unwind!Value {
    if (chars) {
        const s = th.rt.makeStringFilled(items.len, 0) catch return oom(th);
        for (items, 0..) |x, i| {
            if (!x.isChar()) {
                _ = th.typeError(x, cl(th, "CHARACTER"));
                return error.Unwind;
            }
            th.rt.stringSetChar(s, i, x.asChar()) catch return oom(th);
        }
        return s;
    }
    return th.rt.makeVector(items) catch oom(th);
}

// ---------------------------------------------------------------------------
// member・assoc・rassoc

fn memberImpl(th: *Thread, m: *const Matcher, list: Value) Unwind!Value {
    var x = list;
    while (x.isCons()) : (x = Runtime.consPtr(x).cdr) {
        if (try m.matches(Runtime.consPtr(x).car)) return x;
    }
    if (x != Value.nil) {
        _ = th.typeError(list, th.rt.syms.list);
        return error.Unwind;
    }
    return Value.nil;
}

pub fn member(th: *Thread, args: []const Value) Value {
    var kv: [3]?Value = undefined;
    if (!keyargs.parse(th, args[2..], &.{ "KEY", "TEST", "TEST-NOT" }, &kv)) return Value.unwind;
    // よく使う形（キーなし・eql）は関数を作らずにたどる
    if (kv[0] == null and kv[1] == null and kv[2] == null) {
        var x = args[1];
        while (x.isCons()) : (x = Runtime.consPtr(x).cdr) if (lists.eql2(args[0], Runtime.consPtr(x).car)) return x;
        if (x != Value.nil) return th.typeError(args[1], th.rt.syms.list);
        return Value.nil;
    }
    const m = testMatcher(th, args[0], kv[1], kv[2], kv[0]) catch return Value.unwind;
    return single(th, memberImpl(th, &m, args[1]) catch return Value.unwind);
}

fn memberIfImpl(th: *Thread, args: []const Value, negate: bool) Value {
    var kv: [1]?Value = undefined;
    if (!keyargs.parse(th, args[2..], &.{"KEY"}, &kv)) return Value.unwind;
    const m = predMatcher(th, args[0], negate, kv[0]);
    return single(th, memberImpl(th, &m, args[1]) catch return Value.unwind);
}

pub fn memberIf(th: *Thread, args: []const Value) Value {
    return memberIfImpl(th, args, false);
}
pub fn memberIfNot(th: *Thread, args: []const Value) Value {
    return memberIfImpl(th, args, true);
}

fn assocImpl(th: *Thread, m: *const Matcher, alist: Value, comptime use_cdr: bool) Unwind!Value {
    var x = alist;
    while (x.isCons()) : (x = Runtime.consPtr(x).cdr) {
        const pair = Runtime.consPtr(x).car;
        if (pair == Value.nil) continue;
        if (!pair.isCons()) {
            _ = th.typeError(pair, th.rt.syms.list);
            return error.Unwind;
        }
        const part = if (use_cdr) Runtime.consPtr(pair).cdr else Runtime.consPtr(pair).car;
        if (try m.matches(part)) return pair;
    }
    if (x != Value.nil) {
        _ = th.typeError(alist, th.rt.syms.list);
        return error.Unwind;
    }
    return Value.nil;
}

fn assocTest(th: *Thread, args: []const Value, comptime use_cdr: bool) Value {
    var kv: [3]?Value = undefined;
    if (!keyargs.parse(th, args[2..], &.{ "KEY", "TEST", "TEST-NOT" }, &kv)) return Value.unwind;
    const m = testMatcher(th, args[0], kv[1], kv[2], kv[0]) catch return Value.unwind;
    return single(th, assocImpl(th, &m, args[1], use_cdr) catch return Value.unwind);
}

fn assocPred(th: *Thread, args: []const Value, negate: bool, comptime use_cdr: bool) Value {
    var kv: [1]?Value = undefined;
    if (!keyargs.parse(th, args[2..], &.{"KEY"}, &kv)) return Value.unwind;
    const m = predMatcher(th, args[0], negate, kv[0]);
    return single(th, assocImpl(th, &m, args[1], use_cdr) catch return Value.unwind);
}

pub fn assoc(th: *Thread, args: []const Value) Value {
    return assocTest(th, args, false);
}
pub fn assocIf(th: *Thread, args: []const Value) Value {
    return assocPred(th, args, false, false);
}
pub fn assocIfNot(th: *Thread, args: []const Value) Value {
    return assocPred(th, args, true, false);
}
pub fn rassoc(th: *Thread, args: []const Value) Value {
    return assocTest(th, args, true);
}
pub fn rassocIf(th: *Thread, args: []const Value) Value {
    return assocPred(th, args, false, true);
}
pub fn rassocIfNot(th: *Thread, args: []const Value) Value {
    return assocPred(th, args, true, true);
}

// ---------------------------------------------------------------------------
// find・position・count

const ScanOp = enum { find, position, count };

/// 列の [start, end) を調べる。find は要素、position は添字、count は数を返す
fn scan(th: *Thread, m: *const Matcher, seq_v: Value, start: ?Value, end: ?Value, from_end: bool, comptime op: ScanOp) Unwind!Value {
    const s = try seqOf(th, seq_v);
    var found: ?usize = null;
    var found_elem = Value.nil;
    var n: usize = 0;
    switch (s) {
        .list => |l| {
            const need_len = start != null or (end != null and end.? != Value.nil);
            const len = if (need_len) try listLength(th, l) else std.math.maxInt(usize);
            const r = if (need_len) try range(th, start, end, len) else [2]usize{ 0, len };
            var x = l;
            var i: usize = 0;
            while (x.isCons() and i < r[1]) : ({
                x = Runtime.consPtr(x).cdr;
                i += 1;
            }) {
                if (i < r[0]) continue;
                const e = Runtime.consPtr(x).car;
                if (try m.matches(e)) {
                    n += 1;
                    if (op != .count) {
                        found = i;
                        found_elem = e;
                        if (!from_end) break;
                    }
                }
            }
            if (!need_len and !x.isCons() and x != Value.nil) {
                _ = th.typeError(l, th.rt.syms.list);
                return error.Unwind;
            }
        },
        .vector => |v| {
            const r = try range(th, start, end, v.len);
            if (from_end and op != .count) {
                var i = r[1];
                while (i > r[0]) {
                    i -= 1;
                    const e = arrays.storageGet(v.data, i);
                    if (try m.matches(e)) {
                        found = i;
                        found_elem = e;
                        break;
                    }
                }
            } else {
                for (r[0]..r[1]) |i| {
                    const e = arrays.storageGet(v.data, i);
                    if (try m.matches(e)) {
                        n += 1;
                        if (op != .count) {
                            found = i;
                            found_elem = e;
                            break;
                        }
                    }
                }
            }
        },
    }
    return switch (op) {
        .find => if (found != null) found_elem else Value.nil,
        .position => if (found) |i| Value.fromFixnum(@intCast(i)) else Value.nil,
        .count => Value.fromFixnum(@intCast(n)),
    };
}

fn scanTest(comptime op: ScanOp) fn (*Thread, []const Value) Value {
    return struct {
        fn f(th: *Thread, args: []const Value) Value {
            var kv: [6]?Value = undefined;
            if (!keyargs.parse(th, args[2..], &.{ "FROM-END", "TEST", "TEST-NOT", "START", "END", "KEY" }, &kv)) return Value.unwind;
            const m = testMatcher(th, args[0], kv[1], kv[2], kv[5]) catch return Value.unwind;
            return single(th, scan(th, &m, args[1], kv[3], kv[4], isTrue(kv[0]), op) catch return Value.unwind);
        }
    }.f;
}

fn scanPred(comptime op: ScanOp, comptime negate: bool) fn (*Thread, []const Value) Value {
    return struct {
        fn f(th: *Thread, args: []const Value) Value {
            var kv: [4]?Value = undefined;
            if (!keyargs.parse(th, args[2..], &.{ "FROM-END", "START", "END", "KEY" }, &kv)) return Value.unwind;
            const m = predMatcher(th, args[0], negate, kv[3]);
            return single(th, scan(th, &m, args[1], kv[1], kv[2], isTrue(kv[0]), op) catch return Value.unwind);
        }
    }.f;
}

pub const find = scanTest(.find);
pub const findIf = scanPred(.find, false);
pub const findIfNot = scanPred(.find, true);
pub const position = scanTest(.position);
pub const positionIf = scanPred(.position, false);
pub const positionIfNot = scanPred(.position, true);
pub const count = scanTest(.count);
pub const countIf = scanPred(.count, false);
pub const countIfNot = scanPred(.count, true);

// ---------------------------------------------------------------------------
// remove・substitute

/// :count（NIL なら上限なし。負の数は 0）
fn countArg(th: *Thread, v: ?Value) Unwind!usize {
    const c = v orelse return std.math.maxInt(usize);
    if (c == Value.nil) return std.math.maxInt(usize);
    if (c.isFixnum()) return if (c.asFixnum() < 0) 0 else @intCast(c.asFixnum());
    if (c.isOther() and Runtime.kindOf(c) == .bignum) return if (Runtime.bignumPtr(c).positive()) std.math.maxInt(usize) else 0;
    _ = th.typeError(c, th.rt.syms.integer);
    return error.Unwind;
}

/// 対象の要素の印を付ける：[start, end) で一致した要素のうち、:count 個（:from-end なら後ろから）
fn markMatches(m: *const Matcher, items: []const Value, r: [2]usize, limit: usize, from_end: bool, marks: []bool) Unwind!void {
    @memset(marks, false);
    var total: usize = 0;
    for (r[0]..r[1]) |i| {
        if (try m.matches(items[i])) {
            marks[i] = true;
            total += 1;
        }
    }
    if (total <= limit) return;
    // 数を超えた分の印を外す（:from-end なら前から、そうでなければ後ろから）
    var extra = total - limit;
    if (from_end) {
        var i = r[0];
        while (extra > 0 and i < r[1]) : (i += 1) if (marks[i]) {
            marks[i] = false;
            extra -= 1;
        };
    } else {
        var i = r[1];
        while (extra > 0 and i > r[0]) {
            i -= 1;
            if (marks[i]) {
                marks[i] = false;
                extra -= 1;
            }
        }
    }
}

const EditOp = enum { remove, substitute, nsubstitute };

/// remove・substitute・nsubstitute の本体。new_item は substitute の新しい要素
fn editSeq(th: *Thread, m: *const Matcher, seq_v: Value, kv_start: ?Value, kv_end: ?Value, kv_count: ?Value, from_end: bool, new_item: Value, comptime op: EditOp) Unwind!Value {
    const gpa = th.rt.gpa;
    const s = try seqOf(th, seq_v);
    var items: std.ArrayList(Value) = .empty;
    defer items.deinit(gpa);
    try collect(th, s, &items);
    const r = try range(th, kv_start, kv_end, items.items.len);
    const limit = try countArg(th, kv_count);
    const marks = gpa.alloc(bool, items.items.len) catch return oom(th);
    defer gpa.free(marks);
    try markMatches(m, items.items, r, limit, from_end, marks);
    switch (op) {
        .remove => {
            // 最後に除く要素より後ろは、リストなら元のリストを共有する
            var last: ?usize = null;
            for (marks, 0..) |mk, i| if (mk) {
                last = i;
            };
            const cut = last orelse return seq_v; // 除く要素がなければ元の列（CLHS remove：共有してよい）
            var kept: std.ArrayList(Value) = .empty;
            defer kept.deinit(gpa);
            if (seq_v.isList()) {
                for (items.items[0 .. cut + 1], 0..) |x, i| if (!marks[i]) kept.append(gpa, x) catch return oom(th);
                var tail = seq_v;
                for (0..cut + 1) |_| tail = Runtime.consPtr(tail).cdr;
                return buildList(th, kept.items, tail);
            }
            for (items.items, 0..) |x, i| if (!marks[i]) kept.append(gpa, x) catch return oom(th);
            return buildLike(th, seq_v, kept.items);
        },
        .substitute => {
            for (marks, 0..) |mk, i| if (mk) {
                items.items[i] = new_item;
            };
            return buildLike(th, seq_v, items.items);
        },
        .nsubstitute => {
            switch (s) {
                .list => |l| {
                    var x = l;
                    var i: usize = 0;
                    while (x.isCons()) : ({
                        x = Runtime.consPtr(x).cdr;
                        i += 1;
                    }) if (marks[i]) {
                        Runtime.consPtr(x).car = new_item;
                    };
                },
                .vector => |v| for (marks, 0..) |mk, i| if (mk) {
                    _ = try check(arrays.storageSet(th, v.data, i, new_item));
                },
            }
            return seq_v;
        },
    }
}

fn removeTest(th: *Thread, args: []const Value) Value {
    var kv: [7]?Value = undefined;
    if (!keyargs.parse(th, args[2..], &.{ "FROM-END", "TEST", "TEST-NOT", "START", "END", "COUNT", "KEY" }, &kv)) return Value.unwind;
    const m = testMatcher(th, args[0], kv[1], kv[2], kv[6]) catch return Value.unwind;
    return single(th, editSeq(th, &m, args[1], kv[3], kv[4], kv[5], isTrue(kv[0]), Value.nil, .remove) catch return Value.unwind);
}

fn removePred(comptime negate: bool) fn (*Thread, []const Value) Value {
    return struct {
        fn f(th: *Thread, args: []const Value) Value {
            var kv: [5]?Value = undefined;
            if (!keyargs.parse(th, args[2..], &.{ "FROM-END", "START", "END", "COUNT", "KEY" }, &kv)) return Value.unwind;
            const m = predMatcher(th, args[0], negate, kv[4]);
            return single(th, editSeq(th, &m, args[1], kv[1], kv[2], kv[3], isTrue(kv[0]), Value.nil, .remove) catch return Value.unwind);
        }
    }.f;
}

pub const remove = removeTest;
pub const removeIf = removePred(false);
pub const removeIfNot = removePred(true);

fn substTest(comptime op: EditOp) fn (*Thread, []const Value) Value {
    return struct {
        fn f(th: *Thread, args: []const Value) Value {
            var kv: [7]?Value = undefined;
            if (!keyargs.parse(th, args[3..], &.{ "FROM-END", "TEST", "TEST-NOT", "START", "END", "COUNT", "KEY" }, &kv)) return Value.unwind;
            const m = testMatcher(th, args[1], kv[1], kv[2], kv[6]) catch return Value.unwind;
            return single(th, editSeq(th, &m, args[2], kv[3], kv[4], kv[5], isTrue(kv[0]), args[0], op) catch return Value.unwind);
        }
    }.f;
}

fn substPred(comptime op: EditOp, comptime negate: bool) fn (*Thread, []const Value) Value {
    return struct {
        fn f(th: *Thread, args: []const Value) Value {
            var kv: [5]?Value = undefined;
            if (!keyargs.parse(th, args[3..], &.{ "FROM-END", "START", "END", "COUNT", "KEY" }, &kv)) return Value.unwind;
            const m = predMatcher(th, args[1], negate, kv[4]);
            return single(th, editSeq(th, &m, args[2], kv[1], kv[2], kv[3], isTrue(kv[0]), args[0], op) catch return Value.unwind);
        }
    }.f;
}

pub const substitute = substTest(.substitute);
pub const substituteIf = substPred(.substitute, false);
pub const substituteIfNot = substPred(.substitute, true);
pub const nsubstitute = substTest(.nsubstitute);
pub const nsubstituteIf = substPred(.nsubstitute, false);
pub const nsubstituteIfNot = substPred(.nsubstitute, true);

/// (remove-duplicates 列 &key from-end test test-not start end key)：重複した要素の、:from-end なら後ろの方を、
/// そうでなければ前の方を除く（CLHS remove-duplicates）
pub fn removeDuplicates(th: *Thread, args: []const Value) Value {
    var kv: [6]?Value = undefined;
    if (!keyargs.parse(th, args[1..], &.{ "FROM-END", "TEST", "TEST-NOT", "START", "END", "KEY" }, &kv)) return Value.unwind;
    return single(th, removeDuplicatesImpl(th, args[0], kv) catch return Value.unwind);
}

fn removeDuplicatesImpl(th: *Thread, seq_v: Value, kv: [6]?Value) Unwind!Value {
    const gpa = th.rt.gpa;
    const m = try testMatcher(th, Value.nil, kv[1], kv[2], kv[5]);
    const from_end = isTrue(kv[0]);
    var items: std.ArrayList(Value) = .empty;
    defer items.deinit(gpa);
    try collect(th, try seqOf(th, seq_v), &items);
    const r = try range(th, kv[3], kv[4], items.items.len);
    const marks = gpa.alloc(bool, items.items.len) catch return oom(th);
    defer gpa.free(marks);
    @memset(marks, false);
    var any = false;
    for (r[0]..r[1]) |i| {
        const ki = try m.keyOf(items.items[i]);
        if (from_end) {
            // 前に同じものがあれば除く
            for (r[0]..i) |j| {
                if (marks[j]) continue;
                if (try m.compare(try m.keyOf(items.items[j]), ki)) {
                    marks[i] = true;
                    any = true;
                    break;
                }
            }
        } else {
            // 後ろに同じものがあれば除く
            for (i + 1..r[1]) |j| {
                if (try m.compare(ki, try m.keyOf(items.items[j]))) {
                    marks[i] = true;
                    any = true;
                    break;
                }
            }
        }
    }
    if (!any) return seq_v;
    var kept: std.ArrayList(Value) = .empty;
    defer kept.deinit(gpa);
    for (items.items, 0..) |x, i| if (!marks[i]) kept.append(gpa, x) catch return oom(th);
    return buildLike(th, seq_v, kept.items);
}

// ---------------------------------------------------------------------------
// sort・stable-sort（安定なマージソート。リストは cons の car を並べ替え、ベクタはその場で並べ替える）

const Sorter = struct {
    th: *Thread,
    pred: Value,
    key: Value,

    fn less(s: *const Sorter, a: Value, b: Value) Unwind!bool {
        var ka = a;
        var kb = b;
        if (s.key != Value.nil) {
            ka = try check(s.th.call(s.key, &.{a}));
            kb = try check(s.th.call(s.key, &.{b}));
        }
        return (try check(s.th.call(s.pred, &.{ ka, kb }))) != Value.nil;
    }

    fn sort(s: *const Sorter, items: []Value, tmp: []Value) Unwind!void {
        if (items.len < 2) return;
        if (items.len <= 8) {
            // 挿入ソート（安定）
            var i: usize = 1;
            while (i < items.len) : (i += 1) {
                const x = items[i];
                var j = i;
                while (j > 0 and try s.less(x, items[j - 1])) : (j -= 1) items[j] = items[j - 1];
                items[j] = x;
            }
            return;
        }
        const mid = items.len / 2;
        try s.sort(items[0..mid], tmp[0..mid]);
        try s.sort(items[mid..], tmp[mid..]);
        @memcpy(tmp[0..items.len], items);
        var i: usize = 0;
        var j: usize = mid;
        var k: usize = 0;
        while (i < mid and j < items.len) : (k += 1) {
            // 右が真に小さいときだけ右を取る（安定）
            if (try s.less(tmp[j], tmp[i])) {
                items[k] = tmp[j];
                j += 1;
            } else {
                items[k] = tmp[i];
                i += 1;
            }
        }
        while (i < mid) : (i += 1) {
            items[k] = tmp[i];
            k += 1;
        }
        while (j < items.len) : (j += 1) {
            items[k] = tmp[j];
            k += 1;
        }
    }
};

pub fn sort(th: *Thread, args: []const Value) Value {
    var kv: [1]?Value = undefined;
    if (!keyargs.parse(th, args[2..], &.{"KEY"}, &kv)) return Value.unwind;
    return single(th, sortImpl(th, args[0], args[1], kv[0] orelse Value.nil) catch return Value.unwind);
}

fn sortImpl(th: *Thread, seq_v: Value, pred: Value, key: Value) Unwind!Value {
    const gpa = th.rt.gpa;
    const s = try seqOf(th, seq_v);
    var items: std.ArrayList(Value) = .empty;
    defer items.deinit(gpa);
    try collect(th, s, &items);
    // 並べ替えの途中で GC が起きても、要素は元の列から届く（書き戻すのは並べ終えてから）
    const tmp = gpa.alloc(Value, items.items.len) catch return oom(th);
    defer gpa.free(tmp);
    const sorter: Sorter = .{ .th = th, .pred = pred, .key = key };
    try sorter.sort(items.items, tmp);
    switch (s) {
        .list => |l| {
            var x = l;
            for (items.items) |v| {
                Runtime.consPtr(x).car = v;
                x = Runtime.consPtr(x).cdr;
            }
        },
        .vector => |v| for (items.items, 0..) |e, i| {
            _ = try check(arrays.storageSet(th, v.data, i, e));
        },
    }
    return seq_v;
}

// ---------------------------------------------------------------------------
// search・mismatch

const TwoSeq = struct { a: []Value, b: []Value, ra: [2]usize, rb: [2]usize };

pub fn search(th: *Thread, args: []const Value) Value {
    var kv: [8]?Value = undefined;
    if (!keyargs.parse(th, args[2..], &.{ "FROM-END", "TEST", "TEST-NOT", "KEY", "START1", "END1", "START2", "END2" }, &kv)) return Value.unwind;
    return single(th, searchImpl(th, args, kv) catch return Value.unwind);
}

fn searchImpl(th: *Thread, args: []const Value, kv: [8]?Value) Unwind!Value {
    const gpa = th.rt.gpa;
    const m = try testMatcher(th, Value.nil, kv[1], kv[2], kv[3]);
    var a: std.ArrayList(Value) = .empty;
    defer a.deinit(gpa);
    var b: std.ArrayList(Value) = .empty;
    defer b.deinit(gpa);
    try collect(th, try seqOf(th, args[0]), &a);
    try collect(th, try seqOf(th, args[1]), &b);
    const ra = try range(th, kv[4], kv[5], a.items.len);
    const rb = try range(th, kv[6], kv[7], b.items.len);
    const n = ra[1] - ra[0];
    if (n > rb[1] - rb[0]) return Value.nil;
    const from_end = isTrue(kv[0]);
    var result: ?usize = null;
    var p = rb[0];
    while (p + n <= rb[1]) : (p += 1) {
        var ok = true;
        for (0..n) |k| {
            const x = try m.keyOf(a.items[ra[0] + k]);
            const y = try m.keyOf(b.items[p + k]);
            if (!try m.compare(x, y)) {
                ok = false;
                break;
            }
        }
        if (ok) {
            result = p;
            if (!from_end) break;
        }
    }
    return if (result) |r| Value.fromFixnum(@intCast(r)) else Value.nil;
}

pub fn mismatch(th: *Thread, args: []const Value) Value {
    var kv: [8]?Value = undefined;
    if (!keyargs.parse(th, args[2..], &.{ "FROM-END", "TEST", "TEST-NOT", "KEY", "START1", "END1", "START2", "END2" }, &kv)) return Value.unwind;
    return single(th, mismatchImpl(th, args, kv) catch return Value.unwind);
}

/// 最初に違う位置（seq1 の添字）。:from-end なら、後ろから比べて違った位置の1つ後ろ。同じなら NIL
fn mismatchImpl(th: *Thread, args: []const Value, kv: [8]?Value) Unwind!Value {
    const gpa = th.rt.gpa;
    const m = try testMatcher(th, Value.nil, kv[1], kv[2], kv[3]);
    var a: std.ArrayList(Value) = .empty;
    defer a.deinit(gpa);
    var b: std.ArrayList(Value) = .empty;
    defer b.deinit(gpa);
    try collect(th, try seqOf(th, args[0]), &a);
    try collect(th, try seqOf(th, args[1]), &b);
    const ra = try range(th, kv[4], kv[5], a.items.len);
    const rb = try range(th, kv[6], kv[7], b.items.len);
    const la = ra[1] - ra[0];
    const lb = rb[1] - rb[0];
    const n = @min(la, lb);
    if (isTrue(kv[0])) {
        for (0..n) |k| {
            const x = try m.keyOf(a.items[ra[1] - 1 - k]);
            const y = try m.keyOf(b.items[rb[1] - 1 - k]);
            if (!try m.compare(x, y)) return Value.fromFixnum(@intCast(ra[1] - k));
        }
        if (la == lb) return Value.nil;
        return Value.fromFixnum(@intCast(ra[1] - n));
    }
    for (0..n) |k| {
        const x = try m.keyOf(a.items[ra[0] + k]);
        const y = try m.keyOf(b.items[rb[0] + k]);
        if (!try m.compare(x, y)) return Value.fromFixnum(@intCast(ra[0] + k));
    }
    if (la == lb) return Value.nil;
    return Value.fromFixnum(@intCast(ra[0] + n));
}

// ---------------------------------------------------------------------------
// elt・subseq・fill・replace

fn indexError(th: *Thread, i: Value, n: usize) Value {
    const rt = th.rt;
    const bound = rt.cons(Value.fromFixnum(@intCast(n)), Value.nil) catch return th.outOfMemory();
    var t = rt.cons(bound, Value.nil) catch return th.outOfMemory();
    t = rt.cons(Value.fromFixnum(0), t) catch return th.outOfMemory();
    t = rt.cons(rt.syms.integer, t) catch return th.outOfMemory();
    return th.typeError(i, t);
}

/// elt の場所：リストなら cons、ベクタなら添字
fn eltPlace(th: *Thread, seq_v: Value, idx: Value) Unwind!union(enum) { cons: Value, index: usize } {
    const s = try seqOf(th, seq_v);
    if (!idx.isFixnum() or idx.asFixnum() < 0) {
        _ = th.typeError(idx, cl(th, "UNSIGNED-BYTE"));
        return error.Unwind;
    }
    const i: usize = @intCast(idx.asFixnum());
    switch (s) {
        .list => |l| {
            var x = l;
            var k: usize = 0;
            while (x.isCons()) : (x = Runtime.consPtr(x).cdr) {
                if (k == i) return .{ .cons = x };
                k += 1;
            }
            _ = indexError(th, idx, k);
            return error.Unwind;
        },
        .vector => |v| {
            if (i >= v.len) {
                _ = indexError(th, idx, v.len);
                return error.Unwind;
            }
            return .{ .index = i };
        },
    }
}

pub fn elt(th: *Thread, args: []const Value) Value {
    const p = eltPlace(th, args[0], args[1]) catch return Value.unwind;
    return switch (p) {
        .cons => |c| Runtime.consPtr(c).car,
        .index => |i| arrays.storageGet(arrays.dataOf(args[0]), i),
    };
}

/// ZILISP-SYSTEM::%SET-ELT 列 添字 値
pub fn sysSetElt(th: *Thread, args: []const Value) Value {
    const p = eltPlace(th, args[0], args[1]) catch return Value.unwind;
    switch (p) {
        .cons => |c| Runtime.consPtr(c).car = args[2],
        .index => |i| return arrays.storageSet(th, arrays.dataOf(args[0]), i, args[2]),
    }
    return args[2];
}

/// (subseq 列 start &optional end)
pub fn subseq(th: *Thread, args: []const Value) Value {
    return subseqImpl(th, args[0], args[1], if (args.len > 2) args[2] else null) catch Value.unwind;
}

fn subseqImpl(th: *Thread, seq_v: Value, start: Value, end: ?Value) Unwind!Value {
    const s = try seqOf(th, seq_v);
    switch (s) {
        .list => |l| {
            const len = try listLength(th, l);
            const r = try range(th, start, end, len);
            var x = l;
            for (0..r[0]) |_| x = Runtime.consPtr(x).cdr;
            var head = Value.nil;
            var tail = Value.nil;
            for (r[0]..r[1]) |_| {
                const c = th.rt.cons(Runtime.consPtr(x).car, Value.nil) catch return oom(th);
                if (tail == Value.nil) head = c else Runtime.consPtr(tail).cdr = c;
                tail = c;
                x = Runtime.consPtr(x).cdr;
            }
            return head;
        },
        .vector => |v| {
            const r = try range(th, start, end, v.len);
            const chars = arrays.isSimpleString(v.data);
            const n = r[1] - r[0];
            if (chars) {
                const out = th.rt.makeStringFilled(n, 0) catch return oom(th);
                for (0..n) |i| th.rt.stringSetChar(out, i, Runtime.stringPtr(v.data).charAt(r[0] + i)) catch return oom(th);
                return out;
            }
            return th.rt.makeVector(Runtime.vectorPtr(v.data).items()[r[0]..r[1]]) catch oom(th);
        },
    }
}

/// (fill 列 要素 &key start end)
pub fn fill(th: *Thread, args: []const Value) Value {
    var kv: [2]?Value = undefined;
    if (!keyargs.parse(th, args[2..], &.{ "START", "END" }, &kv)) return Value.unwind;
    return fillImpl(th, args[0], args[1], kv) catch Value.unwind;
}

fn fillImpl(th: *Thread, seq_v: Value, item: Value, kv: [2]?Value) Unwind!Value {
    const s = try seqOf(th, seq_v);
    const len = try seqLen(th, s);
    const r = try range(th, kv[0], kv[1], len);
    switch (s) {
        .list => |l| {
            var x = l;
            var i: usize = 0;
            while (i < r[1]) : (i += 1) {
                if (i >= r[0]) Runtime.consPtr(x).car = item;
                x = Runtime.consPtr(x).cdr;
            }
        },
        .vector => |v| for (r[0]..r[1]) |i| {
            _ = try check(arrays.storageSet(th, v.data, i, item));
        },
    }
    return seq_v;
}

/// (replace 列1 列2 &key start1 end1 start2 end2)：列1 の範囲を、列2 の範囲の要素で書き換える（短い方の長さだけ）
pub fn replace(th: *Thread, args: []const Value) Value {
    var kv: [4]?Value = undefined;
    if (!keyargs.parse(th, args[2..], &.{ "START1", "END1", "START2", "END2" }, &kv)) return Value.unwind;
    return replaceImpl(th, args[0], args[1], kv) catch Value.unwind;
}

fn replaceImpl(th: *Thread, dst_v: Value, src_v: Value, kv: [4]?Value) Unwind!Value {
    const gpa = th.rt.gpa;
    const d = try seqOf(th, dst_v);
    var src: std.ArrayList(Value) = .empty;
    defer src.deinit(gpa);
    // 同じ列の重なる範囲でも正しく写せるように、先に列2 の要素を並べておく
    try collect(th, try seqOf(th, src_v), &src);
    const rd = try range(th, kv[0], kv[1], try seqLen(th, d));
    const rs = try range(th, kv[2], kv[3], src.items.len);
    const n = @min(rd[1] - rd[0], rs[1] - rs[0]);
    switch (d) {
        .list => |l| {
            var x = l;
            for (0..rd[0]) |_| x = Runtime.consPtr(x).cdr;
            for (0..n) |k| {
                Runtime.consPtr(x).car = src.items[rs[0] + k];
                x = Runtime.consPtr(x).cdr;
            }
        },
        .vector => |v| for (0..n) |k| {
            _ = try check(arrays.storageSet(th, v.data, rd[0] + k, src.items[rs[0] + k]));
        },
    }
    return dst_v;
}

// ---------------------------------------------------------------------------
// 型の指定から列を作る（concatenate・coerce・make-sequence・map）

pub const SeqKind = enum { list, vector, string };

/// 列の型の指定（list・vector・string など）。列の型でなければ null。長さの指定があれば size に書く
fn seqKind(th: *Thread, spec: Value, size: *?usize) ?SeqKind {
    size.* = null;
    const names = [_]struct { []const u8, SeqKind }{
        .{ "LIST", .list },           .{ "CONS", .list },                 .{ "NULL", .list },
        .{ "VECTOR", .vector },       .{ "SIMPLE-VECTOR", .vector },      .{ "ARRAY", .vector },
        .{ "SIMPLE-ARRAY", .vector }, .{ "STRING", .string },             .{ "SIMPLE-STRING", .string },
        .{ "BASE-STRING", .string },  .{ "SIMPLE-BASE-STRING", .string },
    };
    if (!spec.isCons()) {
        for (names) |n| if (spec == cl(th, n[0])) return n[1];
        return null;
    }
    const head = Runtime.consPtr(spec).car;
    var kind: ?SeqKind = null;
    for (names) |n| if (head == cl(th, n[0])) {
        kind = n[1];
    };
    const k = kind orelse return null;
    const rest = Runtime.consPtr(spec).cdr;
    switch (k) {
        .list => return .list,
        .string => {
            // (string 長さ)
            if (rest.isCons() and Runtime.consPtr(rest).car.isFixnum()) size.* = @intCast(Runtime.consPtr(rest).car.asFixnum());
            return .string;
        },
        .vector => {
            if (head == cl(th, "SIMPLE-VECTOR")) {
                if (rest.isCons() and Runtime.consPtr(rest).car.isFixnum()) size.* = @intCast(Runtime.consPtr(rest).car.asFixnum());
                return .vector;
            }
            // (vector 要素の型 [長さ])・(array 要素の型 (長さ))
            if (!rest.isCons()) return .vector;
            const et = Runtime.consPtr(rest).car;
            const chars = et == cl(th, "CHARACTER") or et == cl(th, "BASE-CHAR") or et == cl(th, "STANDARD-CHAR");
            const dims = Runtime.consPtr(rest).cdr;
            if (dims.isCons()) {
                const d = Runtime.consPtr(dims).car;
                if (d.isFixnum()) size.* = @intCast(d.asFixnum());
                if (d.isCons() and Runtime.consPtr(d).car.isFixnum()) size.* = @intCast(Runtime.consPtr(d).car.asFixnum());
            }
            return if (chars) .string else .vector;
        },
    }
}

fn seqKindArg(th: *Thread, spec: Value, size: *?usize) Unwind!SeqKind {
    if (seqKind(th, spec, size)) |k| return k;
    _ = th.signal(.unimplemented, "この列の型は未実装です（list・vector・string とその仲間だけ）", spec, Value.unbound);
    return error.Unwind;
}

fn buildKind(th: *Thread, kind: SeqKind, size: ?usize, spec: Value, items: []const Value) Unwind!Value {
    if (size) |n| if (n != items.len) {
        _ = th.typeError(try buildList(th, items, Value.nil), spec);
        return error.Unwind;
    };
    return switch (kind) {
        .list => buildList(th, items, Value.nil),
        .vector => buildVector(th, false, items),
        .string => buildVector(th, true, items),
    };
}

/// (concatenate 型 列...)
pub fn concatenate(th: *Thread, args: []const Value) Value {
    return concatenateImpl(th, args) catch Value.unwind;
}

fn concatenateImpl(th: *Thread, args: []const Value) Unwind!Value {
    const gpa = th.rt.gpa;
    var size: ?usize = null;
    const kind = try seqKindArg(th, args[0], &size);
    var items: std.ArrayList(Value) = .empty;
    defer items.deinit(gpa);
    for (args[1..]) |s| try collect(th, try seqOf(th, s), &items);
    return buildKind(th, kind, size, args[0], items.items);
}

/// (make-sequence 型 長さ &key initial-element)
pub fn makeSequence(th: *Thread, args: []const Value) Value {
    var kv: [1]?Value = undefined;
    if (!keyargs.parse(th, args[2..], &.{"INITIAL-ELEMENT"}, &kv)) return Value.unwind;
    return makeSequenceImpl(th, args, kv[0]) catch Value.unwind;
}

fn makeSequenceImpl(th: *Thread, args: []const Value, init: ?Value) Unwind!Value {
    var size: ?usize = null;
    const kind = try seqKindArg(th, args[0], &size);
    const n_v = args[1];
    if (!n_v.isFixnum() or n_v.asFixnum() < 0) {
        _ = th.typeError(n_v, cl(th, "UNSIGNED-BYTE"));
        return error.Unwind;
    }
    const n: usize = @intCast(n_v.asFixnum());
    if (size) |s| if (s != n) {
        _ = th.signal(.simple_error, "長さが型の指定と違います", n_v, args[0]);
        return error.Unwind;
    };
    switch (kind) {
        .list => {
            var out = Value.nil;
            for (0..n) |_| out = th.rt.cons(init orelse Value.nil, out) catch return oom(th);
            return out;
        },
        .vector => return th.rt.makeVectorFilled(n, init orelse Value.fromFixnum(0)) catch oom(th),
        .string => {
            var c: u21 = 0;
            if (init) |v| {
                if (!v.isChar()) {
                    _ = th.typeError(v, cl(th, "CHARACTER"));
                    return error.Unwind;
                }
                c = v.asChar();
            }
            return th.rt.makeStringFilled(n, c) catch oom(th);
        },
    }
}

/// 列の型の名前（シンボル）について、x がすでにその型か
fn alreadyOfType(th: *Thread, x: Value, spec: Value) bool {
    if (spec.isCons()) return false;
    const is_vector = arrays.vectorView(x) != null;
    const checks = [_]struct { []const u8, bool }{
        .{ "SEQUENCE", x.isList() or is_vector },
        .{ "LIST", x.isList() },
        .{ "CONS", x.isCons() },
        .{ "NULL", x == Value.nil },
        .{ "VECTOR", is_vector },
        .{ "ARRAY", arrays.isArray(x) },
        .{ "SIMPLE-ARRAY", arrays.isSimpleVector(x) or arrays.isSimpleString(x) },
        .{ "SIMPLE-VECTOR", arrays.isSimpleVector(x) },
        .{ "STRING", arrays.isStringLike(x) },
        .{ "BASE-STRING", arrays.isStringLike(x) },
        .{ "SIMPLE-STRING", arrays.isSimpleString(x) },
        .{ "SIMPLE-BASE-STRING", arrays.isSimpleString(x) },
    };
    for (checks) |c| if (spec == cl(th, c[0])) return c[1];
    return false;
}

/// (coerce オブジェクト 型)：列の型（list・vector・string など）、character、浮動小数の型、t・function
pub fn coerce(th: *Thread, args: []const Value) Value {
    return coerceImpl(th, args[0], args[1]) catch Value.unwind;
}

fn coerceImpl(th: *Thread, x: Value, spec: Value) Unwind!Value {
    const gpa = th.rt.gpa;
    if (spec == th.rt.t) return x;
    // すでにその型の値なら、そのまま返す（CLHS coerce。SBCL 2.6.7 と同じく同じオブジェクト）
    if (alreadyOfType(th, x, spec)) return x;
    var size: ?usize = null;
    if (seqKind(th, spec, &size)) |kind| {
        var items: std.ArrayList(Value) = .empty;
        defer items.deinit(gpa);
        try collect(th, try seqOf(th, x), &items);
        return buildKind(th, kind, size, spec, items.items);
    }
    if (spec == cl(th, "CHARACTER")) {
        if (x.isChar()) return x;
        // 長さ 1 の文字列指定子（文字列・シンボル）
        var name = x;
        if (x == Value.nil or (x.isOther() and Runtime.kindOf(x) == .symbol))
            name = if (x == Value.nil) th.rt.nil_symbol.name else th.rt.symbolPtr(x).name;
        if (arrays.isStringLike(name)) {
            const v = arrays.vectorView(name).?;
            if (v.len == 1) return arrays.storageGet(v.data, 0);
        }
        _ = th.typeError(x, cl(th, "CHARACTER"));
        return error.Unwind;
    }
    const float_types = [_]struct { []const u8, ?bool }{ .{ "FLOAT", null }, .{ "SINGLE-FLOAT", false }, .{ "SHORT-FLOAT", false }, .{ "DOUBLE-FLOAT", true }, .{ "LONG-FLOAT", true } };
    for (float_types) |ft| if (spec == cl(th, ft[0])) {
        if (!numbers.isNumber(x)) {
            _ = th.typeError(x, spec);
            return error.Unwind;
        }
        const proto: Value = if (ft[1]) |dbl| (if (dbl) th.rt.makeDouble(1.0) catch return oom(th) else Value.fromSingle(1.0)) else Value.nil;
        // (coerce 浮動小数 'float) はそのまま。そうでなければ float と同じ
        const fargs = [_]Value{ x, proto };
        const fl = th.rt.symbolPtr(cl(th, "FLOAT")).function;
        if (ft[1] == null) {
            if (x.isSingleFloat() or (x.isOther() and Runtime.kindOf(x) == .double_float)) return x;
            return check(th.call(fl, fargs[0..1]));
        }
        return check(th.call(fl, &fargs));
    };
    if (spec == cl(th, "FUNCTION")) {
        const f = th.resolveFunction(x);
        return check(f);
    }
    // 数の型は、その型の値ならそのまま返す（ほかの型は typep と合わせて実装する）
    const is_float = x.isSingleFloat() or (x.isOther() and Runtime.kindOf(x) == .double_float);
    const is_integer = x.isFixnum() or (x.isOther() and Runtime.kindOf(x) == .bignum);
    const num_types = [_]struct { []const u8, bool }{
        .{ "NUMBER", numbers.isNumber(x) }, // 複素数は未実装なので、数はすべて実数
        .{ "REAL", numbers.isNumber(x) },
        .{ "RATIONAL", numbers.isNumber(x) and !is_float },
        .{ "INTEGER", is_integer },
    };
    for (num_types) |n| if (spec == cl(th, n[0])) {
        if (n[1]) return x;
        _ = th.typeError(x, spec);
        return error.Unwind;
    };
    _ = th.signal(.unimplemented, "coerce のこの型は未実装です", spec, Value.unbound);
    return error.Unwind;
}

// ---------------------------------------------------------------------------
// map・map-into・some・every・notany・notevery

/// 各列の i 番目の要素を引数に並べる。どれかの列が尽きたら偽
const MultiSeq = struct {
    seqs: []Seq,
    cursors: []Value, // リストのたどっている位置
    len: usize, // 最も短い列の長さ

    fn init(th: *Thread, vals: []const Value) Unwind!MultiSeq {
        const gpa = th.rt.gpa;
        const seqs = gpa.alloc(Seq, vals.len) catch return oom(th);
        errdefer gpa.free(seqs);
        const cursors = gpa.alloc(Value, vals.len) catch return oom(th);
        errdefer gpa.free(cursors);
        var len: usize = std.math.maxInt(usize);
        for (vals, 0..) |v, i| {
            seqs[i] = try seqOf(th, v);
            cursors[i] = v;
            const n = switch (seqs[i]) {
                // リストの長さは、真リストでなくても尽きるまで（ドット対の終わりはそこまで）
                .list => |l| blk: {
                    var k: usize = 0;
                    var x = l;
                    while (x.isCons()) : (x = Runtime.consPtr(x).cdr) k += 1;
                    break :blk k;
                },
                .vector => |vv| vv.len,
            };
            len = @min(len, n);
        }
        return .{ .seqs = seqs, .cursors = cursors, .len = len };
    }

    fn deinit(ms: *MultiSeq, th: *Thread) void {
        th.rt.gpa.free(ms.seqs);
        th.rt.gpa.free(ms.cursors);
    }

    fn fillArgs(ms: *MultiSeq, i: usize, out: []Value) void {
        for (ms.seqs, 0..) |s, k| switch (s) {
            .list => {
                const c = ms.cursors[k];
                out[k] = Runtime.consPtr(c).car;
                ms.cursors[k] = Runtime.consPtr(c).cdr;
            },
            .vector => |v| out[k] = arrays.storageGet(v.data, i),
        };
    }
};

/// (map 型 関数 列...)。型が NIL なら NIL を返す
pub fn map(th: *Thread, args: []const Value) Value {
    return single(th, mapImpl(th, args) catch return Value.unwind);
}

fn mapImpl(th: *Thread, args: []const Value) Unwind!Value {
    const gpa = th.rt.gpa;
    const spec = args[0];
    var size: ?usize = null;
    const kind: ?SeqKind = if (spec == Value.nil) null else try seqKindArg(th, spec, &size);
    var ms = try MultiSeq.init(th, args[2..]);
    defer ms.deinit(th);
    const fargs = gpa.alloc(Value, ms.seqs.len) catch return oom(th);
    defer gpa.free(fargs);
    // 結果は、作り終えるまで Lisp のリストに積む（GC から届くように）
    var acc = Value.nil;
    for (0..ms.len) |i| {
        ms.fillArgs(i, fargs);
        const r = try check(th.call(args[1], fargs));
        if (kind != null) acc = th.rt.cons(r, acc) catch return oom(th);
    }
    const k = kind orelse return Value.nil;
    var items: std.ArrayList(Value) = .empty;
    defer items.deinit(gpa);
    var x = acc;
    while (x.isCons()) : (x = Runtime.consPtr(x).cdr) items.append(gpa, Runtime.consPtr(x).car) catch return oom(th);
    std.mem.reverse(Value, items.items);
    const out = try buildKind(th, k, size, spec, items.items);
    std.mem.doNotOptimizeAway(acc);
    return out;
}

/// (map-into 結果の列 関数 列...)：結果の列の要素を、関数の値で前から書き換える
pub fn mapInto(th: *Thread, args: []const Value) Value {
    return single(th, mapIntoImpl(th, args) catch return Value.unwind);
}

fn mapIntoImpl(th: *Thread, args: []const Value) Unwind!Value {
    const gpa = th.rt.gpa;
    const dst = args[0];
    const d = try seqOf(th, dst);
    var ms = try MultiSeq.init(th, args[2..]);
    defer ms.deinit(th);
    const fargs = gpa.alloc(Value, ms.seqs.len) catch return oom(th);
    defer gpa.free(fargs);
    // fill-pointer のあるベクタは、全体の大きさまで書き、fill-pointer を書いた数にする（CLHS map-into）
    const has_fp = arrays.hasFillPointer(dst);
    const capacity = switch (d) {
        .list => |l| try listLength(th, l),
        .vector => |v| if (has_fp) arrays.storageLen(v.data) else v.len,
    };
    const n = @min(capacity, if (ms.seqs.len == 0) capacity else ms.len);
    var cursor = dst;
    for (0..n) |i| {
        ms.fillArgs(i, fargs);
        const r = try check(th.call(args[1], fargs[0..ms.seqs.len]));
        switch (d) {
            .list => {
                Runtime.consPtr(cursor).car = r;
                cursor = Runtime.consPtr(cursor).cdr;
            },
            .vector => |v| _ = try check(arrays.storageSet(th, v.data, i, r)),
        }
    }
    if (has_fp) arrays.setFillPointerUnchecked(dst, n);
    return dst;
}

const Quant = enum { some, every, notany, notevery };

fn quantifier(comptime q: Quant) fn (*Thread, []const Value) Value {
    return struct {
        fn f(th: *Thread, args: []const Value) Value {
            return single(th, impl(th, args) catch return Value.unwind);
        }
        fn impl(th: *Thread, args: []const Value) Unwind!Value {
            const gpa = th.rt.gpa;
            var ms = try MultiSeq.init(th, args[1..]);
            defer ms.deinit(th);
            const fargs = gpa.alloc(Value, ms.seqs.len) catch return oom(th);
            defer gpa.free(fargs);
            for (0..ms.len) |i| {
                ms.fillArgs(i, fargs);
                const r = try check(th.call(args[0], fargs));
                switch (q) {
                    .some => if (r != Value.nil) return r,
                    .every => if (r == Value.nil) return Value.nil,
                    .notany => if (r != Value.nil) return Value.nil,
                    .notevery => if (r == Value.nil) return th.rt.t,
                }
            }
            return switch (q) {
                .some => Value.nil,
                .every => th.rt.t,
                .notany => th.rt.t,
                .notevery => Value.nil,
            };
        }
    }.f;
}

pub const some = quantifier(.some);
pub const every = quantifier(.every);
pub const notany = quantifier(.notany);
pub const notevery = quantifier(.notevery);

// ---------------------------------------------------------------------------
// リスト・ベクタの小さな関数

/// (make-list 長さ &key initial-element)
pub fn makeList(th: *Thread, args: []const Value) Value {
    var kv: [1]?Value = undefined;
    if (!keyargs.parse(th, args[1..], &.{"INITIAL-ELEMENT"}, &kv)) return Value.unwind;
    const n = args[0];
    if (!n.isFixnum() or n.asFixnum() < 0) return th.typeError(n, cl(th, "UNSIGNED-BYTE"));
    var out = Value.nil;
    var i: i64 = 0;
    while (i < n.asFixnum()) : (i += 1) out = th.rt.cons(kv[0] orelse Value.nil, out) catch return th.outOfMemory();
    return out;
}

/// (list-length リスト)：循環リストなら NIL
pub fn listLength_(th: *Thread, args: []const Value) Value {
    const l = args[0];
    if (!l.isList()) return th.typeError(l, th.rt.syms.list);
    var n: i64 = 0;
    var fast = l;
    var slow = l;
    while (true) {
        if (fast == Value.nil) return Value.fromFixnum(n);
        if (!fast.isCons()) return th.typeError(l, th.rt.syms.list);
        fast = Runtime.consPtr(fast).cdr;
        n += 1;
        if (fast == Value.nil) return Value.fromFixnum(n);
        if (!fast.isCons()) return th.typeError(l, th.rt.syms.list);
        fast = Runtime.consPtr(fast).cdr;
        n += 1;
        slow = Runtime.consPtr(slow).cdr;
        if (fast == slow) return Value.nil;
    }
}

/// (vector-pop ベクタ)：fill-pointer を1つ戻し、その位置の要素を返す。0 なら エラー
pub fn vectorPop(th: *Thread, args: []const Value) Value {
    const v = args[0];
    if (!arrays.hasFillPointer(v)) return th.typeError(v, cl(th, "VECTOR"));
    const view = arrays.vectorView(v).?;
    if (view.len == 0) return th.signal(.simple_error, "fill-pointer が 0 のベクタから vector-pop できません", v, Value.unbound);
    arrays.setFillPointerUnchecked(v, view.len - 1);
    return arrays.storageGet(view.data, view.len - 1);
}
