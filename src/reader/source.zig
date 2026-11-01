//! 読み取り元のテキストと、位置の追跡（詳細設計 §4.1）。
//! テキストは UTF-8 とし、1 文字（コードポイント）ずつ読む。列は文字単位で数える。

const std = @import("std");

pub const SourceLoc = struct {
    /// ソースファイルの番号（0 は不明）
    file: u32 = 0,
    /// 1 起点
    line: u32,
    /// 1 起点（文字単位）
    col: u32,
};

pub const Char = struct {
    cp: u21,
    /// UTF-8 でのバイト数
    len: u3,
};

pub const Source = struct {
    text: []const u8,
    file: u32 = 0,
    pos: usize = 0,
    line: u32 = 1,
    col: u32 = 1,

    pub fn init(text: []const u8, file: u32) Source {
        return .{ .text = text, .file = file };
    }

    pub fn loc(s: *const Source) SourceLoc {
        return .{ .file = s.file, .line = s.line, .col = s.col };
    }

    /// 次の文字を読まずに返す。テキストの終わりなら null。
    pub fn peek(s: *const Source) error{InvalidUtf8}!?Char {
        if (s.pos >= s.text.len) return null;
        const len = std.unicode.utf8ByteSequenceLength(s.text[s.pos]) catch return error.InvalidUtf8;
        if (s.pos + len > s.text.len) return error.InvalidUtf8;
        const cp = std.unicode.utf8Decode(s.text[s.pos .. s.pos + len]) catch return error.InvalidUtf8;
        return .{ .cp = cp, .len = len };
    }

    /// peek で得た文字を読み進める
    pub fn advance(s: *Source, ch: Char) void {
        s.pos += ch.len;
        if (ch.cp == '\n') {
            s.line += 1;
            s.col = 1;
        } else {
            s.col += 1;
        }
    }

    pub fn next(s: *Source) error{InvalidUtf8}!?u21 {
        const ch = (try s.peek()) orelse return null;
        s.advance(ch);
        return ch.cp;
    }
};

test "line and column tracking" {
    var s = Source.init("a\nλb", 1);
    try std.testing.expectEqual(@as(?u21, 'a'), try s.next());
    try std.testing.expectEqual(@as(?u21, '\n'), try s.next());
    try std.testing.expectEqual(SourceLoc{ .file = 1, .line = 2, .col = 1 }, s.loc());
    try std.testing.expectEqual(@as(?u21, 'λ'), try s.next());
    try std.testing.expectEqual(SourceLoc{ .file = 1, .line = 2, .col = 2 }, s.loc());
    try std.testing.expectEqual(@as(?u21, 'b'), try s.next());
    try std.testing.expectEqual(@as(?u21, null), try s.next());
}

test "invalid utf8" {
    var s = Source.init("\xff", 0);
    try std.testing.expectError(error.InvalidUtf8, s.next());
}
