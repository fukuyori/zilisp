//! ネイティブバックエンドが生成したコードが使うランタイムの関数（詳細設計 §7A）。
//! 生成したコードは、この関数群とランタイムの Zig ソースと一緒にコンパイルする（D-5）。
//! 小さい関数（fixnum の高速経路、car・cdr など）は inline にして、生成したコードに展開させる。
//!
//! 規約は VM と同じ（§6.2）：主値を返し、エラーは Value.unwind（理由は th.fault・th.err）。
//! GC：生成したコードは局所変数の Lisp の値を登録しない（ネイティブのスタックとレジスタの保守的な走査で見つかる：§7A.4）。

const std = @import("std");
const Io = std.Io;
const Value = @import("../values/value.zig").Value;
const object = @import("../values/object.zig");
const runtime = @import("../runtime/runtime.zig");
const Runtime = runtime.Runtime;
const thread_mod = @import("../runtime/thread.zig");
const Thread = thread_mod.Thread;
const function = @import("../runtime/function.zig");
const numbers = @import("../primitives/numbers.zig");
const reader = @import("../reader/reader.zig");
const vb = @import("../reader/value_builder.zig");

pub const Entry = function.Entry;

// ---------------------------------------------------------------------------
// スタックの溢れの検査（§6.7：ネイティブコードの関数の入口で残り量を検査する）

/// これより低いアドレスにフレームが来たら、スタックが溢れそうと判断する（runProgram が設定する）
pub var stack_limit: usize = 0;

pub inline fn stackOk() bool {
    return @frameAddress() > stack_limit;
}

pub fn stackOverflow(th: *Thread) Value {
    return th.signal(.storage_condition, "ネイティブのスタックが溢れました（呼び出しが深すぎます）", Value.unbound, Value.unbound);
}

pub fn argCountError(th: *Thread, self: Value, nargs: u32) Value {
    return th.argCountError(self, nargs);
}

// ---------------------------------------------------------------------------
// 変数・関数

pub inline fn loadSpecial(th: *Thread, sym: Value) Value {
    const v = th.rt.symbolPtr(sym).value;
    if (v == Value.unbound) return th.signal(.unbound_variable, "", sym, Value.unbound);
    return v;
}

pub inline fn storeSpecial(th: *Thread, sym: Value, v: Value) void {
    th.rt.symbolPtr(sym).value = v;
}

pub inline fn loadFunction(th: *Thread, sym: Value) Value {
    return th.resolveFunction(sym);
}

pub inline fn captured(self: Value, i: usize) Value {
    return function.closurePtr(self).captured()[i];
}

pub inline fn makeCell(th: *Thread, v: Value) Value {
    return function.makeCell(th.rt, v) catch th.outOfMemory();
}

pub inline fn cellRef(c: Value) Value {
    return function.cellPtr(c).value;
}

pub inline fn cellSet(c: Value, v: Value) void {
    function.cellPtr(c).value = v;
}

pub inline fn makeClosure(th: *Thread, code: Value, entry: Entry, caps: []const Value) Value {
    return function.makeClosure(th.rt, code, entry, caps) catch th.outOfMemory();
}

/// 関数の値を呼ぶ（funcall の意味。シンボルなら大域の関数）
pub inline fn call(th: *Thread, f: Value, args: []const Value) Value {
    const fv = if (f.isFunctionPointer()) f else th.resolveFunction(f);
    if (fv == Value.unwind) return fv;
    return function.functionHeader(fv).entry(th, fv, args.ptr, @intCast(args.len));
}

/// シンボルの関数セルの関数を呼ぶ（呼び出しのたびに関数セルを参照する：再定義をすぐに反映する）
pub inline fn callGlobal(th: *Thread, sym: Value, args: []const Value) Value {
    const fv = th.resolveFunction(sym);
    if (fv == Value.unwind) return fv;
    return function.functionHeader(fv).entry(th, fv, args.ptr, @intCast(args.len));
}

// ---------------------------------------------------------------------------
// 動的束縛（§6.5）

pub inline fn bindingDepth(th: *Thread) usize {
    return th.binding_depth;
}

pub inline fn bindSpecial(th: *Thread, sym: Value, v: Value) Value {
    return th.bind(sym, v);
}

pub inline fn unbindTo(th: *Thread, depth: usize) void {
    th.unbindTo(depth);
}

pub inline fn progvBind(th: *Thread, syms: Value, vals: Value) Value {
    return th.progvBind(syms, vals);
}

// ---------------------------------------------------------------------------
// 高速経路（VM の命令と同じ意味：§7.4）

inline fn tagged(v: Value) i64 {
    return @bitCast(v.raw());
}

pub inline fn car(th: *Thread, x: Value) Value {
    if (x.isCons()) return Runtime.consPtr(x).car;
    if (x == Value.nil) return Value.nil;
    return th.typeError(x, th.rt.syms.list);
}

pub inline fn cdr(th: *Thread, x: Value) Value {
    if (x.isCons()) return Runtime.consPtr(x).cdr;
    if (x == Value.nil) return Value.nil;
    return th.typeError(x, th.rt.syms.list);
}

pub inline fn cons(th: *Thread, a: Value, b: Value) Value {
    return th.rt.cons(a, b) catch th.outOfMemory();
}

pub inline fn eq(th: *Thread, a: Value, b: Value) Value {
    return th.rt.boolean(a == b);
}

pub inline fn not(th: *Thread, a: Value) Value {
    return th.rt.boolean(a == Value.nil);
}

pub inline fn add2(th: *Thread, a: Value, b: Value) Value {
    if (a.isFixnum() and b.isFixnum()) {
        const x = @addWithOverflow(tagged(a), tagged(b));
        if (x[1] == 0) return Value.fromRaw(@bitCast(x[0]));
    }
    return numbers.add2(th, a, b);
}

pub inline fn sub2(th: *Thread, a: Value, b: Value) Value {
    if (a.isFixnum() and b.isFixnum()) {
        const x = @subWithOverflow(tagged(a), tagged(b));
        if (x[1] == 0) return Value.fromRaw(@bitCast(x[0]));
    }
    return numbers.sub2(th, a, b);
}

pub inline fn add1(th: *Thread, a: Value) Value {
    return add2(th, a, Value.fromFixnum(1));
}

pub inline fn sub1(th: *Thread, a: Value) Value {
    return sub2(th, a, Value.fromFixnum(1));
}

inline fn compare(th: *Thread, comptime c: numbers.Cmp, a: Value, b: Value) Value {
    if (a.isFixnum() and b.isFixnum()) {
        const x = tagged(a);
        const y = tagged(b);
        return th.rt.boolean(switch (c) {
            .lt => x < y,
            .gt => x > y,
            .le => x <= y,
            .ge => x >= y,
            .eq => x == y,
        });
    }
    return numbers.compare2(th, c, a, b);
}

pub inline fn lt2(th: *Thread, a: Value, b: Value) Value {
    return compare(th, .lt, a, b);
}
pub inline fn gt2(th: *Thread, a: Value, b: Value) Value {
    return compare(th, .gt, a, b);
}
pub inline fn le2(th: *Thread, a: Value, b: Value) Value {
    return compare(th, .le, a, b);
}
pub inline fn ge2(th: *Thread, a: Value, b: Value) Value {
    return compare(th, .ge, a, b);
}
pub inline fn numeq2(th: *Thread, a: Value, b: Value) Value {
    return compare(th, .eq, a, b);
}

// ---------------------------------------------------------------------------
// プログラムの起動（生成したファイルの main から呼ぶ）

/// 生成した lambda 1つの情報。起動時に Code（印字用の名前と引数の個数）を作り、定数表に置く
pub const LambdaSpec = struct {
    entry: Entry,
    nparams: u32,
    /// 名前の付け方（ir.Lambda.FnKind と同じ）
    kind: enum { none, global, flet, labels },
    /// 関数の名前（kind が none 以外）、またはラムダリスト（none）の定数の番号
    name_k: u32,
    /// Code を置く定数の番号
    code_k: u32,
    /// 捕捉のない lambda なら、前もって作った closure を置く定数の番号
    closure_k: ?u32,
};

pub const Toplevel = struct {
    entry: Entry,
    line: u32,
    col: u32,
};

pub const Program = struct {
    file: []const u8,
    /// 読み込む定数（prin1 で印字したものを空白で区切って並べたテキスト）
    constants_text: []const u8,
    /// 定数表の大きさ（読み込む定数 + Code + 前もって作る closure）
    nconsts: u32,
    lambdas: []const LambdaSpec,
    toplevels: []const Toplevel,
};

/// 定数表（GC のルートに登録した simple-vector の要素）。生成したコードは K[i] で参照する
pub var K: []Value = &.{};

fn buildConstants(th: *Thread, prog: *const Program) !void {
    const rt = th.rt;
    // 定数表の vector を作り、ルートに登録する（vector は動かないので、要素の場所は変わらない）
    const items = try rt.gpa.alloc(Value, prog.nconsts);
    defer rt.gpa.free(items);
    @memset(items, Value.nil);
    const table = try rt.makeVector(items);
    _ = try rt.roots.register(table);
    K = Runtime.vectorPtr(table).items();

    var src = reader.Source.init(prog.constants_text, 0);
    var b: vb.ValueBuilder = .{ .rt = rt };
    var r = reader.Reader(vb.ValueBuilder).init(rt.gpa, &src, &b, .{});
    defer r.deinit();
    var i: usize = 0;
    while (try r.read()) |v| : (i += 1) K[i] = v;

    for (prog.lambdas) |l| {
        var name = K[l.name_k];
        switch (l.kind) {
            .global => {},
            .flet, .labels => {
                name = try rt.cons(name, Value.nil);
                name = try rt.cons(if (l.kind == .flet) rt.syms.flet else rt.syms.labels, name);
            },
            .none => {
                name = try rt.cons(name, Value.nil);
                name = try rt.cons(rt.syms.lambda, name);
            },
        }
        K[l.code_k] = try function.makeCode(rt, .{
            .bytecode = &.{},
            .consts = Value.nil,
            .name = name,
            .nparams = l.nparams,
            .nlocals = l.nparams,
            .ncaptured = 0,
            .max_stack = 0,
        });
        if (l.closure_k) |ck| K[ck] = try function.makeClosure(rt, K[l.code_k], l.entry, &.{});
    }
}

/// 生成したプログラムを実行する。トップレベルのフォームを順に実行し、エラーで止まる（--script と同じ）
pub fn runProgram(init: std.process.Init, prog: *const Program) !u8 {
    runtime.main_stack_top = @frameAddress();
    const io = init.io;
    var stdout_buffer: [4096]u8 = undefined;
    var stdout_file_writer: Io.File.Writer = .init(.stdout(), io, &stdout_buffer);
    const stdout = &stdout_file_writer.interface;
    var stderr_buffer: [1024]u8 = undefined;
    var stderr_file_writer: Io.File.Writer = .init(.stderr(), io, &stderr_buffer);
    const stderr = &stderr_file_writer.interface;

    // スタックの溢れの検査の境界：今の位置から（予約したスタックの大きさ − 余裕）だけ下
    stack_limit = @frameAddress() -| (stack_size - stack_margin);

    const rt = try Runtime.create(init.gpa);
    defer rt.destroy();
    rt.io = io;
    const th = try Thread.create(rt, stdout, .{});
    defer th.destroy();
    try buildConstants(th, prog);

    for (prog.toplevels) |t| {
        const v = t.entry(th, Value.nil, &[_]Value{}, 0);
        if (v == Value.unwind) {
            try stdout.flush();
            try stderr.print("{s}:{d}:{d}: ", .{ prog.file, t.line, t.col });
            try th.writeError(stderr);
            try stderr.writeByte('\n');
            try stderr.flush();
            return 1;
        }
    }
    try stdout.flush();
    return 0;
}

/// 生成した実行ファイルのスタックの大きさ（build.zig で設定する値と同じ。§6.7）
pub const stack_size: usize = 64 * 1024 * 1024;
/// スタックの溢れを検査するときの余裕（ランタイムの関数・GC が使う分）
pub const stack_margin: usize = 1024 * 1024;
