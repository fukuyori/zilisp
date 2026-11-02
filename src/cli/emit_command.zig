//! zilisp --emit-zig FILE OUT.zig：FILE のフォームを、ネイティブバックエンドで Zig のソースにする（Phase 12 の開発用）。
//! 生成したソースは、ランタイム（zilisp モジュール）と一緒にコンパイルすると、FILE を --script で実行したのと
//! 同じ動作をする実行ファイルになる（zig build native-test が、VM との結果の一致を確かめる）。
//! 単一の実行ファイルを作る zilisp build（Phase 36）は、この仕組みの上に作る。

const std = @import("std");
const Io = std.Io;
const reader = @import("../reader/reader.zig");
const vb = @import("../reader/value_builder.zig");
const Value = @import("../values/value.zig").Value;
const Runtime = @import("../runtime/runtime.zig").Runtime;
const resolver_mod = @import("../compiler/resolver.zig");
const verify_ir = @import("../compiler/verify_ir.zig");
const emit = @import("../native/emit.zig");
const eval_command = @import("eval_command.zig");
const Options = @import("args.zig").Options;

pub fn run(gpa: std.mem.Allocator, io: Io, options: Options, path: []const u8, out_path: []const u8, stdout: *Io.Writer, stderr: *Io.Writer) Io.Writer.Error!eval_command.Result {
    const text = Io.Dir.cwd().readFileAlloc(io, path, gpa, .limited(256 * 1024 * 1024)) catch |err| {
        try stderr.print("zilisp: {s} を読めません: {t}\n", .{ path, err });
        return .failed;
    };
    defer gpa.free(text);
    var s = eval_command.Session.create(gpa, io, options, stdout) catch {
        try stderr.writeAll("zilisp: メモリが足りません\n");
        return .failed;
    };
    defer s.destroy(stderr);
    const rt = s.rt;

    // 読んだフォームは、生成が終わるまで GC のルートにする（IR の定数はフォームから届く：§5.4）
    const root = rt.roots.register(Value.nil) catch return oom(stderr);
    defer _ = rt.roots.unregister(root);
    var arena: std.heap.ArenaAllocator = .init(gpa);
    defer arena.deinit();
    var pins = @import("../compiler/codegen.zig").Pins.init(rt) catch return oom(stderr);
    defer pins.deinit();
    var em = emit.Emitter.init(rt, gpa);
    defer em.deinit();
    var toplevels: std.ArrayList(emit.ToplevelForm) = .empty;
    defer toplevels.deinit(gpa);

    var src = reader.Source.init(text, 1);
    var b: vb.ValueBuilder = .{ .rt = rt };
    var r = reader.Reader(vb.ValueBuilder).init(gpa, &src, &b, .{});
    defer r.deinit();
    while (true) {
        const form = r.read() catch |err| {
            const d = r.diagnostic;
            try stderr.print("{s}:{d}:{d}: {s}: {s}\n", .{ path, d.loc.line, d.loc.col, @errorName(err), d.message });
            return .failed;
        } orelse break;
        const loc = r.start_loc orelse src.loc();
        const list = rt.cons(form, rt.roots.get(root).?) catch return oom(stderr);
        _ = rt.roots.set(root, list);

        var res = resolver_mod.Resolver.init(s.th, arena.allocator(), &pins);
        const lambda = res.toplevel(form) catch |err| {
            if (err == error.OutOfMemory) return oom(stderr);
            try stderr.print("{s}:{d}:{d}: ", .{ path, loc.line, loc.col });
            try s.th.writeError(stderr);
            try stderr.writeByte('\n');
            return .failed;
        };
        verify_ir.verify(lambda) catch |err| {
            try stderr.print("{s}:{d}:{d}: 内部エラー：IR が正しくありません（{t}）\n", .{ path, loc.line, loc.col, err });
            return .failed;
        };
        _ = em.emitLambda(lambda) catch return oom(stderr);
        toplevels.append(gpa, .{ .lambda = lambda, .line = loc.line, .col = loc.col }) catch return oom(stderr);
    }
    em.registerNames() catch return oom(stderr);
    var out: Io.Writer.Allocating = .init(gpa);
    defer out.deinit();
    em.finish(&out.writer, path, toplevels.items) catch return oom(stderr);
    Io.Dir.cwd().writeFile(io, .{ .sub_path = out_path, .data = out.written() }) catch |err| {
        try stderr.print("zilisp: {s} に書けません: {t}\n", .{ out_path, err });
        return .failed;
    };
    return .ok;
}

fn oom(stderr: *Io.Writer) Io.Writer.Error!eval_command.Result {
    try stderr.writeAll("zilisp: メモリが足りません\n");
    return .failed;
}
