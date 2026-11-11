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
//!
//! 試験は並列に実行する（確保のたびに GC を行う gc-stress の試験に時間がかかる）。ディレクトリが違っても同じ名前の
//! 試験（eval/NAME.lisp と gc-stress/NAME.lisp）は同じファイルを書くことがあるので、同じ名前の試験は 1 つの組にして
//! 順に実行し、組どうしを並列にする。並列の数は、環境変数 ZILISP_LANG_TEST_JOBS（1 以上の数）か、なければ
//! 論理プロセッサの数（1〜16）。結果は、すべて終わってからパスの順に表示する（並列の数によらず同じ出力）。

const std = @import("std");
const Io = std.Io;

/// 試験 1 つの結果。report は失敗の内容（成功なら空）
const Result = struct {
    ok: bool = false,
    report: []const u8 = "",
};

/// 並列に実行する試験が共有するもの。cases と results は同じ長さ。groups は同じ名前の試験の番号の組で、
/// next が次に実行する組の番号
const Shared = struct {
    io: Io,
    /// スレッドから使えるアロケータ（結果の文字列はプロセスが終わるまで持つ）
    gpa: std.mem.Allocator,
    exe: []const u8,
    tests_path: []const u8,
    cases: []const []const u8,
    results: []Result,
    groups: []const []const usize,
    next: std.atomic.Value(usize) = .init(0),
};

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

    // 同じ名前（ディレクトリを除いたファイル名）の試験を 1 つの組にする
    var groups: std.ArrayList([]const usize) = .empty;
    {
        var by_name: std.StringHashMapUnmanaged(std.ArrayList(usize)) = .empty;
        var order: std.ArrayList([]const u8) = .empty;
        for (cases.items, 0..) |rel, i| {
            const name = std.fs.path.basename(rel);
            const gop = try by_name.getOrPut(arena, name);
            if (!gop.found_existing) {
                gop.value_ptr.* = .empty;
                try order.append(arena, name);
            }
            try gop.value_ptr.append(arena, i);
        }
        for (order.items) |name| try groups.append(arena, by_name.get(name).?.items);
    }

    const results = try arena.alloc(Result, cases.items.len);
    @memset(results, .{});
    var shared: Shared = .{
        .io = io,
        .gpa = std.heap.smp_allocator,
        .exe = exe,
        .tests_path = tests_path,
        .cases = cases.items,
        .results = results,
        .groups = groups.items,
    };

    // 並列の数：環境変数か、論理プロセッサの数。組の数より多くはしない
    var jobs: usize = @min(16, @max(1, std.Thread.getCpuCount() catch 2));
    if (init.environ_map.get("ZILISP_LANG_TEST_JOBS")) |s| {
        jobs = std.fmt.parseInt(usize, std.mem.trim(u8, s, " \t\r\n"), 10) catch 0;
        if (jobs == 0) {
            try out.writeAll("lang-test: ZILISP_LANG_TEST_JOBS は 1 以上の数にしてください\n");
            return 2;
        }
    }
    jobs = @max(1, @min(jobs, @max(groups.items.len, 1)));

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
    try out.print("lang-test: {d} passed, {d} failed, {d} total\n", .{ passed, failed, cases.items.len });
    return if (failed == 0) 0 else 1;
}

/// 残っている組を 1 つずつ取り、組の中の試験を順に実行する
fn worker(s: *Shared) void {
    while (true) {
        const g = s.next.fetchAdd(1, .monotonic);
        if (g >= s.groups.len) return;
        for (s.groups[g]) |i| {
            s.results[i] = runCase(s, s.cases[i]) catch |err| .{
                .ok = false,
                .report = std.fmt.allocPrint(s.gpa, "FAIL {s}: 実行器のエラー（{t}）\n", .{ s.cases[i], err }) catch "FAIL: 実行器のエラー\n",
            };
        }
    }
}

/// 試験 1 つ：実行して、標準出力と終了コードを期待値と比べる。失敗の内容は report に書く（表示は main がパスの順に行う）
fn runCase(s: *Shared, rel: []const u8) !Result {
    const gpa = s.gpa;
    const io = s.io;
    var arena_state: std.heap.ArenaAllocator = .init(gpa);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    var report: Io.Writer.Allocating = .init(gpa);
    errdefer report.deinit();
    const out = &report.writer;

    const cwd = Io.Dir.cwd();
    const stem = rel[0 .. rel.len - ".lisp".len];
    const full = try std.fs.path.join(arena, &.{ s.tests_path, rel });
    const expected_path = try std.fmt.allocPrint(arena, "{s}{c}{s}.expected", .{ s.tests_path, std.fs.path.sep, stem });
    const exit_path = try std.fmt.allocPrint(arena, "{s}{c}{s}.exit", .{ s.tests_path, std.fs.path.sep, stem });

    const expected = cwd.readFileAlloc(io, expected_path, arena, .limited(16 * 1024 * 1024)) catch |err| {
        try out.print("FAIL {s}: {s}.expected を読めません（{t}）\n", .{ rel, stem, err });
        return .{ .ok = false, .report = try report.toOwnedSlice() };
    };
    var expected_exit: u8 = 0;
    if (cwd.readFileAlloc(io, exit_path, arena, .limited(64))) |text| {
        expected_exit = std.fmt.parseInt(u8, std.mem.trim(u8, text, " \t\r\n"), 10) catch 255;
    } else |_| {}

    var argv: std.ArrayList([]const u8) = .empty;
    try argv.append(arena, s.exe);
    const args_path = try std.fmt.allocPrint(arena, "{s}{c}{s}.args", .{ s.tests_path, std.fs.path.sep, stem });
    const default_args_path = try std.fs.path.join(arena, &.{ s.tests_path, std.fs.path.dirname(rel) orelse ".", "default.args" });
    const args_text: ?[]u8 = cwd.readFileAlloc(io, args_path, arena, .limited(4096)) catch
        (cwd.readFileAlloc(io, default_args_path, arena, .limited(4096)) catch null);
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
        report.deinit();
        return .{ .ok = true, .report = "" };
    }
    try out.print("FAIL {s}: exit={?d}（期待 {d}）\n--- expected\n{s}\n--- actual\n{s}\n--- stderr\n{s}\n", .{
        rel, code, expected_exit, want, got, r.stderr,
    });
    return .{ .ok = false, .report = try report.toOwnedSlice() };
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
