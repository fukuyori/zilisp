//! zilisp --read FILE：ファイルのデータを読み、1つずつ prin1 で印字する（各データの後に改行）。
//! SBCL での同じ処理（tools/sbcl_read_print.lisp）と出力を比べて、Reader と印字を確かめる。

const std = @import("std");
const Io = std.Io;
const reader = @import("../reader/reader.zig");
const vb = @import("../reader/value_builder.zig");
const printer = @import("../printer/printer.zig");
const Runtime = @import("../runtime/runtime.zig").Runtime;

pub const Result = enum { ok, failed };

pub fn run(gpa: std.mem.Allocator, io: Io, path: []const u8, stdout: *Io.Writer, stderr: *Io.Writer) Io.Writer.Error!Result {
    const text = Io.Dir.cwd().readFileAlloc(io, path, gpa, .limited(256 * 1024 * 1024)) catch |err| {
        try stderr.print("zilisp: {s} を読めません: {t}\n", .{ path, err });
        return .failed;
    };
    defer gpa.free(text);

    const rt = Runtime.create(gpa) catch {
        try stderr.writeAll("zilisp: メモリが足りません\n");
        return .failed;
    };
    defer rt.destroy();

    var src = reader.Source.init(text, 1);
    var b: vb.ValueBuilder = .{ .rt = rt };
    var r = reader.Reader(vb.ValueBuilder).init(gpa, &src, &b, .{});
    defer r.deinit();
    while (true) {
        const v = r.read() catch |err| {
            const d = r.diagnostic;
            const kind = switch (err) {
                error.EndOfFile => "end-of-file",
                error.ReaderError => "reader-error",
                error.OutOfMemory => "storage-condition",
            };
            try stderr.print("{s}:{d}:{d}: {s}: {s}\n", .{ path, d.loc.line, d.loc.col, kind, d.message });
            return .failed;
        };
        const value = v orelse break;
        try printer.prin1(rt, stdout, value);
        try stdout.writeByte('\n');
    }
    return .ok;
}
