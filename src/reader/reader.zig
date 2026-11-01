//! Reader（CLHS 2.2「Reader Algorithm」）。
//!
//! Reader は Lisp の値の表現から独立させる（基本設計 §4.1）。値を作る処理は、型 `Builder` として
//! コンパイル時に受け取る。Phase 05 で、本物の Value を作る Builder を用意する。
//!
//! Builder に必要な宣言:
//!   pub const Datum: type
//!   fn integer(b: *Builder, loc: SourceLoc, negative: bool, digits: []const u8, radix: u8) Error!Datum
//!   fn ratio(b: *Builder, loc: SourceLoc, negative: bool, numerator: []const u8, denominator: []const u8, radix: u8) Error!Datum
//!   fn float(b: *Builder, loc: SourceLoc, value: number.Float) Error!Datum
//!   fn symbol(b: *Builder, loc: SourceLoc, package: PackageRef, name: []const u8) Error!Datum
//! 文字列の引数は呼び出しの間だけ有効である（Builder が必要なら複製する）。
//!
//! Phase 03 の範囲：空白、コメント（`;`、`#| |#`）、数、シンボル（エスケープ、パッケージ修飾、大文字への変換）。
//! マクロ文字（`(` `)` `'` `"` `` ` `` `,` と `#` の他の dispatch）は Phase 04 で実装する。それまでは
//! 「未実装」の reader-error にする（黙って別の値を返さない：基本設計 §3.1）。

const std = @import("std");
pub const source = @import("source.zig");
pub const syntax = @import("syntax.zig");
pub const number = @import("number.zig");

pub const SourceLoc = source.SourceLoc;
pub const Source = source.Source;

pub const Error = error{
    /// 構文の誤り（詳細は Reader.diagnostic）
    ReaderError,
    /// データの途中でテキストが終わった（CL の end-of-file）
    EndOfFile,
    OutOfMemory,
};

pub const Diagnostic = struct {
    loc: SourceLoc = .{ .line = 0, .col = 0 },
    message: []const u8 = "",
};

pub const PackageRef = union(enum) {
    /// 修飾なし（*package* で解決する）
    current,
    /// :name
    keyword,
    /// pkg:name（external = true）、pkg::name（external = false）
    named: struct { name: []const u8, external: bool },
};

pub const Options = struct {
    /// *read-base*
    read_base: u8 = 10,
    /// *read-default-float-format*
    default_float: number.FloatFormat = .single,
    /// true なら read-preserving-whitespace と同じく、トークンの後ろの空白を読まない
    preserve_whitespace: bool = false,
};

const TokenChar = struct { cp: u21, escaped: bool };

pub fn Reader(comptime Builder: type) type {
    return struct {
        const Self = @This();
        pub const Datum = Builder.Datum;

        src: *Source,
        builder: *Builder,
        gpa: std.mem.Allocator,
        options: Options = .{},
        diagnostic: Diagnostic = .{},
        token: std.ArrayList(TokenChar) = .empty,
        scratch: std.ArrayList(u8) = .empty,
        scratch2: std.ArrayList(u8) = .empty,

        pub fn init(gpa: std.mem.Allocator, src: *Source, builder: *Builder, options: Options) Self {
            return .{ .src = src, .builder = builder, .gpa = gpa, .options = options };
        }

        pub fn deinit(self: *Self) void {
            self.token.deinit(self.gpa);
            self.scratch.deinit(self.gpa);
            self.scratch2.deinit(self.gpa);
        }

        fn fail(self: *Self, loc: SourceLoc, message: []const u8) Error {
            self.diagnostic = .{ .loc = loc, .message = message };
            return error.ReaderError;
        }

        fn eof(self: *Self, loc: SourceLoc, message: []const u8) Error {
            self.diagnostic = .{ .loc = loc, .message = message };
            return error.EndOfFile;
        }

        fn peek(self: *Self) Error!?source.Char {
            return self.src.peek() catch self.fail(self.src.loc(), "UTF-8 として正しくないバイト列です");
        }

        /// 次のデータを1つ読む。データの前でテキストが終われば null を返す。
        pub fn read(self: *Self) Error!?Datum {
            while (true) {
                const ch = (try self.peek()) orelse return null;
                switch (syntax.syntaxType(ch.cp)) {
                    .invalid => return self.fail(self.src.loc(), "この文字はトークンに使えません（Backspace・Rubout）"),
                    .whitespace => self.src.advance(ch),
                    .terminating_macro => switch (ch.cp) {
                        ';' => try self.skipLineComment(),
                        ')' => return self.fail(self.src.loc(), "対応する開き括弧のない ) です"),
                        else => return self.fail(self.src.loc(), "このマクロ文字は未実装です（Phase 04 で実装予定）"),
                    },
                    .non_terminating_macro => {
                        // '#' の dispatch。Phase 03 では #| |# だけを扱う
                        const loc = self.src.loc();
                        self.src.advance(ch);
                        const sub = (try self.peek()) orelse return self.eof(loc, "# の後でテキストが終わりました");
                        if (sub.cp == '|') {
                            self.src.advance(sub);
                            try self.skipBlockComment(loc);
                        } else {
                            return self.fail(loc, "この # の dispatch は未実装です（Phase 04 で実装予定）");
                        }
                    },
                    .single_escape, .multiple_escape, .constituent => return try self.readToken(),
                }
            }
        }

        fn skipLineComment(self: *Self) Error!void {
            while (try self.peek()) |ch| {
                self.src.advance(ch);
                if (ch.cp == '\n') return;
            }
        }

        /// #| ... |#（入れ子にできる）。開始の #| は読み終えている
        fn skipBlockComment(self: *Self, start: SourceLoc) Error!void {
            var depth: usize = 1;
            var prev: u21 = 0;
            while (try self.peek()) |ch| {
                self.src.advance(ch);
                if (prev == '|' and ch.cp == '#') {
                    depth -= 1;
                    if (depth == 0) return;
                    prev = 0;
                    continue;
                }
                if (prev == '#' and ch.cp == '|') {
                    depth += 1;
                    prev = 0;
                    continue;
                }
                prev = ch.cp;
            }
            return self.eof(start, "#| のコメントが閉じられていません");
        }

        fn readToken(self: *Self) Error!Datum {
            const start = self.src.loc();
            self.token.clearRetainingCapacity();
            var in_multiple = false;
            while (true) {
                const ch_opt = try self.peek();
                if (in_multiple) {
                    const ch = ch_opt orelse return self.eof(start, "| で始まるエスケープが閉じられていません");
                    self.src.advance(ch);
                    switch (syntax.syntaxType(ch.cp)) {
                        .multiple_escape => in_multiple = false,
                        .single_escape => {
                            const e = (try self.peek()) orelse return self.eof(start, "\\ の後でテキストが終わりました");
                            self.src.advance(e);
                            try self.token.append(self.gpa, .{ .cp = e.cp, .escaped = true });
                        },
                        else => try self.token.append(self.gpa, .{ .cp = ch.cp, .escaped = true }),
                    }
                    continue;
                }
                const ch = ch_opt orelse break;
                switch (syntax.syntaxType(ch.cp)) {
                    .constituent, .non_terminating_macro => {
                        self.src.advance(ch);
                        try self.token.append(self.gpa, .{ .cp = syntax.upcase(ch.cp), .escaped = false });
                    },
                    .single_escape => {
                        self.src.advance(ch);
                        const e = (try self.peek()) orelse return self.eof(start, "\\ の後でテキストが終わりました");
                        self.src.advance(e);
                        try self.token.append(self.gpa, .{ .cp = e.cp, .escaped = true });
                    },
                    .multiple_escape => {
                        self.src.advance(ch);
                        in_multiple = true;
                    },
                    .invalid => return self.fail(self.src.loc(), "この文字はトークンに使えません（Backspace・Rubout）"),
                    .terminating_macro => break,
                    .whitespace => {
                        if (!self.options.preserve_whitespace) self.src.advance(ch);
                        break;
                    },
                }
            }
            return self.interpretToken(start);
        }

        fn interpretToken(self: *Self, loc: SourceLoc) Error!Datum {
            const tok = self.token.items;
            var any_escaped = false;
            var all_ascii = true;
            var all_dots = true;
            for (tok) |c| {
                if (c.escaped) any_escaped = true;
                if (c.cp > 0x7F) all_ascii = false;
                if (c.escaped or c.cp != '.') all_dots = false;
            }
            if (all_dots and tok.len > 0) {
                return self.fail(loc, if (tok.len == 1) "ドット（.）はリストの中でしか使えません" else "ドットだけのトークンは読めません");
            }

            // 数（エスケープを含まない ASCII のトークンだけ）
            if (!any_escaped and all_ascii) {
                self.scratch.clearRetainingCapacity();
                for (tok) |c| try self.scratch.append(self.gpa, @intCast(c.cp));
                try self.scratch2.resize(self.gpa, tok.len + 8);
                const parsed = number.parse(self.scratch.items, self.options.read_base, self.options.default_float, self.scratch2.items) catch |err| switch (err) {
                    error.DivisionByZero => return self.fail(loc, "分母が 0 の比は読めません"),
                    error.FloatOverflow => return self.fail(loc, "浮動小数の範囲を超えています"),
                };
                if (parsed) |n| switch (n) {
                    .integer => |i| return self.builder.integer(loc, i.negative, i.digits, i.radix),
                    .ratio => |r| return self.builder.ratio(loc, r.negative, r.numerator, r.denominator, r.radix),
                    .float => |f| return self.builder.float(loc, f),
                };
            }

            // シンボル：エスケープされていないコロンでパッケージを分ける
            var colon: ?usize = null;
            var colons: usize = 0;
            for (tok, 0..) |c, i| {
                if (!c.escaped and c.cp == ':') {
                    if (colon == null) colon = i;
                    colons += 1;
                }
            }
            var pkg: PackageRef = .current;
            var name_start: usize = 0;
            if (colon) |ci| {
                const double = ci + 1 < tok.len and !tok[ci + 1].escaped and tok[ci + 1].cp == ':';
                const used: usize = if (double) 2 else 1;
                if (colons > used) return self.fail(loc, "トークンにコロンが多すぎます");
                name_start = ci + used;
                if (name_start >= tok.len) return self.fail(loc, "コロンの後にシンボル名がありません");
                if (ci == 0) {
                    pkg = .keyword; // :name と ::name（SBCL 2.6.7 と同じく ::name もキーワードとする）
                } else {
                    try self.encode(tok[0..ci], &self.scratch2);
                    pkg = .{ .named = .{ .name = self.scratch2.items, .external = !double } };
                }
            }
            try self.encode(tok[name_start..], &self.scratch);
            return self.builder.symbol(loc, pkg, self.scratch.items);
        }

        fn encode(self: *Self, chars: []const TokenChar, out: *std.ArrayList(u8)) Error!void {
            out.clearRetainingCapacity();
            for (chars) |c| {
                var b: [4]u8 = undefined;
                const n = std.unicode.utf8Encode(c.cp, &b) catch unreachable;
                try out.appendSlice(self.gpa, b[0..n]);
            }
        }
    };
}

// ---------------------------------------------------------------------------
// 試験用の Builder：読んだデータを文字列で表す（Value ができる Phase 05 までの確認用）

const TestBuilder = struct {
    arena: std.mem.Allocator,
    locs: std.ArrayList(SourceLoc) = .empty,

    pub const Datum = []const u8;

    fn note(b: *TestBuilder, loc: SourceLoc) Error!void {
        try b.locs.append(b.arena, loc);
    }
    pub fn integer(b: *TestBuilder, loc: SourceLoc, negative: bool, digits: []const u8, radix: u8) Error!Datum {
        try b.note(loc);
        return std.fmt.allocPrint(b.arena, "int:{s}{s}@{d}", .{ if (negative) "-" else "", digits, radix });
    }
    pub fn ratio(b: *TestBuilder, loc: SourceLoc, negative: bool, num: []const u8, den: []const u8, radix: u8) Error!Datum {
        try b.note(loc);
        return std.fmt.allocPrint(b.arena, "ratio:{s}{s}/{s}@{d}", .{ if (negative) "-" else "", num, den, radix });
    }
    pub fn float(b: *TestBuilder, loc: SourceLoc, value: number.Float) Error!Datum {
        try b.note(loc);
        return switch (value) {
            .single => |v| std.fmt.allocPrint(b.arena, "sf:{d}", .{v}),
            .double => |v| std.fmt.allocPrint(b.arena, "df:{d}", .{v}),
        };
    }
    pub fn symbol(b: *TestBuilder, loc: SourceLoc, pkg: PackageRef, name: []const u8) Error!Datum {
        try b.note(loc);
        return switch (pkg) {
            .current => std.fmt.allocPrint(b.arena, "sym:{s}", .{name}),
            .keyword => std.fmt.allocPrint(b.arena, "kw:{s}", .{name}),
            .named => |n| std.fmt.allocPrint(b.arena, "sym:{s}{s}{s}", .{ n.name, if (n.external) ":" else "::", name }),
        };
    }
};

const testing = std.testing;

const Case = struct { input: []const u8, expect: []const u8 };

fn readOne(input: []const u8, options: Options) ![]const u8 {
    var arena_state = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena_state.deinit();
    var src = Source.init(input, 0);
    var b: TestBuilder = .{ .arena = arena_state.allocator() };
    var r = Reader(TestBuilder).init(testing.allocator, &src, &b, options);
    defer r.deinit();
    const d = r.read() catch |err| return switch (err) {
        error.ReaderError => "ERROR",
        error.EndOfFile => "EOF-ERROR",
        error.OutOfMemory => err,
    };
    const s = d orelse "NONE";
    return testing.allocator.dupe(u8, s);
}

fn expectRead(cases: []const Case, options: Options) !void {
    for (cases) |c| {
        const got = try readOne(c.input, options);
        defer if (!std.mem.eql(u8, got, "ERROR") and !std.mem.eql(u8, got, "EOF-ERROR")) testing.allocator.free(got);
        testing.expectEqualStrings(c.expect, got) catch |err| {
            std.debug.print("input: {s}\n", .{c.input});
            return err;
        };
    }
}

// 期待値は SBCL 2.6.7 で同じ入力を read-from-string した結果に合わせている。
// ただし整数・比は、Reader の段階では正規化しない（2/4 の約分は数値の層の役割：Phase 20）。
test "numbers (SBCL 2.6.7)" {
    try expectRead(&.{
        .{ .input = "42", .expect = "int:42@10" },
        .{ .input = "+42", .expect = "int:42@10" },
        .{ .input = "-42", .expect = "int:-42@10" },
        .{ .input = "42.", .expect = "int:42@10" },
        .{ .input = "-0", .expect = "int:-0@10" },
        .{ .input = "1/2", .expect = "ratio:1/2@10" },
        .{ .input = "-3/6", .expect = "ratio:-3/6@10" },
        .{ .input = "1/0", .expect = "ERROR" },
        .{ .input = "1.5", .expect = "sf:1.5" },
        .{ .input = ".5", .expect = "sf:0.5" },
        .{ .input = "-.5", .expect = "sf:-0.5" },
        .{ .input = "+.5", .expect = "sf:0.5" },
        .{ .input = "1.", .expect = "int:1@10" },
        .{ .input = "1e5", .expect = "sf:100000" },
        .{ .input = "1E5", .expect = "sf:100000" },
        .{ .input = "1.5e3", .expect = "sf:1500" },
        .{ .input = "1.5d0", .expect = "df:1.5" },
        .{ .input = "1.5s0", .expect = "sf:1.5" },
        .{ .input = "1.5f0", .expect = "sf:1.5" },
        .{ .input = "1.5l0", .expect = "df:1.5" },
        .{ .input = "3.4028236e38", .expect = "ERROR" },
        .{ .input = "1.0e-50", .expect = "sf:0" },
        .{ .input = "1.0d-400", .expect = "df:0" },
        .{ .input = "123456789012345678901234567890", .expect = "int:123456789012345678901234567890@10" },
    }, .{});
}

test "read-base 16 (SBCL 2.6.7)" {
    try expectRead(&.{
        .{ .input = "a", .expect = "int:A@16" },
        .{ .input = "ff", .expect = "int:FF@16" },
        .{ .input = "1.", .expect = "int:1@10" },
        .{ .input = "10", .expect = "int:10@16" },
        .{ .input = "1.5", .expect = "sf:1.5" },
        .{ .input = "g", .expect = "sym:G" },
    }, .{ .read_base = 16 });
}

test "double default float format" {
    try expectRead(&.{
        .{ .input = "1.5", .expect = "df:1.5" },
        .{ .input = "1.5e0", .expect = "df:1.5" },
        .{ .input = "1.5f0", .expect = "sf:1.5" },
    }, .{ .default_float = .double });
}

test "symbols (SBCL 2.6.7)" {
    try expectRead(&.{
        .{ .input = "1e", .expect = "sym:1E" },
        .{ .input = "1e+", .expect = "sym:1E+" },
        .{ .input = "1.0.0", .expect = "sym:1.0.0" },
        .{ .input = "1/2/3", .expect = "sym:1/2/3" },
        .{ .input = "1+", .expect = "sym:1+" },
        .{ .input = "+", .expect = "sym:+" },
        .{ .input = "-", .expect = "sym:-" },
        .{ .input = "+.", .expect = "sym:+." },
        .{ .input = "foo", .expect = "sym:FOO" },
        .{ .input = "Foo", .expect = "sym:FOO" },
        .{ .input = "fOO-bar", .expect = "sym:FOO-BAR" },
        .{ .input = "\\a", .expect = "sym:a" },
        .{ .input = "\\aB", .expect = "sym:aB" },
        .{ .input = "|aB|c", .expect = "sym:aBC" },
        .{ .input = "a|b c|d", .expect = "sym:Ab cD" },
        .{ .input = "|a\\|b|", .expect = "sym:a|b" },
        .{ .input = "1a", .expect = "sym:1A" },
        .{ .input = "a1", .expect = "sym:A1" },
        .{ .input = "-1-", .expect = "sym:-1-" },
        .{ .input = "^", .expect = "sym:^" },
        .{ .input = "a#b", .expect = "sym:A#B" },
        .{ .input = "日本語", .expect = "sym:日本語" },
        // ASCII 以外の大文字への変換は処理系依存。Zilisp は変換しない（SBCL は É にする）
        .{ .input = "é", .expect = "sym:é" },
        .{ .input = "\\1", .expect = "sym:1" },
        .{ .input = "|42|", .expect = "sym:42" },
    }, .{});
}

test "package markers (SBCL 2.6.7)" {
    try expectRead(&.{
        .{ .input = ":kw", .expect = "kw:KW" },
        .{ .input = ":Kw", .expect = "kw:KW" },
        .{ .input = "::a", .expect = "kw:A" },
        .{ .input = "cl:car", .expect = "sym:CL:CAR" },
        .{ .input = "cl::car", .expect = "sym:CL::CAR" },
        .{ .input = "a:b:c", .expect = "ERROR" },
        .{ .input = "a:", .expect = "ERROR" },
        .{ .input = "a::", .expect = "ERROR" },
        .{ .input = ":", .expect = "ERROR" },
        .{ .input = "|a:b|", .expect = "sym:a:b" },
        .{ .input = "a\\:b", .expect = "sym:A:B" },
    }, .{});
}

test "dots and errors" {
    try expectRead(&.{
        .{ .input = ".", .expect = "ERROR" },
        .{ .input = "..", .expect = "ERROR" },
        .{ .input = "...", .expect = "ERROR" },
        .{ .input = "\\.", .expect = "sym:." },
        .{ .input = ")", .expect = "ERROR" },
        .{ .input = "'a", .expect = "ERROR" },
        .{ .input = "\\", .expect = "EOF-ERROR" },
        .{ .input = "|abc", .expect = "EOF-ERROR" },
        .{ .input = "a\x08b", .expect = "ERROR" },
        .{ .input = "a\x7fb", .expect = "ERROR" },
        .{ .input = "#| x", .expect = "EOF-ERROR" },
        .{ .input = "", .expect = "NONE" },
        .{ .input = "   ; only comment", .expect = "NONE" },
    }, .{});
}

test "comments and whitespace (SBCL 2.6.7)" {
    try expectRead(&.{
        .{ .input = "#|a #|b|# c|# x", .expect = "sym:X" },
        .{ .input = "; c\ny", .expect = "sym:Y" },
        .{ .input = "  z  ", .expect = "sym:Z" },
        .{ .input = "a\tb", .expect = "sym:A" },
        .{ .input = "a\x00b", .expect = "sym:A\x00B" },
    }, .{});
}

test "sequence of data with locations" {
    var arena_state = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena_state.deinit();
    const input = "a b ; c\n  1.5 #| x\n|# 42\r\nλ";
    var src = Source.init(input, 7);
    var b: TestBuilder = .{ .arena = arena_state.allocator() };
    var r = Reader(TestBuilder).init(testing.allocator, &src, &b, .{});
    defer r.deinit();
    const expected = [_][]const u8{ "sym:A", "sym:B", "sf:1.5", "int:42@10", "sym:λ" };
    for (expected) |e| try testing.expectEqualStrings(e, (try r.read()).?);
    try testing.expectEqual(@as(?[]const u8, null), try r.read());
    const locs = [_]SourceLoc{
        .{ .file = 7, .line = 1, .col = 1 },
        .{ .file = 7, .line = 1, .col = 3 },
        .{ .file = 7, .line = 2, .col = 3 },
        .{ .file = 7, .line = 3, .col = 4 },
        .{ .file = 7, .line = 4, .col = 1 },
    };
    try testing.expectEqualSlices(SourceLoc, &locs, b.locs.items);
}

test "consumes one trailing whitespace like SBCL read" {
    var arena_state = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena_state.deinit();
    var src = Source.init("  z  ", 0);
    var b: TestBuilder = .{ .arena = arena_state.allocator() };
    var r = Reader(TestBuilder).init(testing.allocator, &src, &b, .{});
    defer r.deinit();
    _ = try r.read();
    try testing.expectEqual(@as(usize, 4), src.pos); // SBCL 2.6.7 の read-from-string も 4 を返す

    var src2 = Source.init("  z  ", 0);
    var r2 = Reader(TestBuilder).init(testing.allocator, &src2, &b, .{ .preserve_whitespace = true });
    defer r2.deinit();
    _ = try r2.read();
    try testing.expectEqual(@as(usize, 3), src2.pos);
}

test "diagnostic location" {
    var arena_state = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena_state.deinit();
    var src = Source.init("ok\n  a:b:c", 0);
    var b: TestBuilder = .{ .arena = arena_state.allocator() };
    var r = Reader(TestBuilder).init(testing.allocator, &src, &b, .{});
    defer r.deinit();
    _ = try r.read();
    try testing.expectError(error.ReaderError, r.read());
    try testing.expectEqual(SourceLoc{ .line = 2, .col = 3 }, r.diagnostic.loc);
}

test {
    _ = source;
    _ = syntax;
    _ = number;
}
