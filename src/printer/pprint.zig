//! pretty printing の印字（Phase 24 の P24d）。SBCL 2.6.7 の src/code/print.lisp の output-object と、
//! src/code/pprint.lisp（どちらも public domain）の pprint-logical-block・pprint-dispatch・標準の印字関数を移植した。
//!   - *print-pretty* が真のとき、オブジェクトは outputObject で書く：*print-circle*（2回の走査と論理ブロックの印）、
//!     pprint-dispatch の表の関数、なければ普通の印字（cons・ベクタは要素を outputObject で書く）。
//!   - 論理ブロックは pretty stream（pretty.zig）の上で行う。pretty stream でないストリームに書くときは、
//!     そのストリームに書き出す pretty stream を作り、書き終えたら残りを書き出す（SBCL の with-pretty-stream）。
//!   - 標準の印字関数（let・defun などの形）は、SBCL と同じ format の制御文字列を、format.zig で解釈して書く。

const std = @import("std");
const Value = @import("../values/value.zig").Value;
const Thread = @import("../runtime/thread.zig").Thread;
const Runtime = @import("../runtime/runtime.zig").Runtime;
const object = @import("../values/object.zig");
const function = @import("../runtime/function.zig");
const printer = @import("printer.zig");
const pretty = @import("pretty.zig");
const streams = @import("../primitives/streams.zig");
const arrays = @import("../primitives/arrays.zig");
const numbers = @import("../primitives/numbers.zig");
const format = @import("../primitives/format.zig");

pub const Fail = error{Lisp};

// ---------------------------------------------------------------------------
// *print-circle* の状態（SBCL の *circularity-hash-table* と *circularity-counter*）

/// 表の値：t（output-object で一度見た）・logical_block（論理ブロックで一度見た）・logical_block_circular・
/// zero（2回以上現れるが、まだ番号がない）・番号（正）
const Mark = union(enum) { t, logical_block, logical_block_circular, zero, label: i64 };

pub const Circle = struct {
    table: std.AutoHashMapUnmanaged(u64, Mark) = .empty,
    /// null なら1回目の走査（集める）、数なら2回目（書く）
    counter: ?i64 = null,
};

const CheckResult = union(enum) { none, initiate, seen, label: i64 };

fn uniquelyIdentified(v: Value) bool {
    if (numbers.isNumber(v) or v.isChar()) return true;
    if (v == Value.nil) return true;
    if (v.isOther() and Runtime.kindOf(v) == .symbol) return pkgOf(v) != Value.nil;
    return false;
}

fn compoundObject(v: Value) bool {
    if (v.isCons()) return true;
    if (v.isOther()) return switch (Runtime.kindOf(v) orelse return false) {
        .simple_vector, .array => !arrays.isStringLike(v),
        else => false,
    };
    return false;
}

fn circleOn(th: *Thread) bool {
    return th.rt.symbolPtr(th.rt.syms.@"*print-circle*").value != Value.nil;
}

/// SBCL の check-for-circularity（mode は .t か .logical_block）
fn checkForCircularity(th: *Thread, v: Value, assign: bool, mode: enum { t, logical_block }) Fail!CheckResult {
    if (!circleOn(th)) return .none;
    const c = th.pp_circle orelse return .initiate;
    const gpa = th.rt.gpa;
    const key = v.raw();
    if (c.counter == null) {
        const g = c.table.getOrPut(gpa, key) catch return oom(th);
        if (!g.found_existing) {
            g.value_ptr.* = if (mode == .logical_block) .logical_block else .t;
            return .none;
        }
        switch (g.value_ptr.*) {
            .logical_block => {
                g.value_ptr.* = .logical_block_circular;
                return .seen;
            },
            .t => {
                if (mode == .logical_block) {
                    g.value_ptr.* = .logical_block;
                    return .none;
                }
                g.value_ptr.* = .zero;
                return .seen;
            },
            .zero, .logical_block_circular, .label => return .seen,
        }
    }
    const ptr = c.table.getPtr(key) orelse return .none;
    switch (ptr.*) {
        .t, .logical_block => return .none,
        .logical_block_circular => {
            if (!assign and mode == .logical_block) return .seen;
            if (assign and mode == .logical_block) {
                c.counter.? += 1;
                ptr.* = .{ .label = c.counter.? };
                return .{ .label = c.counter.? };
            }
            return .none;
        },
        .zero => {
            if (assign) {
                c.counter.? += 1;
                ptr.* = .{ .label = c.counter.? };
                return .{ .label = c.counter.? };
            }
            return .seen;
        },
        .label => |n| return .{ .label = -n },
    }
}

/// SBCL の handle-circularity：真なら続けて書く
fn handleCircularity(th: *Thread, r: CheckResult, stream: Value) Fail!bool {
    switch (r) {
        .none => return true,
        .initiate => return true,
        .seen => return false,
        .label => |n| {
            var buf: [32]u8 = undefined;
            const text = std.fmt.bufPrint(&buf, "#{d}{c}", .{ @abs(n), @as(u8, if (n < 0) '#' else '=') }) catch unreachable;
            try emit(th, stream, text);
            return n > 0;
        },
    }
}

/// シンボルのホームパッケージ（オブジェクト）
fn pkgOf(v: Value) Value {
    const so: *object.Symbol = @ptrCast(@alignCast(v.pointer()));
    return so.package;
}

fn oom(th: *Thread) Fail {
    _ = th.outOfMemory();
    return error.Lisp;
}

fn emit(th: *Thread, stream: Value, bytes: []const u8) Fail!void {
    if (!streams.emit(th, stream, bytes)) return error.Lisp;
}

fn sym(th: *Thread, name: []const u8) Value {
    return (th.rt.findSymbol(th.rt.cl, name) orelse unreachable).symbol;
}

fn special(th: *Thread, s: Value) Value {
    return th.rt.symbolPtr(s).value;
}

fn prettyOn(th: *Thread) bool {
    return special(th, th.rt.syms.@"*print-pretty*") != Value.nil;
}

fn readablyOn(th: *Thread) bool {
    return special(th, th.rt.syms.@"*print-readably*") != Value.nil;
}

// ---------------------------------------------------------------------------
// output-object

/// *print-pretty* が真のときの印字（SBCL の output-object）
pub fn outputObject(th: *Thread, stream: Value, v: Value) Fail!void {
    if (!circleOn(th) or uniquelyIdentified(v)) return handleIt(th, stream, v);
    if (th.pp_circle != null or compoundObject(v)) return checkIt(th, stream, v);
    return handleIt(th, stream, v);
}

fn checkIt(th: *Thread, stream: Value, v: Value) Fail!void {
    const r = try checkForCircularity(th, v, true, .t);
    if (r == .initiate) {
        // 1回目：何も書かないストリームで走査して、共有されているものに印を付ける。2回目：番号を付けて書く
        var c: Circle = .{};
        defer c.table.deinit(th.rt.gpa);
        th.pp_circle = &c;
        defer th.pp_circle = null;
        const sink = streams.makeNullOutput(th) orelse return error.Lisp;
        try checkIt(th, sink, v);
        c.counter = 0;
        return checkIt(th, stream, v);
    }
    if (r == .none) return handleIt(th, stream, v);
    if (try handleCircularity(th, r, stream)) try handleIt(th, stream, v);
}

fn handleIt(th: *Thread, stream: Value, v: Value) Fail!void {
    if (prettyOn(th)) {
        if (try dispatch(th, v, currentTable(th))) |f| return withPrettyStream(th, stream, .{ .call = .{ .f = f, .obj = v } });
    }
    return outputUgly(th, stream, v);
}

/// pretty printing の関数がないときの印字（SBCL の output-ugly-object）。cons とベクタの要素は outputObject で書く
fn outputUgly(th: *Thread, stream: Value, v: Value) Fail!void {
    if (v.isCons()) return uglyList(th, stream, v);
    // 配列の要素も outputObject で書く（*print-circle* の番号を外側と共有する。Codex P24 #2）
    if (v.isOther() and (readablyOn(th) or special(th, th.rt.syms.@"*print-array*") != Value.nil)) if (Runtime.kindOf(v)) |kind| switch (kind) {
        .simple_vector => return uglyVector(th, stream, Runtime.vectorPtr(v).items()),
        .array => {
            const ar: *object.Array = @ptrCast(@alignCast(v.pointer()));
            const dims = ar.dims();
            const is_string = Runtime.kindOf(ar.data) == .string;
            if (dims.len == 1 and !is_string) {
                const n = if (ar.header.flags & object.Array.has_fill_pointer != 0) ar.fill_pointer else dims[0];
                return uglyVector(th, stream, Runtime.vectorPtr(ar.data).items()[0..n]);
            }
            if (dims.len != 1) {
                if (readablyOn(th) and !printer.readablyPrintable(dims, is_string)) return readableArrayForm(th, stream, ar);
                if (!is_string) {
                    var buf: [24]u8 = undefined;
                    try emit(th, stream, std.fmt.bufPrint(&buf, "#{d}A", .{dims.len}) catch unreachable);
                    var index: usize = 0;
                    return uglyAxis(th, stream, Runtime.vectorPtr(ar.data).items(), dims, &index);
                }
            }
        },
        else => {},
    };
    // condition・restart：Lisp の印字の関数（zl-sys::%print-record。boot.lisp）で書く（Phase 25）
    if (v.isOther() and Runtime.kindOf(v) == .record) {
        const f = th.rt.symbolPtr(th.rt.sys_print_record).function;
        if (f.isFunctionPointer()) {
            var argv: [2]Value = .{ v, stream };
            if (th.call(f, &argv) == Value.unwind) return error.Lisp;
            return;
        }
    }
    // アトム：今の印字の変数で書く（*print-circle* の番号は outputObject が付ける）
    var buf: std.Io.Writer.Allocating = .init(th.rt.gpa);
    defer buf.deinit();
    var s = printer.Settings.current(th.rt, null);
    s.circle = false;
    var bad: Value = Value.nil;
    printer.writeObject(th.rt, &buf.writer, v, s, &bad) catch |err| switch (err) {
        error.NotReadable => {
            _ = th.signal(.print_not_readable, "読み戻せる形で印字できません", bad, Value.unbound);
            return error.Lisp;
        },
        error.WriteFailed => return oom(th),
    };
    return emit(th, stream, buf.written());
}

fn levelExceeded(th: *Thread) bool {
    if (readablyOn(th)) return false;
    const l = special(th, th.rt.syms.@"*print-level*");
    return l.isFixnum() and l.asFixnum() >= 0 and th.pp_level >= @as(usize, @intCast(l.asFixnum()));
}

fn lengthLimit(th: *Thread) ?usize {
    if (readablyOn(th)) return null;
    const l = special(th, th.rt.syms.@"*print-length*");
    return if (l.isFixnum() and l.asFixnum() >= 0) @intCast(l.asFixnum()) else null;
}

fn uglyList(th: *Thread, stream: Value, v: Value) Fail!void {
    if (levelExceeded(th)) return emit(th, stream, "#");
    th.pp_level += 1;
    defer th.pp_level -= 1;
    try emit(th, stream, "(");
    var x = v;
    var i: usize = 0;
    while (true) {
        if (lengthLimit(th)) |l| if (i >= l) {
            try emit(th, stream, "...");
            break;
        };
        try outputObject(th, stream, Runtime.consPtr(x).car);
        i += 1;
        x = Runtime.consPtr(x).cdr;
        if (x == Value.nil) break;
        if (!x.isCons() or (try checkForCircularity(th, x, false, .t)) != .none) {
            try emit(th, stream, " . ");
            try outputObject(th, stream, x);
            break;
        }
        try emit(th, stream, " ");
    }
    try emit(th, stream, ")");
}

fn uglyVector(th: *Thread, stream: Value, items: []const Value) Fail!void {
    if (levelExceeded(th)) return emit(th, stream, "#");
    th.pp_level += 1;
    defer th.pp_level -= 1;
    try emit(th, stream, "#(");
    for (items, 0..) |x, i| {
        if (i > 0) try emit(th, stream, " ");
        if (lengthLimit(th)) |l| if (i >= l) {
            try emit(th, stream, "...");
            break;
        };
        try outputObject(th, stream, x);
    }
    try emit(th, stream, ")");
}

/// 多次元の配列の1つの軸（要素の型が T。SBCL の sub-output-array-guts）
fn uglyAxis(th: *Thread, stream: Value, items: []const Value, dims: []const usize, index: *usize) Fail!void {
    if (dims.len == 0) {
        const x = items[index.*];
        index.* += 1;
        return outputObject(th, stream, x);
    }
    var rest: usize = 1;
    for (dims[1..]) |d| rest *= d;
    if (levelExceeded(th)) {
        index.* += dims[0] * rest;
        return emit(th, stream, "#");
    }
    th.pp_level += 1;
    defer th.pp_level -= 1;
    try emit(th, stream, "(");
    for (0..dims[0]) |i| {
        if (i > 0) try emit(th, stream, " ");
        if (lengthLimit(th)) |l| if (i >= l) {
            try emit(th, stream, "...");
            index.* += (dims[0] - i) * rest;
            break;
        };
        try uglyAxis(th, stream, items, dims[1..], index);
    }
    try emit(th, stream, ")");
}

/// #A(次元 要素の型 . 中身)：#nA で読み戻せない配列を *print-readably* で書く
/// （SBCL の output-unreadable-array-readably：そのリストを作って、ストリームに write する）
fn readableArrayForm(th: *Thread, stream: Value, ar: *object.Array) Fail!void {
    const rt = th.rt;
    const dims = ar.dims();
    const is_string = Runtime.kindOf(ar.data) == .string;
    var index: usize = 0;
    const contents = listifyAxis(rt, ar.data, is_string, dims, &index) catch return oom(th);
    var dim_list = Value.nil;
    var i = dims.len;
    while (i > 0) {
        i -= 1;
        dim_list = rt.cons(Value.fromFixnum(@intCast(dims[i])), dim_list) catch return oom(th);
    }
    const etype = sym(th, if (is_string) "CHARACTER" else "T");
    const form = rt.cons(dim_list, rt.cons(etype, contents) catch return oom(th)) catch return oom(th);
    try emit(th, stream, "#A");
    return outputObject(th, stream, form);
}

// ---------------------------------------------------------------------------
// with-pretty-stream と論理ブロック

const Body = union(enum) {
    /// (関数 ストリーム オブジェクト)
    call: struct { f: Value, obj: Value },
    /// 論理ブロック（pprint-logical-block）
    block: struct { obj: Value, obj_supplied: bool, prefix: ?[]const u21, per_line: bool, suffix: []const u21, f: Value },
    /// 組み込みの印字（Zig の関数）
    builtin: struct { k: Std, obj: Value },
    /// pprint-fill・pprint-linear・pprint-tabular
    list: struct { obj: Value, colon: bool, style: NewlineStyle },
    /// Zig の本体の論理ブロック（format の ~<…~:>）
    zblock: struct { obj: Value, prefix: []const u21, per_line: bool, suffix: []const u21, body: BlockBody },
};

pub fn prettyState(s: Value) ?*pretty.State {
    return streams.prettyStateOf(s);
}

/// stream が pretty stream ならそのまま、でなければそこに書き出す pretty stream を作って body を行う（SBCL の with-pretty-stream）
fn withPrettyStream(th: *Thread, stream: Value, body: Body) Fail!void {
    if (prettyState(stream) != null) return runBody(th, stream, body);
    const col = streams.columnOf(th, stream) orelse 0;
    const ps = streams.makePrettyStream(th, stream, col) orelse return error.Lisp;
    defer streams.closePrettyStream(th, ps);
    try runBody(th, ps, body);
    const st = prettyState(ps).?;
    try st.forceOutput();
}

fn runBody(th: *Thread, ps: Value, body: Body) Fail!void {
    switch (body) {
        .call => |c| {
            if (stdOf(th, c.f)) |k| return runStd(th, ps, k, c.obj);
            var argv: [2]Value = .{ ps, c.obj };
            if (th.call(c.f, &argv) == Value.unwind) return error.Lisp;
        },
        .builtin => |b| return runStd(th, ps, b.k, b.obj),
        .list => |l| return listBlock(th, ps, l.obj, l.colon, l.style),
        .zblock => |z| return logicalBlock(th, ps, z.obj, true, z.prefix, z.per_line, z.suffix, z.body),
        .block => |b| return logicalBlock(th, ps, b.obj, b.obj_supplied, b.prefix, b.per_line, b.suffix, .{ .lisp = b.f }),
    }
}

/// format の ~<…~:>：stream（pretty stream でなければ、そこに書き出す pretty stream を作る）に論理ブロックを書く
pub fn formatLogicalBlock(th: *Thread, stream: Value, obj: Value, prefix: []const u21, per_line: bool, suffix: []const u21, body: BlockBody) Fail!void {
    return withPrettyStream(th, stream, .{ .zblock = .{ .obj = obj, .prefix = prefix, .per_line = per_line, .suffix = suffix, .body = body } });
}

/// 論理ブロックの本体：Lisp の関数（stream list state）か、Zig の関数
pub const BlockBody = union(enum) {
    lisp: Value,
    zig: struct { ctx: *anyopaque, f: *const fn (ctx: *anyopaque, th: *Thread, ps: Value, state: Value) Fail!void },
};

/// SBCL の call-logical-block-printer（ps は pretty stream）
pub fn logicalBlock(th: *Thread, ps: Value, obj: Value, obj_supplied: bool, prefix: ?[]const u21, per_line: bool, suffix: []const u21, body: BlockBody) Fail!void {
    const quasi = obj.isCons() and Runtime.consPtr(obj).car == th.rt.sys_quasiquote and singleton(Runtime.consPtr(obj).cdr);
    if (obj_supplied and (!isList(obj) or quasi)) return outputObject(th, ps, obj);
    // 状態：(数 . ストリーム)。pprint-pop が数える
    const state = th.rt.cons(Value.fromFixnum(0), ps) catch return oom(th);
    if (obj_supplied and circleOn(th) and !uniquelyIdentified(obj) and th.pp_circle != null) {
        const r = try checkForCircularity(th, obj, true, .logical_block);
        if (r != .none) {
            if (try handleCircularity(th, r, ps)) try descend(th, ps, obj, prefix, per_line, suffix, body, state);
            return;
        }
        return descend(th, ps, obj, prefix, per_line, suffix, body, state);
    }
    if (obj_supplied and circleOn(th) and !uniquelyIdentified(obj) and th.pp_circle == null) {
        // 走査を始める（SBCL の with-circularity-detection の3つ目の場合）
        var c: Circle = .{};
        defer c.table.deinit(th.rt.gpa);
        th.pp_circle = &c;
        defer th.pp_circle = null;
        {
            const sink = streams.makeNullOutput(th) orelse return error.Lisp;
            const sps = streams.makePrettyStream(th, sink, 0) orelse return error.Lisp;
            defer streams.closePrettyStream(th, sps);
            const st2 = th.rt.cons(Value.fromFixnum(0), sps) catch return oom(th);
            try descend(th, sps, obj, prefix, per_line, suffix, body, st2);
        }
        c.counter = 0;
        const r = try checkForCircularity(th, obj, true, .logical_block);
        if (r != .none) _ = try handleCircularity(th, r, ps);
        return descend(th, ps, obj, prefix, per_line, suffix, body, state);
    }
    return descend(th, ps, obj, prefix, per_line, suffix, body, state);
}

fn descend(th: *Thread, ps: Value, obj: Value, prefix: ?[]const u21, per_line: bool, suffix: []const u21, body: BlockBody, state: Value) Fail!void {
    if (levelExceeded(th)) return emit(th, ps, "#");
    th.pp_level += 1;
    defer th.pp_level -= 1;
    const st = prettyState(ps).?;
    try st.startLogicalBlock(prefix, per_line, suffix);
    switch (body) {
        .lisp => |f| {
            var argv: [3]Value = .{ ps, obj, state };
            if (th.call(f, &argv) == Value.unwind) return error.Lisp;
        },
        .zig => |z| try z.f(z.ctx, th, ps, state),
    }
    try st.endLogicalBlock();
}

fn isList(v: Value) bool {
    return v == Value.nil or v.isCons();
}

fn singleton(v: Value) bool {
    return v.isCons() and Runtime.consPtr(v).cdr == Value.nil;
}

/// SBCL の pprint-length-check：続けて書くなら真（state の数を増やす）。リストでない尾・*print-length*・循環なら書いて偽
pub fn lengthCheck(th: *Thread, obj: Value, state: Value) Fail!bool {
    const stream = Runtime.consPtr(state).cdr;
    const quasi = obj.isCons() and Runtime.consPtr(obj).car == th.rt.sys_quasiquote and singleton(Runtime.consPtr(obj).cdr);
    if (!isList(obj) or quasi) {
        try emit(th, stream, ". ");
        try outputObject(th, stream, obj);
        return false;
    }
    const count: usize = @intCast(Runtime.consPtr(state).car.asFixnum());
    if (lengthLimit(th)) |l| if (count == l) {
        try emit(th, stream, "...");
        return false;
    };
    if (obj != Value.nil and count > 0 and (try checkForCircularity(th, obj, false, .logical_block)) != .none) {
        try emit(th, stream, ". ");
        try outputObject(th, stream, obj);
        return false;
    }
    Runtime.consPtr(state).car = Value.fromFixnum(@intCast(count + 1));
    return true;
}

/// SBCL の pprint-length-check*（オブジェクトのない論理ブロック）
pub fn lengthCheckStar(th: *Thread, state: Value) Fail!bool {
    const stream = Runtime.consPtr(state).cdr;
    const count: usize = @intCast(Runtime.consPtr(state).car.asFixnum());
    if (lengthLimit(th)) |l| if (count == l) {
        try emit(th, stream, "...");
        return false;
    };
    Runtime.consPtr(state).car = Value.fromFixnum(@intCast(count + 1));
    return true;
}

// ---------------------------------------------------------------------------
// pprint-dispatch の表（object.PprintDispatch）。entries は ((優先度 型 関数) …)（優先度の高い順）、
// cons_entries は ((シンボル 優先度 型 関数) …)。initial なら標準の表のまま（Zig で直接振り分ける）

pub fn isTable(v: Value) bool {
    return v.isOther() and Runtime.kindOf(v) == .pprint_dispatch;
}

pub fn tablePtr(v: Value) *object.PprintDispatch {
    return @ptrCast(@alignCast(v.pointer()));
}

fn currentTable(th: *Thread) Value {
    const v = special(th, th.rt.syms.@"*print-pprint-dispatch*");
    return if (isTable(v)) v else Value.nil;
}

/// 標準の印字関数（SBCL の pprint-array・pprint-let など）
pub const Std = enum(u8) {
    none,
    array,
    call_form,
    fill,
    linear,
    tabular,
    quote,
    unquote,
    lambda,
    declare,
    block,
    flet,
    @"if",
    let,
    progn,
    progv,
    setq,
    tagbody,
    case,
    typecase,
    defun,
    defmethod,
    defpackage,
    destructuring_bind,
    do,
    dolist,
    loop,
    prog2,
    prog,
    lambda_list,
    fun_call,
    spread_fun_call,
};

/// 標準の表の cons の項目（SBCL の !pprint-cold-init と同じ組み合わせ）
const magic_forms = [_]struct { names: []const []const u8, k: Std }{
    .{ .names = &.{"LAMBDA"}, .k = .lambda },
    .{ .names = &.{ "DECLARE", "DECLAIM" }, .k = .declare },
    .{ .names = &.{ "BLOCK", "CATCH", "RETURN-FROM", "THROW", "EVAL-WHEN", "MULTIPLE-VALUE-CALL", "MULTIPLE-VALUE-PROG1", "UNWIND-PROTECT" }, .k = .block },
    .{ .names = &.{ "FLET", "LABELS", "MACROLET" }, .k = .flet },
    .{ .names = &.{ "FUNCTION", "QUOTE" }, .k = .quote },
    .{ .names = &.{"IF"}, .k = .@"if" },
    .{ .names = &.{ "LET", "LET*", "SYMBOL-MACROLET" }, .k = .let },
    .{ .names = &.{ "LOCALLY", "PROGN" }, .k = .progn },
    .{ .names = &.{"PROGV"}, .k = .progv },
    .{ .names = &.{ "SETQ", "PSETQ", "SETF", "PSETF" }, .k = .setq },
    .{ .names = &.{"TAGBODY"}, .k = .tagbody },
    .{ .names = &.{ "CASE", "CCASE", "ECASE" }, .k = .case },
    .{ .names = &.{ "CTYPECASE", "ETYPECASE", "TYPECASE" }, .k = .typecase },
    .{ .names = &.{ "DEFCONSTANT", "DEFPARAMETER", "DEFSTRUCT", "DEFVAR" }, .k = .block },
    .{ .names = &.{ "DEFINE-MODIFY-MACRO", "DEFINE-SETF-EXPANDER", "DEFMACRO", "DEFSETF", "DEFTYPE", "DEFUN" }, .k = .defun },
    .{ .names = &.{"DEFMETHOD"}, .k = .defmethod },
    .{ .names = &.{"DEFPACKAGE"}, .k = .defpackage },
    .{ .names = &.{"DESTRUCTURING-BIND"}, .k = .destructuring_bind },
    .{ .names = &.{ "DO", "DO*" }, .k = .do },
    .{ .names = &.{ "DO-ALL-SYMBOLS", "DO-EXTERNAL-SYMBOLS", "DO-SYMBOLS", "DOLIST", "DOTIMES" }, .k = .dolist },
    .{ .names = &.{"LOOP"}, .k = .loop },
    .{ .names = &.{ "MULTIPLE-VALUE-BIND", "PROG2" }, .k = .prog2 },
    .{ .names = &.{ "MULTIPLE-VALUE-SETQ", "PROG1", "PPRINT-LOGICAL-BLOCK", "PRINT-UNREADABLE-OBJECT" }, .k = .block },
    .{ .names = &.{ "PROG", "PROG*" }, .k = .prog },
    .{ .names = &.{ "STEP", "TIME" }, .k = .progn },
    .{ .names = &.{ "UNLESS", "WHEN" }, .k = .block },
    .{ .names = &.{ "WITH-COMPILATION-UNIT", "WITH-SIMPLE-RESTART", "WITH-HASH-TABLE-ITERATOR", "WITH-PACKAGE-ITERATOR", "WITH-INPUT-FROM-STRING", "WITH-OUTPUT-TO-STRING", "WITH-OPEN-FILE", "WITH-OPEN-STREAM" }, .k = .block },
    .{ .names = &.{"WITH-STANDARD-IO-SYNTAX"}, .k = .progn },
};

/// 標準の表での振り分け（SBCL の初めの項目と、cons の特別な形）
fn standardDispatch(th: *Thread, v: Value) Std {
    const rt = th.rt;
    if (v.isCons()) {
        const head = Runtime.consPtr(v).car;
        if (head == rt.sys_quasiquote) return .quote;
        if (head.isOther() and Runtime.kindOf(head) == .symbol) {
            if (isUnquote(th, head)) return .unquote;
            if (head.isOther() and pkgOf(head) == rt.cl.obj) {
                const name = symbolNameUtf8(rt, head);
                for (magic_forms) |m| for (m.names) |n| if (std.mem.eql(u8, n, name)) return m.k;
            }
            if (fboundp(rt, head)) return .call_form;
        }
        return .fill;
    }
    if (v.isOther()) switch (Runtime.kindOf(v) orelse return .none) {
        .simple_vector => return .array,
        .array => return if (arrays.isStringLike(v)) .none else .array,
        else => {},
    };
    return .none;
}

var name_buf: [64]u8 = undefined;

fn symbolNameUtf8(rt: *Runtime, s: Value) []const u8 {
    const name = rt.symbolPtr(s).name;
    var w: std.Io.Writer = .fixed(&name_buf);
    Runtime.writeStringUtf8(name, &w) catch return "";
    return w.buffered();
}

fn isUnquote(th: *Thread, head: Value) bool {
    const rt = th.rt;
    if (pkgOf(head) != rt.sys.obj) return false;
    const n = symbolNameUtf8(rt, head);
    return std.mem.eql(u8, n, "UNQUOTE") or std.mem.eql(u8, n, "UNQUOTE-SPLICING") or std.mem.eql(u8, n, "UNQUOTE-NSPLICING");
}

fn fboundp(rt: *Runtime, s: Value) bool {
    const so = rt.symbolPtr(s);
    return so.function != Value.unbound and so.header.flags & object.SymbolFlags.unimplemented == 0;
}

/// オブジェクトの pretty printing の関数（なければ null）。Lisp の関数か、標準の関数の値
fn dispatch(th: *Thread, v: Value, table: Value) Fail!?Value {
    if (table == Value.nil) return null;
    const t = tablePtr(table);
    if (t.header.flags & object.PprintDispatch.initial_flag != 0) {
        const k = standardDispatch(th, v);
        if (k == .none) return null;
        return stdFunction(th, k);
    }
    // cons の特別な形（car のシンボル）と、型の項目（優先度の高い順）
    var cons_entry: ?Value = null;
    if (v.isCons()) {
        var x = t.cons_entries;
        const head = Runtime.consPtr(v).car;
        while (x.isCons()) : (x = Runtime.consPtr(x).cdr) {
            const e = Runtime.consPtr(x).car;
            if (Runtime.consPtr(e).car == head) {
                cons_entry = Runtime.consPtr(e).cdr;
                break;
            }
        }
    }
    var x = t.entries;
    while (x.isCons()) : (x = Runtime.consPtr(x).cdr) {
        const e = Runtime.consPtr(x).car; // (優先度 型 関数)
        if (cons_entry) |ce| if (priorityLess(th, e, ce)) return entryFunction(ce);
        if (try typep(th, v, listNth(e, 1))) return entryFunction(e);
    }
    if (cons_entry) |ce| return entryFunction(ce);
    return null;
}

fn listNth(l: Value, n: usize) Value {
    var x = l;
    for (0..n) |_| x = Runtime.consPtr(x).cdr;
    return Runtime.consPtr(x).car;
}

fn entryFunction(e: Value) Value {
    return listNth(e, 2);
}

fn priorityLess(th: *Thread, a: Value, b: Value) bool {
    const pa = Runtime.consPtr(a).car;
    const pb = Runtime.consPtr(b).car;
    const r = numbers.compare2(th, .lt, pa, pb);
    return r == th.rt.t;
}

// ---------------------------------------------------------------------------
// 型の判定（set-pprint-dispatch の型指定子。src/primitives/types.zig）

fn typep(th: *Thread, v: Value, spec: Value) Fail!bool {
    return @import("../primitives/types.zig").typep(th, v, spec);
}

// ---------------------------------------------------------------------------
// 標準の印字関数

fn stdFunction(th: *Thread, k: Std) Value {
    return th.rt.pprint_builtins[@backingInt(k)];
}

fn stdOf(th: *Thread, f: Value) ?Std {
    if (!f.isFunctionPointer()) return null;
    for (th.rt.pprint_builtins, 0..) |b, i| if (i != 0 and b == f) return @fromBackingInt(@intCast(i));
    return null;
}

/// 制御文字列を、引数（リスト1つ）で解釈する（SBCL の (funcall (formatter "…") stream list)）
fn fmt(th: *Thread, ps: Value, control: []const u8, list: Value) Fail!void {
    if (!format.formatToStream(th, ps, control, &.{list})) return error.Lisp;
}

/// 標準の印字関数を行う（ps は pretty stream）
fn runStd(th: *Thread, ps: Value, k: Std, list: Value) Fail!void {
    switch (k) {
        .none => return outputUgly(th, ps, list),
        .array => return pprintArray(th, ps, list),
        .fill => return listBlock(th, ps, list, true, .fill),
        .linear => return listBlock(th, ps, list, true, .linear),
        .tabular => return listBlock(th, ps, list, true, .{ .tabular = 16 }),
        .quote => return pprintQuote(th, ps, list),
        .unquote => return pprintUnquote(th, ps, list),
        .call_form => return pprintCallForm(th, ps, list),
        .lambda => return fmt(th, ps, "~:<~^~W~^~3I ~:_~/ZILISP-SYSTEM::%PPRINT-LAMBDA-LIST/~1I~@{ ~_~W~}~:>", list),
        .block => return fmt(th, ps, "~:<~^~W~^~3I ~:_~W~1I~@{ ~_~W~}~:>", list),
        .flet => {
            if (list.isCons() and Runtime.consPtr(list).cdr.isCons() and Runtime.consPtr(Runtime.consPtr(list).cdr).cdr.isCons())
                return fmt(th, ps, "~:<~^~W~^ ~@_~:<~@{~:<~^~W~^~3I ~:_~/ZILISP-SYSTEM::%PPRINT-LAMBDA-LIST/~1I~:@_~@{~W~^ ~_~}~:>~^ ~_~}~:>~1I~@:_~@{~W~^ ~_~}~:>", list);
            return listBlock(th, ps, list, true, .space);
        },
        .let => return fmt(th, ps, "~:<~^~W~^ ~@_~:<~@{~:<~^~W~@{ ~_~W~}~:>~^ ~_~}~:>~1I~^~:@_~@{~W~^ ~_~}~:>", list),
        .progn => return listBlock(th, ps, list, true, .linear),
        .progv => return fmt(th, ps, "~:<~^~W~^~3I ~_~W~^ ~_~W~^~1I~@{ ~_~W~}~:>", list),
        .prog2 => return fmt(th, ps, "~:<~^~W~^~3I ~:_~W~^ ~_~W~^~1I~@{ ~_~W~}~:>", list),
        .declare => {
            const rt = th.rt;
            const depth = th.binding_depth;
            defer th.unbindTo(depth);
            const s = rt.intern(rt.sys, "*PPRINT-QUOTE-WITH-SYNTACTIC-SUGAR*") catch return oom(th);
            if (th.bind(s, Value.nil) == Value.unwind) return error.Lisp;
            return fmt(th, ps, "~:<~^~W~^ ~:_~:I~@{~W~^ ~:@_~}~:>", list);
        },
        .setq => return pprintSetq(th, ps, list),
        .tagbody => return pprintTagbody(th, ps, list),
        .case => return fmt(th, ps, "~:<~^~W~^ ~3I~:_~W~1I~@{ ~_~:<~^~:/PPRINT-FILL/~^~@{ ~_~W~}~:>~}~:>", list),
        .typecase => return fmt(th, ps, "~:<~^~W~^ ~3I~:_~W~1I~@{ ~_~:<~^~W~^~@{ ~_~W~}~:>~}~:>", list),
        .defun => return fmt(th, ps, "~:<~^~W~^ ~@_~:I~W~^ ~:_~/ZILISP-SYSTEM::%PPRINT-LAMBDA-LIST/~1I~@{ ~_~W~}~:>", list),
        .defmethod => {
            const l = list;
            if (l.isCons() and Runtime.consPtr(l).cdr.isCons() and Runtime.consPtr(Runtime.consPtr(l).cdr).cdr.isCons() and
                Runtime.consPtr(Runtime.consPtr(Runtime.consPtr(l).cdr).cdr).car.isCons())
                return fmt(th, ps, "~:<~^~W~^ ~@_~:I~W~^ ~:_~/ZILISP-SYSTEM::%PPRINT-LAMBDA-LIST/~1I~@{ ~_~W~}~:>", list);
            return fmt(th, ps, "~:<~^~W~^ ~@_~:I~W~^ ~W~^ ~:_~/ZILISP-SYSTEM::%PPRINT-LAMBDA-LIST/~1I~@{ ~_~W~}~:>", list);
        },
        .defpackage => return fmt(th, ps, "~:<~W~^ ~3I~:_~W~^~1I~@{~:@_~:<~^~W~^ ~:I~@_~@{~W~^ ~_~}~:>~}~:>", list),
        .destructuring_bind => return fmt(th, ps, "~:<~^~W~^~3I ~_~:/ZILISP-SYSTEM::%PPRINT-LAMBDA-LIST/~^ ~_~W~^~1I~@{ ~_~W~}~:>", list),
        .do => return pprintDo(th, ps, list),
        .dolist => return pprintDolist(th, ps, list),
        .loop => {
            const clauses = if (list.isCons()) Runtime.consPtr(list).cdr else Value.nil;
            if (!clauses.isCons() or Runtime.consPtr(clauses).car.isCons()) return fmt(th, ps, "~:<~^~W~^ ~:_~:I~@{~W~^ ~:@_~}~:>", list);
            return pprintExtendedLoop(th, ps, list);
        },
        .prog => return pprintProg(th, ps, list),
        .@"if" => return fmt(th, ps, "~:<~^~W~^ ~:I~W~^ ~:@_~@{~W~^ ~:@_~}~:>", list),
        .fun_call => return fmt(th, ps, "~:<~^~W~^ ~:_~:I~@{~W~^ ~:_~}~:>", list),
        .spread_fun_call => return fmt(th, ps, "~:<~^~W~^ ~:_~:I~@{~W~^ ~:@_~}~:>", list),
        .lambda_list => return pprintLambdaList(th, ps, list),
    }
}

fn pst(ps: Value) *pretty.State {
    return prettyState(ps).?;
}

const NewlineStyle = union(enum) { fill, linear, space, tabular: i64 };

/// pprint-fill・pprint-linear・pprint-tabular（colon なら括弧で囲む）
fn listBlock(th: *Thread, ps: Value, list: Value, colon: bool, style: NewlineStyle) Fail!void {
    const Ctx = struct {
        list: Value,
        style: NewlineStyle,
        fn body(ctx: *anyopaque, t: *Thread, p: Value, state: Value) Fail!void {
            const c: *@This() = @ptrCast(@alignCast(ctx));
            var l = c.list;
            if (l == Value.nil) return;
            while (true) {
                if (!(try lengthCheck(t, l, state))) return;
                const x = Runtime.consPtr(l).car;
                l = Runtime.consPtr(l).cdr;
                try outputObject(t, p, x);
                if (l == Value.nil) return;
                try emit(t, p, " ");
                switch (c.style) {
                    .fill => try pst(p).enqueueNewline(.fill),
                    .linear => try pst(p).enqueueNewline(.linear),
                    .space => {},
                    .tabular => |n| {
                        try pprintTabOn(t, p, .section_relative, 0, n);
                        try pst(p).enqueueNewline(.fill);
                    },
                }
            }
        }
    };
    var ctx: Ctx = .{ .list = list, .style = style };
    const pfx: []const u21 = if (colon) &.{'('} else &.{};
    const sfx: []const u21 = if (colon) &.{')'} else &.{};
    return logicalBlock(th, ps, list, true, pfx, false, sfx, .{ .zig = .{ .ctx = &ctx, .f = Ctx.body } });
}

fn pprintTabOn(th: *Thread, ps: Value, kind: pretty.TabKind, colnum: i64, colinc: i64) Fail!void {
    _ = th;
    try pst(ps).enqueueTab(kind, colnum, colinc);
}

fn pprintArray(th: *Thread, ps: Value, a: Value) Fail!void {
    if (!readablyOn(th) and special(th, th.rt.syms.@"*print-array*") == Value.nil) return outputUgly(th, ps, a);
    const view = arrays.vectorView(a);
    if (view != null) {
        const Ctx = struct {
            a: Value,
            fn body(ctx: *anyopaque, t: *Thread, p: Value, state: Value) Fail!void {
                const c: *@This() = @ptrCast(@alignCast(ctx));
                const v = arrays.vectorView(c.a).?;
                for (0..v.len) |i| {
                    if (i > 0) {
                        try emit(t, p, " ");
                        try pst(p).enqueueNewline(.fill);
                    }
                    if (!(try lengthCheckStar(t, state))) return;
                    try outputObject(t, p, arrays.storageGet(v.data, i));
                }
            }
        };
        var ctx: Ctx = .{ .a = a };
        return logicalBlock(th, ps, Value.nil, false, &.{ '#', '(' }, false, &.{')'}, .{ .zig = .{ .ctx = &ctx, .f = Ctx.body } });
    }
    // 多次元の配列：#nA と、各軸を論理ブロックで
    const ar: *object.Array = @ptrCast(@alignCast(a.pointer()));
    const dims = ar.dims();
    // #nA で読み戻せない配列は #A(次元 要素の型 . 中身) の形で（SBCL の pprint-array も output-ugly-object にする）
    if (readablyOn(th) and !printer.readablyPrintable(dims, Runtime.kindOf(ar.data) == .string)) return readableArrayForm(th, ps, ar);
    var buf: [24]u8 = undefined;
    try emit(th, ps, std.fmt.bufPrint(&buf, "#{d}A", .{dims.len}) catch unreachable);
    return multiDimGuts(th, ps, ar.data, 0, dims);
}

/// 配列の要素を、軸ごとのリストにする（SBCL の listify-array。0次元なら要素そのもの）
fn listifyAxis(rt: *Runtime, data: Value, is_string: bool, dims: []const usize, index: *usize) !Value {
    if (dims.len == 0) {
        const x = if (is_string) Value.fromChar(Runtime.stringPtr(data).charAt(index.*)) else Runtime.vectorPtr(data).items()[index.*];
        index.* += 1;
        return x;
    }
    // 要素を順に作って後ろに付ける（頭は GC から見えるよう、スタックの変数に持つ）
    var head = Value.nil;
    var last = Value.nil;
    for (0..dims[0]) |_| {
        const item = try listifyAxis(rt, data, is_string, dims[1..], index);
        const cell = try rt.cons(item, Value.nil);
        if (head == Value.nil) head = cell else Runtime.consPtr(last).cdr = cell;
        last = cell;
    }
    std.mem.doNotOptimizeAway(head);
    return head;
}

fn multiDimGuts(th: *Thread, ps: Value, data: Value, index: usize, dims: []const usize) Fail!void {
    if (dims.len == 0) return outputObject(th, ps, arrays.storageGet(data, index));
    const Ctx = struct {
        data: Value,
        index: usize,
        dims: []const usize,
        fn body(ctx: *anyopaque, t: *Thread, p: Value, state: Value) Fail!void {
            const c: *@This() = @ptrCast(@alignCast(ctx));
            const dim = c.dims[0];
            if (dim == 0) return;
            const rest = c.dims[1..];
            var step: usize = 1;
            for (rest) |d| step *= d;
            var idx = c.index;
            var count: usize = 0;
            while (true) {
                if (!(try lengthCheckStar(t, state))) return;
                try multiDimGuts(t, p, c.data, idx, rest);
                count += 1;
                if (count == dim) return;
                try emit(t, p, " ");
                try pst(p).enqueueNewline(if (rest.len > 0) .linear else .fill);
                idx += step;
            }
        }
    };
    var ctx: Ctx = .{ .data = data, .index = index, .dims = dims };
    return logicalBlock(th, ps, Value.nil, false, &.{'('}, false, &.{')'}, .{ .zig = .{ .ctx = &ctx, .f = Ctx.body } });
}

fn quoteSugar(th: *Thread) bool {
    const rt = th.rt;
    const s = (rt.findSymbol(rt.sys, "*PPRINT-QUOTE-WITH-SYNTACTIC-SUGAR*") orelse return true).symbol;
    const v = special(th, s);
    return v != Value.nil;
}

fn pprintQuote(th: *Thread, ps: Value, list: Value) Fail!void {
    const rt = th.rt;
    if (list.isCons() and singleton(Runtime.consPtr(list).cdr)) {
        const head = Runtime.consPtr(list).car;
        const sigil: []const u8 = if (head == sym(th, "FUNCTION")) "#'" else if (head == rt.sys_quasiquote) "`" else "'";
        if (head == rt.sys_quasiquote or quoteSugar(th)) {
            try emit(th, ps, sigil);
            return outputObject(th, ps, Runtime.consPtr(Runtime.consPtr(list).cdr).car);
        }
    }
    return listBlock(th, ps, list, true, .fill);
}

/// (zl-sys:unquote x) は ,x、unquote-splicing は ,@x、unquote-nsplicing は ,.x（SBCL の pprint-unquoting-comma）
fn pprintUnquote(th: *Thread, ps: Value, list: Value) Fail!void {
    if (!(list.isCons() and singleton(Runtime.consPtr(list).cdr))) return listBlock(th, ps, list, true, .fill);
    const name = symbolNameUtf8(th.rt, Runtime.consPtr(list).car);
    if (std.mem.eql(u8, name, "UNQUOTE")) {
        try emit(th, ps, ",");
        pst(ps).comma_hook = true;
    } else if (std.mem.eql(u8, name, "UNQUOTE-SPLICING")) try emit(th, ps, ",@") else try emit(th, ps, ",.");
    return outputObject(th, ps, Runtime.consPtr(Runtime.consPtr(list).cdr).car);
}

fn pprintSetq(th: *Thread, ps: Value, list: Value) Fail!void {
    const Outer = struct {
        list: Value,
        fn body(ctx: *anyopaque, t: *Thread, p: Value, state: Value) Fail!void {
            const c: *@This() = @ptrCast(@alignCast(ctx));
            var l = c.list;
            if (l == Value.nil) return;
            if (!(try lengthCheck(t, l, state))) return;
            try outputObject(t, p, Runtime.consPtr(l).car);
            l = Runtime.consPtr(l).cdr;
            if (l == Value.nil) return;
            try emit(t, p, " ");
            if (!isList(Runtime.consPtr(c.list).cdr)) try emit(t, p, ". ");
            try pst(p).enqueueNewline(.miser);
            const Inner = struct {
                list: Value,
                fn body2(ctx2: *anyopaque, t2: *Thread, p2: Value, state2: Value) Fail!void {
                    const c2: *@This() = @ptrCast(@alignCast(ctx2));
                    var l2 = c2.list;
                    while (true) {
                        try pst(p2).enqueueIndent(.block, 2);
                        if (!(try lengthCheck(t2, l2, state2))) return;
                        try outputObject(t2, p2, Runtime.consPtr(l2).car);
                        l2 = Runtime.consPtr(l2).cdr;
                        if (l2 == Value.nil) return;
                        try emit(t2, p2, " ");
                        try pst(p2).enqueueNewline(.fill);
                        try pst(p2).enqueueIndent(.block, 0);
                        if (!(try lengthCheck(t2, l2, state2))) return;
                        try outputObject(t2, p2, Runtime.consPtr(l2).car);
                        l2 = Runtime.consPtr(l2).cdr;
                        if (l2 == Value.nil) return;
                        try emit(t2, p2, " ");
                        try pst(p2).enqueueNewline(.mandatory);
                    }
                }
            };
            var inner: Inner = .{ .list = l };
            try logicalBlock(t, p, l, true, &.{}, false, &.{}, .{ .zig = .{ .ctx = &inner, .f = Inner.body2 } });
        }
    };
    var ctx: Outer = .{ .list = list };
    return logicalBlock(th, ps, list, true, &.{'('}, false, &.{')'}, .{ .zig = .{ .ctx = &ctx, .f = Outer.body } });
}

/// SBCL の pprint-tagbody-guts：残りの各要素（タグは字下げ 0、フォームは 1）
fn tagbodyGuts(th: *Thread, ps: Value, l0: Value, state: Value) Fail!void {
    var l = l0;
    while (l != Value.nil) {
        try emit(th, ps, " ");
        if (!(try lengthCheck(th, l, state))) return;
        const x = Runtime.consPtr(l).car;
        l = Runtime.consPtr(l).cdr;
        try pst(ps).enqueueIndent(.block, if (x.isCons()) 1 else 0);
        try pst(ps).enqueueNewline(.linear);
        try outputObject(th, ps, x);
    }
}

fn pprintTagbody(th: *Thread, ps: Value, list: Value) Fail!void {
    const Ctx = struct {
        list: Value,
        fn body(ctx: *anyopaque, t: *Thread, p: Value, state: Value) Fail!void {
            const c: *@This() = @ptrCast(@alignCast(ctx));
            if (c.list == Value.nil) return;
            if (!(try lengthCheck(t, c.list, state))) return;
            try outputObject(t, p, Runtime.consPtr(c.list).car);
            try tagbodyGuts(t, p, Runtime.consPtr(c.list).cdr, state);
        }
    };
    var ctx: Ctx = .{ .list = list };
    return logicalBlock(th, ps, list, true, &.{'('}, false, &.{')'}, .{ .zig = .{ .ctx = &ctx, .f = Ctx.body } });
}

fn pprintDo(th: *Thread, ps: Value, list: Value) Fail!void {
    const Ctx = struct {
        list: Value,
        fn body(ctx: *anyopaque, t: *Thread, p: Value, state: Value) Fail!void {
            const c: *@This() = @ptrCast(@alignCast(ctx));
            var l = c.list;
            if (l == Value.nil) return;
            if (!(try lengthCheck(t, l, state))) return;
            try outputObject(t, p, Runtime.consPtr(l).car);
            l = Runtime.consPtr(l).cdr;
            if (l == Value.nil) return;
            try emit(t, p, " ");
            try pst(p).enqueueIndent(.current, 0);
            if (!(try lengthCheck(t, l, state))) return;
            try fmt(t, p, "~:<~@{~:<~^~W~^ ~@_~:I~W~@{ ~_~W~}~:>~^~:@_~}~:>", Runtime.consPtr(l).car);
            l = Runtime.consPtr(l).cdr;
            if (l == Value.nil) return;
            try emit(t, p, " ");
            try pst(p).enqueueNewline(.linear);
            if (!(try lengthCheck(t, l, state))) return;
            try listBlock(t, p, Runtime.consPtr(l).car, true, .linear);
            try tagbodyGuts(t, p, Runtime.consPtr(l).cdr, state);
        }
    };
    var ctx: Ctx = .{ .list = list };
    return logicalBlock(th, ps, list, true, &.{'('}, false, &.{')'}, .{ .zig = .{ .ctx = &ctx, .f = Ctx.body } });
}

fn pprintDolist(th: *Thread, ps: Value, list: Value) Fail!void {
    const Ctx = struct {
        list: Value,
        fn body(ctx: *anyopaque, t: *Thread, p: Value, state: Value) Fail!void {
            const c: *@This() = @ptrCast(@alignCast(ctx));
            var l = c.list;
            if (l == Value.nil) return;
            if (!(try lengthCheck(t, l, state))) return;
            try outputObject(t, p, Runtime.consPtr(l).car);
            l = Runtime.consPtr(l).cdr;
            if (l == Value.nil) return;
            try pst(p).enqueueIndent(.block, 3);
            try emit(t, p, " ");
            try pst(p).enqueueNewline(.fill);
            if (!(try lengthCheck(t, l, state))) return;
            try fmt(t, p, "~:<~^~W~^ ~:_~:I~W~@{ ~_~W~}~:>", Runtime.consPtr(l).car);
            try tagbodyGuts(t, p, Runtime.consPtr(l).cdr, state);
        }
    };
    var ctx: Ctx = .{ .list = list };
    return logicalBlock(th, ps, list, true, &.{'('}, false, &.{')'}, .{ .zig = .{ .ctx = &ctx, .f = Ctx.body } });
}

fn pprintProg(th: *Thread, ps: Value, list: Value) Fail!void {
    const Ctx = struct {
        list: Value,
        fn body(ctx: *anyopaque, t: *Thread, p: Value, state: Value) Fail!void {
            const c: *@This() = @ptrCast(@alignCast(ctx));
            var l = c.list;
            if (l == Value.nil) return;
            if (!(try lengthCheck(t, l, state))) return;
            try outputObject(t, p, Runtime.consPtr(l).car);
            l = Runtime.consPtr(l).cdr;
            if (l == Value.nil) return;
            try emit(t, p, " ");
            try pst(p).enqueueNewline(.miser);
            if (!(try lengthCheck(t, l, state))) return;
            try listBlock(t, p, Runtime.consPtr(l).car, true, .fill);
            try tagbodyGuts(t, p, Runtime.consPtr(l).cdr, state);
        }
    };
    var ctx: Ctx = .{ .list = list };
    return logicalBlock(th, ps, list, true, &.{'('}, false, &.{')'}, .{ .zig = .{ .ctx = &ctx, .f = Ctx.body } });
}

const loop_separating = [_][]const u8{ "AND", "WITH", "FOR", "INITIALLY", "FINALLY", "DO", "DOING", "COLLECT", "COLLECTING", "APPEND", "APPENDING", "NCONC", "NCONCING", "COUNT", "COUNTING", "SUM", "SUMMING", "MAXIMIZE", "MAXIMIZING", "MINIMIZE", "MINIMIZING", "IF", "WHEN", "UNLESS", "END", "WHILE", "UNTIL", "REPEAT", "ALWAYS", "NEVER", "THEREIS" };

fn pprintExtendedLoop(th: *Thread, ps: Value, list: Value) Fail!void {
    const Ctx = struct {
        list: Value,
        fn body(ctx: *anyopaque, t: *Thread, p: Value, state: Value) Fail!void {
            const c: *@This() = @ptrCast(@alignCast(ctx));
            var l = c.list;
            if (!(try lengthCheck(t, l, state))) return;
            try outputObject(t, p, Runtime.consPtr(l).car);
            l = Runtime.consPtr(l).cdr;
            if (l == Value.nil) return;
            try emit(t, p, " ");
            try pst(p).enqueueIndent(.current, 0);
            if (!(try lengthCheck(t, l, state))) return;
            try outputObject(t, p, Runtime.consPtr(l).car);
            l = Runtime.consPtr(l).cdr;
            if (l == Value.nil) return;
            try emit(t, p, " ");
            while (true) {
                if (!(try lengthCheck(t, l, state))) return;
                const thing = Runtime.consPtr(l).car;
                l = Runtime.consPtr(l).cdr;
                if (thing == Value.nil or (thing.isOther() and Runtime.kindOf(thing) == .symbol)) {
                    const n = if (thing == Value.nil) "NIL" else symbolNameUtf8(t.rt, thing);
                    for (loop_separating) |s| if (std.mem.eql(u8, s, n)) {
                        try pst(p).enqueueNewline(.mandatory);
                        break;
                    };
                }
                try outputObject(t, p, thing);
                if (l == Value.nil) return;
                try emit(t, p, " ");
            }
        }
    };
    var ctx: Ctx = .{ .list = list };
    return logicalBlock(th, ps, list, true, &.{'('}, false, &.{')'}, .{ .zig = .{ .ctx = &ctx, .f = Ctx.body } });
}

/// マクロのラムダリストの &body の前の引数の数（SBCL の macro-indentation。&body がなければ null）
fn macroIndentation(th: *Thread, head: Value) ?usize {
    const rt = th.rt;
    const so = rt.symbolPtr(head);
    if (so.header.flags & object.SymbolFlags.macro == 0) return null;
    const key = (rt.findSymbol(rt.sys, "%MACRO-LAMBDA-LIST") orelse return null).symbol;
    var p = so.plist;
    var ll: ?Value = null;
    while (p.isCons() and Runtime.consPtr(p).cdr.isCons()) : (p = Runtime.consPtr(Runtime.consPtr(p).cdr).cdr) {
        if (Runtime.consPtr(p).car == key) {
            ll = Runtime.consPtr(Runtime.consPtr(p).cdr).car;
            break;
        }
    }
    var x = ll orelse return null;
    var n: usize = 0;
    const body = sym(th, "&BODY");
    const optional = sym(th, "&OPTIONAL");
    while (x.isCons() and Runtime.consPtr(x).car != body) : (x = Runtime.consPtr(x).cdr) {
        if (Runtime.consPtr(x).car != optional) n += 1;
    }
    if (x == Value.nil) return null;
    return n;
}

fn pprintCallForm(th: *Thread, ps: Value, list: Value) Fail!void {
    const head = Runtime.consPtr(list).car;
    const indentation = macroIndentation(th, head) orelse return fmt(th, ps, "~:<~^~W~^ ~:_~:I~@{~W~^ ~:_~}~:>", list);
    const Ctx = struct {
        list: Value,
        indentation: usize,
        fn body(ctx: *anyopaque, t: *Thread, p: Value, state: Value) Fail!void {
            const c: *@This() = @ptrCast(@alignCast(ctx));
            var l = c.list;
            if (!(try lengthCheck(t, l, state))) return;
            try outputObject(t, p, Runtime.consPtr(l).car);
            l = Runtime.consPtr(l).cdr;
            if (l == Value.nil) return;
            try emit(t, p, " ");
            var indent: usize = 0;
            while (indent < c.indentation) : (indent += 1) {
                if (indent != 0) {
                    try pst(p).enqueueIndent(.block, 3);
                    try pst(p).enqueueNewline(.mandatory);
                }
                if (!(try lengthCheck(t, l, state))) return;
                try outputObject(t, p, Runtime.consPtr(l).car);
                l = Runtime.consPtr(l).cdr;
                if (l == Value.nil) return;
            }
            try pst(p).enqueueIndent(.block, 1);
            try pst(p).enqueueNewline(.mandatory);
            while (true) {
                if (!(try lengthCheck(t, l, state))) return;
                try outputObject(t, p, Runtime.consPtr(l).car);
                l = Runtime.consPtr(l).cdr;
                if (l == Value.nil) return;
                try pst(p).enqueueNewline(.mandatory);
            }
        }
    };
    var ctx: Ctx = .{ .list = list, .indentation = indentation };
    return logicalBlock(th, ps, list, true, &.{'('}, false, &.{')'}, .{ .zig = .{ .ctx = &ctx, .f = Ctx.body } });
}

/// SBCL の pprint-lambda-list
fn pprintLambdaList(th: *Thread, ps: Value, list: Value) Fail!void {
    const Ctx = struct {
        list: Value,
        fn body(ctx: *anyopaque, t: *Thread, p: Value, state: Value) Fail!void {
            const c: *@This() = @ptrCast(@alignCast(ctx));
            var l = c.list;
            const State = enum { required, optional, key };
            var mode: State = .required;
            var first = true;
            while (l != Value.nil) {
                if (!first) try emit(t, p, " ");
                if (!(try lengthCheck(t, l, state))) return;
                const arg = Runtime.consPtr(l).car;
                l = Runtime.consPtr(l).cdr;
                if (arg == sym(t, "&OPTIONAL") or arg == sym(t, "&AUX")) {
                    mode = .optional;
                    try pst(p).enqueueNewline(.linear);
                } else if (arg == sym(t, "&REST") or arg == sym(t, "&BODY")) {
                    mode = .required;
                    try pst(p).enqueueNewline(.linear);
                } else if (arg == sym(t, "&KEY")) {
                    mode = .key;
                    try pst(p).enqueueNewline(.linear);
                } else try pst(p).enqueueNewline(.fill);
                switch (mode) {
                    .required => try listBlock(t, p, arg, true, .linear),
                    .optional, .key => try optionalArg(t, p, arg, mode == .key),
                }
                first = false;
            }
        }
    };
    var ctx: Ctx = .{ .list = list };
    return logicalBlock(th, ps, list, true, &.{'('}, false, &.{')'}, .{ .zig = .{ .ctx = &ctx, .f = Ctx.body } });
}

fn optionalArg(th: *Thread, ps: Value, arg: Value, key: bool) Fail!void {
    const Ctx = struct {
        arg: Value,
        key: bool,
        fn body(ctx: *anyopaque, t: *Thread, p: Value, state: Value) Fail!void {
            const c: *@This() = @ptrCast(@alignCast(ctx));
            var l = c.arg;
            if (l == Value.nil) return;
            if (!(try lengthCheck(t, l, state))) return;
            const first = Runtime.consPtr(l).car;
            l = Runtime.consPtr(l).cdr;
            if (c.key) try listBlock(t, p, first, true, .fill) else try outputObject(t, p, first);
            while (l != Value.nil) {
                try emit(t, p, " ");
                try pst(p).enqueueNewline(.linear);
                if (!(try lengthCheck(t, l, state))) return;
                try outputObject(t, p, Runtime.consPtr(l).car);
                l = Runtime.consPtr(l).cdr;
            }
        }
    };
    var ctx: Ctx = .{ .arg = arg, .key = key };
    return logicalBlock(th, ps, arg, true, &.{'('}, false, &.{')'}, .{ .zig = .{ .ctx = &ctx, .f = Ctx.body } });
}

// ---------------------------------------------------------------------------
// 印字の入口（streams.zig が呼ぶ）

/// *print-pretty* が真のときの prin1・princ・write など：stream に書く
pub fn printTop(th: *Thread, stream: Value, v: Value) bool {
    outputObject(th, stream, v) catch return false;
    return true;
}

// ---------------------------------------------------------------------------
// Lisp の関数（CLHS 22.4）

fn optArg(args: []const Value, i: usize) ?Value {
    return if (i < args.len) args[i] else null;
}

fn kwIs(th: *Thread, v: Value, name: []const u8) bool {
    return v == (th.rt.internKeyword(name) catch return false);
}

/// 出力のストリームの指定子（NIL は *standard-output*、T は *terminal-io*）
fn outStream(th: *Thread, v: ?Value) ?Value {
    return streams.outputDesignator(th, v);
}

/// pretty printing を行うストリームか（pretty stream で、*print-pretty* が真）
fn prettyOnStream(th: *Thread, s: Value) ?*pretty.State {
    if (!prettyOn(th)) return null;
    return prettyState(s);
}

fn wrap(th: *Thread, r: Fail!void) Value {
    r catch return Value.unwind;
    th.mv_count = 1;
    return Value.nil;
}

/// (pprint-newline kind &optional stream)
pub fn pprintNewline(th: *Thread, args: []const Value) Value {
    const k = args[0];
    const kind: pretty.NewlineKind = if (kwIs(th, k, "LINEAR")) .linear else if (kwIs(th, k, "FILL")) .fill else if (kwIs(th, k, "MISER")) .miser else if (kwIs(th, k, "MANDATORY")) .mandatory else return th.typeError(k, sym(th, "SYMBOL"));
    const s = outStream(th, optArg(args, 1)) orelse return Value.unwind;
    const ps = prettyOnStream(th, s) orelse return Value.nil;
    return wrap(th, ps.enqueueNewline(kind));
}

/// (pprint-indent relative-to n &optional stream)
pub fn pprintIndent(th: *Thread, args: []const Value) Value {
    const k = args[0];
    const kind: pretty.IndentKind = if (kwIs(th, k, "BLOCK")) .block else if (kwIs(th, k, "CURRENT")) .current else return th.typeError(k, sym(th, "SYMBOL"));
    const n = args[1];
    if (!numbers.isNumber(n)) return th.typeError(n, sym(th, "REAL"));
    const amount: i64 = if (n.isFixnum()) n.asFixnum() else blk: {
        const t = numbers.truncate(th, &.{n});
        if (t == Value.unwind) return t;
        break :blk if (t.isFixnum()) t.asFixnum() else 0;
    };
    const s = outStream(th, optArg(args, 2)) orelse return Value.unwind;
    const ps = prettyOnStream(th, s) orelse return Value.nil;
    return wrap(th, ps.enqueueIndent(kind, amount));
}

/// (pprint-tab kind colnum colinc &optional stream)
pub fn pprintTab(th: *Thread, args: []const Value) Value {
    const k = args[0];
    const kind: pretty.TabKind = if (kwIs(th, k, "LINE")) .line else if (kwIs(th, k, "LINE-RELATIVE")) .line_relative else if (kwIs(th, k, "SECTION")) .section else if (kwIs(th, k, "SECTION-RELATIVE")) .section_relative else return th.typeError(k, sym(th, "SYMBOL"));
    if (!args[1].isFixnum() or args[1].asFixnum() < 0) return th.typeError(args[1], sym(th, "INTEGER"));
    if (!args[2].isFixnum() or args[2].asFixnum() < 0) return th.typeError(args[2], sym(th, "INTEGER"));
    const s = outStream(th, optArg(args, 3)) orelse return Value.unwind;
    const ps = prettyOnStream(th, s) orelse return Value.nil;
    return wrap(th, ps.enqueueTab(kind, args[1].asFixnum(), args[2].asFixnum()));
}

fn listFn(th: *Thread, args: []const Value, style: NewlineStyle) Value {
    const s = outStream(th, args[0]) orelse return Value.unwind;
    const colon = if (optArg(args, 2)) |c| c != Value.nil else true;
    var sty = style;
    if (style == .tabular) {
        if (optArg(args, 4)) |t| if (t != Value.nil) {
            if (!t.isFixnum()) return th.typeError(t, sym(th, "INTEGER"));
            sty = .{ .tabular = t.asFixnum() };
        };
    }
    return wrap(th, withPrettyStream(th, s, .{ .list = .{ .obj = args[1], .colon = colon, .style = sty } }));
}

/// (pprint-fill stream list &optional colon-p at-sign-p)
pub fn pprintFill(th: *Thread, args: []const Value) Value {
    return listFn(th, args, .fill);
}

/// (pprint-linear stream list &optional colon-p at-sign-p)
pub fn pprintLinear(th: *Thread, args: []const Value) Value {
    return listFn(th, args, .linear);
}

/// (pprint-tabular stream list &optional colon-p at-sign-p tabsize)
pub fn pprintTabular(th: *Thread, args: []const Value) Value {
    return listFn(th, args, .{ .tabular = 16 });
}

/// 標準の印字関数の本体（zl-sys::%PPRINT-LET など）：(関数 stream object &rest noise)
pub fn stdImpl(comptime k: Std) fn (*Thread, []const Value) Value {
    return struct {
        fn f(th: *Thread, args: []const Value) Value {
            const s = outStream(th, args[0]) orelse return Value.unwind;
            return wrap(th, withPrettyStream(th, s, .{ .builtin = .{ .k = k, .obj = args[1] } }));
        }
    }.f;
}

/// (zl-sys::%pprint-logical-block stream object prefix per-line-p suffix 関数 object-supplied-p)：pprint-logical-block の本体。
/// 関数は (stream list state) を受け取る
pub fn sysLogicalBlock(th: *Thread, args: []const Value) Value {
    const s = outStream(th, args[0]) orelse return Value.unwind;
    var arena_state = std.heap.ArenaAllocator.init(th.rt.gpa);
    defer arena_state.deinit();
    const ar = arena_state.allocator();
    const prefix: ?[]const u21 = if (args[2] == Value.nil) null else (charsOf(th, ar, args[2]) orelse return Value.unwind);
    const suffix: []const u21 = charsOf(th, ar, args[4]) orelse return Value.unwind;
    return wrap(th, withPrettyStream(th, s, .{ .block = .{ .obj = args[1], .obj_supplied = args[6] != Value.nil, .prefix = prefix, .per_line = args[3] != Value.nil, .suffix = suffix, .f = args[5] } }));
}

fn charsOf(th: *Thread, ar: std.mem.Allocator, v: Value) ?[]const u21 {
    if (!arrays.isStringLike(v)) {
        _ = th.typeError(v, sym(th, "STRING"));
        return null;
    }
    const view = arrays.vectorView(v).?;
    const str = Runtime.stringPtr(view.data);
    const out = ar.alloc(u21, view.len) catch {
        _ = th.outOfMemory();
        return null;
    };
    for (out, 0..) |*c, i| c.* = str.charAt(i);
    return out;
}

/// (zl-sys::%pprint-length-check list state)：pprint-pop の検査（偽なら論理ブロックを抜ける）
pub fn sysLengthCheck(th: *Thread, args: []const Value) Value {
    const ok = lengthCheck(th, args[0], args[1]) catch return Value.unwind;
    return th.rt.boolean(ok);
}

/// (zl-sys::%pprint-length-check* state)
pub fn sysLengthCheckStar(th: *Thread, args: []const Value) Value {
    const ok = lengthCheckStar(th, args[0]) catch return Value.unwind;
    return th.rt.boolean(ok);
}

// ---------------------------------------------------------------------------
// pprint-dispatch の表の関数

fn makeTable(rt: *Runtime, entries: Value, cons_entries: Value, initial: bool) error{OutOfMemory}!Value {
    const t = try rt.heap.create(object.PprintDispatch, 0);
    t.* = .{ .header = .{ .kind = .pprint_dispatch, .flags = if (initial) object.PprintDispatch.initial_flag else 0 }, .entries = entries, .cons_entries = cons_entries };
    return Value.fromPointer(t, .other);
}

/// 表の写し（項目のリストを写す。cons の項目も）
fn copyTable(rt: *Runtime, from: Value) error{OutOfMemory}!Value {
    const f = tablePtr(from);
    const entries = try copyList(rt, f.entries);
    const cons_entries = try copyList(rt, tablePtr(from).cons_entries);
    return makeTable(rt, entries, cons_entries, tablePtr(from).header.flags & object.PprintDispatch.initial_flag != 0);
}

fn copyList(rt: *Runtime, list: Value) error{OutOfMemory}!Value {
    var out = Value.nil;
    var last = Value.nil;
    var x = list;
    while (x.isCons()) : (x = Runtime.consPtr(x).cdr) {
        const c = try rt.cons(Runtime.consPtr(x).car, Value.nil);
        if (last == Value.nil) out = c else Runtime.consPtr(last).cdr = c;
        last = c;
    }
    return out;
}

const std_field_names = @typeInfo(Std).@"enum".field_names;

/// 標準の印字関数の名前（zl-sys::%PPRINT-LET など）
const std_names = blk: {
    var names: [std_field_names.len][]const u8 = undefined;
    for (std_field_names, 0..) |name, i| {
        var buf: [name.len + 8]u8 = undefined;
        @memcpy(buf[0..8], "%PPRINT-");
        for (name, 0..) |c, j| buf[8 + j] = if (c == '_') '-' else std.ascii.toUpper(c);
        const final = buf;
        names[i] = &final;
    }
    break :blk names;
};

/// 標準の印字関数を作り、標準の表と *print-pprint-dispatch* を作る（Runtime の初期化。primitives.install の後）
pub fn install(rt: *Runtime) error{OutOfMemory}!void {
    inline for (std_field_names, 0..) |_, i| {
        if (i == 0) continue;
        const k: Std = @fromBackingInt(@intCast(i));
        const f = switch (k) {
            // pprint-fill・pprint-linear・pprint-tabular は CL の関数そのもの
            .fill => (rt.findSymbol(rt.cl, "PPRINT-FILL") orelse unreachable).symbol,
            .linear => (rt.findSymbol(rt.cl, "PPRINT-LINEAR") orelse unreachable).symbol,
            .tabular => (rt.findSymbol(rt.cl, "PPRINT-TABULAR") orelse unreachable).symbol,
            else => blk: {
                const s = try rt.intern(rt.sys, std_names[i]);
                rt.symbolPtr(s).function = try function.makeNative(rt, s, stdImpl(k), 2, std.math.maxInt(u32));
                break :blk s;
            },
        };
        rt.pprint_builtins[i] = rt.symbolPtr(f).function;
    }
    // 標準の表：振り分けは Zig で行う（initial）
    const standard = try makeTable(rt, Value.nil, Value.nil, true);
    const sym_std = try rt.intern(rt.sys, "*STANDARD-PPRINT-DISPATCH-TABLE*");
    rt.symbolPtr(sym_std).value = standard;
    rt.symbolPtr(sym_std).header.flags |= object.SymbolFlags.special;
    rt.symbolPtr(rt.syms.@"*print-pprint-dispatch*").value = try copyTable(rt, standard);
    // pprint-declare の中では quote の略記を使わない（(declare (function f)) を #'f と書かない）
    const sugar = try rt.intern(rt.sys, "*PPRINT-QUOTE-WITH-SYNTACTIC-SUGAR*");
    rt.symbolPtr(sugar).value = rt.t;
    rt.symbolPtr(sugar).header.flags |= object.SymbolFlags.special;
}

fn tableArg(th: *Thread, v: ?Value) ?Value {
    const x = v orelse return currentTable(th);
    if (x == Value.nil) {
        const s = (th.rt.findSymbol(th.rt.sys, "*STANDARD-PPRINT-DISPATCH-TABLE*") orelse unreachable).symbol;
        return th.rt.symbolPtr(s).value;
    }
    if (isTable(x)) return x;
    _ = th.typeError(x, sym(th, "SYMBOL"));
    return null;
}

/// (copy-pprint-dispatch &optional table)
pub fn copyPprintDispatch(th: *Thread, args: []const Value) Value {
    const t = tableArg(th, optArg(args, 0)) orelse return Value.unwind;
    return copyTable(th.rt, t) catch th.outOfMemory();
}

/// (pprint-dispatch object &optional table)：関数と found-p
pub fn pprintDispatch(th: *Thread, args: []const Value) Value {
    const t = tableArg(th, optArg(args, 1)) orelse return Value.unwind;
    const f = dispatch(th, args[0], t) catch return Value.unwind;
    th.mv[1] = th.rt.boolean(f != null);
    th.mv_count = 2;
    // 見つからなければ、普通の印字の関数（SBCL は #'output-ugly-object）
    return f orelse th.rt.symbolPtr((th.rt.findSymbol(th.rt.sys, "%OUTPUT-UGLY-OBJECT") orelse unreachable).symbol).function;
}

/// (zl-sys::%output-ugly-object stream object)
pub fn sysOutputUgly(th: *Thread, args: []const Value) Value {
    const s = outStream(th, args[0]) orelse return Value.unwind;
    return wrap(th, outputUgly(th, s, args[1]));
}

/// (set-pprint-dispatch type function &optional priority table)
pub fn setPprintDispatch(th: *Thread, args: []const Value) Value {
    const rt = th.rt;
    const spec = args[0];
    const f = args[1];
    const priority = optArg(args, 2) orelse Value.fromFixnum(0);
    if (!numbers.isNumber(priority)) return th.typeError(priority, sym(th, "REAL"));
    const t = tableArg(th, optArg(args, 3)) orelse return Value.unwind;
    const std_sym = (rt.findSymbol(rt.sys, "*STANDARD-PPRINT-DISPATCH-TABLE*") orelse unreachable).symbol;
    if (t == rt.symbolPtr(std_sym).value) return th.signal(.simple_error, "標準の pprint-dispatch の表は変えられません", t, Value.unbound);
    // 型指定子を確かめる（判定できない指定子は、ここで未実装のエラー。satisfies の関数は呼ばない）
    if (!checkSpec(th, spec)) return Value.unwind;
    if (tablePtr(t).header.flags & object.PprintDispatch.initial_flag != 0) {
        // 標準の項目を、表の項目として展開してから変える
        expandInitial(th, t) catch return th.outOfMemory();
    }
    // (cons (member シンボル…)) は cons の項目
    if (consMemberSymbols(th, spec)) |members| {
        var x = members;
        while (x.isCons()) : (x = Runtime.consPtr(x).cdr) {
            const key = Runtime.consPtr(x).car;
            removeConsEntry(tablePtr(t), key);
            if (f != Value.nil) {
                const e = makeEntry(rt, priority, spec, f) catch return th.outOfMemory();
                const c = rt.cons(key, e) catch return th.outOfMemory();
                tablePtr(t).cons_entries = rt.cons(c, tablePtr(t).cons_entries) catch return th.outOfMemory();
            }
        }
        return Value.nil;
    }
    // 同じ型（equal）の項目を除き、優先度の順に入れる（同じ優先度なら後から入れたものが後ろ）
    var kept = Value.nil;
    var last = Value.nil;
    var x = tablePtr(t).entries;
    while (x.isCons()) : (x = Runtime.consPtr(x).cdr) {
        const e = Runtime.consPtr(x).car;
        if (@import("../primitives/lists.zig").equal2(listNth(e, 1), spec)) continue;
        const c = rt.cons(e, Value.nil) catch return th.outOfMemory();
        if (last == Value.nil) kept = c else Runtime.consPtr(last).cdr = c;
        last = c;
    }
    if (f != Value.nil) {
        const e = makeEntry(rt, priority, spec, f) catch return th.outOfMemory();
        // 優先度が e より低い最初の項目の前に入れる
        var prev = Value.nil;
        var y = kept;
        while (y.isCons()) : (y = Runtime.consPtr(y).cdr) {
            if (priorityLess(th, Runtime.consPtr(y).car, e)) break;
            prev = y;
        }
        const cell = rt.cons(e, y) catch return th.outOfMemory();
        if (prev == Value.nil) kept = cell else Runtime.consPtr(prev).cdr = cell;
    }
    tablePtr(t).entries = kept;
    return Value.nil;
}

/// 判定できる型指定子か（typep を NIL で試す。satisfies は関数を呼ばずに受け付ける）
fn checkSpec(th: *Thread, spec: Value) bool {
    if (spec.isCons() and Runtime.consPtr(spec).car == sym(th, "SATISFIES")) return true;
    if (spec.isCons()) {
        var x = Runtime.consPtr(spec).cdr;
        const h = Runtime.consPtr(spec).car;
        if (h == sym(th, "MEMBER") or h == sym(th, "EQL")) return true;
        if (h == sym(th, "AND") or h == sym(th, "OR") or h == sym(th, "NOT") or h == sym(th, "CONS")) {
            while (x.isCons()) : (x = Runtime.consPtr(x).cdr) if (!checkSpec(th, Runtime.consPtr(x).car)) return false;
            return true;
        }
    }
    _ = typep(th, Value.nil, spec) catch return false;
    return true;
}

fn makeEntry(rt: *Runtime, priority: Value, spec: Value, f: Value) error{OutOfMemory}!Value {
    const c3 = try rt.cons(f, Value.nil);
    const c2 = try rt.cons(spec, c3);
    return rt.cons(priority, c2);
}

fn removeConsEntry(tp: *object.PprintDispatch, key: Value) void {
    var prev = Value.nil;
    var x = tp.cons_entries;
    while (x.isCons()) : (x = Runtime.consPtr(x).cdr) {
        if (Runtime.consPtr(Runtime.consPtr(x).car).car == key) {
            if (prev == Value.nil) tp.cons_entries = Runtime.consPtr(x).cdr else Runtime.consPtr(prev).cdr = Runtime.consPtr(x).cdr;
            return;
        }
        prev = x;
    }
}

/// (cons (member a b …)) か (cons (eql a)) なら、そのシンボルのリスト
fn consMemberSymbols(th: *Thread, spec: Value) ?Value {
    if (!spec.isCons() or Runtime.consPtr(spec).car != sym(th, "CONS")) return null;
    const args = Runtime.consPtr(spec).cdr;
    if (!args.isCons() or Runtime.consPtr(args).cdr != Value.nil) return null;
    const car_t = Runtime.consPtr(args).car;
    if (!car_t.isCons()) return null;
    const h = Runtime.consPtr(car_t).car;
    if (h == sym(th, "MEMBER") or h == sym(th, "EQL")) return Runtime.consPtr(car_t).cdr;
    return null;
}

/// 標準の表（initial）を、型と cons の項目の形にする（ユーザーが項目を足す前に）
fn expandInitial(th: *Thread, t: Value) error{OutOfMemory}!void {
    const rt = th.rt;
    tablePtr(t).header.flags &= ~object.PprintDispatch.initial_flag;
    const low = Value.fromSingle(-std.math.inf(f32));
    // 特別な形の項目は most-negative-single-float、型の項目は負の無限大（SBCL と同じ。型の項目に負けないように。
    // Codex のレビュー 0.3 #5）
    const magic = Value.fromSingle(-std.math.floatMax(f32));
    const member_sym = sym(th, "MEMBER");
    const cons_sym = sym(th, "CONS");
    // cons の特別な形
    for (magic_forms) |m| {
        const f = stdFunction(th, m.k);
        for (m.names) |n| {
            const s = (rt.findSymbol(rt.cl, n) orelse continue).symbol;
            try addConsEntry(rt, t, s, magic, cons_sym, member_sym, f);
        }
    }
    // quasiquote と , の形
    for ([_][]const u8{ "QUASIQUOTE", "UNQUOTE", "UNQUOTE-SPLICING", "UNQUOTE-NSPLICING" }) |n| {
        const s = (rt.findSymbol(rt.sys, n) orelse continue).symbol;
        const f = stdFunction(th, if (std.mem.eql(u8, n, "QUASIQUOTE")) .quote else .unquote);
        try addConsEntry(rt, t, s, magic, cons_sym, member_sym, f);
    }
    // 型の項目：配列（文字列以外）、fboundp のシンボルで始まる cons、cons（SBCL の初めの項目と同じ順）
    const not_string = try rt.cons(sym(th, "NOT"), try rt.cons(sym(th, "STRING"), Value.nil));
    const arr = try rt.cons(sym(th, "AND"), try rt.cons(sym(th, "ARRAY"), try rt.cons(not_string, Value.nil)));
    const sat = try rt.cons(sym(th, "SATISFIES"), try rt.cons(sym(th, "FBOUNDP"), Value.nil));
    const sym_and = try rt.cons(sym(th, "AND"), try rt.cons(sym(th, "SYMBOL"), try rt.cons(sat, Value.nil)));
    const fb = try rt.cons(cons_sym, try rt.cons(sym_and, Value.nil));
    const e1 = try makeEntry(rt, low, arr, stdFunction(th, .array));
    const e2 = try makeEntry(rt, low, fb, stdFunction(th, .call_form));
    const e3 = try makeEntry(rt, low, cons_sym, stdFunction(th, .fill));
    const rest = try rt.cons(e3, tablePtr(t).entries);
    tablePtr(t).entries = try rt.cons(e1, try rt.cons(e2, rest));
}

fn addConsEntry(rt: *Runtime, t: Value, s: Value, low: Value, cons_sym: Value, member_sym: Value, f: Value) error{OutOfMemory}!void {
    const member = try rt.cons(member_sym, try rt.cons(s, Value.nil));
    const spec = try rt.cons(cons_sym, try rt.cons(member, Value.nil));
    const e = try makeEntry(rt, low, spec, f);
    const c = try rt.cons(s, e);
    tablePtr(t).cons_entries = try rt.cons(c, tablePtr(t).cons_entries);
}

/// (pprint object &optional stream)：改行と、*print-escape* 真・*print-pretty* 真の印字（値はない）
pub fn pprint(th: *Thread, args: []const Value) Value {
    const s = outStream(th, optArg(args, 1)) orelse return Value.unwind;
    const depth = th.binding_depth;
    defer th.unbindTo(depth);
    if (th.bind(th.rt.syms.@"*print-escape*", th.rt.t) == Value.unwind) return Value.unwind;
    if (th.bind(th.rt.syms.@"*print-pretty*", th.rt.t) == Value.unwind) return Value.unwind;
    if (!streams.emit(th, s, "\n")) return Value.unwind;
    outputObject(th, s, args[0]) catch return Value.unwind;
    th.mv_count = 0;
    return Value.nil;
}
