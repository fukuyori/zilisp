//! ネイティブバックエンドの試験の実行器（`zig build native-test`。Phase 12）。
//!
//! tests/language/eval/ の各 `NAME.lisp` について、次を行う。
//!   1. `zilisp --emit-zig NAME.lisp WORK/NAME.zig` で Zig のソースを生成する
//!   2. `zig build-exe` で、ランタイム（src/lib.zig を zilisp モジュールとして）と一緒にコンパイルする
//!   3. 実行し、標準出力を `NAME.expected`（VM の言語試験と同じ期待値）と、終了コードを `NAME.exit`（なければ 0）と比べる
//! 詳細設計 §5.1「意味論の一致は、全言語試験を VM とネイティブの両方で実行して確認する」。
//! ディレクトリは実行時に読む（試験のファイルを足すだけで対象になる）。
//!
//! 試験は並列に実行する（ランタイムを試験ごとにコンパイルし直すので、順に実行すると Debug で 1 ファイル約 1 分かかる）。
//! 並列の数は、環境変数 ZILISP_NATIVE_TEST_JOBS（1 以上の数）か、なければ論理プロセッサの数の半分（1〜8）。
//! 結果は、すべて終わってから試験の名前の順に表示する（並列の数によらず同じ出力）。
//!
//! 使い方：native-test <zilisp-exe> <zig-exe> <tests-dir> <lib.zig> <work-dir> <Debug|ReleaseSafe|ReleaseFast|ReleaseSmall>

const std = @import("std");
const Io = std.Io;

/// 試験 1 つの結果。report は失敗の内容（成功なら空）
const Result = struct {
    ok: bool = false,
    report: []const u8 = "",
};

/// 並列に実行する試験が共有するもの。cases と results は同じ長さで、next が次に実行する番号
const Shared = struct {
    io: Io,
    /// スレッドから使えるアロケータ（結果の文字列はプロセスが終わるまで持つ）
    gpa: std.mem.Allocator,
    zilisp: []const u8,
    zig: []const u8,
    tests_path: []const u8,
    lib_path: []const u8,
    work: []const u8,
    optimize: []const u8,
    cases: []const []const u8,
    results: []Result,
    next: std.atomic.Value(usize) = .init(0),
};

pub fn main(init: std.process.Init) !u8 {
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
    const tests_path = args[3];
    const work = args[5];

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

    const results = try arena.alloc(Result, cases.items.len);
    @memset(results, .{});
    var shared: Shared = .{
        .io = io,
        .gpa = std.heap.smp_allocator,
        .zilisp = args[1],
        .zig = args[2],
        .tests_path = tests_path,
        .lib_path = args[4],
        .work = work,
        .optimize = args[6],
        .cases = cases.items,
        .results = results,
    };

    // 並列の数：環境変数か、論理プロセッサの数の半分（zig build-exe も中でスレッドを使う）。試験の数より多くはしない
    var jobs: usize = @min(8, @max(1, (std.Thread.getCpuCount() catch 2) / 2));
    if (init.environ_map.get("ZILISP_NATIVE_TEST_JOBS")) |s| {
        jobs = std.fmt.parseInt(usize, std.mem.trim(u8, s, " \t\r\n"), 10) catch 0;
        if (jobs == 0) {
            try out.writeAll("native-test: ZILISP_NATIVE_TEST_JOBS は 1 以上の数にしてください\n");
            return 2;
        }
    }
    jobs = @max(1, @min(jobs, cases.items.len));

    // 自分のスレッドも 1 つ分として働く。スレッドを作れなければ、作れた分だけで続ける
    const threads = try arena.alloc(std.Thread, jobs - 1);
    var started: usize = 0;
    for (threads) |*t| {
        t.* = std.Thread.spawn(.{}, worker, .{&shared}) catch break;
        started += 1;
    }
    worker(&shared);
    for (threads[0..started]) |t| t.join();

    var passed: usize = 0;
    var failed: usize = 0;
    for (results) |r| {
        if (r.ok) passed += 1 else failed += 1;
        try out.writeAll(r.report);
    }
    try out.print("native-test: {d} passed, {d} failed, {d} total（各ファイルを通常と --gc-stress で実行）\n", .{ passed, failed, cases.items.len });
    return if (failed == 0) 0 else 1;
}

/// 残っている試験を 1 つずつ取って実行する
fn worker(s: *Shared) void {
    while (true) {
        const i = s.next.fetchAdd(1, .monotonic);
        if (i >= s.cases.len) return;
        s.results[i] = runCase(s, s.cases[i]) catch |err| .{
            .ok = false,
            .report = std.fmt.allocPrint(s.gpa, "FAIL {s}: 実行器のエラー（{t}）\n", .{ s.cases[i], err }) catch "FAIL: 実行器のエラー\n",
        };
    }
}

/// 試験 1 つ：生成・コンパイル・実行と比較。失敗の内容は report に書く（表示は main が名前の順に行う）
fn runCase(s: *Shared, stem: []const u8) !Result {
    const gpa = s.gpa;
    const io = s.io;
    var arena_state: std.heap.ArenaAllocator = .init(gpa);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    var report: Io.Writer.Allocating = .init(gpa);
    errdefer report.deinit();
    const out = &report.writer;

    const src = try std.fs.path.join(arena, &.{ s.tests_path, try std.fmt.allocPrint(arena, "{s}.lisp", .{stem}) });
    const gen = try std.fs.path.join(arena, &.{ s.work, try std.fmt.allocPrint(arena, "{s}.zig", .{stem}) });
    const bin = try std.fs.path.join(arena, &.{ s.work, try std.fmt.allocPrint(arena, "native-{s}.exe", .{stem}) });

    // 1. 生成
    if (!try step(gpa, io, out, stem, "emit", &.{ s.zilisp, "--emit-zig", src, gen }))
        return .{ .ok = false, .report = try report.toOwnedSlice() };
    // 2. コンパイル（スタックの大きさは src/native/rt.zig の stack_size と同じ。§6.7）
    const root_arg = try std.fmt.allocPrint(arena, "-Mroot={s}", .{gen});
    const lib_arg = try std.fmt.allocPrint(arena, "-Mzilisp={s}", .{s.lib_path});
    const bin_arg = try std.fmt.allocPrint(arena, "-femit-bin={s}", .{bin});
    if (!try step(gpa, io, out, stem, "compile", &.{ s.zig, "build-exe", "-O", s.optimize, "--stack", "67108864", "--dep", "zilisp", root_arg, lib_arg, bin_arg }))
        return .{ .ok = false, .report = try report.toOwnedSlice() };
    // 3. 実行と比較
    const cwd = Io.Dir.cwd();
    const expected_path = try std.fs.path.join(arena, &.{ s.tests_path, try std.fmt.allocPrint(arena, "{s}.expected", .{stem}) });
    const expected = cwd.readFileAlloc(io, expected_path, arena, .limited(16 * 1024 * 1024)) catch |err| {
        try out.print("FAIL {s}: {s}.expected を読めません（{t}）\n", .{ stem, stem, err });
        return .{ .ok = false, .report = try report.toOwnedSlice() };
    };
    var expected_exit: u8 = 0;
    const exit_path = try std.fs.path.join(arena, &.{ s.tests_path, try std.fmt.allocPrint(arena, "{s}.exit", .{stem}) });
    if (cwd.readFileAlloc(io, exit_path, arena, .limited(64))) |text| {
        expected_exit = std.fmt.parseInt(u8, std.mem.trim(u8, text, " \t\r\n"), 10) catch 255;
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
    return .{ .ok = ok, .report = try report.toOwnedSlice() };
}

/// 外部のコマンドを実行する。成功すれば true、失敗すれば内容を out に書いて false
fn step(gpa: std.mem.Allocator, io: Io, out: *Io.Writer, stem: []const u8, what: []const u8, argv: []const []const u8) !bool {
    const r = try std.process.run(gpa, io, .{ .argv = argv });
    defer gpa.free(r.stdout);
    defer gpa.free(r.stderr);
    const ok = switch (r.term) {
        .exited => |c| c == 0,
        else => false,
    };
    if (ok) return true;
    try out.print("FAIL {s}: {s} に失敗しました\n{s}{s}\n", .{ stem, what, r.stdout, r.stderr });
    return false;
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
