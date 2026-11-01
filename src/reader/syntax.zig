//! 標準の readtable の構文型（CLHS 2.1.4「Character Syntax Types」）。
//! ユーザー定義の readtable（set-macro-character など）は Phase 24 で追加する。

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

/// readtable-case が :upcase のときの変換。
/// 標準の文字（ASCII）以外の大文字への変換は処理系依存であり（CLHS 13.1.4.3）、
/// Zilisp は現時点では ASCII だけを変換する（SBCL は é → É のように変換する）。
pub fn upcase(cp: u21) u21 {
    return if (cp >= 'a' and cp <= 'z') cp - ('a' - 'A') else cp;
}

test "syntax types" {
    const std = @import("std");
    try std.testing.expectEqual(SyntaxType.whitespace, syntaxType(' '));
    try std.testing.expectEqual(SyntaxType.terminating_macro, syntaxType('('));
    try std.testing.expectEqual(SyntaxType.non_terminating_macro, syntaxType('#'));
    try std.testing.expectEqual(SyntaxType.constituent, syntaxType('a'));
    try std.testing.expectEqual(SyntaxType.constituent, syntaxType(0x3000));
    try std.testing.expectEqual(SyntaxType.invalid, syntaxType(0x7F));
    try std.testing.expectEqual(@as(u21, 'A'), upcase('a'));
    try std.testing.expectEqual(@as(u21, 'λ'), upcase('λ'));
}
