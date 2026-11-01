//! *features* の初期値と、#+ / #- の機能式（CLHS 24.1.2.1「Feature Expressions」）。

const std = @import("std");
const builtin = @import("builtin");

/// 起動時の *features*（キーワードの名前。大文字）。
/// :ANSI-CL は入れない（Zilisp は ANSI Common Lisp の実用的なサブセットであり、完全な準拠を表明しないため）。
pub const default: []const []const u8 = blk: {
    var list: []const []const u8 = &.{ "ZILISP", "COMMON-LISP", "64-BIT", "IEEE-FLOATING-POINT" };
    list = list ++ switch (builtin.cpu.arch.endian()) {
        .little => &[_][]const u8{"LITTLE-ENDIAN"},
        .big => &[_][]const u8{"BIG-ENDIAN"},
    };
    list = list ++ switch (builtin.cpu.arch) {
        .x86_64 => &[_][]const u8{"X86-64"},
        .aarch64 => &[_][]const u8{"ARM64"},
        else => &[_][]const u8{},
    };
    list = list ++ switch (builtin.os.tag) {
        // SBCL は :WIN32、他の処理系・ライブラリは :WINDOWS を使うため両方を入れる
        .windows => &[_][]const u8{ "WINDOWS", "WIN32" },
        .linux => &[_][]const u8{ "UNIX", "LINUX" },
        .macos => &[_][]const u8{ "UNIX", "DARWIN" },
        else => &[_][]const u8{},
    };
    break :blk list;
};

pub fn contains(features: []const []const u8, name: []const u8) bool {
    for (features) |f| {
        if (std.mem.eql(u8, f, name)) return true;
    }
    return false;
}

test "default features" {
    try std.testing.expect(contains(default, "ZILISP"));
    try std.testing.expect(contains(default, "COMMON-LISP"));
    try std.testing.expect(!contains(default, "ANSI-CL"));
}
