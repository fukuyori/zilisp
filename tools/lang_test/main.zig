//! 言語試験の実行器（`zig build lang-test`）。
//!
//! tests/language/ の下の各 `NAME.lisp` を `zilisp NAME.lisp` で実行し、
//! 標準出力を `NAME.expected` と比べる。終了コードは 0 を期待する。
//! 0 以外を期待する場合は、`NAME.exit` に期待する終了コードを書く。
//! ファイル名の前に渡す引数は、`NAME.args` に空白区切りで書く（例：--read）。
//! ディレクトリに `default.args` があれば、`NAME.args` がないファイルにはそれを使う。
//!
//! 比較の前に、改行コードを LF にそろえ、末尾の空白・改行を取り除く。
//! 方式が混ざる経路の試験（詳細設計 §13.1）や、VM とネイティブの両方での実行は、
//! それぞれの機能ができた Phase で追加する。

const std = @import("std");
const Io = std.Io;

pub fn main(init: std.process.Init) !u8 {
    const gpa = init.gpa;
    const arena = init.arena.allocator();
    const io = init.io;
    const args = try init.minimal.args.toSlice(arena);

    var out_buf: [4096]u8 = undefined;
    var out_fw: Io.File.Writer = .init(.stdout(), io, &out_buf);
    const out = &out_fw.interface;
    defer out.flush() catch {};

    if (args.len != 3) {
        try out.writeAll("usage: lang-test <zilisp-exe> <tests-dir>\n");
        return 2;
    }
    const exe = args[1];
    const tests_path = args[2];

    const cwd = Io.Dir.cwd();
    var dir = cwd.openDir(io, tests_path, .{ .iterate = true }) catch |err| switch (err) {
        error.FileNotFound => {
            try out.print("lang-test: {s} がありません（0 件）\n", .{tests_path});
            return 0;
        },
        else => return err,
    };
    defer dir.close(io);

    var cases: std.ArrayList([]const u8) = .empty;
    {
        var walker = try dir.walk(gpa);
        defer walker.deinit();
        while (try walker.next(io)) |e| {
            if (e.kind != .file or !std.mem.endsWith(u8, e.path, ".lisp")) continue;
            try cases.append(arena, try arena.dupe(u8, e.path));
        }
    }
    std.mem.sort([]const u8, cases.items, {}, struct {
        fn lt(_: void, a: []const u8, b: []const u8) bool {
            return std.mem.lessThan(u8, a, b);
        }
    }.lt);

    var passed: usize = 0;
    var failed: usize = 0;
    for (cases.items) |rel| {
        const stem = rel[0 .. rel.len - ".lisp".len];
        const full = try std.fs.path.join(arena, &.{ tests_path, rel });
        const expected_path = try std.fmt.allocPrint(arena, "{s}.expected", .{stem});
        const exit_path = try std.fmt.allocPrint(arena, "{s}.exit", .{stem});

        const expected = dir.readFileAlloc(io, expected_path, arena, .limited(16 * 1024 * 1024)) catch |err| {
            try out.print("FAIL {s}: {s} を読めません（{t}）\n", .{ rel, expected_path, err });
            failed += 1;
            continue;
        };
        var expected_exit: u8 = 0;
        if (dir.readFileAlloc(io, exit_path, arena, .limited(64))) |s| {
            expected_exit = std.fmt.parseInt(u8, std.mem.trim(u8, s, " \t\r\n"), 10) catch 255;
        } else |_| {}

        var argv: std.ArrayList([]const u8) = .empty;
        try argv.append(arena, exe);
        const args_path = try std.fmt.allocPrint(arena, "{s}.args", .{stem});
        const default_args_path = try std.fs.path.join(arena, &.{ std.fs.path.dirname(rel) orelse ".", "default.args" });
        const args_text: ?[]u8 = dir.readFileAlloc(io, args_path, arena, .limited(4096)) catch
            (dir.readFileAlloc(io, default_args_path, arena, .limited(4096)) catch null);
        if (args_text) |t| {
            var it = std.mem.tokenizeAny(u8, t, " \t\r\n");
            while (it.next()) |a| try argv.append(arena, a);
        }
        try argv.append(arena, full);

        const r = try std.process.run(gpa, io, .{ .argv = argv.items });
        defer gpa.free(r.stdout);
        defer gpa.free(r.stderr);

        const code: ?u8 = switch (r.term) {
            .exited => |c| c,
            else => null,
        };
        const got = try normalize(arena, r.stdout);
        const want = try normalize(arena, expected);
        if (code == expected_exit and std.mem.eql(u8, got, want)) {
            passed += 1;
        } else {
            failed += 1;
            try out.print("FAIL {s}: exit={?d}（期待 {d}）\n--- expected\n{s}\n--- actual\n{s}\n--- stderr\n{s}\n", .{
                rel, code, expected_exit, want, got, r.stderr,
            });
        }
    }
    try out.print("lang-test: {d} passed, {d} failed, {d} total\n", .{ passed, failed, cases.items.len });
    return if (failed == 0) 0 else 1;
}

/// 改行コードを LF にそろえ、末尾の空白・改行を除く
pub fn normalize(gpa: std.mem.Allocator, s: []const u8) ![]u8 {
    var buf: std.ArrayList(u8) = .empty;
    errdefer buf.deinit(gpa);
    var i: usize = 0;
    while (i < s.len) : (i += 1) {
        if (s[i] == '\r' and i + 1 < s.len and s[i + 1] == '\n') continue;
        try buf.append(gpa, s[i]);
    }
    const trimmed_len = std.mem.trimEnd(u8, buf.items, " \t\r\n").len;
    buf.shrinkRetainingCapacity(trimmed_len);
    return buf.toOwnedSlice(gpa);
}

test "normalize" {
    const a = std.testing.allocator;
    const r = try normalize(a, "3\r\n(1 2)\r\n\r\n");
    defer a.free(r);
    try std.testing.expectEqualStrings("3\n(1 2)", r);
}
