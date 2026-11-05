//! 型の判定（CLHS 4.2・typep。Phase 25）。
//! condition と restart の型は、クラスの記述（zl-sys::%class の属性。boot.lisp の define-condition）の CPL で判定する。
//! 型指定子のうち、教材と標準ライブラリで使うものを判定する。判定できない CL の型指定子は zilisp:unimplemented、
//! 型でないシンボルは simple-error（SBCL 2.6.7 も知らない型指定子はエラー）。
//! set-pprint-dispatch の型指定子（pprint.zig）も、ここで判定する。

const std = @import("std");
const Value = @import("../values/value.zig").Value;
const object = @import("../values/object.zig");
const Runtime = @import("../runtime/runtime.zig").Runtime;
const Thread = @import("../runtime/thread.zig").Thread;
const arrays = @import("arrays.zig");
const numbers = @import("numbers.zig");
const lists = @import("lists.zig");

pub const Fail = error{Lisp};

fn isSymbol(v: Value) bool {
    return v == Value.nil or (v.isOther() and Runtime.kindOf(v) == .symbol);
}

fn kindOf(v: Value) ?object.ObjKind {
    return if (v.isOther()) Runtime.kindOf(v) else null;
}

fn isList(v: Value) bool {
    return v == Value.nil or v.isCons();
}

/// シンボルの名前（ASCII で、長さ 64 以下のときだけ。型の名前の照合に使う）
fn asciiName(rt: *Runtime, s: Value, buf: *[64]u8) ?[]const u8 {
    const str = Runtime.stringPtr(rt.symbolPtr(s).name);
    if (str.width() != 1 or str.length() > buf.len) return null;
    @memcpy(buf[0..str.length()], str.data[0..str.length()]);
    return buf[0..str.length()];
}

/// condition・restart のクラスの記述（シンボルの zl-sys::%class の属性）。なければ null
pub fn classOf(rt: *Runtime, name: Value) ?Value {
    if (name == Value.nil or rt.sys_class_key == Value.nil) return null;
    var x = rt.symbolPtr(name).plist;
    while (x.isCons()) {
        const c = Runtime.consPtr(x);
        if (!c.cdr.isCons()) return null;
        if (c.car == rt.sys_class_key) {
            const v = Runtime.consPtr(c.cdr).car;
            return if (v.isOther() and Runtime.kindOf(v) == .simple_vector) v else null;
        }
        x = Runtime.consPtr(c.cdr).cdr;
    }
    return null;
}

/// record（condition・restart）が型 name のクラスか、その下位のクラスか
pub fn recordTypep(v: Value, name: Value) bool {
    if (kindOf(v) != .record) return false;
    const r: *object.Record = @ptrCast(@alignCast(v.pointer()));
    var x = Runtime.vectorPtr(r.class).items()[object.record_class_cpl];
    while (x.isCons()) : (x = Runtime.consPtr(x).cdr) if (Runtime.consPtr(x).car == name) return true;
    return false;
}

fn unknown(th: *Thread, spec: Value) Fail {
    const sym = if (spec.isCons()) Runtime.consPtr(spec).car else spec;
    if (isSymbol(sym) and sym != Value.nil and th.rt.symbolPtr(sym).package == th.rt.cl.obj) {
        _ = th.signal(.unimplemented, "この型指定子は未実装です", spec, Value.unbound);
    } else {
        _ = th.signal(.simple_error, "型指定子ではありません", spec, Value.unbound);
    }
    return error.Lisp;
}

fn isInteger(v: Value) bool {
    return v.isFixnum() or kindOf(v) == .bignum;
}

fn isRational(v: Value) bool {
    return isInteger(v) or kindOf(v) == .ratio;
}

fn isFloat(v: Value) bool {
    return v.isSingleFloat() or kindOf(v) == .double_float;
}

/// (型 下限 上限) の範囲。限界は * か数か (数)（その数を含まない）
fn inRange(th: *Thread, v: Value, args: Value) Fail!bool {
    var x = args;
    var i: usize = 0;
    while (x.isCons() and i < 2) : ({
        x = Runtime.consPtr(x).cdr;
        i += 1;
    }) {
        var bound = Runtime.consPtr(x).car;
        if (isStar(th, bound)) continue;
        var exclusive = false;
        if (bound.isCons()) {
            exclusive = true;
            bound = Runtime.consPtr(bound).car;
        }
        if (!numbers.isNumber(bound)) return unknown(th, args);
        const r = if (i == 0)
            (if (exclusive) numbers.compare2(th, .gt, v, bound) else numbers.compare2(th, .ge, v, bound))
        else
            (if (exclusive) numbers.compare2(th, .lt, v, bound) else numbers.compare2(th, .le, v, bound));
        if (r == Value.unwind) return error.Lisp;
        if (r == Value.nil) return false;
    }
    return true;
}

fn isStar(th: *Thread, v: Value) bool {
    return v == (th.rt.findSymbol(th.rt.cl, "*") orelse return false).symbol;
}

/// ベクタ・配列の要素の型の指定が、置き場所 data の要素の型と合うか（* は何でもよい）
fn elementTypeMatches(th: *Thread, data: Value, etype: Value) Fail!bool {
    if (isStar(th, etype)) return true;
    var buf: [64]u8 = undefined;
    const name = if (isSymbol(etype)) asciiName(th.rt, etype, &buf) orelse return unknown(th, etype) else return unknown(th, etype);
    const chars = arrays.isSimpleString(data);
    if (etype == th.rt.t) return !chars;
    if (std.mem.eql(u8, name, "CHARACTER") or std.mem.eql(u8, name, "BASE-CHAR")) return chars;
    return unknown(th, etype);
}

/// 配列の大きさの指定（* か長さ）が合うか
fn sizeMatches(th: *Thread, len: usize, size: Value) Fail!bool {
    if (isStar(th, size)) return true;
    if (size.isFixnum()) return size.asFixnum() >= 0 and @as(usize, @intCast(size.asFixnum())) == len;
    // (長さ) の形の次元のリスト（1 次元）
    if (size.isCons() and Runtime.consPtr(size).cdr == Value.nil) return sizeMatches(th, len, Runtime.consPtr(size).car);
    return unknown(th, size);
}

fn arrayRank(v: Value) ?usize {
    return switch (kindOf(v) orelse return null) {
        .simple_vector, .string => 1,
        .array => Runtime.arrayPtr(v).header.len,
        else => null,
    };
}

fn isSimpleArray(v: Value) bool {
    if (arrays.isSimpleVector(v) or arrays.isSimpleString(v)) return true;
    // 多次元の配列は、fill-pointer も adjustable もなければ単純とみなす（SBCL 2.6.7 と同じ）
    if (kindOf(v) == .array) {
        const a = Runtime.arrayPtr(v);
        return a.header.len != 1 and a.header.flags & (object.Array.adjustable | object.Array.has_fill_pointer) == 0;
    }
    return false;
}

/// v が型 spec か。判定できない型指定子はエラー（error.Lisp。th にエラーを記録済み）
pub fn typep(th: *Thread, v: Value, spec: Value) Fail!bool {
    const rt = th.rt;
    if (spec == rt.t) return true;
    if (spec == Value.nil) return false;
    if (isSymbol(spec)) {
        if (classOf(rt, spec) != null) return recordTypep(v, spec);
        if (rt.symbolPtr(spec).package != rt.cl.obj) return unknown(th, spec);
        var buf: [64]u8 = undefined;
        const name = asciiName(rt, spec, &buf) orelse return unknown(th, spec);
        const kind = kindOf(v);
        const Is = struct {
            fn eq(n: []const u8, s: []const u8) bool {
                return std.mem.eql(u8, n, s);
            }
        };
        if (Is.eq(name, "CONS")) return v.isCons();
        if (Is.eq(name, "LIST")) return isList(v);
        if (Is.eq(name, "NULL")) return v == Value.nil;
        if (Is.eq(name, "ATOM")) return !v.isCons();
        if (Is.eq(name, "SYMBOL")) return isSymbol(v);
        if (Is.eq(name, "KEYWORD")) return kind == .symbol and rt.symbolPtr(v).package == rt.keyword.obj;
        if (Is.eq(name, "BOOLEAN")) return v == Value.nil or v == rt.t;
        if (Is.eq(name, "STRING")) return arrays.isStringLike(v);
        if (Is.eq(name, "SIMPLE-STRING")) return arrays.isSimpleString(v);
        if (Is.eq(name, "BASE-STRING") or Is.eq(name, "SIMPLE-BASE-STRING")) {
            // 幅 1 バイトの文字列（SBCL 2.6.7 の base-string は ASCII の文字だけを持てる。Zilisp は幅で区別しない）
            return false;
        }
        if (Is.eq(name, "CHARACTER")) return v.isChar();
        if (Is.eq(name, "BASE-CHAR")) return v.isChar() and v.asChar() < 128;
        if (Is.eq(name, "STANDARD-CHAR")) return v.isChar() and (v.asChar() == '\n' or (v.asChar() >= ' ' and v.asChar() <= '~'));
        if (Is.eq(name, "NUMBER")) return numbers.isNumber(v);
        if (Is.eq(name, "REAL")) return numbers.isNumber(v); // 複素数はない
        if (Is.eq(name, "COMPLEX")) return false;
        if (Is.eq(name, "INTEGER")) return isInteger(v);
        if (Is.eq(name, "FIXNUM")) return v.isFixnum();
        if (Is.eq(name, "BIGNUM")) return kind == .bignum;
        if (Is.eq(name, "BIT")) return v.isFixnum() and (v.asFixnum() == 0 or v.asFixnum() == 1);
        if (Is.eq(name, "UNSIGNED-BYTE")) {
            if (!isInteger(v)) return false;
            const r = numbers.compare2(th, .ge, v, Value.fromFixnum(0));
            if (r == Value.unwind) return error.Lisp;
            return r != Value.nil;
        }
        if (Is.eq(name, "SIGNED-BYTE")) return isInteger(v);
        if (Is.eq(name, "RATIO")) return kind == .ratio;
        if (Is.eq(name, "RATIONAL")) return isRational(v);
        if (Is.eq(name, "FLOAT")) return isFloat(v);
        if (Is.eq(name, "SINGLE-FLOAT") or Is.eq(name, "SHORT-FLOAT")) return v.isSingleFloat();
        if (Is.eq(name, "DOUBLE-FLOAT") or Is.eq(name, "LONG-FLOAT")) return kind == .double_float;
        if (Is.eq(name, "ARRAY")) return arrayRank(v) != null;
        if (Is.eq(name, "SIMPLE-ARRAY")) return isSimpleArray(v);
        if (Is.eq(name, "VECTOR")) return arrays.vectorView(v) != null;
        if (Is.eq(name, "SIMPLE-VECTOR")) return kind == .simple_vector;
        if (Is.eq(name, "SEQUENCE")) return isList(v) or arrays.vectorView(v) != null;
        if (Is.eq(name, "HASH-TABLE")) return kind == .hash_table;
        if (Is.eq(name, "FUNCTION") or Is.eq(name, "COMPILED-FUNCTION")) return v.isFunctionPointer();
        if (Is.eq(name, "PATHNAME")) return kind == .pathname;
        if (Is.eq(name, "STREAM")) return kind == .stream;
        if (Is.eq(name, "PACKAGE")) return kind == .package;
        if (Is.eq(name, "READTABLE")) return kind == .readtable;
        return unknown(th, spec);
    }
    if (!spec.isCons()) return unknown(th, spec);
    const head = Runtime.consPtr(spec).car;
    const args = Runtime.consPtr(spec).cdr;
    if (!isSymbol(head) or rt.symbolPtr(head).package != rt.cl.obj) return unknown(th, spec);
    var buf: [64]u8 = undefined;
    const hn = asciiName(rt, head, &buf) orelse return unknown(th, spec);
    const Is = struct {
        fn eq(n: []const u8, s: []const u8) bool {
            return std.mem.eql(u8, n, s);
        }
    };
    const first: ?Value = if (args.isCons()) Runtime.consPtr(args).car else null;
    const second: ?Value = if (args.isCons() and Runtime.consPtr(args).cdr.isCons()) Runtime.consPtr(Runtime.consPtr(args).cdr).car else null;
    if (Is.eq(hn, "CONS")) {
        if (!v.isCons()) return false;
        if (first) |a| if (!isStar(th, a) and !(try typep(th, Runtime.consPtr(v).car, a))) return false;
        if (second) |d| if (!isStar(th, d) and !(try typep(th, Runtime.consPtr(v).cdr, d))) return false;
        return true;
    }
    if (Is.eq(hn, "MEMBER")) {
        var x = args;
        while (x.isCons()) : (x = Runtime.consPtr(x).cdr) if (lists.eql2(v, Runtime.consPtr(x).car)) return true;
        return false;
    }
    if (Is.eq(hn, "EQL")) return first != null and lists.eql2(v, first.?);
    if (Is.eq(hn, "AND")) {
        var x = args;
        while (x.isCons()) : (x = Runtime.consPtr(x).cdr) if (!(try typep(th, v, Runtime.consPtr(x).car))) return false;
        return true;
    }
    if (Is.eq(hn, "OR")) {
        var x = args;
        while (x.isCons()) : (x = Runtime.consPtr(x).cdr) if (try typep(th, v, Runtime.consPtr(x).car)) return true;
        return false;
    }
    if (Is.eq(hn, "NOT")) return !(try typep(th, v, first orelse return unknown(th, spec)));
    if (Is.eq(hn, "SATISFIES")) {
        var argv: [1]Value = .{v};
        const r = th.call(first orelse return unknown(th, spec), &argv);
        if (r == Value.unwind) return error.Lisp;
        return r != Value.nil;
    }
    if (Is.eq(hn, "INTEGER")) return isInteger(v) and try inRange(th, v, args);
    if (Is.eq(hn, "RATIONAL")) return isRational(v) and try inRange(th, v, args);
    if (Is.eq(hn, "REAL")) return numbers.isNumber(v) and try inRange(th, v, args);
    if (Is.eq(hn, "FLOAT")) return isFloat(v) and try inRange(th, v, args);
    if (Is.eq(hn, "SINGLE-FLOAT") or Is.eq(hn, "SHORT-FLOAT")) return v.isSingleFloat() and try inRange(th, v, args);
    if (Is.eq(hn, "DOUBLE-FLOAT") or Is.eq(hn, "LONG-FLOAT")) return kindOf(v) == .double_float and try inRange(th, v, args);
    if (Is.eq(hn, "MOD")) {
        const n = first orelse return unknown(th, spec);
        if (!isInteger(n)) return unknown(th, spec);
        if (!isInteger(v)) return false;
        const lo = numbers.compare2(th, .ge, v, Value.fromFixnum(0));
        if (lo == Value.unwind) return error.Lisp;
        const hi = numbers.compare2(th, .lt, v, n);
        if (hi == Value.unwind) return error.Lisp;
        return lo != Value.nil and hi != Value.nil;
    }
    if (Is.eq(hn, "UNSIGNED-BYTE") or Is.eq(hn, "SIGNED-BYTE")) {
        if (!isInteger(v)) return false;
        const n = first orelse return typep(th, v, head);
        if (isStar(th, n)) return typep(th, v, head);
        if (!n.isFixnum() or n.asFixnum() < 1) return unknown(th, spec);
        // 整数の長さ（integer-length）で判定する
        var argv: [1]Value = .{v};
        const len = numbers.integerLength(th, &argv);
        if (len == Value.unwind) return error.Lisp;
        const bits = n.asFixnum();
        if (Is.eq(hn, "UNSIGNED-BYTE")) {
            const sign = numbers.compare2(th, .ge, v, Value.fromFixnum(0));
            if (sign == Value.unwind) return error.Lisp;
            return sign != Value.nil and len.asFixnum() <= bits;
        }
        return len.asFixnum() < bits;
    }
    if (Is.eq(hn, "VECTOR") or Is.eq(hn, "SIMPLE-VECTOR") or Is.eq(hn, "STRING") or Is.eq(hn, "SIMPLE-STRING")) {
        const view = arrays.vectorView(v) orelse return false;
        // 型指定子の大きさは配列の次元の大きさ（fill-pointer ではない。CLHS 15.1.2.2）
        const dim = if (kindOf(v) == .array) Runtime.arrayPtr(v).dims()[0] else arrays.storageLen(v);
        if (Is.eq(hn, "SIMPLE-VECTOR")) {
            if (kindOf(v) != .simple_vector) return false;
            return if (first) |s| try sizeMatches(th, dim, s) else true;
        }
        if (Is.eq(hn, "STRING")) {
            if (!arrays.isStringLike(v)) return false;
            return if (first) |s| try sizeMatches(th, dim, s) else true;
        }
        if (Is.eq(hn, "SIMPLE-STRING")) {
            if (!arrays.isSimpleString(v)) return false;
            return if (first) |s| try sizeMatches(th, dim, s) else true;
        }
        if (first) |e| if (!(try elementTypeMatches(th, view.data, e))) return false;
        if (second) |s| if (!(try sizeMatches(th, dim, s))) return false;
        return true;
    }
    if (Is.eq(hn, "ARRAY") or Is.eq(hn, "SIMPLE-ARRAY")) {
        if (Is.eq(hn, "SIMPLE-ARRAY") and !isSimpleArray(v)) return false;
        const rank = arrayRank(v) orelse return false;
        if (first) |e| if (!(try elementTypeMatches(th, arrays.dataOf(v), e))) return false;
        if (second) |d| {
            if (isStar(th, d)) return true;
            if (d.isFixnum()) return d.asFixnum() >= 0 and @as(usize, @intCast(d.asFixnum())) == rank;
            // 次元のリスト：各次元の大きさ（* か整数）
            var dims_buf: [1]usize = undefined;
            const dims: []const usize = if (kindOf(v) == .array) Runtime.arrayPtr(v).dims() else blk: {
                dims_buf[0] = arrays.storageLen(v);
                break :blk &dims_buf;
            };
            var x = d;
            var i: usize = 0;
            while (x.isCons()) : ({
                x = Runtime.consPtr(x).cdr;
                i += 1;
            }) {
                if (i >= dims.len) return false;
                if (!(try sizeMatches(th, dims[i], Runtime.consPtr(x).car))) return false;
            }
            return i == dims.len;
        }
        return true;
    }
    return unknown(th, spec);
}

// ---------------------------------------------------------------------------
// Lisp の関数

/// (typep 値 型 &optional 環境)
pub fn typepFn(th: *Thread, args: []const Value) Value {
    const r = typep(th, args[0], args[1]) catch return Value.unwind;
    th.mv_count = 1;
    return th.rt.boolean(r);
}
