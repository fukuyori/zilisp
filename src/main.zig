//! Zilisp のコマンドラインの入口。

const std = @import("std");
const Io = std.Io;
const version = @import("version.zig");
const args_mod = @import("cli/args.zig");

/// 終了コード（基本設計 §12.1、詳細設計 §9.4）
pub const ExitCode = enum(u8) {
    success = 0,
    /// 処理されなかったエラー
    failure = 1,
    /// 使い方の誤り・未実装のコマンド
    usage = 2,
};

pub fn main(init: std.process.Init) !u8 {
    const arena = init.arena.allocator();
    const io = init.io;
    const args = try init.minimal.args.toSlice(arena);

    var stdout_buffer: [4096]u8 = undefined;
    var stdout_file_writer: Io.File.Writer = .init(.stdout(), io, &stdout_buffer);
    const stdout = &stdout_file_writer.interface;

    var stderr_buffer: [1024]u8 = undefined;
    var stderr_file_writer: Io.File.Writer = .init(.stderr(), io, &stderr_buffer);
    const stderr = &stderr_file_writer.interface;

    const code = run(args_mod.parse(args), stdout, stderr) catch |err| {
        stderr.print("zilisp: 出力に失敗しました: {t}\n", .{err}) catch {};
        stderr.flush() catch {};
        return @backingInt(ExitCode.failure);
    };
    try stdout.flush();
    try stderr.flush();
    return @backingInt(code);
}

pub fn run(command: args_mod.Command, stdout: *Io.Writer, stderr: *Io.Writer) Io.Writer.Error!ExitCode {
    switch (command) {
        .version => {
            try printVersion(stdout);
            return .success;
        },
        .help => {
            try printHelp(stdout);
            return .success;
        },
        .none => {
            try stderr.writeAll("zilisp: REPL は未実装です（Phase 08 で実装予定）。--help で使い方を表示します。\n");
            return .usage;
        },
        .unsupported => |arg| {
            try stderr.print("zilisp: '{s}' は未実装、または不明なオプションです。--help で使い方を表示します。\n", .{arg});
            return .usage;
        },
    }
}

pub fn printVersion(w: *Io.Writer) Io.Writer.Error!void {
    try w.print("{s} {s} (zig {s})\n", .{ version.name, version.version, version.zig_version });
}

pub fn printHelp(w: *Io.Writer) Io.Writer.Error!void {
    try w.print(
        \\{s} {s} - Zig で実装する Common Lisp 互換処理系
        \\
        \\使い方:
        \\  zilisp --version, -v    バージョンを表示する
        \\  zilisp --help, -h       このヘルプを表示する
        \\
        \\未実装（今後の Phase で実装予定）:
        \\  zilisp                  REPL
        \\  zilisp FILE.lisp        ソースの実行
        \\  zilisp --script FILE    スクリプトの実行
        \\  zilisp --eval FORM      式の評価
        \\  zilisp --load FILE      ファイルの読み込み
        \\  zilisp build FILE -o OUT  実行ファイルの生成
        \\
    , .{ version.name, version.version });
}

test "run version" {
    var out_buf: [256]u8 = undefined;
    var out: Io.Writer = .fixed(&out_buf);
    var err_buf: [256]u8 = undefined;
    var err: Io.Writer = .fixed(&err_buf);
    const code = try run(.version, &out, &err);
    try std.testing.expectEqual(ExitCode.success, code);
    try std.testing.expect(std.mem.startsWith(u8, out.buffered(), "zilisp " ++ version.version));
}

test "run help" {
    var out_buf: [2048]u8 = undefined;
    var out: Io.Writer = .fixed(&out_buf);
    var err_buf: [256]u8 = undefined;
    var err: Io.Writer = .fixed(&err_buf);
    try std.testing.expectEqual(ExitCode.success, try run(.help, &out, &err));
    try std.testing.expect(std.mem.indexOf(u8, out.buffered(), "--version") != null);
}

test "run unsupported returns usage" {
    var out_buf: [256]u8 = undefined;
    var out: Io.Writer = .fixed(&out_buf);
    var err_buf: [512]u8 = undefined;
    var err: Io.Writer = .fixed(&err_buf);
    try std.testing.expectEqual(ExitCode.usage, try run(.{ .unsupported = "x.lisp" }, &out, &err));
    try std.testing.expectEqual(ExitCode.usage, try run(.none, &out, &err));
}

test {
    _ = version;
    _ = args_mod;
    _ = @import("reader/reader.zig");
}
