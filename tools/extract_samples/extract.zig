//! Markdown からコードブロックを取り出す処理（詳細設計 §12 の手順 2）。
//!
//! 規則
//! - 行頭（先頭の空白は 3 文字まで許す）の ``` で始まる行を囲みの開始・終了とみなす。
//! - 開始行の ``` の後ろの文字列を言語の指定（info string）とする。
//! - ブロックの中で ``` で始まる行が現れたら、ブロックを閉じる。
//!   ``` の後ろに文字列が続く場合（例：「```この性質により」）は CommonMark では閉じないが、
//!   書き手の意図は「閉じる」であると判断して閉じ、異常として記録する。
//! - ファイルの終わりまで閉じられなかったブロックも、異常として記録する。

const std = @import("std");

pub const Block = struct {
    /// 言語の指定（空なら指定なし）
    lang: []const u8,
    /// 開始の ``` の行番号（1 起点）
    start_line: u32,
    /// 終了の ``` の行番号（閉じられなかった場合はファイルの最終行）
    end_line: u32,
    /// ブロックの中身（開始行と終了行を含まない）
    body: []const u8,
};

pub const AnomalyKind = enum {
    /// 閉じの ``` の後ろに本文が続いている
    closing_fence_with_text,
    /// ファイルの終わりまで閉じられていない
    unclosed_block,

    pub fn label(k: AnomalyKind) []const u8 {
        return switch (k) {
            .closing_fence_with_text => "closing-fence-with-text",
            .unclosed_block => "unclosed-block",
        };
    }
};

pub const Anomaly = struct {
    kind: AnomalyKind,
    line: u32,
    /// 異常のある行の内容（先頭 80 バイトまで）
    text: []const u8,
};

pub const Result = struct {
    blocks: std.ArrayList(Block) = .empty,
    anomalies: std.ArrayList(Anomaly) = .empty,

    pub fn deinit(r: *Result, gpa: std.mem.Allocator) void {
        r.blocks.deinit(gpa);
        r.anomalies.deinit(gpa);
    }
};

/// Lisp のコードとみなす言語の指定か
pub fn isLispLang(lang: []const u8) bool {
    const names = [_][]const u8{ "lisp", "common-lisp", "commonlisp", "cl" };
    for (names) |n| {
        if (std.ascii.eqlIgnoreCase(lang, n)) return true;
    }
    return false;
}

/// 行頭の空白（3 文字まで）を除いた後、``` で始まっていれば、``` の後ろを返す
fn fenceRest(line: []const u8) ?[]const u8 {
    var i: usize = 0;
    while (i < line.len and i < 3 and line[i] == ' ') : (i += 1) {}
    const rest = line[i..];
    if (!std.mem.startsWith(u8, rest, "```")) return null;
    var j: usize = 3;
    while (j < rest.len and rest[j] == '`') : (j += 1) {}
    return rest[j..];
}

/// `text` は呼び出し側が保持する。返す Block・Anomaly のスライスは `text` を指す。
pub fn extract(gpa: std.mem.Allocator, text: []const u8) !Result {
    var result: Result = .{};
    errdefer result.deinit(gpa);

    var in_block = false;
    var lang: []const u8 = "";
    var start_line: u32 = 0;
    var body_start: usize = 0;

    var line_no: u32 = 0;
    var pos: usize = 0;
    while (pos <= text.len) {
        const line_start = pos;
        const nl = std.mem.indexOfScalarPos(u8, text, pos, '\n');
        const line_end = nl orelse text.len;
        var line = text[line_start..line_end];
        if (line.len > 0 and line[line.len - 1] == '\r') line = line[0 .. line.len - 1];
        line_no += 1;
        pos = if (nl) |n| n + 1 else text.len + 1;

        const rest = fenceRest(line) orelse continue;
        const info = std.mem.trim(u8, rest, " \t");
        if (!in_block) {
            in_block = true;
            lang = info;
            start_line = line_no;
            body_start = pos;
        } else {
            if (info.len > 0) {
                try result.anomalies.append(gpa, .{
                    .kind = .closing_fence_with_text,
                    .line = line_no,
                    .text = line[0..@min(line.len, 80)],
                });
            }
            const body_end = @min(line_start, text.len);
            try result.blocks.append(gpa, .{
                .lang = lang,
                .start_line = start_line,
                .end_line = line_no,
                .body = text[@min(body_start, body_end)..body_end],
            });
            in_block = false;
        }
    }
    if (in_block) {
        try result.anomalies.append(gpa, .{ .kind = .unclosed_block, .line = start_line, .text = "" });
        try result.blocks.append(gpa, .{
            .lang = lang,
            .start_line = start_line,
            .end_line = line_no,
            .body = text[@min(body_start, text.len)..],
        });
    }
    return result;
}

const testing = std.testing;

test "simple lisp block" {
    const md = "# title\n\n```lisp\n(+ 1 2)\n```\ntext\n";
    var r = try extract(testing.allocator, md);
    defer r.deinit(testing.allocator);
    try testing.expectEqual(@as(usize, 1), r.blocks.items.len);
    const b = r.blocks.items[0];
    try testing.expectEqualStrings("lisp", b.lang);
    try testing.expectEqual(@as(u32, 3), b.start_line);
    try testing.expectEqual(@as(u32, 5), b.end_line);
    try testing.expectEqualStrings("(+ 1 2)\n", b.body);
    try testing.expectEqual(@as(usize, 0), r.anomalies.items.len);
}

test "crlf and unlabeled block" {
    const md = "```\r\nhello\r\n```\r\n```lisp\r\n(car x)\r\n```\r\n";
    var r = try extract(testing.allocator, md);
    defer r.deinit(testing.allocator);
    try testing.expectEqual(@as(usize, 2), r.blocks.items.len);
    try testing.expectEqualStrings("", r.blocks.items[0].lang);
    try testing.expectEqualStrings("lisp", r.blocks.items[1].lang);
    try testing.expectEqualStrings("(car x)\r\n", r.blocks.items[1].body);
}

test "closing fence followed by text is an anomaly but closes" {
    const md = "```lisp\n(a)\n```この性質により\n次の文\n```lisp\n(b)\n```\n";
    var r = try extract(testing.allocator, md);
    defer r.deinit(testing.allocator);
    try testing.expectEqual(@as(usize, 2), r.blocks.items.len);
    try testing.expectEqualStrings("(a)\n", r.blocks.items[0].body);
    try testing.expectEqualStrings("(b)\n", r.blocks.items[1].body);
    try testing.expectEqual(@as(usize, 1), r.anomalies.items.len);
    try testing.expectEqual(AnomalyKind.closing_fence_with_text, r.anomalies.items[0].kind);
    try testing.expectEqual(@as(u32, 3), r.anomalies.items[0].line);
}

test "unclosed block" {
    const md = "```lisp\n(a)\n";
    var r = try extract(testing.allocator, md);
    defer r.deinit(testing.allocator);
    try testing.expectEqual(@as(usize, 1), r.blocks.items.len);
    try testing.expectEqual(AnomalyKind.unclosed_block, r.anomalies.items[0].kind);
}

test "indented fence and longer backticks" {
    const md = "  ````lisp\n(x)\n  ````\n";
    var r = try extract(testing.allocator, md);
    defer r.deinit(testing.allocator);
    try testing.expectEqual(@as(usize, 1), r.blocks.items.len);
    try testing.expectEqualStrings("lisp", r.blocks.items[0].lang);
}

test "lisp languages" {
    try testing.expect(isLispLang("lisp"));
    try testing.expect(isLispLang("Common-Lisp"));
    try testing.expect(isLispLang("cl"));
    try testing.expect(!isLispLang("bash"));
    try testing.expect(!isLispLang("mermaid"));
}
