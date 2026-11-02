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

pub const Error = error{ OutOfMemory, WriteFailed };

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
        for (e.consts.items) |v| {
            try printer.prin1(e.rt, &text.writer, v);
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

/// 1つの lambda の Zig の関数を生成する
const FnGen = struct {
    e: *Emitter,
    lambda: *Lambda,
    out: std.Io.Writer.Allocating,
    next_temp: u32 = 0,
    /// 使われた Zig の局所変数（v番号）
    used: std.AutoHashMapUnmanaged(u32, void) = .empty,

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
        try f.w().print(";\n    if (t{d} == Value.unwind) return t{d};\n", .{ t, t });
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
        const result = try f.gen(l.body);
        try f.w().print("    th.mv_count = 1;\n    return {s};\n}}\n\n", .{result.s()});
        std.mem.swap(std.Io.Writer.Allocating, &f.out, &body_out);

        try f.w().print("fn @\"{s}\"(th: *Thread, self: Value, args: [*]const Value, nargs: u32) callconv(.c) Value {{\n", .{info.fn_name});
        if (l.params.len == 0) try f.w().writeAll("    _ = args;\n");
        try f.w().print("    if (nargs != {d}) return N.argCountError(th, self, nargs);\n", .{l.params.len});
        try f.w().writeAll("    if (!N.stackOk()) return N.stackOverflow(th);\n");
        for (l.params, 0..) |p, i| {
            const id = try e.varId(p);
            if (p.boxed()) {
                try f.w().print("    const v{d} = N.makeCell(th, args[{d}]);\n    if (v{d} == Value.unwind) return v{d};\n", .{ id, i, id, id });
            } else {
                const kw = if (p.assigned) "var" else "const";
                try f.w().print("    {s} v{d} = args[{d}];\n", .{ kw, id, i });
            }
            if (!f.used.contains(id)) try f.w().print("    _ = &v{d};\n", .{id});
        }
        try f.w().writeAll(body_out.written());
        f.used.deinit(e.gpa);
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
            else => _ = try f.gen(n),
        }
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
            .let_ => |b| {
                var inits: std.ArrayList(Expr) = .empty;
                defer inits.deinit(e.gpa);
                for (b.inits) |i| try inits.append(e.gpa, try f.gen(i));
                // 本体を先に生成し、使われた変数が分かってから宣言を書く
                var body_out: std.Io.Writer.Allocating = .init(e.gpa);
                defer body_out.deinit();
                std.mem.swap(std.Io.Writer.Allocating, &f.out, &body_out);
                const result = try f.gen(b.body);
                std.mem.swap(std.Io.Writer.Allocating, &f.out, &body_out);
                for (b.vars, inits.items) |v, init| {
                    const id = try e.varId(v);
                    if (v.boxed()) {
                        try f.w().print("    const v{d} = N.makeCell(th, {s});\n    if (v{d} == Value.unwind) return v{d};\n", .{ id, init.s(), id, id });
                    } else {
                        const kw = if (v.assigned) "var" else "const";
                        try f.w().print("    {s} v{d} = {s};\n", .{ kw, id, init.s() });
                    }
                    if (!f.used.contains(id)) try f.w().print("    _ = &v{d};\n", .{id});
                }
                try f.w().writeAll(body_out.written());
                return result;
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
