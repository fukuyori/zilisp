//! 配列（Phase 16 の最小版を、Phase 21 で一般の配列に広げた）。
//!
//! 表し方
//!   - 1次元で fill-pointer も adjustable もない配列：要素の型が T なら simple-vector、文字なら文字列
//!   - それ以外（多次元、fill-pointer、adjustable）：object.Array。要素は data（simple-vector か文字列）に行優先で並べる
//! 要素の型は T と文字（character・base-char・standard-char）の2つ（ほかの型は T に格上げする：CLHS 15.1.2.1）。
//! displaced な配列は未実装（明示的なエラー）。
//!
//! 関数：make-array・aref（多次元）・row-major-aref・svref・char・schar と書き込み、array-dimensions・array-dimension・
//! array-rank・array-total-size・array-row-major-index・array-element-type・array-has-fill-pointer-p・adjustable-array-p、
//! fill-pointer、vector-push・vector-push-extend・adjust-array、length・copy-seq・vectorp・arrayp・stringp・
//! simple-vector-p・simple-string-p。

const std = @import("std");
const Value = @import("../values/value.zig").Value;
const Thread = @import("../runtime/thread.zig").Thread;
const Runtime = @import("../runtime/runtime.zig").Runtime;
const object = @import("../values/object.zig");
const keyargs = @import("keyargs.zig");

pub fn isSimpleVector(v: Value) bool {
    return v.isOther() and Runtime.kindOf(v) == .simple_vector;
}
pub fn isSimpleString(v: Value) bool {
    return v.isOther() and Runtime.kindOf(v) == .string;
}
pub fn isArrayObject(v: Value) bool {
    return v.isOther() and Runtime.kindOf(v) == .array;
}

/// 配列か（単純ベクタ・文字列・単純でない配列）
pub fn isArray(v: Value) bool {
    return isSimpleVector(v) or isSimpleString(v) or isArrayObject(v);
}

fn cl(th: *Thread, name: []const u8) Value {
    return (th.rt.findSymbol(th.rt.cl, name) orelse unreachable).symbol;
}

/// 要素の型が文字か（character・base-char・standard-char）
fn isCharacterType(th: *Thread, t: Value) bool {
    for ([_][]const u8{ "CHARACTER", "BASE-CHAR", "STANDARD-CHAR" }) |n| if (t == cl(th, n)) return true;
    // (simple-array character (*)) などの複合の型指定は、要素の型だけを見る
    if (t.isCons()) {
        var x = Runtime.consPtr(t).cdr;
        if (x.isCons()) return isCharacterType(th, Runtime.consPtr(x).car);
        x = Value.nil;
    }
    return false;
}

// ---------------------------------------------------------------------------
// 要素の置き場所（data：simple-vector か文字列）

pub fn storageLen(data: Value) usize {
    if (isSimpleString(data)) return Runtime.stringPtr(data).length();
    return Runtime.vectorPtr(data).items().len;
}

pub fn storageGet(data: Value, i: usize) Value {
    if (isSimpleString(data)) return Value.fromChar(Runtime.stringPtr(data).charAt(i));
    return Runtime.vectorPtr(data).items()[i];
}

/// 書き込む。文字列に文字以外を書こうとしたら type-error（Value.unwind）
pub fn storageSet(th: *Thread, data: Value, i: usize, v: Value) Value {
    if (isSimpleString(data)) {
        if (!v.isChar()) return th.typeError(v, cl(th, "CHARACTER"));
        th.rt.stringSetChar(data, i, v.asChar()) catch return th.outOfMemory();
        return v;
    }
    Runtime.vectorPtr(data).items()[i] = v;
    return v;
}

/// data と同じ要素の型の、長さ n の単純なベクタか文字列（エラーなら Value.unwind）
pub fn makeLike(th: *Thread, data: Value, n: usize) Value {
    const chars = isSimpleString(data);
    return makeStorage(th, n, chars, if (chars) Value.fromChar(0) else Value.nil);
}

/// 配列の要素の置き場所（単純な配列は自分自身）
pub fn dataOf(v: Value) Value {
    if (isArrayObject(v)) return Runtime.arrayPtr(v).data;
    return v;
}

/// 1次元の配列（ベクタ）として見る：置き場所と、有効な長さ（fill-pointer があればその値）
pub const VectorView = struct { data: Value, len: usize };

pub fn vectorView(v: Value) ?VectorView {
    if (isSimpleVector(v) or isSimpleString(v)) return .{ .data = v, .len = storageLen(v) };
    if (isArrayObject(v)) {
        const a = Runtime.arrayPtr(v);
        if (a.header.len != 1) return null;
        const len = if (a.header.flags & object.Array.has_fill_pointer != 0) a.fill_pointer else a.dims()[0];
        return .{ .data = a.data, .len = len };
    }
    return null;
}

/// 文字列か（単純な文字列と、文字を要素とする単純でない1次元の配列）
pub fn isStringLike(v: Value) bool {
    if (isSimpleString(v)) return true;
    if (vectorView(v)) |view| return isSimpleString(view.data) and isArrayObject(v);
    return false;
}

/// 文字列の有効な部分を、単純な文字列で返す（単純ならそのまま。そうでなければ写す）
pub fn simpleStringOf(th: *Thread, v: Value) Value {
    if (isSimpleString(v)) return v;
    const view = vectorView(v).?;
    const s = th.rt.makeStringFilled(view.len, ' ') catch return th.outOfMemory();
    for (0..view.len) |i| th.rt.stringSetChar(s, i, Runtime.stringPtr(view.data).charAt(i)) catch return th.outOfMemory();
    return s;
}

fn rankOf(v: Value) usize {
    if (isArrayObject(v)) return Runtime.arrayPtr(v).header.len;
    return 1;
}

pub fn dimsOf(v: Value, buf: *[1]usize) []usize {
    if (isArrayObject(v)) return Runtime.arrayPtr(v).dims();
    buf[0] = storageLen(v);
    return buf[0..1];
}

// ---------------------------------------------------------------------------
// 添字

/// 添字の型 (INTEGER 0 (n)) の type-error
fn indexError(th: *Thread, i: Value, n: usize) Value {
    const rt = th.rt;
    const bound = rt.cons(Value.fromFixnum(@intCast(n)), Value.nil) catch return th.outOfMemory();
    var t = rt.cons(bound, Value.nil) catch return th.outOfMemory();
    t = rt.cons(Value.fromFixnum(0), t) catch return th.outOfMemory();
    t = rt.cons(rt.syms.integer, t) catch return th.outOfMemory();
    return th.typeError(i, t);
}

fn index(th: *Thread, i: Value, n: usize) ?usize {
    if (i.isFixnum() and i.asFixnum() >= 0 and @as(usize, @intCast(i.asFixnum())) < n) return @intCast(i.asFixnum());
    _ = indexError(th, i, n);
    return null;
}

/// 添字の並びを行優先の番号にする
fn rowMajor(th: *Thread, a: Value, subs: []const Value) ?usize {
    if (!isArray(a)) {
        _ = th.typeError(a, cl(th, "ARRAY"));
        return null;
    }
    var buf: [1]usize = undefined;
    const dims = dimsOf(a, &buf);
    if (subs.len != dims.len) {
        _ = th.signal(.simple_error, "配列の添字の数が次元の数と違います", Value.fromFixnum(@intCast(subs.len)), Value.unbound);
        return null;
    }
    var r: usize = 0;
    for (subs, dims) |s, d| r = r * d + (index(th, s, d) orelse return null);
    return r;
}

// ---------------------------------------------------------------------------
// make-array

/// 次元の指定（非負の整数か、そのリスト）を読む
fn parseDims(th: *Thread, spec: Value, out: *std.ArrayList(usize)) bool {
    const gpa = th.rt.gpa;
    if (spec.isFixnum()) {
        if (spec.asFixnum() < 0) {
            _ = th.typeError(spec, cl(th, "UNSIGNED-BYTE"));
            return false;
        }
        out.append(gpa, @intCast(spec.asFixnum())) catch {
            _ = th.outOfMemory();
            return false;
        };
        return true;
    }
    var x = spec;
    while (x.isCons()) : (x = Runtime.consPtr(x).cdr) {
        const d = Runtime.consPtr(x).car;
        if (!d.isFixnum() or d.asFixnum() < 0) {
            _ = th.typeError(d, cl(th, "UNSIGNED-BYTE"));
            return false;
        }
        out.append(gpa, @intCast(d.asFixnum())) catch {
            _ = th.outOfMemory();
            return false;
        };
    }
    if (x != Value.nil) {
        _ = th.typeError(spec, th.rt.syms.list);
        return false;
    }
    return true;
}

fn totalOf(th: *Thread, dims: []const usize) ?usize {
    var n: usize = 1;
    for (dims) |d| {
        const m = @mulWithOverflow(n, d);
        if (m[1] != 0 or m[0] > (1 << 40)) {
            _ = th.signal(.storage_condition, "配列が大きすぎます", Value.unbound, Value.unbound);
            return null;
        }
        n = m[0];
    }
    return n;
}

/// 列（リスト・ベクタ・文字列）の要素の数と、i 番目の要素
fn seqLength(v: Value) ?usize {
    if (v.isList()) {
        var n: usize = 0;
        var x = v;
        while (x.isCons()) : (x = Runtime.consPtr(x).cdr) n += 1;
        return n;
    }
    if (vectorView(v)) |view| return view.len;
    return null;
}

fn seqElt(v: Value, i: usize) Value {
    if (v.isList()) {
        var x = v;
        var k = i;
        while (k > 0) : (k -= 1) x = Runtime.consPtr(x).cdr;
        return Runtime.consPtr(x).car;
    }
    const view = vectorView(v).?;
    return storageGet(view.data, i);
}

/// :initial-contents を、次元に合わせて行優先で data に書く
fn fillContents(th: *Thread, data: Value, dims: []const usize, contents: Value, base: *usize) bool {
    if (dims.len == 0) {
        if (storageSet(th, data, base.*, contents) == Value.unwind) return false;
        base.* += 1;
        return true;
    }
    const n = seqLength(contents) orelse {
        _ = th.typeError(contents, cl(th, "SEQUENCE"));
        return false;
    };
    if (n != dims[0]) {
        _ = th.signal(.simple_error, ":initial-contents の長さが次元と違います", contents, Value.unbound);
        return false;
    }
    for (0..n) |i| {
        if (!fillContents(th, data, dims[1..], seqElt(contents, i), base)) return false;
    }
    return true;
}

/// 要素の置き場所を作る（初期値で埋める）
fn makeStorage(th: *Thread, n: usize, chars: bool, init: ?Value) Value {
    if (chars) {
        var c: u21 = 0;
        if (init) |v| {
            if (!v.isChar()) return th.typeError(v, cl(th, "CHARACTER"));
            c = v.asChar();
        }
        return th.rt.makeStringFilled(n, c) catch th.outOfMemory();
    }
    // 要素の型が T の既定の初期値は 0（SBCL 2.6.7 と同じ）
    return th.rt.makeVectorFilled(n, init orelse Value.fromFixnum(0)) catch th.outOfMemory();
}

/// make-array 次元 &key element-type initial-element initial-contents adjustable fill-pointer displaced-to displaced-index-offset
pub fn makeArray(th: *Thread, args: []const Value) Value {
    var kv: [7]?Value = undefined;
    if (!keyargs.parse(th, args[1..], &.{ "ELEMENT-TYPE", "INITIAL-ELEMENT", "INITIAL-CONTENTS", "ADJUSTABLE", "FILL-POINTER", "DISPLACED-TO", "DISPLACED-INDEX-OFFSET" }, &kv)) return Value.unwind;
    if (kv[5] != null and kv[5].? != Value.nil)
        return th.signal(.unimplemented, "displaced な配列は未実装です", kv[5].?, Value.unbound);
    if (kv[1] != null and kv[2] != null)
        return th.signal(.program_error, ":initial-element と :initial-contents は同時に指定できません", Value.unbound, Value.unbound);
    var dims: std.ArrayList(usize) = .empty;
    defer dims.deinit(th.rt.gpa);
    if (!parseDims(th, args[0], &dims)) return Value.unwind;
    const total = totalOf(th, dims.items) orelse return Value.unwind;
    const chars = if (kv[0]) |t| isCharacterType(th, t) else false;
    const adjustable = kv[3] != null and kv[3].? != Value.nil;
    var flags: u8 = if (adjustable) object.Array.adjustable else 0;
    var fill: usize = 0;
    if (kv[4]) |fp| if (fp != Value.nil) {
        if (dims.items.len != 1) return th.signal(.program_error, "fill-pointer は1次元の配列にだけ付けられます", fp, Value.unbound);
        // fill-pointer のあるベクタは、大きさを変えられる（adjustable-array-p が真。SBCL 2.6.7 と同じ）
        flags |= object.Array.has_fill_pointer | object.Array.adjustable;
        if (fp == th.rt.t) {
            fill = dims.items[0];
        } else {
            if (!fp.isFixnum() or fp.asFixnum() < 0 or @as(usize, @intCast(fp.asFixnum())) > dims.items[0])
                return indexError(th, fp, dims.items[0] + 1);
            fill = @intCast(fp.asFixnum());
        }
    };
    const data = makeStorage(th, total, chars, kv[1]);
    if (data == Value.unwind) return data;
    if (kv[2]) |contents| {
        var base: usize = 0;
        if (!fillContents(th, data, dims.items, contents, &base)) return Value.unwind;
    }
    if (dims.items.len == 1 and flags == 0) return data;
    const a = th.rt.makeArrayObject(dims.items, data, flags, fill) catch return th.outOfMemory();
    std.mem.doNotOptimizeAway(data);
    return a;
}

// ---------------------------------------------------------------------------
// 要素の読み書き

pub fn aref(th: *Thread, args: []const Value) Value {
    const a = args[0];
    const i = rowMajor(th, a, args[1..]) orelse return Value.unwind;
    return storageGet(dataOf(a), i);
}

/// ZILISP-SYSTEM::%ASET 配列 添字... 値：(setf (aref 配列 添字...) 値) の展開先。値を返す
pub fn sysAset(th: *Thread, args: []const Value) Value {
    const a = args[0];
    const v = args[args.len - 1];
    const i = rowMajor(th, a, args[1 .. args.len - 1]) orelse return Value.unwind;
    return storageSet(th, dataOf(a), i, v);
}

fn totalSize(v: Value) usize {
    return storageLen(dataOf(v));
}

pub fn rowMajorAref(th: *Thread, args: []const Value) Value {
    const a = args[0];
    if (!isArray(a)) return th.typeError(a, cl(th, "ARRAY"));
    const i = index(th, args[1], totalSize(a)) orelse return Value.unwind;
    return storageGet(dataOf(a), i);
}

pub fn sysSetRowMajorAref(th: *Thread, args: []const Value) Value {
    const a = args[0];
    if (!isArray(a)) return th.typeError(a, cl(th, "ARRAY"));
    const i = index(th, args[1], totalSize(a)) orelse return Value.unwind;
    return storageSet(th, dataOf(a), i, args[2]);
}

pub fn svref(th: *Thread, args: []const Value) Value {
    if (!isSimpleVector(args[0])) return th.typeError(args[0], cl(th, "SIMPLE-VECTOR"));
    return aref(th, args);
}

pub fn sysSvset(th: *Thread, args: []const Value) Value {
    if (!isSimpleVector(args[0])) return th.typeError(args[0], cl(th, "SIMPLE-VECTOR"));
    return sysAset(th, args);
}

/// char：文字列（単純でないものも）の要素
pub fn char(th: *Thread, args: []const Value) Value {
    if (!isStringLike(args[0])) return th.typeError(args[0], cl(th, "STRING"));
    return aref(th, args);
}

pub fn sysSetChar(th: *Thread, args: []const Value) Value {
    if (!isStringLike(args[0])) return th.typeError(args[0], cl(th, "STRING"));
    return sysAset(th, args);
}

/// schar：単純な文字列の要素
pub fn schar(th: *Thread, args: []const Value) Value {
    if (!isSimpleString(args[0])) return th.typeError(args[0], cl(th, "SIMPLE-STRING"));
    return aref(th, args);
}

// ---------------------------------------------------------------------------
// 配列の情報

fn arrayArg(th: *Thread, v: Value) bool {
    if (isArray(v)) return true;
    _ = th.typeError(v, cl(th, "ARRAY"));
    return false;
}

pub fn arrayDimensions(th: *Thread, args: []const Value) Value {
    if (!arrayArg(th, args[0])) return Value.unwind;
    var buf: [1]usize = undefined;
    const dims = dimsOf(args[0], &buf);
    var list = Value.nil;
    var i = dims.len;
    while (i > 0) : (i -= 1) list = th.rt.cons(Value.fromFixnum(@intCast(dimsOf(args[0], &buf)[i - 1])), list) catch return th.outOfMemory();
    return list;
}

pub fn arrayDimension(th: *Thread, args: []const Value) Value {
    if (!arrayArg(th, args[0])) return Value.unwind;
    var buf: [1]usize = undefined;
    const dims = dimsOf(args[0], &buf);
    const axis = index(th, args[1], dims.len) orelse return Value.unwind;
    return Value.fromFixnum(@intCast(dims[axis]));
}

pub fn arrayRank(th: *Thread, args: []const Value) Value {
    if (!arrayArg(th, args[0])) return Value.unwind;
    return Value.fromFixnum(@intCast(rankOf(args[0])));
}

pub fn arrayTotalSize(th: *Thread, args: []const Value) Value {
    if (!arrayArg(th, args[0])) return Value.unwind;
    return Value.fromFixnum(@intCast(totalSize(args[0])));
}

pub fn arrayRowMajorIndex(th: *Thread, args: []const Value) Value {
    const i = rowMajor(th, args[0], args[1..]) orelse return Value.unwind;
    return Value.fromFixnum(@intCast(i));
}

pub fn arrayElementType(th: *Thread, args: []const Value) Value {
    if (!arrayArg(th, args[0])) return Value.unwind;
    return if (isSimpleString(dataOf(args[0]))) cl(th, "CHARACTER") else th.rt.t;
}

pub fn hasFillPointer(v: Value) bool {
    return isArrayObject(v) and Runtime.arrayPtr(v).header.flags & object.Array.has_fill_pointer != 0;
}

/// fill-pointer を書き換える（fill-pointer があり、n が大きさ以下であることは呼び出し側で確かめてある）
pub fn setFillPointerUnchecked(v: Value, n: usize) void {
    Runtime.arrayPtr(v).fill_pointer = n;
}

/// (array-in-bounds-p 配列 添字...)
pub fn arrayInBoundsP(th: *Thread, args: []const Value) Value {
    if (!arrayArg(th, args[0])) return Value.unwind;
    var buf: [1]usize = undefined;
    const dims = dimsOf(args[0], &buf);
    const subs = args[1..];
    if (subs.len != dims.len) return th.signal(.simple_error, "配列の添字の数が次元の数と違います", Value.fromFixnum(@intCast(subs.len)), Value.unbound);
    for (subs, dims) |s, d| {
        if (!s.isFixnum()) {
            if (s.isOther() and Runtime.kindOf(s) == .bignum) return Value.nil;
            return th.typeError(s, th.rt.syms.integer);
        }
        if (s.asFixnum() < 0 or @as(usize, @intCast(s.asFixnum())) >= d) return Value.nil;
    }
    return th.rt.t;
}

pub fn arrayHasFillPointerP(th: *Thread, args: []const Value) Value {
    if (!arrayArg(th, args[0])) return Value.unwind;
    return th.rt.boolean(hasFillPointer(args[0]));
}

pub fn adjustableArrayP(th: *Thread, args: []const Value) Value {
    if (!arrayArg(th, args[0])) return Value.unwind;
    return th.rt.boolean(isArrayObject(args[0]) and Runtime.arrayPtr(args[0]).header.flags & object.Array.adjustable != 0);
}

fn fillPointerArg(th: *Thread, v: Value) ?*object.Array {
    if (hasFillPointer(v)) return Runtime.arrayPtr(v);
    _ = th.typeError(v, cl(th, "VECTOR"));
    return null;
}

pub fn fillPointer(th: *Thread, args: []const Value) Value {
    const a = fillPointerArg(th, args[0]) orelse return Value.unwind;
    return Value.fromFixnum(@intCast(a.fill_pointer));
}

/// ZILISP-SYSTEM::%SET-FILL-POINTER ベクタ 値
pub fn sysSetFillPointer(th: *Thread, args: []const Value) Value {
    const a = fillPointerArg(th, args[0]) orelse return Value.unwind;
    const v = args[1];
    if (!v.isFixnum() or v.asFixnum() < 0 or @as(usize, @intCast(v.asFixnum())) > a.dims()[0]) return indexError(th, v, a.dims()[0] + 1);
    a.fill_pointer = @intCast(v.asFixnum());
    return v;
}

/// (vector-push 要素 ベクタ)：fill-pointer の位置に置いて進める。いっぱいなら NIL
pub fn vectorPush(th: *Thread, args: []const Value) Value {
    const a = fillPointerArg(th, args[1]) orelse return Value.unwind;
    if (a.fill_pointer >= a.dims()[0]) return Value.nil;
    const i = a.fill_pointer;
    if (storageSet(th, a.data, i, args[0]) == Value.unwind) return Value.unwind;
    a.fill_pointer += 1;
    return Value.fromFixnum(@intCast(i));
}

/// (vector-push-extend 要素 ベクタ [増やす数])：いっぱいなら大きくしてから置く（adjustable なベクタ）。
/// 増やす数の既定は今の大きさ（0 なら 1。SBCL 2.6.7 と同じ）
pub fn vectorPushExtend(th: *Thread, args: []const Value) Value {
    const v = args[1];
    const a = fillPointerArg(th, v) orelse return Value.unwind;
    if (a.fill_pointer >= a.dims()[0]) {
        if (a.header.flags & object.Array.adjustable == 0)
            return th.signal(.simple_error, "adjustable でないベクタは大きくできません", v, Value.unbound);
        var extra: usize = @max(a.dims()[0], 1);
        if (args.len > 2) {
            if (!args[2].isFixnum() or args[2].asFixnum() < 1) return th.typeError(args[2], cl(th, "INTEGER"));
            extra = @intCast(args[2].asFixnum());
        }
        const old = a.dims()[0];
        const chars = isSimpleString(a.data);
        const data = makeStorage(th, old + extra, chars, if (chars) Value.fromChar(0) else Value.fromFixnum(0));
        if (data == Value.unwind) return data;
        // 確保の間に GC が起きても、配列は引数（VM の値スタック）にあるので動かない。ポインタは引き直す
        const b = Runtime.arrayPtr(v);
        for (0..old) |i| _ = storageSet(th, data, i, storageGet(b.data, i));
        b.data = data;
        b.dims()[0] = old + extra;
    }
    const b = Runtime.arrayPtr(v);
    const i = b.fill_pointer;
    if (storageSet(th, b.data, i, args[0]) == Value.unwind) return Value.unwind;
    b.fill_pointer += 1;
    return Value.fromFixnum(@intCast(i));
}

/// (adjust-array 配列 新しい次元 &key element-type initial-element initial-contents fill-pointer displaced-to …)。
/// 両方の次元に収まる要素を写す。adjustable な配列はその配列を書き換えて返し、そうでなければ新しい配列を返す
pub fn adjustArray(th: *Thread, args: []const Value) Value {
    const a = args[0];
    if (!arrayArg(th, a)) return Value.unwind;
    var kv: [6]?Value = undefined;
    if (!keyargs.parse(th, args[2..], &.{ "ELEMENT-TYPE", "INITIAL-ELEMENT", "INITIAL-CONTENTS", "FILL-POINTER", "DISPLACED-TO", "DISPLACED-INDEX-OFFSET" }, &kv)) return Value.unwind;
    if (kv[4] != null and kv[4].? != Value.nil) return th.signal(.unimplemented, "displaced な配列は未実装です", kv[4].?, Value.unbound);
    var dims: std.ArrayList(usize) = .empty;
    defer dims.deinit(th.rt.gpa);
    if (!parseDims(th, args[1], &dims)) return Value.unwind;
    if (dims.items.len != rankOf(a)) return th.signal(.program_error, "adjust-array で次元の数は変えられません", args[1], Value.unbound);
    const total = totalOf(th, dims.items) orelse return Value.unwind;
    const chars = isSimpleString(dataOf(a));
    const data = makeStorage(th, total, chars, kv[1]);
    if (data == Value.unwind) return data;
    if (kv[2]) |contents| {
        var base: usize = 0;
        if (!fillContents(th, data, dims.items, contents, &base)) return Value.unwind;
    } else {
        // 両方の次元に収まる添字の要素を写す
        var buf: [1]usize = undefined;
        const old_dims = dimsOf(a, &buf);
        const old = dataOf(a);
        const sub = th.rt.gpa.alloc(usize, dims.items.len) catch return th.outOfMemory();
        defer th.rt.gpa.free(sub);
        var k: usize = 0;
        while (k < total) : (k += 1) {
            var rem = k;
            var i = dims.items.len;
            while (i > 0) : (i -= 1) {
                sub[i - 1] = rem % dims.items[i - 1];
                rem /= dims.items[i - 1];
            }
            var inside = true;
            var old_index: usize = 0;
            for (sub, old_dims) |s, d| {
                if (s >= d) inside = false;
                old_index = old_index * d + s;
            }
            if (inside) _ = storageSet(th, data, k, storageGet(old, old_index));
        }
    }
    var flags: u8 = if (isArrayObject(a)) Runtime.arrayPtr(a).header.flags else 0;
    var fill: usize = if (isArrayObject(a)) Runtime.arrayPtr(a).fill_pointer else 0;
    if (kv[3]) |fp| if (fp != Value.nil) {
        flags |= object.Array.has_fill_pointer;
        fill = if (fp == th.rt.t) dims.items[0] else blk: {
            if (!fp.isFixnum() or fp.asFixnum() < 0 or @as(usize, @intCast(fp.asFixnum())) > dims.items[0]) return indexError(th, fp, dims.items[0] + 1);
            break :blk @intCast(fp.asFixnum());
        };
    };
    if (flags & object.Array.has_fill_pointer != 0 and fill > dims.items[0]) fill = dims.items[0];
    if (isArrayObject(a) and Runtime.arrayPtr(a).header.flags & object.Array.adjustable != 0) {
        const p = Runtime.arrayPtr(a);
        p.data = data;
        @memcpy(p.dims(), dims.items);
        p.header.flags = flags;
        p.fill_pointer = fill;
        return a;
    }
    if (dims.items.len == 1 and flags == 0) return data;
    return th.rt.makeArrayObject(dims.items, data, flags, fill) catch th.outOfMemory();
}

// ---------------------------------------------------------------------------
// 列としての関数

/// length：リスト（真リスト）・ベクタ（fill-pointer があればその値）・文字列の長さ
pub fn length(th: *Thread, args: []const Value) Value {
    const x = args[0];
    if (x.isList()) {
        var n: i64 = 0;
        var p = x;
        while (p.isCons()) : (p = Runtime.consPtr(p).cdr) n += 1;
        if (p != Value.nil) return th.typeError(x, th.rt.syms.list);
        return Value.fromFixnum(n);
    }
    if (vectorView(x)) |view| return Value.fromFixnum(@intCast(view.len));
    return th.typeError(x, cl(th, "SEQUENCE"));
}

/// copy-seq：リスト・ベクタ・文字列を写す（単純でないベクタは、有効な部分を単純なベクタ・文字列に写す）
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
    const view = vectorView(x) orelse return th.typeError(x, cl(th, "SEQUENCE"));
    const chars = isSimpleString(view.data);
    const out = makeStorage(th, view.len, chars, if (chars) Value.fromChar(0) else Value.nil);
    if (out == Value.unwind) return out;
    const src = dataOf(x);
    for (0..view.len) |i| _ = storageSet(th, out, i, storageGet(src, i));
    return out;
}

pub fn vectorp(th: *Thread, args: []const Value) Value {
    return th.rt.boolean(vectorView(args[0]) != null);
}

pub fn arrayp(th: *Thread, args: []const Value) Value {
    return th.rt.boolean(isArray(args[0]));
}

pub fn stringp(th: *Thread, args: []const Value) Value {
    return th.rt.boolean(isStringLike(args[0]));
}

pub fn simpleVectorP(th: *Thread, args: []const Value) Value {
    return th.rt.boolean(isSimpleVector(args[0]));
}

pub fn simpleStringP(th: *Thread, args: []const Value) Value {
    return th.rt.boolean(isSimpleString(args[0]));
}
