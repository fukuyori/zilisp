//! コマンドライン引数の解析。
//! 全体のオプション（--gc-stress、--gc-stats）の後に、コマンドを置く（基本設計 §12.1）。
//!   （なし）REPL    FILE・--script FILE ソースの実行    --eval TEXT 式の評価    --load FILE 読み込んでから REPL
//!   --version  --help  --read FILE（Reader と印字の確認用）
//! その他（build、compile-file など）は未実装として明示的に拒否する。

const std = @import("std");

pub const Command = union(enum) {
    /// 引数なし：REPL
    none,
    /// FILE、--script FILE：ソースの実行
    script: []const u8,
    /// --eval TEXT：式の評価
    eval: []const u8,
    /// --load FILE：読み込んでから REPL
    load: []const u8,
    /// --emit-zig FILE OUT.zig：ネイティブバックエンドで Zig のソースを生成する（Phase 12 の開発用）
    emit_zig: struct { src: []const u8, out: []const u8 },
    version,
    help,
    /// --read FILE：ファイルのデータを読み、1つずつ印字する（Reader と印字の確認用）
    read: []const u8,
    /// 引数の不足
    missing_argument: []const u8,
    /// 未実装のコマンド・オプション
    unsupported: []const u8,
};

pub const Options = struct {
    /// 確保のたびに GC を行う（ルートの登録漏れの検出用。詳細設計 §3.7）
    gc_stress: bool = false,
    /// 終了時に GC の統計を標準エラー出力に表示する
    gc_stats: bool = false,
};

pub const Parsed = struct {
    options: Options = .{},
    command: Command,
};

pub fn parse(args: []const [:0]const u8) Parsed {
    var options: Options = .{};
    var i: usize = 1;
    while (i < args.len) : (i += 1) {
        const a = args[i];
        if (eql(a, "--gc-stress")) {
            options.gc_stress = true;
        } else if (eql(a, "--gc-stats")) {
            options.gc_stats = true;
        } else break;
    }
    return .{ .options = options, .command = parseCommand(args[i..]) };
}

fn parseCommand(rest: []const [:0]const u8) Command {
    if (rest.len == 0) return .none;
    const first = rest[0];
    if (eql(first, "--version") or eql(first, "-v")) return .version;
    if (eql(first, "--help") or eql(first, "-h")) return .help;
    if (eql(first, "--emit-zig")) {
        if (rest.len < 3) return .{ .missing_argument = first };
        if (rest.len > 3) return .{ .unsupported = rest[3] };
        return .{ .emit_zig = .{ .src = rest[1], .out = rest[2] } };
    }
    if (eql(first, "--read") or eql(first, "--script") or eql(first, "--eval") or eql(first, "--load")) {
        if (rest.len < 2) return .{ .missing_argument = first };
        if (rest.len > 2) return .{ .unsupported = rest[2] };
        if (eql(first, "--read")) return .{ .read = rest[1] };
        if (eql(first, "--script")) return .{ .script = rest[1] };
        if (eql(first, "--eval")) return .{ .eval = rest[1] };
        return .{ .load = rest[1] };
    }
    // オプションでない最初の引数はソースのファイル（後ろの引数は、スクリプトへの引数として Phase 31 で扱う）
    if (first.len > 0 and first[0] != '-') {
        if (rest.len > 1) return .{ .unsupported = rest[1] };
        return .{ .script = first };
    }
    return .{ .unsupported = first };
}

fn eql(a: []const u8, b: []const u8) bool {
    return std.mem.eql(u8, a, b);
}

test "no arguments" {
    try std.testing.expectEqual(Command.none, parse(&.{"zilisp"}).command);
}

test "version and help" {
    try std.testing.expectEqual(Command.version, parse(&.{ "zilisp", "--version" }).command);
    try std.testing.expectEqual(Command.version, parse(&.{ "zilisp", "-v" }).command);
    try std.testing.expectEqual(Command.help, parse(&.{ "zilisp", "--help" }).command);
    try std.testing.expectEqual(Command.help, parse(&.{ "zilisp", "-h" }).command);
}

test "read" {
    try std.testing.expectEqualStrings("a.lisp", parse(&.{ "zilisp", "--read", "a.lisp" }).command.read);
    try std.testing.expectEqualStrings("--read", parse(&.{ "zilisp", "--read" }).command.missing_argument);
}

test "global options" {
    const p = parse(&.{ "zilisp", "--gc-stress", "--gc-stats", "--read", "a.lisp" });
    try std.testing.expect(p.options.gc_stress and p.options.gc_stats);
    try std.testing.expectEqualStrings("a.lisp", p.command.read);
    try std.testing.expect(!parse(&.{ "zilisp", "--read", "x" }).options.gc_stress);
}

test "script, eval, load" {
    try std.testing.expectEqualStrings("hello.lisp", parse(&.{ "zilisp", "hello.lisp" }).command.script);
    try std.testing.expectEqualStrings("a.lisp", parse(&.{ "zilisp", "--script", "a.lisp" }).command.script);
    try std.testing.expectEqualStrings("(+ 1 2)", parse(&.{ "zilisp", "--eval", "(+ 1 2)" }).command.eval);
    try std.testing.expectEqualStrings("a.lisp", parse(&.{ "zilisp", "--load", "a.lisp" }).command.load);
    try std.testing.expectEqualStrings("--eval", parse(&.{ "zilisp", "--eval" }).command.missing_argument);
}

test "unsupported" {
    try std.testing.expectEqualStrings("--build", parse(&.{ "zilisp", "--build" }).command.unsupported);
    try std.testing.expectEqualStrings("b.lisp", parse(&.{ "zilisp", "a.lisp", "b.lisp" }).command.unsupported);
}
