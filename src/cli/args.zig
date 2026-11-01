//! コマンドライン引数の解析。
//! Phase 01 では --version と --help だけを扱う。その他のコマンド
//! （REPL、ソース実行、--eval、build など。基本設計 §12.1）は未実装として明示的に拒否する。

const std = @import("std");

pub const Command = union(enum) {
    /// 引数なし（将来は REPL を起動する）
    none,
    version,
    help,
    /// 未実装のコマンド・オプション
    unsupported: []const u8,
};

pub fn parse(args: []const [:0]const u8) Command {
    if (args.len <= 1) return .none;
    const first = args[1];
    if (eql(first, "--version") or eql(first, "-v")) return .version;
    if (eql(first, "--help") or eql(first, "-h")) return .help;
    return .{ .unsupported = first };
}

fn eql(a: []const u8, b: []const u8) bool {
    return std.mem.eql(u8, a, b);
}

test "no arguments" {
    try std.testing.expectEqual(Command.none, parse(&.{"zilisp"}));
}

test "version and help" {
    try std.testing.expectEqual(Command.version, parse(&.{ "zilisp", "--version" }));
    try std.testing.expectEqual(Command.version, parse(&.{ "zilisp", "-v" }));
    try std.testing.expectEqual(Command.help, parse(&.{ "zilisp", "--help" }));
    try std.testing.expectEqual(Command.help, parse(&.{ "zilisp", "-h" }));
}

test "unsupported" {
    const c = parse(&.{ "zilisp", "hello.lisp" });
    try std.testing.expectEqualStrings("hello.lisp", c.unsupported);
}
