//! ソースの実行・式の評価・REPL（Phase 08）。
//!   zilisp FILE / zilisp --script FILE   FILE のフォームを順に読んで評価する。エラーで止まり、終了コード 1
//!   zilisp --eval TEXT                   TEXT のフォームを順に評価する（結果は印字しない。SBCL の --eval と同じ）
//!   zilisp --load FILE                   FILE を評価してから REPL を始める
//!   zilisp                               REPL
//! フォームは1つ読むごとに評価する（CL の load と同じ順序。後で in-package などが読み方を変えるため）。

const std = @import("std");
const Io = std.Io;
const reader = @import("../reader/reader.zig");
const vb = @import("../reader/value_builder.zig");
const printer = @import("../printer/printer.zig");
const Runtime = @import("../runtime/runtime.zig").Runtime;
const Thread = @import("../runtime/thread.zig").Thread;
const Value = @import("../values/value.zig").Value;
const eval_mod = @import("../compiler/eval.zig");
const Options = @import("args.zig").Options;
const read_command = @import("read_command.zig");

pub const Result = enum { ok, failed };

pub const Session = struct {
    rt: *Runtime,
    th: *Thread,
    options: Options,

    pub fn create(gpa: std.mem.Allocator, io: ?Io, options: Options, out: *Io.Writer) error{OutOfMemory}!Session {
        const rt = try Runtime.create(gpa);
        errdefer rt.destroy();
        rt.io = io;
        const th = try Thread.create(rt, out, .{});
        rt.heap.stress = options.gc_stress;
        return .{ .rt = rt, .th = th, .options = options };
    }

    pub fn destroy(s: *Session, stderr: *Io.Writer) void {
        if (s.options.gc_stats) read_command.printGcStats(s.rt, stderr) catch {};
        s.th.destroy();
        s.rt.destroy();
    }
};

const LoadResult = enum { ok, failed, incomplete };

/// テキストのフォームを順に読んで評価する。
/// repl が真なら、各フォームの値を印字し、エラーでも続ける。テキストの途中でフォームが終わっていなければ
/// incomplete を返し、consumed にそこまでのバイト数を書く。
fn evalText(
    s: *Session,
    gpa: std.mem.Allocator,
    text: []const u8,
    name: []const u8,
    interactive: bool,
    consumed: *usize,
    stdout: *Io.Writer,
    stderr: *Io.Writer,
) Io.Writer.Error!LoadResult {
    var src = reader.Source.init(text, 1);
    var b: vb.ValueBuilder = .{ .rt = s.rt };
    var r = reader.Reader(vb.ValueBuilder).init(gpa, &src, &b, .{});
    defer r.deinit();
    var failed = false;
    while (true) {
        const start = src.pos;
        const form = r.read() catch |err| {
            if (err == error.EndOfFile and interactive) {
                consumed.* = start;
                return .incomplete;
            }
            const d = r.diagnostic;
            try stdout.flush();
            const kind = switch (err) {
                error.EndOfFile => "END-OF-FILE",
                error.ReaderError => "READER-ERROR",
                error.OutOfMemory => "STORAGE-CONDITION",
            };
            try stderr.print("{s}:{d}:{d}: {s}: {s}\n", .{ name, d.loc.line, d.loc.col, kind, d.message });
            try stderr.flush();
            consumed.* = text.len;
            return .failed;
        } orelse break;
        const loc = r.start_loc orelse src.loc();
        const value = eval_mod.eval(s.th, form);
        if (value == Value.unwind) {
            try stdout.flush();
            try stderr.print("{s}:{d}:{d}: ", .{ name, loc.line, loc.col });
            try s.th.writeError(stderr);
            try stderr.writeByte('\n');
            try stderr.flush();
            s.th.clearError();
            if (!interactive) {
                consumed.* = text.len;
                return .failed;
            }
            failed = true;
            continue;
        }
        if (interactive) {
            try printer.prin1(s.rt, stdout, value);
            try stdout.writeByte('\n');
        }
    }
    consumed.* = text.len;
    return if (failed) .failed else .ok;
}

fn readFile(gpa: std.mem.Allocator, io: Io, path: []const u8, stderr: *Io.Writer) Io.Writer.Error!?[]u8 {
    return Io.Dir.cwd().readFileAlloc(io, path, gpa, .limited(256 * 1024 * 1024)) catch |err| {
        try stderr.print("zilisp: {s} を読めません: {t}\n", .{ path, err });
        return null;
    };
}

/// FILE のフォームを順に評価する
pub fn runScript(gpa: std.mem.Allocator, io: Io, options: Options, path: []const u8, stdout: *Io.Writer, stderr: *Io.Writer) Io.Writer.Error!Result {
    const text = (try readFile(gpa, io, path, stderr)) orelse return .failed;
    defer gpa.free(text);
    var s = Session.create(gpa, io, options, stdout) catch {
        try stderr.writeAll("zilisp: メモリが足りません\n");
        return .failed;
    };
    defer s.destroy(stderr);
    var consumed: usize = 0;
    return switch (try evalText(&s, gpa, text, path, false, &consumed, stdout, stderr)) {
        .ok => .ok,
        else => .failed,
    };
}

/// TEXT のフォームを順に評価する
pub fn runEval(gpa: std.mem.Allocator, io: Io, options: Options, text: []const u8, stdout: *Io.Writer, stderr: *Io.Writer) Io.Writer.Error!Result {
    var s = Session.create(gpa, io, options, stdout) catch {
        try stderr.writeAll("zilisp: メモリが足りません\n");
        return .failed;
    };
    defer s.destroy(stderr);
    var consumed: usize = 0;
    return switch (try evalText(&s, gpa, text, "--eval", false, &consumed, stdout, stderr)) {
        .ok => .ok,
        else => .failed,
    };
}

pub const prompt = "* ";

/// REPL。in から1行ずつ読み、フォームが揃うたびに評価して値を印字する。入力が終われば終わる。
/// 評価のエラーは報告して続ける（終了コードには影響しない。SBCL の REPL と同じ）。
/// フォームの途中で入力が終わった場合・入力を読めない場合・メモリが足りない場合は failed を返す
pub fn repl(s: *Session, gpa: std.mem.Allocator, in: *Io.Reader, stdout: *Io.Writer, stderr: *Io.Writer) Io.Writer.Error!Result {
    var pending: std.ArrayList(u8) = .empty;
    defer pending.deinit(gpa);
    while (true) {
        if (pending.items.len == 0) try stdout.writeAll(prompt);
        try stdout.flush();
        const line = in.takeDelimiter('\n') catch |err| switch (err) {
            error.StreamTooLong => {
                try stderr.writeAll("zilisp: 入力の行が長すぎます\n");
                try stderr.flush();
                pending.clearRetainingCapacity();
                // 行の残りを読み捨てる
                _ = in.discardDelimiterInclusive('\n') catch {};
                continue;
            },
            error.ReadFailed => {
                try stdout.flush();
                try stderr.writeAll("zilisp: 入力を読めません\n");
                try stderr.flush();
                return .failed;
            },
        } orelse {
            try stdout.writeByte('\n');
            if (std.mem.trim(u8, pending.items, " \t\r\n").len != 0) {
                // フォームの途中で入力が終わった：END-OF-FILE として報告する
                var consumed: usize = 0;
                _ = try evalText(s, gpa, pending.items, "<repl>", false, &consumed, stdout, stderr);
                return .failed;
            }
            return .ok;
        };
        pending.appendSlice(gpa, line) catch return outOfMemory(stderr);
        pending.append(gpa, '\n') catch return outOfMemory(stderr);
        var consumed: usize = 0;
        const result = try evalText(s, gpa, pending.items, "<repl>", true, &consumed, stdout, stderr);
        if (result == .incomplete) {
            // 読み終わったフォームを除き、途中のフォームの続きを待つ
            const rest = pending.items.len - consumed;
            std.mem.copyForwards(u8, pending.items[0..rest], pending.items[consumed..]);
            pending.shrinkRetainingCapacity(rest);
        } else {
            pending.clearRetainingCapacity();
        }
    }
}

/// --load FILE の後、または引数なしで REPL を始める
pub fn runRepl(gpa: std.mem.Allocator, io: Io, options: Options, load: ?[]const u8, stdout: *Io.Writer, stderr: *Io.Writer) Io.Writer.Error!Result {
    var s = Session.create(gpa, io, options, stdout) catch {
        try stderr.writeAll("zilisp: メモリが足りません\n");
        return .failed;
    };
    defer s.destroy(stderr);
    if (load) |path| {
        const text = (try readFile(gpa, io, path, stderr)) orelse return .failed;
        defer gpa.free(text);
        var consumed: usize = 0;
        if (try evalText(&s, gpa, text, path, false, &consumed, stdout, stderr) != .ok) return .failed;
    }
    var buf: [64 * 1024]u8 = undefined;
    var fr: Io.File.Reader = .init(.stdin(), io, &buf);
    return repl(&s, gpa, &fr.interface, stdout, stderr);
}

fn outOfMemory(stderr: *Io.Writer) Io.Writer.Error!Result {
    try stderr.writeAll("zilisp: メモリが足りません\n");
    try stderr.flush();
    return .failed;
}

// ---------------------------------------------------------------------------

const testing = std.testing;

const Transcript = struct { text: []u8, result: Result };

fn replTranscript(input: []const u8) !Transcript {
    var out: Io.Writer.Allocating = .init(testing.allocator);
    defer out.deinit();
    var err: Io.Writer.Allocating = .init(testing.allocator);
    defer err.deinit();
    var s = try Session.create(testing.allocator, null, .{}, &out.writer);
    defer s.destroy(&err.writer);
    var in: Io.Reader = .fixed(input);
    const result = try repl(&s, testing.allocator, &in, &out.writer, &err.writer);
    try out.writer.writeAll("--\n");
    try out.writer.writeAll(err.written());
    return .{ .text = try out.toOwnedSlice(), .result = result };
}

test "repl reports END-OF-FILE when input ends inside a form" {
    for ([_][]const u8{ "(+ 1\n", "(+ 1 2) (list\n", "\"abc\n", "#| comment\n", "'\n" }) |input| {
        const t = try replTranscript(input);
        defer testing.allocator.free(t.text);
        testing.expectEqual(Result.failed, t.result) catch |e| {
            std.debug.print("input: {s}\n", .{input});
            return e;
        };
        try testing.expect(std.mem.indexOf(u8, t.text, "END-OF-FILE") != null);
    }
    // 空白とコメントだけで終わるのは正常
    const t = try replTranscript("(+ 1 2)\n  ; comment\n");
    defer testing.allocator.free(t.text);
    try testing.expectEqual(Result.ok, t.result);
}

test "repl evaluates forms, waits for unfinished forms, and keeps going after errors" {
    const t = try replTranscript("(+ 1 2)\n(list 1\n 2 3) 'a\nundefined-var\n(car 1)\n(setq x 5)\nx\n");
    defer testing.allocator.free(t.text);
    // 評価のエラーは終了コードに影響しない
    try testing.expectEqual(Result.ok, t.result);
    const got = t.text;
    try testing.expectEqualStrings(
        "* 3\n* (1 2 3)\nA\n* * * 5\n* 5\n* \n--\n" ++
            "<repl>:1:1: UNBOUND-VARIABLE: 変数 UNDEFINED-VAR に値がありません\n" ++
            "<repl>:1:1: TYPE-ERROR: 値 1 は型 LIST ではありません\n",
        got,
    );
}
