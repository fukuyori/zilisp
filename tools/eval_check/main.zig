//! 教材のブロックを VM で実行し、SBCL の結果と比べる道具（`zig build eval-check`。Phase 13。詳細設計 §13.1）。
//!
//! 対象：classify.tsv で候補が A（外部ライブラリを参照しない）のブロック。
//! 各ブロックを `zilisp --script` と `sbcl --script` で実行し（作業用のディレクトリの中で。時間制限あり）、
//! 結果を次に分ける。
//!   match        両方とも正常に終わり、標準出力が同じ
//!   both-error   両方ともエラーで終わった（教材がエラーを見せる例など）
//!   output-diff  両方とも正常に終わったが、標準出力が違う
//!   zilisp-error Zilisp だけがエラー（未実装の機能など）。最初のエラーの種類で集計する
//!   sbcl-error   SBCL だけがエラー
//!   timeout      どちらかが時間内に終わらなかった
//! 結果の一覧（TSV）と、集計（Markdown）を書く。
//!
//! 使い方：eval-check <zilisp-exe> <sbcl-exe> <samples-dir> <work-dir> <report.md>

const std = @import("std");
const Io = std.Io;

const timeout_s = 10;

const Outcome = enum { match, @"both-error", @"output-diff", @"zilisp-error", @"sbcl-error", timeout };
const outcome_names = std.meta.fieldNames(Outcome);

const Run = struct {
    ok: bool,
    timed_out: bool,
    stdout: []const u8,
    stderr: []const u8,
};

fn runOne(arena: std.mem.Allocator, io: Io, cwd: []const u8, argv: []const []const u8) !Run {
    const r = std.process.run(arena, io, .{
        .argv = argv,
        .cwd = .{ .path = cwd },
        .timeout = .{ .duration = .{ .raw = .fromSeconds(timeout_s), .clock = .awake } },
        .stdout_limit = .limited(4 * 1024 * 1024),
        .stderr_limit = .limited(4 * 1024 * 1024),
    }) catch |err| switch (err) {
        error.Timeout => return .{ .ok = false, .timed_out = true, .stdout = "", .stderr = "" },
        error.StreamTooLong => return .{ .ok = false, .timed_out = true, .stdout = "", .stderr = "出力が多すぎます" },
        else => return err,
    };
    const ok = switch (r.term) {
        .exited => |c| c == 0,
        else => false,
    };
    return .{ .ok = ok, .timed_out = false, .stdout = r.stdout, .stderr = r.stderr };
}

/// Zilisp の標準エラー出力の最初のエラーから、集計の鍵を作る
///   未実装の機能 → その名前（例：DEFVAR、FORMAT）。それ以外 → 型の名前
fn errorKey(arena: std.mem.Allocator, stderr: []const u8) ![]const u8 {
    var lines = std.mem.splitScalar(u8, stderr, '\n');
    const first = std.mem.trimEnd(u8, lines.next() orelse return "（出力なし）", "\r");
    // 形：FILE:LINE:COL: TYPE: 説明[: 値]
    var it = std.mem.splitSequence(u8, first, ": ");
    _ = it.next();
    const kind = it.next() orelse return arena.dupe(u8, first);
    const rest = it.rest();
    if (std.mem.eql(u8, kind, "ZILISP:UNIMPLEMENTED")) {
        // 説明の後の値が未実装のもの（シンボル）。値がなければ説明の先頭
        if (std.mem.lastIndexOf(u8, rest, "）: ")) |i| return std.fmt.allocPrint(arena, "未実装：{s}", .{rest[i + "）: ".len ..]});
        if (std.mem.lastIndexOf(u8, rest, ": ")) |i| return std.fmt.allocPrint(arena, "未実装：{s}", .{rest[i + 2 ..]});
        const cut = std.mem.indexOf(u8, rest, "（") orelse rest.len;
        return std.fmt.allocPrint(arena, "未実装：{s}", .{rest[0..cut]});
    }
    if (std.mem.eql(u8, kind, "UNBOUND-VARIABLE") and std.mem.startsWith(u8, rest, "変数 ") and std.mem.indexOf(u8, rest, "未実装") != null) {
        const after = rest["変数 ".len..];
        const sp = std.mem.indexOfScalar(u8, after, ' ') orelse after.len;
        return std.fmt.allocPrint(arena, "未実装の変数：{s}", .{after[0..sp]});
    }
    if (std.mem.eql(u8, kind, "UNDEFINED-FUNCTION")) {
        // 関数 NAME は未実装です／定義されていません
        if (std.mem.startsWith(u8, rest, "関数 ")) {
            const after = rest["関数 ".len..];
            const sp = std.mem.indexOfScalar(u8, after, ' ') orelse after.len;
            const what = if (std.mem.indexOf(u8, after, "未実装") != null) "未実装の関数" else "未定義の関数";
            return std.fmt.allocPrint(arena, "{s}：{s}", .{ what, after[0..sp] });
        }
    }
    return arena.dupe(u8, kind);
}

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

const Count = struct { key: []const u8, n: usize };

pub fn main(init: std.process.Init) !u8 {
    const arena = init.arena.allocator();
    const io = init.io;
    const args = try init.minimal.args.toSlice(arena);
    var out_buf: [4096]u8 = undefined;
    var out_fw: Io.File.Writer = .init(.stdout(), io, &out_buf);
    const out = &out_fw.interface;
    defer out.flush() catch {};
    if (args.len != 6) {
        try out.writeAll("usage: eval-check <zilisp-exe> <sbcl-exe> <samples-dir> <work-dir> <report.md>\n");
        return 2;
    }
    const zilisp = try Io.Dir.cwd().realPathFileAlloc(io, args[1], arena);
    const sbcl = args[2];
    const samples = args[3];
    const work = args[4];
    const report_path = args[5];

    const cwd = Io.Dir.cwd();
    try cwd.createDirPath(io, work);
    const work_abs = try cwd.realPathFileAlloc(io, work, arena);
    const samples_abs = try cwd.realPathFileAlloc(io, samples, arena);

    const classify = try cwd.readFileAlloc(io, try std.fs.path.join(arena, &.{ samples, "classify.tsv" }), arena, .limited(16 * 1024 * 1024));
    var rows = std.mem.splitScalar(u8, classify, '\n');
    _ = rows.next(); // 見出し

    var counts: [outcome_names.len]usize = @splat(0);
    var keys: std.StringHashMapUnmanaged(usize) = .empty;
    var tsv: Io.Writer.Allocating = .init(arena);
    try tsv.writer.writeAll("seq\tid\toutcome\tdetail\n");
    var total: usize = 0;

    while (rows.next()) |row_raw| {
        const row = std.mem.trimEnd(u8, row_raw, "\r");
        if (row.len == 0) continue;
        var cols = std.mem.splitScalar(u8, row, '\t');
        const seq = cols.next() orelse continue;
        const id = cols.next() orelse continue;
        _ = cols.next(); // status
        const candidate = cols.next() orelse continue;
        if (!std.mem.eql(u8, candidate, "A")) continue;
        total += 1;

        const file = try std.fs.path.join(arena, &.{ samples_abs, "blocks", try std.fmt.allocPrint(arena, "{s}.lisp", .{seq}) });
        // ブロックごとに空の作業用ディレクトリで実行する（ブロックが書くファイルを閉じ込める）
        const dir = try std.fs.path.join(arena, &.{ work_abs, seq });
        try cwd.createDirPath(io, dir);
        const z = try runOne(arena, io, dir, &.{ zilisp, "--script", file });
        const s = try runOne(arena, io, dir, &.{ sbcl, "--script", file });

        var detail: []const u8 = "";
        const outcome: Outcome = blk: {
            if (z.timed_out or s.timed_out) break :blk .timeout;
            if (z.ok and s.ok) {
                const a = try normalize(arena, z.stdout);
                const b = try normalize(arena, s.stdout);
                break :blk if (std.mem.eql(u8, a, b)) .match else .@"output-diff";
            }
            if (!z.ok and !s.ok) break :blk .@"both-error";
            if (!z.ok) {
                detail = try errorKey(arena, z.stderr);
                const gop = try keys.getOrPut(arena, detail);
                if (!gop.found_existing) gop.value_ptr.* = 0;
                gop.value_ptr.* += 1;
                break :blk .@"zilisp-error";
            }
            break :blk .@"sbcl-error";
        };
        counts[@backingInt(outcome)] += 1;
        try tsv.writer.print("{s}\t{s}\t{s}\t{s}\n", .{ seq, id, @tagName(outcome), detail });
    }

    // 集計
    var list: std.ArrayList(Count) = .empty;
    var kit = keys.iterator();
    while (kit.next()) |e| try list.append(arena, .{ .key = e.key_ptr.*, .n = e.value_ptr.* });
    std.mem.sort(Count, list.items, {}, struct {
        fn lt(_: void, a: Count, b: Count) bool {
            if (a.n != b.n) return a.n > b.n;
            return std.mem.lessThan(u8, a.key, b.key);
        }
    }.lt);

    var md: Io.Writer.Allocating = .init(arena);
    const w = &md.writer;
    try w.writeAll(
        \\# 教材のブロックの実行の結果（自動生成）
        \\
        \\このファイルは `zig build eval-check` が生成する。手で編集しない。
        \\教材のブロックのうち、分類の候補が A のものを、Zilisp（VM。`--script`）と SBCL 2.6.7（`--script`）で実行して比べた結果。
        \\ブロックは教材の1つのコードブロックで、単独では動かないもの（前のブロックの定義を使うもの）も含む。
        \\
        \\| 結果 | 意味 | ブロック数 |
        \\|---|---|---|
        \\
    );
    const meanings = [_][]const u8{
        "両方とも正常に終わり、標準出力が同じ",
        "両方ともエラーで終わった",
        "両方とも正常に終わったが、標準出力が違う",
        "Zilisp だけがエラー",
        "SBCL だけがエラー",
        "時間内に終わらなかった",
    };
    for (outcome_names, 0..) |name, i| {
        try w.print("| {s} | {s} | {d} |\n", .{ name, meanings[i], counts[i] });
    }
    try w.print("| 計 | | {d} |\n\n## Zilisp だけがエラーになったブロックの、最初のエラー\n\n| 最初のエラー | ブロック数 |\n|---|---|\n", .{total});
    for (list.items) |c| try w.print("| {s} | {d} |\n", .{ c.key, c.n });
    try w.writeAll("\n各ブロックの結果は `eval-check.tsv`（同じディレクトリ）にある。\n");

    try cwd.writeFile(io, .{ .sub_path = report_path, .data = md.written() });
    const tsv_path = try std.fs.path.join(arena, &.{ std.fs.path.dirname(report_path) orelse ".", "eval-check.tsv" });
    try cwd.writeFile(io, .{ .sub_path = tsv_path, .data = tsv.written() });

    try out.print("eval-check: {d} blocks", .{total});
    for (outcome_names, 0..) |name, i| try out.print(", {s} {d}", .{ name, counts[i] });
    try out.writeAll("\n");
    return 0;
}
