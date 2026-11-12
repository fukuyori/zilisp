//! 標準ライブラリ（Lisp で書く部分：src/lisp/boot.lisp）の読み込み（詳細設計 §11.1 の 7・§11.2。Phase 15）。
//! スレッドを作るたびに VM で読み込む。ソースは実行ファイルに埋め込む。
//! 読み込みに失敗するのは処理系の誤りなので、内容を表示して停止する。

const std = @import("std");
const Value = @import("../values/value.zig").Value;
const Thread = @import("../runtime/thread.zig").Thread;
const reader = @import("../reader/reader.zig");
const vb = @import("../reader/value_builder.zig");
const eval_mod = @import("eval.zig");

pub const source = @embedFile("../lisp/boot.lisp") ++ "\n" ++ @embedFile("../lisp/clos.lisp") ++ "\n" ++ @embedFile("../lisp/generic.lisp") ++ "\n" ++ @embedFile("../lisp/clos-update.lisp");

pub fn load(th: *Thread) error{OutOfMemory}!void {
    const rt = th.rt;
    rt.booting = true;
    defer rt.booting = false;
    var src = reader.Source.init(source, 0);
    var b: vb.ValueBuilder = .{ .rt = rt };
    var r = reader.Reader(vb.ValueBuilder).init(rt.gpa, &src, &b, .{});
    defer r.deinit();
    while (true) {
        const form = r.read() catch |err| switch (err) {
            error.OutOfMemory => return error.OutOfMemory,
            else => std.debug.panic("src/lisp/boot.lisp:{d}:{d}: {s}", .{ r.diagnostic.loc.line, r.diagnostic.loc.col, r.diagnostic.message }),
        } orelse break;
        if (eval_mod.eval(th, form) == Value.unwind) {
            if (th.fault == .out_of_memory or th.err.kind == .storage_condition) return error.OutOfMemory;
            var buf: [1024]u8 = undefined;
            var w: std.Io.Writer = .fixed(&buf);
            th.writeError(&w) catch {};
            const loc = r.start_loc orelse src.loc();
            std.debug.panic("src/lisp/boot.lisp:{d}:{d}: 標準ライブラリを読み込めません: {s}", .{ loc.line, loc.col, w.buffered() });
        }
    }
}
