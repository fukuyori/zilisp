//! 標準の readtable の構文型（CLHS 2.1.4「Character Syntax Types」）。
//! ユーザー定義の readtable（set-macro-character など）は src/reader/readtable.zig（Phase 24）。

pub const SyntaxType = enum {
    whitespace,
    terminating_macro,
    non_terminating_macro,
    single_escape,
    multiple_escape,
    constituent,
    /// 構成文字だが invalid の性質を持つ（トークンに現れるとエラー。CLHS 2.1.4.2）
    invalid,
};

pub fn syntaxType(cp: u21) SyntaxType {
    return switch (cp) {
        // Tab, Newline(Linefeed), Page, Return, Space
        '\t', '\n', 0x0C, '\r', ' ' => .whitespace,
        '"', '\'', '(', ')', ',', ';', '`' => .terminating_macro,
        '#' => .non_terminating_macro,
        '\\' => .single_escape,
        '|' => .multiple_escape,
        // Backspace, Rubout（SBCL 2.6.7 でもトークンの中ではエラー）
        0x08, 0x7F => .invalid,
        else => .constituent,
    };
}

/// readtable-case が :upcase のときの変換（char-upcase と同じ。Unicode 15.0.0 に従う：Phase 21.5。
/// SBCL 2.6.7 と同じく é → É、λ → Λ のように変換する）
pub const upcase = @import("../unicode/unicode.zig").upcase;
/// readtable-case が :downcase・:invert のときの変換（char-downcase と同じ。Phase 24）
pub const downcase = @import("../unicode/unicode.zig").downcase;

test "syntax types" {
    const std = @import("std");
    try std.testing.expectEqual(SyntaxType.whitespace, syntaxType(' '));
    try std.testing.expectEqual(SyntaxType.terminating_macro, syntaxType('('));
    try std.testing.expectEqual(SyntaxType.non_terminating_macro, syntaxType('#'));
    try std.testing.expectEqual(SyntaxType.constituent, syntaxType('a'));
    try std.testing.expectEqual(SyntaxType.constituent, syntaxType(0x3000));
    try std.testing.expectEqual(SyntaxType.invalid, syntaxType(0x7F));
    try std.testing.expectEqual(@as(u21, 'A'), upcase('a'));
    try std.testing.expectEqual(@as(u21, 'Λ'), upcase('λ'));
    try std.testing.expectEqual(@as(u21, 'あ'), upcase('あ'));
}
