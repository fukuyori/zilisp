//! 教材のブロックを Zilisp の Reader で読み、SBCL での読み込みの結果（classify.tsv）と比べる。
//!
//! 使い方:
//!   zig build reader-check -- <samples-dir>
//! <samples-dir> は scripts/curriculum-inventory.ps1 の出力（.work/samples）。
//!
//! Reader だけを確かめる道具なので、値は作らず、読めたかどうかだけを数える。
//! パッケージの解決は Phase 05 以降のため、SBCL で package-ref（存在しないパッケージ）になったブロックも、
//! Zilisp では読める（構文としては正しい）ことを期待する。

const std = @import("std");
const Io = std.Io;
const reader = @import("zilisp").reader;

const NullBuilder = struct {
    pub const Datum = void;
    pub const List = void;
    pub fn integer(_: *NullBuilder, _: *reader.Diagnostic, _: reader.SourceLoc, _: bool, _: []const u8, _: u8) reader.Error!void {}
    pub fn ratio(_: *NullBuilder, _: *reader.Diagnostic, _: reader.SourceLoc, _: bool, _: []const u8, _: []const u8, _: u8) reader.Error!void {}
    pub fn float(_: *NullBuilder, _: reader.SourceLoc, _: reader.number.Float) reader.Error!void {}
    pub fn symbol(_: *NullBuilder, _: *reader.Diagnostic, _: reader.SourceLoc, _: reader.PackageRef, _: []const u8) reader.Error!void {}
    pub fn nil(_: *NullBuilder, _: reader.SourceLoc) reader.Error!void {}
    pub fn string(_: *NullBuilder, _: reader.SourceLoc, _: []const u8) reader.Error!void {}
    pub fn character(_: *NullBuilder, _: reader.SourceLoc, _: u21) reader.Error!void {}
    pub fn listBegin(_: *NullBuilder, _: reader.SourceLoc) reader.Error!void {}
    pub fn listPush(_: *NullBuilder, _: *void, _: void) reader.Error!void {}
    pub fn listEnd(_: *NullBuilder, _: *void, _: ?void) reader.Error!void {}
    pub fn vectorEnd(_: *NullBuilder, _: *void) reader.Error!void {}
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

    if (args.len != 2) {
        try out.writeAll("usage: reader-check <samples-dir>\n");
        return 2;
    }
    var dir = try Io.Dir.cwd().openDir(io, args[1], .{});
    defer dir.close(io);
    const classify = try dir.readFileAlloc(io, "classify.tsv", arena, .limited(64 * 1024 * 1024));

    var total: usize = 0;
    var both_ok: usize = 0;
    var both_error: usize = 0;
    var zilisp_only_error: usize = 0;
    var sbcl_only_error: usize = 0;
    var lines = std.mem.splitScalar(u8, classify, '\n');
    _ = lines.next(); // 見出し
    while (lines.next()) |line_raw| {
        const line = std.mem.trimEnd(u8, line_raw, "\r");
        if (line.len == 0) continue;
        var cols = std.mem.splitScalar(u8, line, '\t');
        const seq = cols.next() orelse continue;
        const id = cols.next() orelse continue;
        const status = cols.next() orelse continue;
        total += 1;

        const path = try std.fmt.allocPrint(arena, "blocks/{s}.lisp", .{seq});
        const text = try dir.readFileAlloc(io, path, gpa, .limited(16 * 1024 * 1024));
        defer gpa.free(text);

        var src = reader.Source.init(text, 0);
        var b: NullBuilder = .{};
        var r = reader.Reader(NullBuilder).init(gpa, &src, &b, .{});
        defer r.deinit();
        var err_name: ?[]const u8 = null;
        while (true) {
            const d = r.read() catch |err| {
                err_name = @errorName(err);
                break;
            };
            if (d == null) break;
        }
        // SBCL で「構文として読めた」とみなす状態
        const sbcl_ok = std.mem.eql(u8, status, "ok") or std.mem.eql(u8, status, "package-ref") or
            std.mem.eql(u8, status, "curriculum-package");
        if (err_name) |e| {
            if (sbcl_ok) {
                zilisp_only_error += 1;
                try out.print("ZILISP-ERROR\t{s}\t{s}\t{d}:{d}\t{s}\n", .{ id, e, r.diagnostic.loc.line, r.diagnostic.loc.col, r.diagnostic.message });
            } else both_error += 1;
        } else {
            if (sbcl_ok) both_ok += 1 else {
                sbcl_only_error += 1;
                try out.print("SBCL-ONLY-ERROR\t{s}\t{s}\n", .{ id, status });
            }
        }
    }
    try out.print("total {d}: both-ok {d}, both-error {d}, zilisp-only-error {d}, sbcl-only-error {d}\n", .{
        total, both_ok, both_error, zilisp_only_error, sbcl_only_error,
    });
    return 0;
}
