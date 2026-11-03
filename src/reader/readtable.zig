//! readtable（Phase 24。CLHS 2.1.1「Readtables」・23.2）。オブジェクトの形は object.Readtable。
//!   - 標準の readtable（zl-sys::*standard-readtable*）は起動時に作る。*readtable* の初期値はその写し（SBCL 2.6.7 と同じ）。
//!   - 標準のマクロ文字の関数は、組み込みの働き（reader.Builtin）ごとの Zig の関数（zl-sys::%READ-LIST など）。
//!     Reader は、マクロ関数がこれらのどれかなら、Lisp を呼ばずに Zig の働きを直接使う。
//!   - 構文とマクロを変えると standard の印を外す（Reader は、印があれば標準の表で速く読む）。

const std = @import("std");
const object = @import("../values/object.zig");
const reader = @import("reader.zig");
const Value = @import("../values/value.zig").Value;
const Runtime = @import("../runtime/runtime.zig").Runtime;
const Thread = @import("../runtime/thread.zig").Thread;
const function = @import("../runtime/function.zig");
const Error = @import("../runtime/runtime.zig").Error;
const Builtin = reader.Builtin;
const SyntaxType = reader.SyntaxType;

pub const Table = object.Readtable;

pub fn isReadtable(v: Value) bool {
    return v.isOther() and Runtime.kindOf(v) == .readtable;
}

pub fn ptr(v: Value) *Table {
    return @ptrCast(@alignCast(v.pointer()));
}

fn charsList(rt: *Runtime) Error!Value {
    return rt.makeVectorFilled(128, Value.nil);
}

/// 空の readtable（すべて構成文字）
fn makeEmpty(rt: *Runtime) Error!Value {
    const macros = try charsList(rt);
    const t = try rt.heap.create(Table, 0);
    t.* = .{ .header = .{ .kind = .readtable }, .syntax = undefined, .macros = macros, .other = Value.nil, .dispatch = Value.nil };
    for (&t.syntax, 0..) |*x, i| x.* = @backingInt(reader.syntax.syntaxType(@intCast(i)));
    return Value.fromPointer(t, .other);
}

/// 組み込みの働きの関数（Runtime.reader_builtins）
pub fn builtinFunction(rt: *Runtime, k: Builtin) Value {
    return rt.reader_builtins[@backingInt(k)];
}

/// 関数が組み込みの働きのどれか（そうでなければ null）
pub fn builtinOf(rt: *Runtime, f: Value) ?Builtin {
    if (!f.isFunctionPointer()) return null;
    for (rt.reader_builtins, 0..) |b, i| if (b == f and i != 0) return @fromBackingInt(@intCast(i));
    return null;
}

const builtin_field_names = @typeInfo(Builtin).@"enum".field_names;

/// 組み込みの働きの関数の名前（zl-sys::%READ-LIST、%READ-SHARP-QUOTE など）
const builtin_names = blk: {
    var names: [builtin_field_names.len][]const u8 = undefined;
    for (builtin_field_names, 0..) |name, i| {
        var buf: [name.len + 6]u8 = undefined;
        @memcpy(buf[0..6], "%READ-");
        for (name, 0..) |c, j| buf[6 + j] = if (c == '_') '-' else std.ascii.toUpper(c);
        const final = buf;
        names[i] = &final;
    }
    break :blk names;
};

/// 組み込みの働きの関数を作り、標準の readtable と *readtable* を作る（Runtime の初期化の最後に呼ぶ）
pub fn install(rt: *Runtime) Error!void {
    inline for (builtin_field_names, 0..) |_, i| {
        if (i == 0) continue;
        const sym = try rt.intern(rt.sys, builtin_names[i]);
        const k: Builtin = @fromBackingInt(@intCast(i));
        // マクロ文字は (stream char)、# の後の文字は (stream char arg)
        const fv = try function.makeNative(rt, sym, builtinImpl(k), 2, 3);
        rt.symbolPtr(sym).function = fv;
        rt.reader_builtins[i] = fv;
    }
    const std_rt = try makeEmpty(rt);
    const sym = try rt.intern(rt.sys, "*STANDARD-READTABLE*");
    rt.symbolPtr(sym).value = std_rt;
    rt.symbolPtr(sym).header.flags |= object.SymbolFlags.special;
    try fillStandard(rt, std_rt);
    rt.standard_readtable = sym;
    rt.symbolPtr(rt.syms.@"*readtable*").value = try copy(rt, std_rt, null);
}

fn fillStandard(rt: *Runtime, tv: Value) Error!void {
    const t = ptr(tv);
    for (0..128) |i| {
        const info = reader.standardChar(@intCast(i));
        t.syntax[i] = @backingInt(info.syntax);
        Runtime.vectorPtr(t.macros).items()[i] = switch (info.macro) {
            .builtin => |k| builtinFunction(rt, k),
            else => Value.nil,
        };
    }
    // # の dispatch の表（英字は大文字の位置に置く）
    const table = try rt.makeVectorFilled(129, Value.nil);
    for (0..128) |i| {
        const k = reader.standardSharp(@intCast(i));
        if (k == .none) continue;
        const up = reader.syntax.upcase(@intCast(i));
        Runtime.vectorPtr(table).items()[up] = builtinFunction(rt, k);
    }
    const entry = try rt.cons(Value.fromChar('#'), table);
    t.dispatch = try rt.cons(entry, Value.nil);
    t.header.flags |= Table.standard_flag;
}

/// 標準の readtable（zl-sys::*standard-readtable* の値）
pub fn standard(rt: *Runtime) Value {
    return rt.symbolPtr(rt.standard_readtable).value;
}

/// 今の *readtable*（readtable でなければ標準の readtable）
pub fn current(rt: *Runtime) Value {
    const v = rt.symbolPtr(rt.syms.@"*readtable*").value;
    return if (isReadtable(v)) v else standard(rt);
}

pub fn caseOf(v: Value) reader.Case {
    return @fromBackingInt(@intCast(@as(u2, @intCast(ptr(v).header.aux & 3))));
}

/// from を写す（to があればそこに上書きする。CLHS copy-readtable）
pub fn copy(rt: *Runtime, from: Value, to: ?Value) Error!Value {
    const dst = to orelse try makeEmpty(rt);
    const s = ptr(from);
    // 写しを作る間に GC が起きても from と dst は（呼び出し側の）スタックから届く
    const macros = try rt.makeVector(Runtime.vectorPtr(s.macros).items());
    const other = try copyAlist(rt, s.other);
    var dispatch = Value.nil;
    var x = s.dispatch;
    var last = Value.nil;
    while (x.isCons()) : (x = Runtime.consPtr(x).cdr) {
        const e = Runtime.consPtr(x).car;
        const tbl = Runtime.consPtr(e).cdr;
        const items = Runtime.vectorPtr(tbl).items();
        const new_tbl = try rt.makeVector(items);
        // 最後の要素（ASCII 以外の文字の表）も写す
        Runtime.vectorPtr(new_tbl).items()[128] = try copyAlist(rt, items[128]);
        const ne = try rt.cons(Runtime.consPtr(e).car, new_tbl);
        const cell = try rt.cons(ne, Value.nil);
        if (last == Value.nil) dispatch = cell else Runtime.consPtr(last).cdr = cell;
        last = cell;
    }
    const d = ptr(dst);
    d.syntax = s.syntax;
    d.macros = macros;
    d.other = other;
    d.dispatch = dispatch;
    d.header.aux = s.header.aux;
    d.header.flags = s.header.flags;
    return dst;
}

/// ((キー . 値) …) の写し（値が cons なら、その cons も写す）
fn copyAlist(rt: *Runtime, list: Value) Error!Value {
    var out = Value.nil;
    var last = Value.nil;
    var x = list;
    while (x.isCons()) : (x = Runtime.consPtr(x).cdr) {
        const e = Runtime.consPtr(x).car;
        var val = Runtime.consPtr(e).cdr;
        if (val.isCons()) val = try rt.cons(Runtime.consPtr(val).car, Runtime.consPtr(val).cdr);
        const ne = try rt.cons(Runtime.consPtr(e).car, val);
        const cell = try rt.cons(ne, Value.nil);
        if (last == Value.nil) out = cell else Runtime.consPtr(last).cdr = cell;
        last = cell;
    }
    return out;
}

fn assoc(list: Value, key: Value) ?Value {
    var x = list;
    while (x.isCons()) : (x = Runtime.consPtr(x).cdr) {
        const e = Runtime.consPtr(x).car;
        if (Runtime.consPtr(e).car == key) return e;
    }
    return null;
}

/// 文字の構文型とマクロ関数（Lisp の値。マクロでなければ NIL）
pub fn charEntry(tv: Value, cp: u21) struct { syntax: SyntaxType, fn_: Value } {
    const t = ptr(tv);
    if (cp < 128) return .{ .syntax = @fromBackingInt(@intCast(t.syntax[cp])), .fn_ = Runtime.vectorPtr(t.macros).items()[cp] };
    if (assoc(t.other, Value.fromChar(cp))) |e| {
        const v = Runtime.consPtr(e).cdr;
        return .{ .syntax = @fromBackingInt(@intCast(@as(u8, @intCast(Runtime.consPtr(v).car.asFixnum())))), .fn_ = Runtime.consPtr(v).cdr };
    }
    return .{ .syntax = reader.syntax.syntaxType(cp), .fn_ = Value.nil };
}

fn setEntry(rt: *Runtime, tv: Value, cp: u21, st: SyntaxType, f: Value) Error!void {
    const t = ptr(tv);
    t.header.flags &= ~Table.standard_flag;
    if (cp < 128) {
        t.syntax[cp] = @backingInt(st);
        Runtime.vectorPtr(t.macros).items()[cp] = f;
        return;
    }
    const key = Value.fromChar(cp);
    const val = try rt.cons(Value.fromFixnum(@backingInt(st)), f);
    if (assoc(t.other, key)) |e| {
        Runtime.consPtr(e).cdr = val;
        return;
    }
    const e = try rt.cons(key, val);
    ptr(tv).other = try rt.cons(e, ptr(tv).other);
}

/// Reader の文字の情報（Macro に変える）
pub fn charInfo(rt: *Runtime, tv: Value, cp: u21) reader.CharInfo {
    const e = charEntry(tv, cp);
    return .{ .syntax = e.syntax, .macro = macroOf(rt, e.fn_) };
}

fn macroOf(rt: *Runtime, f: Value) reader.Macro {
    if (f == Value.nil) return .none;
    if (builtinOf(rt, f)) |k| return .{ .builtin = k };
    return .{ .user = f.raw() };
}

fn dispatchTable(tv: Value, disp: u21) ?Value {
    const e = assoc(ptr(tv).dispatch, Value.fromChar(disp)) orelse return null;
    return Runtime.consPtr(e).cdr;
}

/// dispatch 文字 disp の後の文字 sub の関数（大文字・小文字を区別しない）
pub fn dispatchFunction(tv: Value, disp: u21, sub: u21) ?Value {
    const tbl = dispatchTable(tv, disp) orelse return null;
    const up = reader.syntax.upcase(sub);
    const items = Runtime.vectorPtr(tbl).items();
    if (up < 128) return items[up];
    if (assoc(items[128], Value.fromChar(up))) |e| return Runtime.consPtr(e).cdr;
    return Value.nil;
}

pub fn dispatchInfo(rt: *Runtime, tv: Value, disp: u21, sub: u21) reader.Macro {
    const f = dispatchFunction(tv, disp, sub) orelse return .none;
    return macroOf(rt, f);
}

// ---------------------------------------------------------------------------
// Lisp の関数（CLHS 23.2）

fn readtableDesignator(th: *Thread, v: ?Value) ?Value {
    const x = v orelse return current(th.rt);
    if (isReadtable(x)) return x;
    // NIL は標準の readtable（CLHS 23.2 の readtable designator）
    if (x == Value.nil) return standard(th.rt);
    _ = th.typeError(x, cl(th, "READTABLE"));
    return null;
}

fn cl(th: *Thread, name: []const u8) Value {
    return (th.rt.findSymbol(th.rt.cl, name) orelse unreachable).symbol;
}

fn charArg(th: *Thread, v: Value) ?u21 {
    if (v.isChar()) return v.asChar();
    _ = th.typeError(v, cl(th, "CHARACTER"));
    return null;
}

fn opt(args: []const Value, i: usize) ?Value {
    return if (i < args.len) args[i] else null;
}

/// 標準の readtable は変えられない（SBCL 2.6.7 も standard readtable の変更はエラー）
fn checkMutable(th: *Thread, tv: Value) bool {
    if (tv == standard(th.rt)) {
        _ = th.signal(.simple_error, "標準の readtable は変えられません", tv, Value.unbound);
        return false;
    }
    return true;
}

pub fn readtablep(th: *Thread, args: []const Value) Value {
    return th.rt.boolean(isReadtable(args[0]));
}

/// (copy-readtable &optional from-readtable to-readtable)
pub fn copyReadtable(th: *Thread, args: []const Value) Value {
    const from = readtableDesignator(th, opt(args, 0)) orelse return Value.unwind;
    const to_v = opt(args, 1);
    var to: ?Value = null;
    if (to_v) |t| if (t != Value.nil) {
        if (!isReadtable(t)) return th.typeError(t, cl(th, "READTABLE"));
        if (!checkMutable(th, t)) return Value.unwind;
        to = t;
    };
    return copy(th.rt, from, to) catch th.outOfMemory();
}

/// (set-macro-character char new-function &optional non-terminating-p readtable)
pub fn setMacroCharacter(th: *Thread, args: []const Value) Value {
    const cp = charArg(th, args[0]) orelse return Value.unwind;
    const tv = readtableDesignator(th, opt(args, 3)) orelse return Value.unwind;
    if (!checkMutable(th, tv)) return Value.unwind;
    const non_term = if (opt(args, 2)) |x| x != Value.nil else false;
    const f = args[1];
    if (!f.isFunctionPointer() and !(f.isOther() and Runtime.kindOf(f) == .symbol) and f != Value.nil)
        return th.typeError(f, cl(th, "FUNCTION"));
    setEntry(th.rt, tv, cp, if (non_term) .non_terminating_macro else .terminating_macro, f) catch return th.outOfMemory();
    return th.rt.t;
}

/// (get-macro-character char &optional readtable)：関数と non-terminating-p の2つの値
pub fn getMacroCharacter(th: *Thread, args: []const Value) Value {
    const cp = charArg(th, args[0]) orelse return Value.unwind;
    const tv = readtableDesignator(th, opt(args, 1)) orelse return Value.unwind;
    const e = charEntry(tv, cp);
    const is_macro = e.syntax == .terminating_macro or e.syntax == .non_terminating_macro;
    th.mv[1] = th.rt.boolean(is_macro and e.syntax == .non_terminating_macro);
    th.mv_count = 2;
    if (!is_macro) return Value.nil;
    // 標準の働きは、その関数の名前のシンボル（zl-sys::%READ-LIST など。SBCL 2.6.7 も SB-IMPL::READ-LIST などのシンボル）
    if (builtinOf(th.rt, e.fn_)) |_| return function.nativePtr(e.fn_).name;
    return e.fn_;
}

/// (make-dispatch-macro-character char &optional non-terminating-p readtable)
pub fn makeDispatchMacroCharacter(th: *Thread, args: []const Value) Value {
    const rt = th.rt;
    const cp = charArg(th, args[0]) orelse return Value.unwind;
    const tv = readtableDesignator(th, opt(args, 2)) orelse return Value.unwind;
    if (!checkMutable(th, tv)) return Value.unwind;
    const non_term = if (opt(args, 1)) |x| x != Value.nil else false;
    setEntry(rt, tv, cp, if (non_term) .non_terminating_macro else .terminating_macro, builtinFunction(rt, .dispatch)) catch return th.outOfMemory();
    const tbl = rt.makeVectorFilled(129, Value.nil) catch return th.outOfMemory();
    if (assoc(ptr(tv).dispatch, Value.fromChar(cp))) |e| {
        Runtime.consPtr(e).cdr = tbl;
    } else {
        const e = rt.cons(Value.fromChar(cp), tbl) catch return th.outOfMemory();
        ptr(tv).dispatch = rt.cons(e, ptr(tv).dispatch) catch return th.outOfMemory();
    }
    return rt.t;
}

/// (set-dispatch-macro-character disp-char sub-char new-function &optional readtable)
pub fn setDispatchMacroCharacter(th: *Thread, args: []const Value) Value {
    const rt = th.rt;
    const disp = charArg(th, args[0]) orelse return Value.unwind;
    const sub = charArg(th, args[1]) orelse return Value.unwind;
    const tv = readtableDesignator(th, opt(args, 3)) orelse return Value.unwind;
    if (!checkMutable(th, tv)) return Value.unwind;
    const tbl = dispatchTable(tv, disp) orelse return th.signal(.simple_error, "dispatch のマクロ文字ではありません", args[0], Value.unbound);
    if (sub >= '0' and sub <= '9') return th.signal(.simple_error, "数字は dispatch の後の文字にできません", args[1], Value.unbound);
    ptr(tv).header.flags &= ~Table.standard_flag;
    const up = reader.syntax.upcase(sub);
    const items = Runtime.vectorPtr(tbl).items();
    if (up < 128) {
        items[up] = args[2];
    } else if (assoc(items[128], Value.fromChar(up))) |e| {
        Runtime.consPtr(e).cdr = args[2];
    } else {
        const e = rt.cons(Value.fromChar(up), args[2]) catch return th.outOfMemory();
        Runtime.vectorPtr(tbl).items()[128] = rt.cons(e, Runtime.vectorPtr(tbl).items()[128]) catch return th.outOfMemory();
    }
    return rt.t;
}

/// (get-dispatch-macro-character disp-char sub-char &optional readtable)
pub fn getDispatchMacroCharacter(th: *Thread, args: []const Value) Value {
    const disp = charArg(th, args[0]) orelse return Value.unwind;
    const sub = charArg(th, args[1]) orelse return Value.unwind;
    const tv = readtableDesignator(th, opt(args, 2)) orelse return Value.unwind;
    const f = dispatchFunction(tv, disp, sub) orelse return th.signal(.simple_error, "dispatch のマクロ文字ではありません", args[0], Value.unbound);
    // 数字は引数なので、関数はない（SBCL 2.6.7 と同じく NIL）
    if (sub >= '0' and sub <= '9') return Value.nil;
    return f;
}

/// (set-syntax-from-char to-char from-char &optional to-readtable from-readtable)
pub fn setSyntaxFromChar(th: *Thread, args: []const Value) Value {
    const rt = th.rt;
    const to = charArg(th, args[0]) orelse return Value.unwind;
    const from = charArg(th, args[1]) orelse return Value.unwind;
    const to_rt = readtableDesignator(th, opt(args, 2)) orelse return Value.unwind;
    if (!checkMutable(th, to_rt)) return Value.unwind;
    const from_rt = readtableDesignator(th, if (opt(args, 3)) |x| (if (x == Value.nil) Value.nil else x) else Value.nil) orelse return Value.unwind;
    const e = charEntry(from_rt, from);
    setEntry(rt, to_rt, to, e.syntax, e.fn_) catch return th.outOfMemory();
    // dispatch のマクロ文字なら、dispatch の表も写す
    if (dispatchTable(from_rt, from)) |tbl| {
        const items = Runtime.vectorPtr(tbl).items();
        const new_tbl = rt.makeVector(items) catch return th.outOfMemory();
        Runtime.vectorPtr(new_tbl).items()[128] = copyAlist(rt, items[128]) catch return th.outOfMemory();
        if (assoc(ptr(to_rt).dispatch, Value.fromChar(to))) |d| {
            Runtime.consPtr(d).cdr = new_tbl;
        } else {
            const d = rt.cons(Value.fromChar(to), new_tbl) catch return th.outOfMemory();
            ptr(to_rt).dispatch = rt.cons(d, ptr(to_rt).dispatch) catch return th.outOfMemory();
        }
    }
    return rt.t;
}

const case_names = [_][]const u8{ "UPCASE", "DOWNCASE", "PRESERVE", "INVERT" };

/// (readtable-case readtable)
pub fn readtableCase(th: *Thread, args: []const Value) Value {
    if (!isReadtable(args[0])) return th.typeError(args[0], cl(th, "READTABLE"));
    return th.rt.internKeyword(case_names[@backingInt(caseOf(args[0]))]) catch th.outOfMemory();
}

/// (zl-sys:%set-readtable-case readtable value)：(setf readtable-case)
pub fn setReadtableCase(th: *Thread, args: []const Value) Value {
    const tv = args[0];
    if (!isReadtable(tv)) return th.typeError(tv, cl(th, "READTABLE"));
    if (!checkMutable(th, tv)) return Value.unwind;
    for (case_names, 0..) |n, i| {
        if (args[1] == (th.rt.internKeyword(n) catch return th.outOfMemory())) {
            ptr(tv).header.aux = @intCast(i);
            return args[1];
        }
    }
    return th.typeError(args[1], cl(th, "SYMBOL"));
}

/// 組み込みの働きの関数の本体：(関数 stream char [arg])。ストリームの今の位置から、その働きで読む
fn builtinImpl(comptime k: Builtin) fn (*Thread, []const Value) Value {
    return struct {
        fn f(th: *Thread, args: []const Value) Value {
            return @import("../primitives/streams.zig").readBuiltin(th, args, k);
        }
    }.f;
}
