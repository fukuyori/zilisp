//! 教材の Markdown から Lisp のコードブロックを抽出する（詳細設計 §12 の手順 2）。
//!
//! 使い方:
//!   zig build extract-samples -- <教材のディレクトリ> <出力ディレクトリ>
//!
//! 出力（出力ディレクトリの下）:
//!   blocks/NNNNN.lisp   Lisp のブロックの中身（1 ブロック 1 ファイル）
//!   index.tsv           seq, id, path, start_line, end_line, lang, bytes
//!   langs.tsv           path, lang, count（Lisp 以外を含む全ブロックの言語別の数）
//!   anomalies.tsv       path, line, kind, text（囲みの異常）
//! ID は「<Markdown のパス>#L<開始行>」とする（パスの区切りは / にそろえる）。

const std = @import("std");
const Io = std.Io;
const extract = @import("extract.zig");

pub fn main(init: std.process.Init) !u8 {
    const gpa = init.gpa;
    const arena = init.arena.allocator();
    const io = init.io;
    const args = try init.minimal.args.toSlice(arena);

    var err_buf: [1024]u8 = undefined;
    var err_fw: Io.File.Writer = .init(.stderr(), io, &err_buf);
    const stderr = &err_fw.interface;
    defer stderr.flush() catch {};

    if (args.len != 3) {
        try stderr.writeAll("usage: extract-samples <curriculum-dir> <out-dir>\n");
        return 2;
    }
    const src_path = args[1];
    const out_path = args[2];

    const cwd = Io.Dir.cwd();
    var src_dir = try cwd.openDir(io, src_path, .{ .iterate = true });
    defer src_dir.close(io);
    try cwd.createDirPath(io, out_path);
    var out_dir = try cwd.openDir(io, out_path, .{});
    defer out_dir.close(io);
    try out_dir.createDirPath(io, "blocks");

    // Markdown のパスを集めて並べる（走査の順序は不定のため）
    var paths: std.ArrayList([]const u8) = .empty;
    {
        var walker = try src_dir.walk(gpa);
        defer walker.deinit();
        while (try walker.next(io)) |entry| {
            if (entry.kind != .file) continue;
            if (!std.ascii.endsWithIgnoreCase(entry.path, ".md")) continue;
            const p = try arena.dupe(u8, entry.path);
            std.mem.replaceScalar(u8, p, '\\', '/');
            try paths.append(arena, p);
        }
    }
    std.mem.sort([]const u8, paths.items, {}, struct {
        fn lt(_: void, a: []const u8, b: []const u8) bool {
            return std.mem.lessThan(u8, a, b);
        }
    }.lt);

    var index: Io.Writer.Allocating = .init(gpa);
    defer index.deinit();
    var langs: Io.Writer.Allocating = .init(gpa);
    defer langs.deinit();
    var anomalies: Io.Writer.Allocating = .init(gpa);
    defer anomalies.deinit();
    try index.writer.writeAll("seq\tid\tpath\tstart_line\tend_line\tlang\tbytes\n");
    try langs.writer.writeAll("path\tlang\tcount\n");
    try anomalies.writer.writeAll("path\tline\tkind\ttext\n");

    var seq: u32 = 0;
    var total_blocks: usize = 0;
    var total_anomalies: usize = 0;
    for (paths.items) |p| {
        const text = try src_dir.readFileAlloc(io, p, gpa, .limited(16 * 1024 * 1024));
        defer gpa.free(text);
        var r = try extract.extract(gpa, text);
        defer r.deinit(gpa);
        total_blocks += r.blocks.items.len;
        total_anomalies += r.anomalies.items.len;

        var counts: std.StringArrayHashMapUnmanaged(u32) = .empty;
        defer counts.deinit(gpa);
        for (r.blocks.items) |b| {
            const key = if (b.lang.len == 0) "(none)" else b.lang;
            const gop = try counts.getOrPut(gpa, key);
            if (!gop.found_existing) gop.value_ptr.* = 0;
            gop.value_ptr.* += 1;

            if (!extract.isLispLang(b.lang)) continue;
            seq += 1;
            var name_buf: [32]u8 = undefined;
            const name = try std.fmt.bufPrint(&name_buf, "blocks/{d:0>5}.lisp", .{seq});
            try out_dir.writeFile(io, .{ .sub_path = name, .data = b.body });
            try index.writer.print("{d:0>5}\t{s}#L{d}\t{s}\t{d}\t{d}\t{s}\t{d}\n", .{
                seq, p, b.start_line, p, b.start_line, b.end_line, b.lang, b.body.len,
            });
        }
        var it = counts.iterator();
        while (it.next()) |e| {
            try langs.writer.print("{s}\t{s}\t{d}\n", .{ p, tsvSafe(e.key_ptr.*), e.value_ptr.* });
        }
        for (r.anomalies.items) |a| {
            try anomalies.writer.print("{s}\t{d}\t{s}\t{s}\n", .{ p, a.line, a.kind.label(), tsvSafe(a.text) });
        }
    }

    try out_dir.writeFile(io, .{ .sub_path = "index.tsv", .data = index.written() });
    try out_dir.writeFile(io, .{ .sub_path = "langs.tsv", .data = langs.written() });
    try out_dir.writeFile(io, .{ .sub_path = "anomalies.tsv", .data = anomalies.written() });

    var out_buf: [1024]u8 = undefined;
    var out_fw: Io.File.Writer = .init(.stdout(), io, &out_buf);
    const stdout = &out_fw.interface;
    try stdout.print("markdown files: {d}\nblocks (all languages): {d}\nlisp blocks: {d}\nanomalies: {d}\n", .{
        paths.items.len, total_blocks, seq, total_anomalies,
    });
    try stdout.flush();
    return 0;
}

/// TSV の区切り文字（タブ・改行）を含まないようにする（そのまま返し、含む場合は表示用に置き換えない）
fn tsvSafe(s: []const u8) []const u8 {
    if (std.mem.indexOfAny(u8, s, "\t\r\n") == null) return s;
    return "(contains tab/newline)";
}

test {
    _ = extract;
}
