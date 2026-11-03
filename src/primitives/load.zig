//! load（Phase 22。CLHS load）：ファイルのフォームを順に読んで評価する。
//!
//! - ファイルの指定はパス名指定子（文字列・パス名・ファイルストリーム）。*default-pathname-defaults* と併合する（Phase 23）。
//! - 読み込みの間、*package* をその時点の値に束縛する（ファイルの中の in-package は、読み込みが終われば元に戻る）。
//! - フォームは1つ読むごとに評価する（後のフォームの読み方を、in-package などが変えるため）。
//! - :if-does-not-exist が NIL なら、ファイルがなければ NIL を返す。:verbose・:print を真にするのは未実装（エラー）。

const std = @import("std");
const Io = std.Io;
const Value = @import("../values/value.zig").Value;
const Thread = @import("../runtime/thread.zig").Thread;
const Runtime = @import("../runtime/runtime.zig").Runtime;
const reader = @import("../reader/reader.zig");
const vb = @import("../reader/value_builder.zig");
const eval_mod = @import("../compiler/eval.zig");
const arrays = @import("arrays.zig");
const keyargs = @import("keyargs.zig");

fn cl(th: *Thread, name: []const u8) Value {
    return (th.rt.findSymbol(th.rt.cl, name) orelse unreachable).symbol;
}

/// (load ファイル &key verbose print if-does-not-exist external-format)：読み込めば T
pub fn load(th: *Thread, args: []const Value) Value {
    const rt = th.rt;
    var kv: [4]?Value = undefined;
    if (!keyargs.parse(th, args[1..], &.{ "VERBOSE", "PRINT", "IF-DOES-NOT-EXIST", "EXTERNAL-FORMAT" }, &kv)) return Value.unwind;
    for ([_]?Value{ kv[0], kv[1] }) |flag| if (flag) |f| if (f != Value.nil)
        return th.signal(.unimplemented, "LOAD の :verbose・:print は未実装です", f, Value.unbound);
    if (kv[3]) |ef| if (ef != (rt.internKeyword("DEFAULT") catch return th.outOfMemory()) and ef != (rt.internKeyword("UTF-8") catch return th.outOfMemory()))
        return th.signal(.unimplemented, "LOAD の :external-format は :default か :utf-8 だけです", ef, Value.unbound);
    const spec = args[0];
    // パス名指定子（文字列・パス名・ファイルストリーム。Phase 23）。*default-pathname-defaults* と併合する
    const path = @import("pathnames.zig").osName(th, spec) orelse return Value.unwind;
    defer rt.gpa.free(path);
    const io = rt.io orelse return th.signal(.unimplemented, "この環境では LOAD でファイルを読めません", spec, Value.unbound);
    const text = Io.Dir.cwd().readFileAlloc(io, path, rt.gpa, .limited(256 * 1024 * 1024)) catch |err| switch (err) {
        error.FileNotFound => {
            if (kv[2]) |ide| if (ide == Value.nil) return Value.nil;
            return th.signal(.file_error, "ファイルがありません", spec, Value.unbound);
        },
        error.OutOfMemory => return th.outOfMemory(),
        else => return th.signal(.file_error, "ファイルを読めません", spec, Value.unbound),
    };
    defer rt.gpa.free(text);

    // *package* を束縛する（ファイルの中の in-package は、読み込みが終われば元に戻る。CLHS load）
    const depth = th.binding_depth;
    if (th.bind(rt.package_sym, rt.symbolPtr(rt.package_sym).value) == Value.unwind) return Value.unwind;
    defer th.unbindTo(depth);

    var src = reader.Source.init(text, 0);
    var b: vb.ValueBuilder = .{ .rt = rt };
    var r = reader.Reader(vb.ValueBuilder).init(rt.gpa, &src, &b, .{});
    defer r.deinit();
    while (true) {
        const form = r.read() catch |err| switch (err) {
            error.OutOfMemory => return th.outOfMemory(),
            error.EndOfFile => return th.signal(.end_of_file, "ファイルの途中でフォームが終わっています", spec, Value.unbound),
            error.ReaderError => return th.signal(.reader_error, r.diagnostic.message, spec, Value.unbound),
        } orelse break;
        if (eval_mod.eval(th, form) == Value.unwind) return Value.unwind;
    }
    th.mv_count = 1;
    return rt.t;
}
