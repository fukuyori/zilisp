//! Zilisp のコマンドラインの入口。

const std = @import("std");
const Io = std.Io;
const version = @import("version.zig");
const args_mod = @import("cli/args.zig");
const read_command = @import("cli/read_command.zig");
const eval_command = @import("cli/eval_command.zig");
const emit_command = @import("cli/emit_command.zig");
const runtime = @import("runtime/runtime.zig");

/// コマンドの実行に必要な環境
pub const Context = struct {
    gpa: std.mem.Allocator,
    io: Io,
};

/// 終了コード（基本設計 §12.1、詳細設計 §9.4）
pub const ExitCode = enum(u8) {
    success = 0,
    /// 処理されなかったエラー
    failure = 1,
    /// 使い方の誤り・未実装のコマンド
    usage = 2,
};

pub fn main(init: std.process.Init) !u8 {
    // GC の保守的走査の上端（Windows 以外で使う。main 自身は Lisp の値を持たず、Lisp の値はすべてこれより下のフレームにある）
    runtime.main_stack_top = @frameAddress();
    const arena = init.arena.allocator();
    const io = init.io;
    const args = try init.minimal.args.toSlice(arena);

    var stdout_buffer: [4096]u8 = undefined;
    var stdout_file_writer: Io.File.Writer = .init(.stdout(), io, &stdout_buffer);
    const stdout = &stdout_file_writer.interface;

    var stderr_buffer: [1024]u8 = undefined;
    var stderr_file_writer: Io.File.Writer = .init(.stderr(), io, &stderr_buffer);
    const stderr = &stderr_file_writer.interface;

    const ctx: Context = .{ .gpa = init.gpa, .io = io };
    const parsed = args_mod.parse(args);
    const code = run(ctx, parsed.options, parsed.command, stdout, stderr) catch |err| {
        stderr.print("zilisp: 出力に失敗しました: {t}\n", .{err}) catch {};
        stderr.flush() catch {};
        return @backingInt(ExitCode.failure);
    };
    try stdout.flush();
    try stderr.flush();
    return @backingInt(code);
}

pub fn run(ctx: Context, options: args_mod.Options, command: args_mod.Command, stdout: *Io.Writer, stderr: *Io.Writer) Io.Writer.Error!ExitCode {
    switch (command) {
        .read => |path| {
            return switch (try read_command.run(ctx.gpa, ctx.io, options, path, stdout, stderr)) {
                .ok => .success,
                .failed => .failure,
            };
        },
        .missing_argument => |opt| {
            try stderr.print("zilisp: {s} には引数が必要です。--help で使い方を表示します。\n", .{opt});
            return .usage;
        },
        .version => {
            try printVersion(stdout);
            return .success;
        },
        .help => {
            try printHelp(stdout);
            return .success;
        },
        .none => return exit(try eval_command.runRepl(ctx.gpa, ctx.io, options, null, stdout, stderr)),
        .load => |path| return exit(try eval_command.runRepl(ctx.gpa, ctx.io, options, path, stdout, stderr)),
        .script => |path| return exit(try eval_command.runScript(ctx.gpa, ctx.io, options, path, stdout, stderr)),
        .eval => |text| return exit(try eval_command.runEval(ctx.gpa, ctx.io, options, text, stdout, stderr)),
        .emit_zig => |e| return exit(try emit_command.run(ctx.gpa, ctx.io, options, e.src, e.out, stdout, stderr)),
        .unsupported => |arg| {
            try stderr.print("zilisp: '{s}' は未実装、または不明なオプションです。--help で使い方を表示します。\n", .{arg});
            return .usage;
        },
    }
}

fn exit(r: eval_command.Result) ExitCode {
    return switch (r) {
        .ok => .success,
        .failed => .failure,
    };
}

pub fn printVersion(w: *Io.Writer) Io.Writer.Error!void {
    try w.print("{s} {s} (zig {s})\n", .{ version.name, version.version, version.zig_version });
}

pub fn printHelp(w: *Io.Writer) Io.Writer.Error!void {
    try w.print(
        \\{s} {s} - Zig で実装する Common Lisp 互換処理系
        \\
        \\使い方:
        \\  zilisp                  REPL を始める（入力が終われば終わる）
        \\  zilisp FILE             FILE のフォームを順に評価する（--script FILE と同じ）
        \\  zilisp --script FILE    FILE のフォームを順に評価する。エラーで止まり、終了コード 1
        \\  zilisp --eval TEXT      TEXT のフォームを順に評価する（値は印字しない）
        \\  zilisp --load FILE      FILE を評価してから REPL を始める
        \\  zilisp --version, -v    バージョンを表示する
        \\  zilisp --help, -h       このヘルプを表示する
        \\  zilisp --read FILE      FILE のデータを読み、1つずつ印字する（Reader と印字の確認用）
        \\  zilisp --emit-zig FILE OUT.zig  FILE を Zig のソースにする（ネイティブバックエンドの開発用）
        \\
        \\全体のオプション（コマンドの前に置く）:
        \\  --gc-stress             確保のたびに GC を行う（試験用）
        \\  --gc-stats              終了時に GC の統計を標準エラー出力に表示する
        \\
        \\未実装（今後の Phase で実装予定）:
        \\  zilisp build FILE -o OUT  実行ファイルの生成
        \\
    , .{ version.name, version.version });
}

const test_ctx: Context = .{ .gpa = std.testing.allocator, .io = std.testing.io };

test "run version" {
    var out_buf: [256]u8 = undefined;
    var out: Io.Writer = .fixed(&out_buf);
    var err_buf: [256]u8 = undefined;
    var err: Io.Writer = .fixed(&err_buf);
    const code = try run(test_ctx, .{}, .version, &out, &err);
    try std.testing.expectEqual(ExitCode.success, code);
    try std.testing.expect(std.mem.startsWith(u8, out.buffered(), "zilisp " ++ version.version));
}

test "run help" {
    var out_buf: [2048]u8 = undefined;
    var out: Io.Writer = .fixed(&out_buf);
    var err_buf: [256]u8 = undefined;
    var err: Io.Writer = .fixed(&err_buf);
    try std.testing.expectEqual(ExitCode.success, try run(test_ctx, .{}, .help, &out, &err));
    try std.testing.expect(std.mem.indexOf(u8, out.buffered(), "--version") != null);
}

test "run unsupported returns usage" {
    var out_buf: [256]u8 = undefined;
    var out: Io.Writer = .fixed(&out_buf);
    var err_buf: [512]u8 = undefined;
    var err: Io.Writer = .fixed(&err_buf);
    try std.testing.expectEqual(ExitCode.usage, try run(test_ctx, .{}, .{ .unsupported = "x.lisp" }, &out, &err));
}

test {
    _ = version;
    _ = args_mod;
    _ = @import("reader/reader.zig");
    _ = @import("values/value.zig");
    _ = @import("runtime/heap.zig");
    _ = @import("runtime/runtime.zig");
    _ = @import("runtime/cl_symbols.zig");
    _ = @import("printer/printer.zig");
    _ = @import("support/os_memory.zig");
    _ = @import("runtime/roots.zig");
    _ = @import("runtime/gc.zig");
    _ = @import("primitives/primitives.zig");
    _ = @import("vm/verify.zig");
    _ = @import("compiler/eval_test.zig");
    _ = eval_command;
}
