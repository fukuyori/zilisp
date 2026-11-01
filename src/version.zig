//! Zilisp のバージョン情報。
//! バージョンを変更するときは docs/version-update-checklist.md の手順に従う。

const builtin = @import("builtin");

/// 処理系の名前。
pub const name = "zilisp";

/// 処理系のバージョン（build.zig.zon の .version と一致させる）。
pub const version = "0.0.1";

/// ビルドに使った Zig のバージョン。
pub const zig_version = builtin.zig_version_string;

test "version string is not empty" {
    const std = @import("std");
    try std.testing.expect(version.len > 0);
    try std.testing.expectEqualStrings("zilisp", name);
}
