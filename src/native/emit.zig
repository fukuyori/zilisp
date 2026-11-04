//! ネイティブバックエンド：Core IR から Zig のソースを生成する（詳細設計 §7A。Phase 12 の最小実装）。
//!
//! 生成するファイルの形
//!   - lambda 1つにつき、汎用の入口（§6.2 の Entry、callconv(.c)）の Zig の関数を1つ。
//!     関数名は @"lisp:名前:番号"（Lisp の名前をそのまま識別子に使う：§7A.5 C1）。
//!   - トップレベルのフォーム1つにつき、引数のない関数を1つ。main はそれらを順に実行する（rt.runProgram）。
//!   - 定数（quote したデータ・シンボルなど）は prin1 で印字したテキストとして埋め込み、起動時に Reader で読む。
//!     その後ろに、各 lambda の Code と、捕捉のない lambda の closure を置く（定数表 K）。
//! 式の値は Zig の局所定数（t番号）に入れ、関数の呼び出しのたびに Value.unwind かを確かめて、そうなら返す（§6.4）。
//!
//! Phase 12 の制限
//!   - 同じファイル内の直接呼び出し・高速入口・末尾呼び出しの変換（§7A.3）は、まだ行わない（関数セルを経由して呼ぶ）
//!   - uninterned のシンボルは、定数ごとに別のシンボルとして読み直す（同じファイルの中での同一性を保たない）

const std = @import("std");
const Value = @import("../values/value.zig").Value;
const Runtime = @import("../runtime/runtime.zig").Runtime;
const printer = @import("../printer/printer.zig");
const ir = @import("../compiler/ir.zig");
const Node = ir.Node;
const Lambda = ir.Lambda;
const Var = ir.Var;

/// NotReadable：読み戻せる形で書けない定数（関数・ストリームなど）がある（Emitter.not_readable にその定数）
pub const Error = error{ OutOfMemory, WriteFailed, NotReadable };

pub const ToplevelForm = struct {
    lambda: *Lambda,
    line: u32,
    col: u32,
};

const LambdaInfo = struct {
    lambda: *Lambda,
    id: u32,
    fn_name: []const u8,
};

pub const Emitter = struct {
    rt: *Runtime,
    gpa: std.mem.Allocator,
    consts: std.ArrayList(Value) = .empty,
    const_index: std.AutoHashMapUnmanaged(u64, u32) = .empty,
    lambdas: std.ArrayList(LambdaInfo) = .empty,
    lambda_ids: std.AutoHashMapUnmanaged(*Lambda, u32) = .empty,
    var_ids: std.AutoHashMapUnmanaged(*Var, u32) = .empty,
    next_var: u32 = 0,
    /// 生成した関数の本文（lambda ごと）
    functions: std.Io.Writer.Allocating,
    /// finish が error.NotReadable を返したときの、読み戻せない定数
    not_readable: Value = Value.nil,

    pub fn init(rt: *Runtime, gpa: std.mem.Allocator) Emitter {
        return .{ .rt = rt, .gpa = gpa, .functions = .init(gpa) };
    }

    pub fn deinit(e: *Emitter) void {
        e.consts.deinit(e.gpa);
        e.const_index.deinit(e.gpa);
        for (e.lambdas.items) |l| e.gpa.free(l.fn_name);
        e.lambdas.deinit(e.gpa);
        e.lambda_ids.deinit(e.gpa);
        e.var_ids.deinit(e.gpa);
        e.functions.deinit();
    }

    fn constant(e: *Emitter, v: Value) Error!u32 {
        const gop = try e.const_index.getOrPut(e.gpa, v.raw());
        if (!gop.found_existing) {
            gop.value_ptr.* = @intCast(e.consts.items.len);
            try e.consts.append(e.gpa, v);
        }
        return gop.value_ptr.*;
    }

    fn varId(e: *Emitter, v: *Var) Error!u32 {
        const gop = try e.var_ids.getOrPut(e.gpa, v);
        if (!gop.found_existing) {
            gop.value_ptr.* = e.next_var;
            e.next_var += 1;
        }
        return gop.value_ptr.*;
    }

    /// lambda に番号と Zig の関数名を付ける
    fn register(e: *Emitter, l: *Lambda) Error!u32 {
        if (e.lambda_ids.get(l)) |id| return id;
        const id: u32 = @intCast(e.lambdas.items.len);
        var name: std.Io.Writer.Allocating = .init(e.gpa);
        defer name.deinit();
        try name.writer.writeAll("lisp:");
        if (l.fn_name != Value.nil) {
            var raw: std.Io.Writer.Allocating = .init(e.gpa);
            defer raw.deinit();
            try printer.prin1(e.rt, &raw.writer, l.fn_name);
            // Zig の文字列として書けない文字（" と \ と制御文字）は _ にする
            for (raw.written()) |c| try name.writer.writeByte(if (c == '"' or c == '\\' or c < 0x20) '_' else c);
        } else if (l.parent == null) {
            try name.writer.writeAll("toplevel");
        } else {
            try name.writer.writeAll("lambda");
        }
        try name.writer.print(":{d}", .{id});
        try e.lambdas.append(e.gpa, .{ .lambda = l, .id = id, .fn_name = try name.toOwnedSlice() });
        try e.lambda_ids.put(e.gpa, l, id);
        return id;
    }

    /// lambda とその中の lambda の関数を生成する
    pub fn emitLambda(e: *Emitter, l: *Lambda) Error!u32 {
        const id = try e.register(l);
        var f: FnGen = .{ .e = e, .lambda = l, .out = .init(e.gpa) };
        defer f.out.deinit();
        try f.body();
        try e.functions.writer.writeAll(f.out.written());
        return id;
    }

    /// ファイル全体を書く
    pub fn finish(e: *Emitter, w: *std.Io.Writer, file: []const u8, toplevels: []const ToplevelForm) Error!void {
        const nread: u32 = @intCast(e.consts.items.len);
        const nlam: u32 = @intCast(e.lambdas.items.len);
        try w.writeAll(
            \\// Zilisp のネイティブバックエンドが生成したファイル（編集しないこと）
            \\const std = @import("std");
            \\const zl = @import("zilisp");
            \\const N = zl.native;
            \\const Value = zl.value.Value;
            \\const Thread = zl.thread.Thread;
            \\
            \\
        );
        try w.print("const CODE_BASE: usize = {d};\nconst CLOSURE_BASE: usize = {d};\n\n", .{ nread, nread + nlam });
        try w.writeAll(e.functions.written());
        // 定数のテキスト
        var text: std.Io.Writer.Allocating = .init(e.gpa);
        defer text.deinit();
        // シンボルは「パッケージ::名前」の形で書く（起動時の *package* によらず同じシンボルを読む。Phase 22）
        printer.qualify_all = true;
        defer printer.qualify_all = false;
        // 循環・共有する構造（#1=(a . #1#) など）は #n= と #n# で書く（Phase 24。起動時の Reader が同じ形に読む）
        // *print-readably* の形で書く（#nA で表せない配列は #A(次元 要素の型 . 中身)。読み戻せない定数はエラー）
        var settings = printer.Settings.standard(true);
        settings.circle = true;
        settings.readably = true;
        settings.array = true;
        settings.gensym = true;
        for (e.consts.items) |v| {
            var bad: Value = Value.nil;
            printer.writeObject(e.rt, &text.writer, v, settings, &bad) catch |err| switch (err) {
                error.NotReadable => {
                    e.not_readable = bad;
                    return error.NotReadable;
                },
                error.WriteFailed => return error.WriteFailed,
            };
            try text.writer.writeByte('\n');
        }
        try w.writeAll("const constants_text = ");
        try writeZigString(w, text.written());
        try w.writeAll(";\n\nconst lambdas = [_]N.LambdaSpec{\n");
        for (e.lambdas.items) |li| {
            const l = li.lambda;
            const kind = switch (l.fn_kind) {
                .none => "none",
                .global => "global",
                .flet => "flet",
                .labels => "labels",
                .macro => "macro",
            };
            const name_k = try e.constant(if (l.fn_kind == .none) l.name else l.fn_name);
            try w.print("    .{{ .entry = &@\"{s}\", .nparams = {d}, .kind = .{s}, .name_k = {d}, .code_k = CODE_BASE + {d}, .closure_k = ", .{ li.fn_name, l.params.len, kind, name_k, li.id });
            if (l.parent != null and l.captures.items.len == 0) {
                try w.print("CLOSURE_BASE + {d} }},\n", .{li.id});
            } else {
                try w.writeAll("null },\n");
            }
        }
        // 名前の定数は registerNames で登録済み（定数のテキストに含まれている）
        std.debug.assert(e.consts.items.len == nread);
        try w.writeAll("};\n\nconst toplevels = [_]N.Toplevel{\n");
        for (toplevels) |t| {
            const id = e.lambda_ids.get(t.lambda).?;
            try w.print("    .{{ .entry = &@\"{s}\", .line = {d}, .col = {d} }},\n", .{ e.lambdas.items[id].fn_name, t.line, t.col });
        }
        try w.writeAll("};\n\nconst program: N.Program = .{\n    .file = ");
        try writeZigString(w, file);
        try w.print(",\n    .constants_text = constants_text,\n    .nconsts = {d},\n    .lambdas = &lambdas,\n    .toplevels = &toplevels,\n}};\n\n", .{nread + 2 * nlam});
        try w.writeAll(
            \\pub fn main(init: std.process.Init) !u8 {
            \\    return N.runProgram(init, &program);
            \\}
            \\
        );
    }

    /// lambda の名前の定数を、finish の前に登録する（定数のテキストに含めるため）
    pub fn registerNames(e: *Emitter) Error!void {
        for (e.lambdas.items) |li| {
            const l = li.lambda;
            _ = try e.constant(if (l.fn_kind == .none) l.name else l.fn_name);
        }
    }
};

fn writeZigString(w: *std.Io.Writer, s: []const u8) Error!void {
    try w.writeByte('"');
    for (s) |c| switch (c) {
        '"' => try w.writeAll("\\\""),
        '\\' => try w.writeAll("\\\\"),
        '\n' => try w.writeAll("\\n"),
        '\r' => try w.writeAll("\\r"),
        '\t' => try w.writeAll("\\t"),
        0...8, 11, 12, 14...31, 127 => try w.print("\\x{x:0>2}", .{c}),
        else => try w.writeByte(c),
    };
    try w.writeByte('"');
}

/// 式の値の受け取り方（§5.5 の ValueMode）
const Mode = enum { value, discard, multi };

/// block の出口（Phase 18）。Zig のラベル付きブロック b番号 で表す
const NLabel = struct { blk: *ir.Block, id: u32, mode: Mode };

/// tagbody（Phase 19）。Zig のラベル付き switch s番号 で表し、タグ k の後ろの部分を k+1 の分岐にする
const NTag = struct { tb: *ir.Tagbody, id: u32 };

/// ジャンプ（break）で抜けるときに戻す必要がある、動的な範囲
const NDyn = union(enum) {
    block: *const NLabel,
    tagbody: *const NTag,
    catch_,
    /// 動的束縛。束縛の前の深さを置いた t番号
    bind: u32,
};

/// 1つの lambda の Zig の関数を生成する
const FnGen = struct {
    e: *Emitter,
    lambda: *Lambda,
    out: std.Io.Writer.Allocating,
    next_temp: u32 = 0,
    /// 使われた Zig の局所変数（v番号）
    used: std.AutoHashMapUnmanaged(u32, void) = .empty,
    /// Value.unwind を受け取ったときの行き先：null なら関数から返る。番号なら、その脱出先のブロック b番号 を抜ける
    unwind_exit: ?u32 = null,
    dyn: std.ArrayList(NDyn) = .empty,

    /// Value.unwind を受け取ったときの文（関数から返る、または脱出先のブロックを抜ける）
    fn writeExit(f: *FnGen, x: []const u8) Error!void {
        if (f.unwind_exit) |id| {
            try f.w().print("break :b{d} Value.unwind;\n", .{id});
        } else {
            try f.w().print("return {s};\n", .{x});
        }
    }

    fn w(f: *FnGen) *std.Io.Writer {
        return &f.out.writer;
    }

    fn temp(f: *FnGen) u32 {
        const t = f.next_temp;
        f.next_temp += 1;
        return t;
    }

    fn markUsed(f: *FnGen, id: u32) Error!void {
        try f.used.put(f.e.gpa, id, {});
    }

    /// 式の値を表す Zig の式（t番号、v番号、定数の式）
    const Expr = struct {
        buf: [48]u8 = undefined,
        len: usize = 0,
        fn of(comptime fmt: []const u8, args: anytype) Expr {
            var x: Expr = .{};
            const written = std.fmt.bufPrint(&x.buf, fmt, args) catch unreachable;
            x.len = written.len;
            return x;
        }
        fn s(x: *const Expr) []const u8 {
            return x.buf[0..x.len];
        }
    };

    /// 呼び出しの結果を t番号に入れ、Value.unwind なら返す
    fn checked(f: *FnGen, comptime fmt: []const u8, args: anytype) Error!Expr {
        const t = f.temp();
        try f.w().print("    const t{d} = ", .{t});
        try f.w().print(fmt, args);
        try f.w().print(";\n    if (t{d} == Value.unwind) ", .{t});
        var buf: [16]u8 = undefined;
        try f.writeExit(std.fmt.bufPrint(&buf, "t{d}", .{t}) catch unreachable);
        return Expr.of("t{d}", .{t});
    }

    fn body(f: *FnGen) Error!void {
        const l = f.lambda;
        const e = f.e;
        const info = e.lambdas.items[e.lambda_ids.get(l).?];
        // 本体を先に生成し、使われた引数が分かってから関数の先頭を書く
        var body_out: std.Io.Writer.Allocating = .init(e.gpa);
        defer body_out.deinit();
        std.mem.swap(std.Io.Writer.Allocating, &f.out, &body_out);
        // 本体の最後の式は多値の位置（値の個数は genM が書く：§6.2）
        const result = try f.genM(l.body);
        try f.w().print("    return {s};\n}}\n\n", .{result.s()});
        std.mem.swap(std.Io.Writer.Allocating, &f.out, &body_out);

        try f.w().print("fn @\"{s}\"(th: *Thread, self: Value, args: [*]const Value, nargs: u32) callconv(.c) Value {{\n", .{info.fn_name});
        if (l.params.len == 0) try f.w().writeAll("    _ = args;\n");
        const required = l.params.len - @intFromBool(l.rest_param);
        if (l.rest_param) {
            try f.w().print("    if (nargs < {d}) return N.argCountError(th, self, nargs);\n", .{required});
        } else {
            try f.w().print("    if (nargs != {d}) return N.argCountError(th, self, nargs);\n", .{required});
        }
        try f.w().writeAll("    if (!N.stackOk()) return N.stackOverflow(th);\n");
        for (l.params, 0..) |p, i| {
            const id = try e.varId(p);
            // 必須の引数の後ろの引数は、リストにまとめる（Phase 17）
            var value_buf: [32]u8 = undefined;
            var value: []const u8 = undefined;
            if (l.rest_param and i == required) {
                try f.w().print("    const r{d} = N.restList(th, args, {d}, nargs);\n    if (r{d} == Value.unwind) return r{d};\n", .{ id, required, id, id });
                value = std.fmt.bufPrint(&value_buf, "r{d}", .{id}) catch unreachable;
            } else {
                value = std.fmt.bufPrint(&value_buf, "args[{d}]", .{i}) catch unreachable;
            }
            if (p.boxed()) {
                try f.w().print("    const v{d} = N.makeCell(th, {s});\n    if (v{d} == Value.unwind) return v{d};\n", .{ id, value, id, id });
            } else {
                const kw = if (p.assigned) "var" else "const";
                try f.w().print("    {s} v{d} = {s};\n", .{ kw, id, value });
            }
            if (!f.used.contains(id)) try f.w().print("    _ = &v{d};\n", .{id});
        }
        try f.w().writeAll(body_out.written());
        f.used.deinit(e.gpa);
        f.dyn.deinit(e.gpa);
    }

    /// 変数の中身（箱に入れた変数なら箱そのもの）を表す式
    fn loadRaw(f: *FnGen, v: *Var) Error!Expr {
        if (v.owner == f.lambda) {
            const id = try f.e.varId(v);
            try f.markUsed(id);
            return Expr.of("v{d}", .{id});
        }
        const idx = f.lambda.captureIndex(v) orelse unreachable;
        return Expr.of("N.captured(self, {d})", .{idx});
    }

    fn constExpr(f: *FnGen, v: Value) Error!Expr {
        if (v == Value.nil) return Expr.of("Value.nil", .{});
        if (v == f.e.rt.t) return Expr.of("th.rt.t", .{});
        if (v.isFixnum()) return Expr.of("Value.fromFixnum({d})", .{v.asFixnum()});
        return Expr.of("N.K[{d}]", .{try f.e.constant(v)});
    }

    fn genDiscard(f: *FnGen, n: *Node) Error!void {
        switch (n.kind) {
            .constant, .lex_ref, .lambda => {},
            .if_ => |x| {
                const c = try f.gen(x.cond);
                try f.w().print("    if ({s} != Value.nil) {{\n", .{c.s()});
                try f.genDiscard(x.then);
                try f.w().writeAll("    } else {\n");
                try f.genDiscard(x.else_);
                try f.w().writeAll("    }\n");
            },
            .progn => |forms| for (forms) |x| try f.genDiscard(x),
            .let_ => |b| _ = try f.genLet(b, .discard),
            .progv => |p| _ = try f.genProgv(p, .discard),
            .mv_bind => |b| _ = try f.genMvBind(b, .discard),
            .values => |args| for (args) |x| try f.genDiscard(x),
            .mv_prog1 => |p| {
                try f.genDiscard(p.first);
                for (p.rest) |x| try f.genDiscard(x);
            },
            .block => |b| _ = try f.genBlock(b.blk, b.body, .discard),
            .catch_ => |c| _ = try f.genCatch(c.tag, c.body, .discard),
            .unwind_protect => |u| _ = try f.genUnwindProtect(u.protected, u.cleanup, .discard),
            .tagbody => |t| try f.genTagbody(t.tb, t.items),
            else => _ = try f.gen(n),
        }
    }

    // ------------------------------------------------------------------
    // 非局所脱出（Phase 18。§6.4）
    //
    // 脱出先（エントリのある block・catch）は、本体を Zig のラベル付きブロックにし、本体の中で Value.unwind を
    // 受け取ったらそのブロックを抜ける（writeExit）。ブロックの後で N.land が、自分が脱出先かを確かめる。
    // 同じ lambda の中の return-from は break で抜ける（`if (true) break` にして、後ろのコードも生成できるようにする）

    /// 本体を、ラベル付きブロック b{id} の中に生成する。entry なら、Value.unwind を受け取ったらブロックを抜け、
    /// 脱出先かを確かめる。そうでなければ、ブロックを抜けるのは return-from の break だけ
    fn genLabeled(f: *FnGen, id: u32, body_node: *Node, mode: Mode, entry: bool, d: NDyn) Error!?Expr {
        const void_block = mode == .discard and !entry;
        if (void_block) {
            try f.w().print("    b{d}: {{\n", .{id});
        } else {
            try f.w().print("    {s} t{d}: Value = b{d}: {{\n", .{ if (entry) "var" else "const", id, id });
        }
        const saved = f.unwind_exit;
        if (entry) f.unwind_exit = id;
        try f.dyn.append(f.e.gpa, d);
        const r = try f.genBody(body_node, mode);
        _ = f.dyn.pop();
        f.unwind_exit = saved;
        if (void_block) {
            try f.w().print("    break :b{d};\n    }}\n", .{id});
            return null;
        }
        try f.w().print("    break :b{d} {s};\n    }};\n", .{ id, if (r) |x| x.s() else "Value.nil" });
        if (entry) {
            try f.w().print("    if (t{d} == Value.unwind) {{\n    t{d} = N.land(th);\n    if (t{d} == Value.unwind) ", .{ id, id, id });
            var buf: [16]u8 = undefined;
            try f.writeExit(std.fmt.bufPrint(&buf, "t{d}", .{id}) catch unreachable);
            try f.w().writeAll("    } else N.controlPop(th, 1);\n");
        }
        if (mode == .discard) return null;
        return Expr.of("t{d}", .{id});
    }

    fn genBlock(f: *FnGen, blk: *ir.Block, body_node: *Node, mode: Mode) Error!?Expr {
        // return-from のない block は、本体そのもの
        if (!blk.needs_entry and !blk.has_local) return f.genBody(body_node, mode);
        const id = f.temp();
        const label: NLabel = .{ .blk = blk, .id = id, .mode = mode };
        if (blk.needs_entry) {
            const tok = try f.e.varId(blk.token);
            try f.markUsed(tok);
            try f.w().print("    const v{d} = N.blockEnter(th);\n    if (v{d} == Value.unwind) ", .{ tok, tok });
            var buf: [16]u8 = undefined;
            try f.writeExit(std.fmt.bufPrint(&buf, "v{d}", .{tok}) catch unreachable);
        }
        return f.genLabeled(id, body_node, mode, blk.needs_entry, .{ .block = &label });
    }

    fn genReturnFrom(f: *FnGen, blk: *ir.Block, value: *Node, nonlocal: bool) Error!Expr {
        if (nonlocal) {
            const tok = try f.loadRaw(blk.token);
            const val = try f.genM(value);
            return f.checked("N.returnFrom(th, {s}, {s})", .{ tok.s(), val.s() });
        }
        var label: ?*const NLabel = null;
        var pops: u32 = 0;
        var unbind: ?u32 = null;
        var i = f.dyn.items.len;
        while (i > 0) {
            i -= 1;
            switch (f.dyn.items[i]) {
                .block => |l| {
                    if (l.blk == blk) {
                        label = l;
                        break;
                    }
                    if (l.blk.needs_entry) pops += 1;
                },
                .tagbody => |t| if (t.tb.needs_entry) {
                    pops += 1;
                },
                .catch_ => pops += 1,
                .bind => |t| unbind = t,
            }
        }
        const l = label orelse unreachable;
        const val = try f.genBody(value, l.mode);
        if (unbind) |t| try f.w().print("    N.unbindTo(th, t{d});\n", .{t});
        if (pops > 0) try f.w().print("    N.controlPop(th, {d});\n", .{pops});
        if (l.mode == .discard and !l.blk.needs_entry) {
            try f.w().print("    if (true) break :b{d};\n", .{l.id});
        } else {
            try f.w().print("    if (true) break :b{d} {s};\n", .{ l.id, if (val) |x| x.s() else "Value.nil" });
        }
        return Expr.of("Value.nil", .{});
    }

    /// (tagbody ...)（Phase 19）：ラベル付き switch にする。0 番の分岐は最初のタグの前の部分、k+1 番の分岐はタグ k の後ろの部分。
    /// 同じ lambda の中の go は `continue :s番号 k+1`。実行時の go の脱出先なら、switch をループで囲み、
    /// Value.unwind を受け取ったら N.land で着地して（エントリは残る）、タグの分岐から switch に入り直す
    fn genTagbody(f: *FnGen, tb: *ir.Tagbody, items: []ir.TagItem) Error!void {
        const e = f.e;
        const id = f.temp();
        const label: NTag = .{ .tb = tb, .id = id };
        var state: u32 = 0;
        var result: u32 = 0;
        if (tb.needs_entry) {
            const tok = try e.varId(tb.token);
            try f.markUsed(tok);
            try f.w().print("    const v{d} = N.tagbodyEnter(th);\n    if (v{d} == Value.unwind) ", .{ tok, tok });
            var buf: [16]u8 = undefined;
            try f.writeExit(std.fmt.bufPrint(&buf, "v{d}", .{tok}) catch unreachable);
            state = f.temp();
            result = f.temp();
            try f.w().print("    var t{d}: u32 = 0;\n    l{d}: while (true) {{\n    const t{d}: Value = b{d}: {{\n    s{d}: switch (t{d}) {{\n", .{ state, id, result, id, id, state });
        } else {
            try f.w().print("    s{d}: switch (@as(u32, 0)) {{\n", .{id});
        }
        const saved = f.unwind_exit;
        if (tb.needs_entry) f.unwind_exit = id;
        try f.dyn.append(e.gpa, .{ .tagbody = &label });
        var seg: u32 = 0;
        try f.w().writeAll("    0 => {\n");
        for (items) |item| switch (item) {
            .tag => {
                seg += 1;
                try f.w().print("    continue :s{d} {d};\n    }},\n    {d} => {{\n", .{ id, seg, seg });
            },
            .form => |x| try f.genDiscard(x),
        };
        try f.w().print("    break :s{d};\n    }},\n    else => unreachable,\n    }}\n", .{id});
        _ = f.dyn.pop();
        f.unwind_exit = saved;
        if (tb.needs_entry) {
            const idx = f.temp();
            try f.w().print("    break :b{d} Value.nil;\n    }};\n    if (t{d} == Value.unwind) {{\n    const t{d} = N.land(th);\n    if (t{d} == Value.unwind) ", .{ id, result, idx, idx });
            var buf: [16]u8 = undefined;
            try f.writeExit(std.fmt.bufPrint(&buf, "t{d}", .{idx}) catch unreachable);
            try f.w().print("    t{d} = @intCast(t{d}.asFixnum() + 1);\n    continue :l{d};\n    }}\n    N.controlPop(th, 1);\n    break;\n    }}\n", .{ state, idx, id });
        }
    }

    fn genGo(f: *FnGen, tb: *ir.Tagbody, index: u32, nonlocal: bool) Error!Expr {
        if (nonlocal) {
            const tok = try f.loadRaw(tb.token);
            return f.checked("N.goTo(th, {s}, {d})", .{ tok.s(), index });
        }
        var label: ?*const NTag = null;
        var pops: u32 = 0;
        var unbind: ?u32 = null;
        var i = f.dyn.items.len;
        while (i > 0) {
            i -= 1;
            switch (f.dyn.items[i]) {
                .tagbody => |t| {
                    if (t.tb == tb) {
                        label = t;
                        break;
                    }
                    if (t.tb.needs_entry) pops += 1;
                },
                .block => |l| if (l.blk.needs_entry) {
                    pops += 1;
                },
                .catch_ => pops += 1,
                .bind => |t| unbind = t,
            }
        }
        const l = label orelse unreachable;
        if (unbind) |t| try f.w().print("    N.unbindTo(th, t{d});\n", .{t});
        if (pops > 0) try f.w().print("    N.controlPop(th, {d});\n", .{pops});
        try f.w().print("    if (true) continue :s{d} {d};\n", .{ l.id, index + 1 });
        return Expr.of("Value.nil", .{});
    }

    fn genCatch(f: *FnGen, tag_node: *Node, body_node: *Node, mode: Mode) Error!?Expr {
        const tag = try f.gen(tag_node);
        try f.w().print("    if (N.catchEnter(th, {s}) == Value.unwind) ", .{tag.s()});
        try f.writeExit("Value.unwind");
        return f.genLabeled(f.temp(), body_node, mode, true, .catch_);
    }

    /// unwind-protect：保護したフォームを、Value.unwind を受け取ったら抜けるブロックにし、
    /// N.uwpSave（値の退避、または脱出・エラーの中断）→ cleanup → N.uwpEnd（値の復元、または脱出・エラーの再開）
    fn genUnwindProtect(f: *FnGen, protected: *Node, cleanup: []*Node, mode: Mode) Error!?Expr {
        try f.w().writeAll("    if (N.uwpEnter(th) == Value.unwind) ");
        try f.writeExit("Value.unwind");
        const id = f.temp();
        try f.w().print("    const t{d}: Value = b{d}: {{\n", .{ id, id });
        const saved = f.unwind_exit;
        f.unwind_exit = id;
        var r: ?Expr = null;
        switch (mode) {
            .discard => {
                try f.genDiscard(protected);
                try f.w().writeAll("    th.mv_count = 1;\n");
            },
            .value => {
                r = try f.gen(protected);
                try f.w().writeAll("    th.mv_count = 1;\n");
            },
            .multi => r = try f.genM(protected),
        }
        f.unwind_exit = saved;
        try f.w().print("    break :b{d} {s};\n    }};\n", .{ id, if (r) |x| x.s() else "Value.nil" });
        const marker = f.temp();
        try f.w().print("    const t{d} = N.uwpSave(th, t{d});\n", .{ marker, id });
        for (cleanup) |x| try f.genDiscard(x);
        const v = try f.checked("N.uwpEnd(th, t{d}, t{d})", .{ id, marker });
        if (mode == .discard) return null;
        return v;
    }

    fn genArgs(f: *FnGen, nodes: []*Node) Error!Expr {
        var items: std.ArrayList(Expr) = .empty;
        defer items.deinit(f.e.gpa);
        for (nodes) |a| try items.append(f.e.gpa, try f.gen(a));
        const t = f.temp();
        try f.w().print("    const t{d} = [_]Value{{", .{t});
        for (items.items, 0..) |x, i| {
            if (i > 0) try f.w().writeAll(", ");
            try f.w().writeAll(x.s());
        }
        try f.w().writeAll("};\n");
        return Expr.of("&t{d}", .{t});
    }

    /// let（discard なら本体の値を捨てる。値を捨てる位置では、本体の最後の式も値を捨てる位置になる）
    fn genLet(f: *FnGen, b: anytype, mode: Mode) Error!?Expr {
        var inits: std.ArrayList(Expr) = .empty;
        defer inits.deinit(f.e.gpa);
        for (b.inits) |i| try inits.append(f.e.gpa, try f.gen(i));
        return f.genBound(b.vars, inits.items, b.body, mode);
    }

    /// multiple-value-bind：フォームの値を変数の数だけ取り出して束縛する（足りない分は NIL）
    fn genMvBind(f: *FnGen, b: anytype, mode: Mode) Error!?Expr {
        const primary = try f.genM(b.form);
        var inits: std.ArrayList(Expr) = .empty;
        defer inits.deinit(f.e.gpa);
        for (0..b.vars.len) |i| {
            const t = f.temp();
            try f.w().print("    const t{d} = N.mvValue(th, {s}, {d});\n", .{ t, primary.s(), i });
            try inits.append(f.e.gpa, Expr.of("t{d}", .{t}));
        }
        return f.genBound(b.vars, inits.items, b.body, mode);
    }

    /// 値 init_exprs を vars に束縛して本体を生成する（let・multiple-value-bind）
    fn genBound(f: *FnGen, vars: []*Var, init_exprs: []const Expr, body_node: *Node, mode: Mode) Error!?Expr {
        const e = f.e;
        const b = .{ .vars = vars, .body = body_node };
        // 本体を先に生成し、使われた変数が分かってから宣言を書く
        const special = ir.hasSpecial(b.vars);
        const depth: u32 = if (special) f.temp() else 0;
        var body_out: std.Io.Writer.Allocating = .init(e.gpa);
        defer body_out.deinit();
        std.mem.swap(std.Io.Writer.Allocating, &f.out, &body_out);
        if (special) try f.dyn.append(e.gpa, .{ .bind = depth });
        const result: ?Expr = try f.genBody(b.body, mode);
        if (special) _ = f.dyn.pop();
        std.mem.swap(std.Io.Writer.Allocating, &f.out, &body_out);
        if (special) try f.w().print("    const t{d} = N.bindingDepth(th);\n", .{depth});
        for (b.vars, init_exprs) |v, init| {
            if (v.special) {
                try f.w().print("    if (N.bindSpecial(th, N.K[{d}], {s}) == Value.unwind) ", .{ try e.constant(v.name), init.s() });
                try f.writeExit("Value.unwind");
                continue;
            }
            const id = try e.varId(v);
            if (v.boxed()) {
                try f.w().print("    const v{d} = N.makeCell(th, {s});\n    if (v{d} == Value.unwind) ", .{ id, init.s(), id });
                try f.writeExit("Value.unwind");
            } else {
                const kw = if (v.assigned) "var" else "const";
                try f.w().print("    {s} v{d} = {s};\n", .{ kw, id, init.s() });
            }
            if (!f.used.contains(id)) try f.w().print("    _ = &v{d};\n", .{id});
        }
        try f.w().writeAll(body_out.written());
        if (special) try f.w().print("    N.unbindTo(th, t{d});\n", .{depth});
        return result;
    }

    /// progv（discard なら本体の値を捨てる）
    fn genProgv(f: *FnGen, p: anytype, mode: Mode) Error!?Expr {
        const depth = f.temp();
        try f.w().print("    const t{d} = N.bindingDepth(th);\n", .{depth});
        const syms = try f.gen(p.syms);
        const vals = try f.gen(p.vals);
        try f.w().print("    if (N.progvBind(th, {s}, {s}) == Value.unwind) ", .{ syms.s(), vals.s() });
        try f.writeExit("Value.unwind");
        try f.dyn.append(f.e.gpa, .{ .bind = depth });
        const result: ?Expr = try f.genBody(p.body, mode);
        _ = f.dyn.pop();
        try f.w().print("    N.unbindTo(th, t{d});\n", .{depth});
        return result;
    }

    fn genBody(f: *FnGen, n: *Node, mode: Mode) Error!?Expr {
        return switch (mode) {
            .discard => blk: {
                try f.genDiscard(n);
                break :blk null;
            },
            .value => try f.gen(n),
            .multi => try f.genM(n),
        };
    }

    /// 多値の位置の式（§5.5 の multiple）：主値を返し、全部の値を th.mv_count・th.mv に置くコードを生成する。
    /// 関数の呼び出しは、呼んだ関数が個数を書くので、そのまま使う。単値の式なら個数を 1 にする
    fn genM(f: *FnGen, n: *Node) Error!Expr {
        switch (n.kind) {
            .call, .call_global => return f.gen(n),
            .values => |args| {
                const a = try f.genArgs(args);
                return f.checked("N.values(th, {s})", .{a.s()});
            },
            .if_ => |x| {
                const c = try f.gen(x.cond);
                const r = f.temp();
                try f.w().print("    var t{d}: Value = undefined;\n    if ({s} != Value.nil) {{\n", .{ r, c.s() });
                const a = try f.genM(x.then);
                try f.w().print("    t{d} = {s};\n    }} else {{\n", .{ r, a.s() });
                const b = try f.genM(x.else_);
                try f.w().print("    t{d} = {s};\n    }}\n", .{ r, b.s() });
                return Expr.of("t{d}", .{r});
            },
            .progn => |forms| {
                for (forms[0 .. forms.len - 1]) |x| try f.genDiscard(x);
                return f.genM(forms[forms.len - 1]);
            },
            .let_ => |b| return (try f.genLet(b, .multi)).?,
            .progv => |p| return (try f.genProgv(p, .multi)).?,
            .mv_bind => |b| return (try f.genMvBind(b, .multi)).?,
            .block => |b| return (try f.genBlock(b.blk, b.body, .multi)).?,
            .catch_ => |c| return (try f.genCatch(c.tag, c.body, .multi)).?,
            .unwind_protect => |u| return (try f.genUnwindProtect(u.protected, u.cleanup, .multi)).?,
            .return_from, .throw_, .go_ => return f.gen(n),
            .mv_prog1 => |p| {
                const first = try f.genM(p.first);
                const saved = try f.checked("N.mvList(th, {s})", .{first.s()});
                for (p.rest) |x| try f.genDiscard(x);
                const t = f.temp();
                try f.w().print("    const t{d} = N.mvRestore(th, {s});\n", .{ t, saved.s() });
                return Expr.of("t{d}", .{t});
            },
            else => {
                const r = try f.gen(n);
                try f.w().writeAll("    th.mv_count = 1;\n");
                return r;
            },
        }
    }

    fn gen(f: *FnGen, n: *Node) Error!Expr {
        const e = f.e;
        switch (n.kind) {
            .constant => |v| return f.constExpr(v),
            .lex_ref => |v| {
                const raw = try f.loadRaw(v);
                if (v.boxed()) {
                    const t = f.temp();
                    try f.w().print("    const t{d} = N.cellRef({s});\n", .{ t, raw.s() });
                    return Expr.of("t{d}", .{t});
                }
                if (v.assigned or v.owner != f.lambda) {
                    // 後で書き換わる変数・捕捉した値は、その時点の値を写しておく
                    const t = f.temp();
                    try f.w().print("    const t{d} = {s};\n", .{ t, raw.s() });
                    return Expr.of("t{d}", .{t});
                }
                return raw;
            },
            .lex_set => |s| {
                const val = try f.gen(s.value);
                const raw = try f.loadRaw(s.v);
                if (s.v.boxed()) {
                    try f.w().print("    N.cellSet({s}, {s});\n", .{ raw.s(), val.s() });
                } else {
                    try f.w().print("    {s} = {s};\n", .{ raw.s(), val.s() });
                }
                return val;
            },
            .global_ref => |sym| return f.checked("N.loadSpecial(th, N.K[{d}])", .{try e.constant(sym)}),
            .global_set => |s| {
                const val = try f.gen(s.value);
                try f.w().print("    N.storeSpecial(th, N.K[{d}], {s});\n", .{ try e.constant(s.sym), val.s() });
                return val;
            },
            .global_fn => |sym| return f.checked("N.loadFunction(th, N.K[{d}])", .{try e.constant(sym)}),
            .global_setf_fn => |sym| return f.checked("N.loadSetfFunction(th, N.K[{d}])", .{try e.constant(sym)}),
            .call => |c| {
                const callee = try f.gen(c.callee);
                const a = try f.genArgs(c.args);
                return f.checked("N.call(th, {s}, {s})", .{ callee.s(), a.s() });
            },
            .call_global => |c| {
                const a = try f.genArgs(c.args);
                return f.checked("N.callGlobal(th, N.K[{d}], {s})", .{ try e.constant(c.sym), a.s() });
            },
            .prim => |p| {
                const x = try f.gen(p.args[0]);
                if (p.args.len == 1) return f.checked("N.{s}(th, {s})", .{ @tagName(p.op), x.s() });
                const y = try f.gen(p.args[1]);
                return f.checked("N.{s}(th, {s}, {s})", .{ @tagName(p.op), x.s(), y.s() });
            },
            .if_ => |x| {
                const c = try f.gen(x.cond);
                const r = f.temp();
                try f.w().print("    var t{d}: Value = undefined;\n    if ({s} != Value.nil) {{\n", .{ r, c.s() });
                const a = try f.gen(x.then);
                try f.w().print("    t{d} = {s};\n    }} else {{\n", .{ r, a.s() });
                const b = try f.gen(x.else_);
                try f.w().print("    t{d} = {s};\n    }}\n", .{ r, b.s() });
                return Expr.of("t{d}", .{r});
            },
            .progn => |forms| {
                for (forms[0 .. forms.len - 1]) |x| try f.genDiscard(x);
                return f.gen(forms[forms.len - 1]);
            },
            .let_ => |b| return (try f.genLet(b, .value)).?,
            .progv => |p| return (try f.genProgv(p, .value)).?,
            .mv_bind => |b| return (try f.genMvBind(b, .value)).?,
            .block => |b| return (try f.genBlock(b.blk, b.body, .value)).?,
            .catch_ => |c| return (try f.genCatch(c.tag, c.body, .value)).?,
            .unwind_protect => |u| return (try f.genUnwindProtect(u.protected, u.cleanup, .value)).?,
            .return_from => |rf| return f.genReturnFrom(rf.blk, rf.value, rf.nonlocal),
            .tagbody => |t| {
                try f.genTagbody(t.tb, t.items);
                return Expr.of("Value.nil", .{});
            },
            .go_ => |x| return f.genGo(x.tb, x.index, x.nonlocal),
            .throw_ => |t| {
                const tag = try f.gen(t.tag);
                const val = try f.genM(t.value);
                return f.checked("N.throwTo(th, {s}, {s})", .{ tag.s(), val.s() });
            },
            .values => |args| {
                if (args.len == 0) return Expr.of("Value.nil", .{});
                const first = try f.gen(args[0]);
                // 後で書き換わらないよう、主値をその時点で写しておく
                const t = f.temp();
                try f.w().print("    const t{d} = {s};\n", .{ t, first.s() });
                for (args[1..]) |x| try f.genDiscard(x);
                return Expr.of("t{d}", .{t});
            },
            .mv_list => |x| {
                const p = try f.genM(x);
                return f.checked("N.mvList(th, {s})", .{p.s()});
            },
            .mv_prog1 => |p| {
                const first = try f.gen(p.first);
                const t = f.temp();
                try f.w().print("    const t{d} = {s};\n", .{ t, first.s() });
                for (p.rest) |x| try f.genDiscard(x);
                return Expr.of("t{d}", .{t});
            },
            .lambda => |child| {
                const id = try e.emitLambda(child);
                if (child.captures.items.len == 0) return Expr.of("N.K[CLOSURE_BASE + {d}]", .{id});
                var caps: std.ArrayList(Expr) = .empty;
                defer caps.deinit(e.gpa);
                for (child.captures.items) |v| try caps.append(e.gpa, try f.loadRaw(v));
                const t = f.temp();
                try f.w().print("    const t{d} = [_]Value{{", .{t});
                for (caps.items, 0..) |x, i| {
                    if (i > 0) try f.w().writeAll(", ");
                    try f.w().writeAll(x.s());
                }
                try f.w().writeAll("};\n");
                return f.checked("N.makeClosure(th, N.K[CODE_BASE + {d}], &@\"{s}\", &t{d})", .{ id, e.lambdas.items[id].fn_name, t });
            },
        }
    }
};
