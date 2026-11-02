//! ネイティブバックエンドの試験の実行器（`zig build native-test`。Phase 12）。
//!
//! tests/language/eval/ の各 `NAME.lisp` について、次を行う。
//!   1. `zilisp --emit-zig NAME.lisp WORK/NAME.zig` で Zig のソースを生成する
//!   2. `zig build-exe` で、ランタイム（src/lib.zig を zilisp モジュールとして）と一緒にコンパイルする
//!   3. 実行し、標準出力を `NAME.expected`（VM の言語試験と同じ期待値）と、終了コードを `NAME.exit`（なければ 0）と比べる
//! 詳細設計 §5.1「意味論の一致は、全言語試験を VM とネイティブの両方で実行して確認する」。
//! ディレクトリは実行時に読む（試験のファイルを足すだけで対象になる）。
//!
//! 使い方：native-test <zilisp-exe> <zig-exe> <tests-dir> <lib.zig> <work-dir> <Debug|ReleaseSafe|ReleaseFast|ReleaseSmall>

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

    if (args.len != 7) {
        try out.writeAll("usage: native-test <zilisp-exe> <zig-exe> <tests-dir> <lib.zig> <work-dir> <optimize>\n");
        return 2;
    }
    const zilisp = args[1];
    const zig = args[2];
    const tests_path = args[3];
    const lib_path = args[4];
    const work = args[5];
    const optimize = args[6];

    const cwd = Io.Dir.cwd();
    try cwd.createDirPath(io, work);
    var dir = try cwd.openDir(io, tests_path, .{ .iterate = true });
    defer dir.close(io);

    var cases: std.ArrayList([]const u8) = .empty;
    {
        var it = dir.iterate();
        while (try it.next(io)) |e| {
            if (e.kind != .file or !std.mem.endsWith(u8, e.name, ".lisp")) continue;
            try cases.append(arena, try arena.dupe(u8, e.name[0 .. e.name.len - ".lisp".len]));
        }
    }
    std.mem.sort([]const u8, cases.items, {}, struct {
        fn lt(_: void, a: []const u8, b: []const u8) bool {
            return std.mem.lessThan(u8, a, b);
        }
    }.lt);

    var passed: usize = 0;
    var failed: usize = 0;
    for (cases.items) |stem| {
        const src = try std.fs.path.join(arena, &.{ tests_path, try std.fmt.allocPrint(arena, "{s}.lisp", .{stem}) });
        const gen = try std.fs.path.join(arena, &.{ work, try std.fmt.allocPrint(arena, "{s}.zig", .{stem}) });
        const bin = try std.fs.path.join(arena, &.{ work, try std.fmt.allocPrint(arena, "native-{s}.exe", .{stem}) });

        // 1. 生成
        if (try step(gpa, io, out, stem, "emit", &.{ zilisp, "--emit-zig", src, gen })) |_| {} else {
            failed += 1;
            continue;
        }
        // 2. コンパイル（スタックの大きさは src/native/rt.zig の stack_size と同じ。§6.7）
        const root_arg = try std.fmt.allocPrint(arena, "-Mroot={s}", .{gen});
        const lib_arg = try std.fmt.allocPrint(arena, "-Mzilisp={s}", .{lib_path});
        const bin_arg = try std.fmt.allocPrint(arena, "-femit-bin={s}", .{bin});
        if (try step(gpa, io, out, stem, "compile", &.{ zig, "build-exe", "-O", optimize, "--stack", "67108864", "--dep", "zilisp", root_arg, lib_arg, bin_arg })) |_| {} else {
            failed += 1;
            continue;
        }
        // 3. 実行と比較
        const expected = dir.readFileAlloc(io, try std.fmt.allocPrint(arena, "{s}.expected", .{stem}), arena, .limited(16 * 1024 * 1024)) catch |err| {
            try out.print("FAIL {s}: {s}.expected を読めません（{t}）\n", .{ stem, stem, err });
            failed += 1;
            continue;
        };
        var expected_exit: u8 = 0;
        if (dir.readFileAlloc(io, try std.fmt.allocPrint(arena, "{s}.exit", .{stem}), arena, .limited(64))) |s| {
            expected_exit = std.fmt.parseInt(u8, std.mem.trim(u8, s, " \t\r\n"), 10) catch 255;
        } else |_| {}
        // 通常の実行と、確保のたびに GC を行う実行（生成したコードの局所変数の値が、保守的な走査で守られているか）
        var ok = true;
        for ([_][]const []const u8{ &.{bin}, &.{ bin, "--gc-stress" } }) |argv| {
            const r = try std.process.run(gpa, io, .{ .argv = argv });
            defer gpa.free(r.stdout);
            defer gpa.free(r.stderr);
            const code: ?u8 = switch (r.term) {
                .exited => |c| c,
                else => null,
            };
            const got = try normalize(arena, r.stdout);
            const want = try normalize(arena, expected);
            if (code != expected_exit or !std.mem.eql(u8, got, want)) {
                ok = false;
                try out.print("FAIL {s}（{s}）: exit={?d}（期待 {d}）\n--- expected\n{s}\n--- actual\n{s}\n--- stderr\n{s}\n", .{
                    stem,
                    if (argv.len == 1) "通常" else "--gc-stress",
                    code,
                    expected_exit,
                    want,
                    got,
                    r.stderr,
                });
            }
        }
        if (ok) passed += 1 else failed += 1;
    }
    try out.print("native-test: {d} passed, {d} failed, {d} total（各ファイルを通常と --gc-stress で実行）\n", .{ passed, failed, cases.items.len });
    return if (failed == 0) 0 else 1;
}

/// 外部のコマンドを実行する。成功すれば {}、失敗すれば内容を表示して null
fn step(gpa: std.mem.Allocator, io: Io, out: *Io.Writer, stem: []const u8, what: []const u8, argv: []const []const u8) !?void {
    const r = try std.process.run(gpa, io, .{ .argv = argv });
    defer gpa.free(r.stdout);
    defer gpa.free(r.stderr);
    const ok = switch (r.term) {
        .exited => |c| c == 0,
        else => false,
    };
    if (ok) return {};
    try out.print("FAIL {s}: {s} に失敗しました\n{s}{s}\n", .{ stem, what, r.stdout, r.stderr });
    return null;
}

/// 改行コードを LF にそろえ、末尾の空白・改行を除く（tools/lang_test と同じ）
fn normalize(gpa: std.mem.Allocator, s: []const u8) ![]u8 {
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
