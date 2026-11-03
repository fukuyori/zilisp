//! CL の文字の種類と大文字・小文字（Phase 21.5。詳細設計 §11.2）。
//!
//! Unicode 15.0.0（SBCL 2.6.7 と同じ版）の表（tables.zig。tools/gen_unicode/main.zig が生成する）を引く。
//! ASCII の文字は表を引かずに判定する。判定の仕方は SBCL 2.6.7 の src/code/target-char.lisp と同じ：
//! - 英字（alpha-char-p）：一般カテゴリが L*。英数字（alphanumericp）：L* か Nd。
//! - 大文字・小文字：CL の意味で大文字・小文字のある文字（1 文字から 1 文字への対応で、往復するもの）だけ。
//!   大文字でも小文字でもない文字は含めない（CLHS 13.1.4.3。SBCL 2.6.7 との違い：U+01C5 などの4文字）。
//! - 数字の重み（digit-char-p）：ASCII の 0〜9・A〜Z・a〜z と、U+0660 より後の 10進数字（SBCL 2.6.7 と同じく、
//!   U+0080〜U+0660 は数字としない）。

const tables = @import("tables.zig");

pub const unicode_version = tables.unicode_version;

inline fn prop(cp: u21) u8 {
    return tables.prop_pages[@as(usize, tables.prop_index[cp >> 8]) << 8 | (cp & 0xFF)];
}

inline fn caseSlot(cp: u21) ?usize {
    const page = cp >> 6;
    if (page >= tables.case_index.len) return null;
    const i = tables.case_index[page];
    if (i == 255) return null;
    return @as(usize, i) << 6 | (cp & 63);
}

/// alpha-char-p
pub fn isAlpha(cp: u21) bool {
    if (cp < 0x80) return (cp | 0x20) >= 'a' and (cp | 0x20) <= 'z';
    return prop(cp) & 0x80 != 0;
}

/// alphanumericp
pub fn isAlnum(cp: u21) bool {
    if (cp < 0x80) return isAlpha(cp) or (cp >= '0' and cp <= '9');
    return prop(cp) & 0xC0 != 0;
}

/// upper-case-p
pub fn isUpper(cp: u21) bool {
    if (cp < 0x80) return cp >= 'A' and cp <= 'Z';
    const s = caseSlot(cp) orelse return false;
    return tables.case_upper[s] == cp;
}

/// lower-case-p
pub fn isLower(cp: u21) bool {
    if (cp < 0x80) return cp >= 'a' and cp <= 'z';
    const s = caseSlot(cp) orelse return false;
    return tables.case_lower[s] == cp;
}

/// both-case-p
pub fn hasCase(cp: u21) bool {
    if (cp < 0x80) return isAlpha(cp);
    const s = caseSlot(cp) orelse return false;
    return tables.case_lower[s] != 0;
}

/// char-upcase（小文字でなければそのまま）
pub fn upcase(cp: u21) u21 {
    if (cp < 0x80) return if (cp >= 'a' and cp <= 'z') cp - ('a' - 'A') else cp;
    const s = caseSlot(cp) orelse return cp;
    const u = tables.case_upper[s];
    return if (u != 0) @intCast(u) else cp;
}

/// char-downcase（大文字でなければそのまま）。char-equal・char-lessp と equalp は、この値で比べる
pub fn downcase(cp: u21) u21 {
    if (cp < 0x80) return if (cp >= 'A' and cp <= 'Z') cp + ('a' - 'A') else cp;
    const s = caseSlot(cp) orelse return cp;
    const l = tables.case_lower[s];
    return if (l != 0) @intCast(l) else cp;
}

/// 基数 radix（2〜36）での数字の重み（数字でなければ null）
pub fn digitWeight(cp: u21, radix: u32) ?u32 {
    if (cp < 0x80) {
        const w: u32 = switch (cp) {
            '0'...'9' => cp - '0',
            'A'...'Z' => cp - 'A' + 10,
            'a'...'z' => cp - 'a' + 10,
            else => return null,
        };
        return if (w < radix) w else null;
    }
    // SBCL 2.6.7 の digit-char-p は U+0660 以下を ASCII の判定で調べるので、U+0080〜U+0660 は数字にならない
    if (cp <= 0x660) return null;
    const p = prop(cp);
    if (p & 0x20 == 0) return null;
    const w: u32 = p & 0x0F;
    return if (w < radix) w else null;
}

// ---------------------------------------------------------------------------
// 試験：SBCL 2.6.7 の結果（全符号位置。testdata/sbcl-2.6.7-chars.txt）と比べる

const std = @import("std");

/// SBCL 2.6.7 と違う文字（CLHS 13.1.4.3：大文字でも小文字でもない文字は大文字・小文字のない文字とする）
const clhs_titlecase = [_]u21{ 0x1C5, 0x1C8, 0x1CB, 0x1F2 };

test "all code points agree with SBCL 2.6.7" {
    const data = @embedFile("testdata/sbcl-2.6.7-chars.txt");
    var lines = std.mem.splitScalar(u8, data, '\n');
    var covered: u32 = 0;
    var mismatches: u32 = 0;
    while (lines.next()) |raw| {
        const line = std.mem.trimEnd(u8, raw, "\r");
        if (line.len == 0 or line[0] == '#') continue;
        var it = std.mem.tokenizeScalar(u8, line, ' ');
        const start = try std.fmt.parseInt(u21, it.next().?, 16);
        const end = try std.fmt.parseInt(u21, it.next().?, 16);
        var f: [9]i32 = undefined;
        for (&f) |*x| x.* = try std.fmt.parseInt(i32, it.next().?, 10);
        var cp = start;
        while (true) : (cp += 1) {
            var want = f;
            if (std.mem.indexOfScalar(u21, &clhs_titlecase, cp) != null) {
                want[4] = 0; // both-case-p
                want[7] = 0; // char-upcase
                want[8] = 0; // char-downcase
            }
            const c: i32 = cp;
            const got = [9]i32{
                @intFromBool(isAlpha(cp)),
                @intFromBool(isAlnum(cp)),
                @intFromBool(isUpper(cp)),
                @intFromBool(isLower(cp)),
                @intFromBool(hasCase(cp)),
                @intFromBool(cp >= 0x20 and cp != 0x7F and !(cp >= 0x80 and cp < 0xA0)),
                if (digitWeight(cp, 36)) |w| @intCast(w) else -1,
                @as(i32, upcase(cp)) - c,
                @as(i32, downcase(cp)) - c,
            };
            if (!std.mem.eql(i32, &got, &want)) {
                if (mismatches < 10) std.debug.print("U+{X}: got {any}, SBCL {any}\n", .{ cp, got, want });
                mismatches += 1;
            }
            covered += 1;
            if (cp == end) break;
        }
    }
    try std.testing.expectEqual(@as(u32, 0), mismatches);
    try std.testing.expectEqual(@as(u32, 0x110000), covered);
}

test "case pairs round-trip (CLHS 13.1.4.3)" {
    var cp: u21 = 0;
    while (cp < 0x110000) : (cp += 1) {
        if (!hasCase(cp)) {
            try std.testing.expectEqual(cp, upcase(cp));
            try std.testing.expectEqual(cp, downcase(cp));
            continue;
        }
        try std.testing.expect(isAlpha(cp));
        try std.testing.expect(isUpper(cp) != isLower(cp));
        if (isUpper(cp)) try std.testing.expectEqual(cp, upcase(downcase(cp))) else try std.testing.expectEqual(cp, downcase(upcase(cp)));
    }
}
