//! zilisp --read FILE：ファイルのデータを読み、1つずつ prin1 で印字する（各データの後に改行）。
//! SBCL での同じ処理（tools/sbcl_read_print.lisp）と出力を比べて、Reader と印字を確かめる。

const std = @import("std");
const Io = std.Io;
const reader = @import("../reader/reader.zig");
const vb = @import("../reader/value_builder.zig");
const printer = @import("../printer/printer.zig");
const Runtime = @import("../runtime/runtime.zig").Runtime;
const Options = @import("args.zig").Options;

pub const Result = enum { ok, failed };

pub fn printGcStats(rt: *Runtime, w: *Io.Writer) Io.Writer.Error!void {
    const s = rt.heap.stats;
    try w.print(
        "gc: collections={d} pause_total={d:.3}ms pause_max={d:.3}ms live_bytes={d} live_objects={d} freed_objects={d} allocated_bytes={d} chunks={d}\n",
        .{
            s.collections,
            @as(f64, @floatFromInt(s.pause_ns_total)) / 1e6,
            @as(f64, @floatFromInt(s.pause_ns_max)) / 1e6,
            s.live_bytes,
            s.live_objects,
            s.objects_freed,
            s.bytes_allocated,
            s.chunks,
        },
    );
}

pub fn run(gpa: std.mem.Allocator, io: Io, options: Options, path: []const u8, stdout: *Io.Writer, stderr: *Io.Writer) Io.Writer.Error!Result {
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
    rt.io = io;
    rt.heap.stress = options.gc_stress;
    defer if (options.gc_stats) printGcStats(rt, stderr) catch {};

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
                // read のコマンドは Thread を渡さないので、reader macro・#. は使われない
                error.LispError => "error",
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
