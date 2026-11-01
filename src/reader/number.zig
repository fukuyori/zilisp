//! トークンを数として解釈する（CLHS 2.3.1「Numbers as Tokens」、2.3.2.1「Syntax of a Rational」、
//! 2.3.2.2「Syntax of a Float」）。
//!
//! 数として読めないトークン（潜在的な数を含む）は null を返し、呼び出し側でシンボルとして扱う。
//! 潜在的な数（CLHS 2.3.1.1）をシンボルとして扱うのは、SBCL 2.6.7 と同じ動作である（例：1e → |1E|）。

const std = @import("std");

pub const FloatFormat = enum { single, double };

pub const Number = union(enum) {
    /// digits は符号を含まない数字の並び（radix 進）
    integer: struct { negative: bool, digits: []const u8, radix: u8 },
    ratio: struct { negative: bool, numerator: []const u8, denominator: []const u8, radix: u8 },
    float: Float,
};

pub const Float = union(FloatFormat) {
    single: f32,
    double: f64,
};

pub const Error = error{
    /// 分母が 0 の比
    DivisionByZero,
    /// 浮動小数の範囲を超える
    FloatOverflow,
};

fn digitValue(c: u8) ?u8 {
    return switch (c) {
        '0'...'9' => c - '0',
        'a'...'z' => c - 'a' + 10,
        'A'...'Z' => c - 'A' + 10,
        else => null,
    };
}

fn allDigits(s: []const u8, radix: u8) bool {
    if (s.len == 0) return false;
    for (s) |c| {
        const v = digitValue(c) orelse return false;
        if (v >= radix) return false;
    }
    return true;
}

fn allZero(s: []const u8) bool {
    for (s) |c| if (c != '0') return false;
    return true;
}

fn isExponentMarker(c: u8) bool {
    return switch (c) {
        'e', 'E', 's', 'S', 'f', 'F', 'd', 'D', 'l', 'L' => true,
        else => false,
    };
}

/// `text` は ASCII に限る（ASCII 以外の文字を含むトークンは数ではない）。
/// `buf` は浮動小数の解析に使う作業領域（トークンの長さ + 4 バイト以上）。
pub fn parse(text: []const u8, read_base: u8, default_float: FloatFormat, buf: []u8) Error!?Number {
    if (text.len == 0) return null;
    var negative = false;
    var body = text;
    if (body[0] == '+' or body[0] == '-') {
        negative = body[0] == '-';
        body = body[1..];
    }
    if (body.len == 0) return null;

    // 整数：10進で末尾に小数点（例：42.）
    if (body.len >= 2 and body[body.len - 1] == '.' and allDigits(body[0 .. body.len - 1], 10)) {
        return .{ .integer = .{ .negative = negative, .digits = body[0 .. body.len - 1], .radix = 10 } };
    }
    // 整数：*read-base* 進
    if (allDigits(body, read_base)) {
        return .{ .integer = .{ .negative = negative, .digits = body, .radix = read_base } };
    }
    // 比
    if (std.mem.indexOfScalar(u8, body, '/')) |slash| {
        const num = body[0..slash];
        const den = body[slash + 1 ..];
        if (allDigits(num, read_base) and allDigits(den, read_base)) {
            if (allZero(den)) return error.DivisionByZero;
            return .{ .ratio = .{ .negative = negative, .numerator = num, .denominator = den, .radix = read_base } };
        }
        return null;
    }
    return parseFloat(negative, body, default_float, buf);
}

fn parseFloat(negative: bool, body: []const u8, default_float: FloatFormat, buf: []u8) Error!?Number {
    // [digits] [. digits] [marker [sign] digits]（10進のみ）
    var i: usize = 0;
    const int_start = i;
    while (i < body.len and body[i] >= '0' and body[i] <= '9') : (i += 1) {}
    const int_part = body[int_start..i];
    var frac_part: []const u8 = "";
    var has_point = false;
    if (i < body.len and body[i] == '.') {
        has_point = true;
        i += 1;
        const fs = i;
        while (i < body.len and body[i] >= '0' and body[i] <= '9') : (i += 1) {}
        frac_part = body[fs..i];
    }
    var format = default_float;
    var exp_part: []const u8 = "";
    var exp_negative = false;
    var has_exp = false;
    if (i < body.len and isExponentMarker(body[i])) {
        has_exp = true;
        format = switch (body[i]) {
            'e', 'E' => default_float,
            's', 'S', 'f', 'F' => .single,
            else => .double,
        };
        i += 1;
        if (i < body.len and (body[i] == '+' or body[i] == '-')) {
            exp_negative = body[i] == '-';
            i += 1;
        }
        const es = i;
        while (i < body.len and body[i] >= '0' and body[i] <= '9') : (i += 1) {}
        exp_part = body[es..i];
        if (exp_part.len == 0) return null;
    }
    if (i != body.len) return null;
    // 形の条件：「小数点の後ろに数字がある」か「指数がある」。整数部・小数部の少なくとも一方に数字
    if (int_part.len == 0 and frac_part.len == 0) return null;
    if (!has_exp and (!has_point or frac_part.len == 0)) return null;

    // 正規化した文字列を作って解析する
    const needed = 1 + int_part.len + 1 + frac_part.len + 2 + 2 + exp_part.len;
    if (buf.len < needed) return null;
    var n: usize = 0;
    if (negative) {
        buf[n] = '-';
        n += 1;
    }
    if (int_part.len == 0) {
        buf[n] = '0';
        n += 1;
    } else {
        @memcpy(buf[n .. n + int_part.len], int_part);
        n += int_part.len;
    }
    if (frac_part.len > 0) {
        buf[n] = '.';
        n += 1;
        @memcpy(buf[n .. n + frac_part.len], frac_part);
        n += frac_part.len;
    }
    if (has_exp) {
        buf[n] = 'e';
        n += 1;
        if (exp_negative) {
            buf[n] = '-';
            n += 1;
        }
        @memcpy(buf[n .. n + exp_part.len], exp_part);
        n += exp_part.len;
    }
    const s = buf[0..n];
    switch (format) {
        .single => {
            const v = std.fmt.parseFloat(f32, s) catch return null;
            if (std.math.isInf(v)) return error.FloatOverflow;
            return .{ .float = .{ .single = v } };
        },
        .double => {
            const v = std.fmt.parseFloat(f64, s) catch return null;
            if (std.math.isInf(v)) return error.FloatOverflow;
            return .{ .float = .{ .double = v } };
        },
    }
}

/// 潜在的な数か（CLHS 2.3.1.1「Potential Numbers as Tokens」）。印字でシンボルを |…| で囲むかの判定に使う。
/// 規則（SBCL 2.6.7 の印字で確認）：
///   1. 数字・符号（+ -）・比の記号（/）・小数点（.）・拡張文字（^ _）・英字（数の記号）だけからなる
///   2. 数字を少なくとも1つ含む（*read-base* が 10 より大きければ、その基数の数字になる英字も数字とみなす）
///   3. 先頭は数字・符号・小数点・拡張文字のどれか
///   4. 末尾は符号でない
///   5. 英字が2つ続かない（例：1AB は潜在的な数ではない）
pub fn isPotentialNumber(text: []const u8, read_base: u8) bool {
    if (text.len == 0) return false;
    var has_digit = false;
    var prev_letter = false;
    for (text, 0..) |c, i| {
        const is_dec = c >= '0' and c <= '9';
        const is_letter = std.ascii.isAlphabetic(c);
        const letter_digit = is_letter and (digitValue(c) orelse 99) < read_base;
        const is_digit = is_dec or letter_digit;
        const ok = is_digit or is_letter or c == '+' or c == '-' or c == '/' or c == '.' or c == '^' or c == '_';
        if (!ok) return false;
        if (is_digit) has_digit = true;
        if (i == 0 and !(is_digit or c == '+' or c == '-' or c == '.' or c == '^' or c == '_')) return false;
        const counts_as_letter = is_letter and !letter_digit;
        if (counts_as_letter and prev_letter) return false;
        prev_letter = counts_as_letter;
    }
    const last = text[text.len - 1];
    if (last == '+' or last == '-') return false;
    return has_digit;
}

const testing = std.testing;

test "potential numbers (SBCL 2.6.7)" {
    const yes = [_][]const u8{ "1A", "1A2", "1^", "^1", "_1", "1_", "1.", "1.5X", "+1A", "1-2", "1+2", "--1", "1/", ".1A", "1E5E", "12.", "1E" };
    const no = [_][]const u8{ "1AB", "A1", "-", "/1", "1EE5", "1+", "+.", "FOO", "^", "" };
    for (yes) |t| testing.expect(isPotentialNumber(t, 10)) catch |e| {
        std.debug.print("expected potential: {s}\n", .{t});
        return e;
    };
    for (no) |t| testing.expect(!isPotentialNumber(t, 10)) catch |e| {
        std.debug.print("expected not potential: {s}\n", .{t});
        return e;
    };
}

fn p(text: []const u8, base: u8) Error!?Number {
    var buf: [128]u8 = undefined;
    return parse(text, base, .single, &buf);
}

test "integers" {
    const a = (try p("42", 10)).?.integer;
    try testing.expectEqualStrings("42", a.digits);
    try testing.expect(!a.negative);
    try testing.expect((try p("-42", 10)).?.integer.negative);
    try testing.expectEqualStrings("42", (try p("+42", 10)).?.integer.digits);
    const d = (try p("42.", 16)).?.integer;
    try testing.expectEqual(@as(u8, 10), d.radix);
    const h = (try p("ff", 16)).?.integer;
    try testing.expectEqual(@as(u8, 16), h.radix);
    try testing.expectEqual(@as(?Number, null), try p("g", 16));
}

test "ratios" {
    const r = (try p("-3/6", 10)).?.ratio;
    try testing.expect(r.negative);
    try testing.expectEqualStrings("3", r.numerator);
    try testing.expectEqualStrings("6", r.denominator);
    try testing.expectError(error.DivisionByZero, p("1/0", 10));
    try testing.expectEqual(@as(?Number, null), try p("1/2/3", 10));
}

test "floats" {
    try testing.expectEqual(@as(f32, 1.5), (try p("1.5", 10)).?.float.single);
    try testing.expectEqual(@as(f32, 0.5), (try p(".5", 10)).?.float.single);
    try testing.expectEqual(@as(f32, -0.5), (try p("-.5", 10)).?.float.single);
    try testing.expectEqual(@as(f32, 100000.0), (try p("1e5", 10)).?.float.single);
    try testing.expectEqual(@as(f64, 1.5), (try p("1.5d0", 10)).?.float.double);
    try testing.expectEqual(@as(f64, 1.5), (try p("1.5L0", 10)).?.float.double);
    try testing.expectEqual(@as(f32, 1.5), (try p("1.5s0", 10)).?.float.single);
    try testing.expectEqual(@as(f32, 0.0), (try p("1.0e-50", 10)).?.float.single);
    try testing.expectError(error.FloatOverflow, p("3.4028236e38", 10));
    try testing.expectEqual(@as(f32, 1.5), (try p("1.5", 16)).?.float.single);
}

test "not numbers" {
    for ([_][]const u8{ "1e", "1e+", "1.0.0", "+", "-", "+.", "1+", "1-", "-1-", "1a", "a1", "." }) |t| {
        try testing.expectEqual(@as(?Number, null), try p(t, 10));
    }
}
