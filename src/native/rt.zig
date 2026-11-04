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

pub inline fn loadSetfFunction(th: *Thread, sym: Value) Value {
    return th.resolveSetfFunction(sym);
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
// 多値と &rest（Phase 17）

/// args[from..nargs] をリストにする（必須の引数の後ろの引数）
pub fn restList(th: *Thread, args: [*]const Value, from: usize, nargs: u32) Value {
    var list = Value.nil;
    var i: usize = nargs;
    while (i > from) : (i -= 1) list = th.rt.cons(args[i - 1], list) catch return th.outOfMemory();
    return list;
}

/// (values a ...)：主値を返し、残りを多値レジスタに置く
pub fn values(th: *Thread, args: []const Value) Value {
    if (args.len >= thread_mod.mv_limit) return th.signal(.program_error, "値が多すぎます（multiple-values-limit を超えています）", Value.unbound, Value.unbound);
    th.mv_count = @intCast(args.len);
    if (args.len == 0) return Value.nil;
    for (args[1..], 1..) |v, i| th.mv[i] = v;
    return args[0];
}

/// 今の多値の i 番目（0 が主値）。なければ NIL
pub inline fn mvValue(th: *Thread, primary: Value, i: usize) Value {
    if (i >= th.mv_count) return Value.nil;
    return if (i == 0) primary else th.mv[i];
}

pub fn mvList(th: *Thread, primary: Value) Value {
    return th.valuesToList(primary) catch th.outOfMemory();
}

pub inline fn mvRestore(th: *Thread, list: Value) Value {
    return th.listToValues(list);
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
// 非局所脱出（§6.4。Phase 18）。手順は Thread の同名の関数を参照

/// block に入る：識別子を作ってエントリを積み、識別子を返す（溢れたら Value.unwind）
pub fn blockEnter(th: *Thread) Value {
    const token = th.newBlockToken();
    if (th.pushControl(.block, token, 0, 0, 0) == Value.unwind) return Value.unwind;
    return token;
}

/// tagbody に入る：識別子を作ってエントリを積み、識別子を返す（Phase 19）
pub fn tagbodyEnter(th: *Thread) Value {
    const token = th.newBlockToken();
    if (th.pushControl(.tagbody, token, 0, 0, 0) == Value.unwind) return Value.unwind;
    return token;
}

pub fn goTo(th: *Thread, token: Value, index: u32) Value {
    return th.goTo(token, index);
}

pub fn catchEnter(th: *Thread, tag: Value) Value {
    return th.pushControl(.catch_tag, tag, 0, 0, 0);
}

pub fn uwpEnter(th: *Thread) Value {
    return th.pushControl(.unwind_protect, Value.nil, 0, 0, 0);
}

pub inline fn controlPop(th: *Thread, n: usize) void {
    th.control_depth -= n;
}

pub fn land(th: *Thread) Value {
    return th.land();
}

pub fn uwpSave(th: *Thread, primary: Value) Value {
    return th.uwpSave(primary);
}

pub fn uwpEnd(th: *Thread, primary: Value, marker: Value) Value {
    return th.uwpEnd(primary, marker);
}

pub fn returnFrom(th: *Thread, token: Value, primary: Value) Value {
    return th.returnFrom(token, primary);
}

pub fn throwTo(th: *Thread, tag: Value, primary: Value) Value {
    return th.throwTo(tag, primary);
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
    kind: enum { none, global, flet, labels, macro },
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
    /// このフォームまでに使う定数と lambda の数（このフォームの直前に、そこまで読む）
    nconsts: u32,
    nlambdas: u32,
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
}

/// 定数と lambda を、トップレベルのフォームの直前に、そのフォームの分まで読む（SBCL の fasl と同じく、後ろのフォームの
/// シンボルは、前のフォームを実行した後で intern する。agy のレビュー 0.3 #4）
const Loader = struct {
    src: reader.Source,
    b: vb.ValueBuilder,
    /// #n= のラベル（定数表全体で番号を共有するので、読むたびに消さない）
    labels: Value = Value.nil,
    next_const: usize = 0,
    next_lambda: usize = 0,
};

fn loadUpTo(th: *Thread, prog: *const Program, ld: *Loader, nconsts: usize, nlambdas: usize) !void {
    const rt = th.rt;
    ld.b.labels_ptr = &ld.labels;
    var r = reader.Reader(vb.ValueBuilder).init(rt.gpa, &ld.src, &ld.b, .{});
    defer r.deinit();
    while (ld.next_const < nconsts) : (ld.next_const += 1) {
        K[ld.next_const] = (try r.read()) orelse return error.EndOfFile;
    }
    for (prog.lambdas[ld.next_lambda..nlambdas]) |l| {
        var name = K[l.name_k];
        switch (l.kind) {
            .global => {},
            .flet, .labels, .macro => {
                name = try rt.cons(name, Value.nil);
                name = try rt.cons(switch (l.kind) {
                    .flet => rt.syms.flet,
                    .labels => rt.syms.labels,
                    else => try rt.internKeyword("MACRO"),
                }, name);
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
    ld.next_lambda = nlambdas;
}

/// 生成したプログラムを実行する。トップレベルのフォームを順に実行し、エラーで止まる（--script と同じ）
pub fn runProgram(init: std.process.Init, prog: *const Program) !u8 {
    runtime.main_stack_top = @frameAddress();
    const io = init.io;
    var stdout_buffer: [4096]u8 = undefined;
    // 標準の出力は streaming で書く（positional ではファイルへのリダイレクトで先頭から上書きする）
    var stdout_file_writer: Io.File.Writer = .initStreaming(.stdout(), io, &stdout_buffer);
    const stdout = &stdout_file_writer.interface;
    var stderr_buffer: [1024]u8 = undefined;
    var stderr_file_writer: Io.File.Writer = .initStreaming(.stderr(), io, &stderr_buffer);
    const stderr = &stderr_file_writer.interface;

    // スタックの溢れの検査の境界：今の位置から（予約したスタックの大きさ − 余裕）だけ下
    stack_limit = @frameAddress() -| (stack_size - stack_margin);

    const rt = try Runtime.create(init.gpa);
    defer rt.destroy();
    rt.io = io;
    // --gc-stress：確保のたびに GC を行う（生成したコードの局所変数の値が保守的な走査で守られているかの試験。§3.7）
    const args = try init.minimal.args.toSlice(init.arena.allocator());
    for (args[1..]) |a| {
        if (std.mem.eql(u8, a, "--gc-stress")) rt.heap.stress = true;
    }
    const th = try Thread.create(rt, stdout, .{});
    defer th.destroy();
    try buildConstants(th, prog);
    // 定数は「パッケージ::名前」の形で書いてある（emit.zig）。まだ defpackage を実行していないパッケージは空のまま作る
    var loader: Loader = .{ .src = reader.Source.init(prog.constants_text, 0), .b = .{ .rt = rt, .create_packages = true } };

    for (prog.toplevels) |t| {
        try loadUpTo(th, prog, &loader, t.nconsts, t.nlambdas);
        // エラーで抜けたときは、このフォームの中で作った動的束縛を戻す（VM の run と同じ。§6.5）
        const depth = th.binding_depth;
        const v = t.entry(th, Value.nil, &[_]Value{}, 0);
        if (v == Value.unwind and @import("../primitives/streams.zig").isQuietScriptExit(th)) {
            // 標準入力の終わり・書けない標準出力：表示せずに正常に終える（SBCL 2.6.7 の --script と同じ）
            th.unbindTo(depth);
            th.clearError();
            break;
        }
        if (v == Value.unwind) {
            th.unbindTo(depth);
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
