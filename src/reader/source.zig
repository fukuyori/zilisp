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

/// テキストの終わりで、続きを読み足す（標準入力。読み足したテキスト全体を返す。もうなければ null）
pub const Refill = struct {
    ctx: *anyopaque,
    f: *const fn (ctx: *anyopaque) ?[]const u8,
};

pub const Source = struct {
    text: []const u8,
    file: u32 = 0,
    pos: usize = 0,
    line: u32 = 1,
    col: u32 = 1,
    /// テキストの終わりで続きを読み足す（標準入力。読み直すと #. や reader macro の副作用が2回起きるので、
    /// 読みかけのまま続ける。Codex のレビュー 0.3 #2）
    refill: ?Refill = null,

    pub fn init(text: []const u8, file: u32) Source {
        return .{ .text = text, .file = file };
    }

    pub fn loc(s: *const Source) SourceLoc {
        return .{ .file = s.file, .line = s.line, .col = s.col };
    }

    /// 次の文字を読まずに返す。テキストの終わりなら null。
    pub fn peek(s: *Source) error{InvalidUtf8}!?Char {
        while (s.pos >= s.text.len) {
            const r = s.refill orelse return null;
            s.text = r.f(r.ctx) orelse return null;
        }
        const len = std.unicode.utf8ByteSequenceLength(s.text[s.pos]) catch return error.InvalidUtf8;
        while (s.pos + len > s.text.len) {
            const r = s.refill orelse return error.InvalidUtf8;
            s.text = r.f(r.ctx) orelse return error.InvalidUtf8;
        }
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

    /// 位置を pos にする（行と列も合わせる。reader macro がストリームを読み進めた後。Phase 24）
    pub fn seekTo(s: *Source, pos: usize) void {
        const target = @min(pos, s.text.len);
        if (target < s.pos) {
            s.pos = 0;
            s.line = 1;
            s.col = 1;
        }
        while (s.pos < target) {
            const ch = (s.peek() catch null) orelse {
                s.pos = target;
                break;
            };
            s.advance(ch);
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
