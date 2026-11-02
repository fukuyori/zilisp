//! プリミティブのキーワード引数の解析（CLHS 3.4.1.4）。
//! 引数の並び（キーワード 値 …）から、名前の決まったキーワードの値を取り出す。同じキーワードが重複したら最も左を使う。
//! 数が奇数・知らないキーワードは program-error（:allow-other-keys が真なら知らないキーワードを許す）。

const std = @import("std");
const Value = @import("../values/value.zig").Value;
const Thread = @import("../runtime/thread.zig").Thread;

/// names のキーワードの値を out に書く（なければ null）。エラーなら false（th にエラーを記録済み）
pub fn parse(th: *Thread, args: []const Value, comptime names: []const []const u8, out: *[names.len]?Value) bool {
    out.* = @splat(null);
    if (args.len % 2 != 0) {
        _ = th.signal(.program_error, "キーワード引数の数が奇数です", Value.unbound, Value.unbound);
        return false;
    }
    var keys: [names.len]Value = undefined;
    inline for (names, 0..) |n, i| keys[i] = th.rt.internKeyword(n) catch {
        _ = th.outOfMemory();
        return false;
    };
    const allow_kw = th.rt.internKeyword("ALLOW-OTHER-KEYS") catch {
        _ = th.outOfMemory();
        return false;
    };
    var allow = false;
    var i: usize = 0;
    while (i < args.len) : (i += 2) {
        if (args[i] == allow_kw and args[i + 1] != Value.nil) allow = true;
    }
    i = 0;
    outer: while (i < args.len) : (i += 2) {
        for (keys, 0..) |k, j| {
            if (args[i] == k) {
                if (out[j] == null) out[j] = args[i + 1];
                continue :outer;
            }
        }
        if (args[i] == allow_kw or allow) continue;
        _ = th.signal(.program_error, "知らないキーワード引数です", args[i], Value.unbound);
        return false;
    }
    return true;
}
