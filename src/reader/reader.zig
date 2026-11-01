//! Reader（CLHS 2.2「Reader Algorithm」、2.4「Standard Macro Characters」）。
//!
//! Reader は Lisp の値の表現から独立させる（基本設計 §4.1）。値を作る処理は、型 `Builder` として
//! コンパイル時に受け取る。Phase 05 で、本物の Value を作る Builder を用意する。
//!
//! Builder に必要な宣言（文字列の引数は呼び出しの間だけ有効。必要なら Builder が複製する）。
//! diag を受け取る関数は、失敗するときに diag に位置とメッセージを書いて error.ReaderError を返す:
//!   pub const Datum: type
//!   pub const List: type                       リストやベクタを組み立てる途中の状態
//!   fn integer(b, diag: *Diagnostic, loc, negative: bool, digits: []const u8, radix: u8) Error!Datum
//!   fn ratio(b, diag: *Diagnostic, loc, negative: bool, numerator: []const u8, denominator: []const u8, radix: u8) Error!Datum
//!   fn float(b, loc, value: number.Float) Error!Datum
//!   fn symbol(b, diag: *Diagnostic, loc, package: PackageRef, name: []const u8) Error!Datum
//!   fn nil(b, loc) Error!Datum
//!   fn string(b, loc, utf8: []const u8) Error!Datum
//!   fn character(b, loc, cp: u21) Error!Datum
//!   fn listBegin(b, loc) Error!List
//!   fn listPush(b, list: *List, item: Datum) Error!void
//!   fn listEnd(b, list: *List, tail: ?Datum) Error!Datum        tail は (a . b) の b
//!   fn vectorEnd(b, list: *List) Error!Datum                     #( ... ) の単純ベクタ
//!
//! Phase 04 の範囲：quote、文字列、リスト（ドット対を含む）、#'、#(、#\、#:、#b #o #x #nR、
//! backquote（zl-sys:quasiquote / unquote / unquote-splicing / unquote-nsplicing）、#+ / #-（*read-suppress*）。
//! #P（Phase 23）、#S（Phase 26）、#C（Phase 20）、#A（Phase 21）、#. #= ##（Phase 24）は「未実装」の reader-error にする。

const std = @import("std");
pub const source = @import("source.zig");
pub const syntax = @import("syntax.zig");
pub const number = @import("number.zig");
pub const features = @import("features.zig");

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
    /// #:name
    uninterned,
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
    /// *features*（キーワードの名前。大文字）
    features: []const []const u8 = features.default,
};

const TokenChar = struct { cp: u21, escaped: bool };

const cl_package = "COMMON-LISP";
const sys_package = "ZILISP-SYSTEM";

pub fn Reader(comptime Builder: type) type {
    return struct {
        const Self = @This();
        pub const Datum = Builder.Datum;

        const Obj = union(enum) {
            datum: Datum,
            /// リストの中のドット
            dot: SourceLoc,
            /// )
            close: SourceLoc,
        };

        src: *Source,
        builder: *Builder,
        gpa: std.mem.Allocator,
        options: Options = .{},
        diagnostic: Diagnostic = .{},
        token: std.ArrayList(TokenChar) = .empty,
        scratch: std.ArrayList(u8) = .empty,
        scratch2: std.ArrayList(u8) = .empty,
        /// backquote の入れ子の深さ
        bq_depth: usize = 0,
        /// *read-suppress*（#+ / #- で読み飛ばしている間）
        suppress: bool = false,

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
            const obj = (try self.readObj()) orelse return null;
            return switch (obj) {
                .datum => |d| d,
                .dot => |loc| self.fail(loc, "ドット（.）はリストの中でしか使えません"),
                .close => |loc| self.fail(loc, "対応する開き括弧のない ) です"),
            };
        }

        /// 空白・コメント・#+ / #- で読み飛ばしたものを除いて、次の要素を読む。テキストの終わりなら null。
        fn readObj(self: *Self) Error!?Obj {
            while (true) {
                const ch = (try self.peek()) orelse return null;
                const loc = self.src.loc();
                switch (syntax.syntaxType(ch.cp)) {
                    .invalid => return self.fail(loc, "この文字はトークンに使えません（Backspace・Rubout）"),
                    .whitespace => self.src.advance(ch),
                    .terminating_macro => {
                        self.src.advance(ch);
                        switch (ch.cp) {
                            ';' => try self.skipLineComment(),
                            '(' => return .{ .datum = try self.readList(loc) },
                            ')' => return .{ .close = loc },
                            '\'' => return .{ .datum = try self.wrap(loc, cl_package, "QUOTE", try self.readRequired(loc, "' の後")) },
                            '`' => {
                                self.bq_depth += 1;
                                defer self.bq_depth -= 1;
                                const x = try self.readRequired(loc, "` の後");
                                return .{ .datum = try self.wrap(loc, sys_package, "QUASIQUOTE", x) };
                            },
                            ',' => return .{ .datum = try self.readComma(loc) },
                            '"' => return .{ .datum = try self.readString(loc) },
                            else => unreachable,
                        }
                    },
                    .non_terminating_macro => {
                        self.src.advance(ch);
                        if (try self.readDispatch(loc)) |d| return .{ .datum = d };
                    },
                    .single_escape, .multiple_escape, .constituent => return try self.readToken(.normal),
                }
            }
        }

        /// 必ず1つのデータを読む（' の後など）
        fn readRequired(self: *Self, start: SourceLoc, what: []const u8) Error!Datum {
            _ = what;
            const obj = (try self.readObj()) orelse return self.eof(start, "データの途中でテキストが終わりました");
            return switch (obj) {
                .datum => |d| d,
                .dot => |loc| self.fail(loc, "ここにドット（.）は置けません"),
                .close => |loc| self.fail(loc, "ここに ) は置けません"),
            };
        }

        fn sym(self: *Self, loc: SourceLoc, pkg: []const u8, name: []const u8) Error!Datum {
            return self.builder.symbol(&self.diagnostic, loc, .{ .named = .{ .name = pkg, .external = true } }, name);
        }

        /// (pkg:name x) を作る
        fn wrap(self: *Self, loc: SourceLoc, pkg: []const u8, name: []const u8, x: Datum) Error!Datum {
            var list = try self.builder.listBegin(loc);
            try self.builder.listPush(&list, try self.sym(loc, pkg, name));
            try self.builder.listPush(&list, x);
            return self.builder.listEnd(&list, null);
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

        fn readList(self: *Self, start: SourceLoc) Error!Datum {
            var list = try self.builder.listBegin(start);
            var count: usize = 0;
            while (true) {
                const obj = (try self.readObj()) orelse return self.eof(start, "( が閉じられていません");
                switch (obj) {
                    .close => return self.builder.listEnd(&list, null),
                    .datum => |d| {
                        try self.builder.listPush(&list, d);
                        count += 1;
                    },
                    .dot => |loc| {
                        if (count == 0) return self.fail(loc, "ドット（.）の前に要素がありません");
                        const tail = try self.readRequired(loc, ". の後");
                        const after = (try self.readObj()) orelse return self.eof(start, "( が閉じられていません");
                        switch (after) {
                            .close => return self.builder.listEnd(&list, tail),
                            .datum, .dot => return self.fail(loc, "ドット（.）の後には要素を1つだけ置けます"),
                        }
                    },
                }
            }
        }

        fn readComma(self: *Self, loc: SourceLoc) Error!Datum {
            if (self.bq_depth == 0 and !self.suppress) return self.fail(loc, "コンマ（,）が backquote の外にあります");
            var name: []const u8 = "UNQUOTE";
            if (try self.peek()) |next| {
                if (next.cp == '@') {
                    self.src.advance(next);
                    name = "UNQUOTE-SPLICING";
                } else if (next.cp == '.') {
                    self.src.advance(next);
                    name = "UNQUOTE-NSPLICING";
                }
            }
            const saved = self.bq_depth;
            if (self.bq_depth > 0) self.bq_depth -= 1;
            defer self.bq_depth = saved;
            const x = try self.readRequired(loc, ", の後");
            return self.wrap(loc, sys_package, name, x);
        }

        fn readString(self: *Self, start: SourceLoc) Error!Datum {
            self.scratch.clearRetainingCapacity();
            while (true) {
                const ch = (try self.peek()) orelse return self.eof(start, "文字列が閉じられていません");
                self.src.advance(ch);
                var cp = ch.cp;
                if (cp == '"') break;
                if (syntax.syntaxType(cp) == .single_escape) {
                    const e = (try self.peek()) orelse return self.eof(start, "文字列が閉じられていません");
                    self.src.advance(e);
                    cp = e.cp;
                }
                try self.appendUtf8(&self.scratch, cp);
            }
            if (self.suppress) return self.builder.nil(start);
            return self.builder.string(start, self.scratch.items);
        }

        /// # の後。null は「何も作らなかった」（コメント・#+ / #- で読み飛ばした）ことを表す
        fn readDispatch(self: *Self, loc: SourceLoc) Error!?Datum {
            // #n( などの10進の引数
            var arg: ?usize = null;
            var ch = (try self.peek()) orelse return self.eof(loc, "# の後でテキストが終わりました");
            while (ch.cp >= '0' and ch.cp <= '9') {
                self.src.advance(ch);
                const d: usize = ch.cp - '0';
                arg = std.math.add(usize, std.math.mul(usize, arg orelse 0, 10) catch return self.fail(loc, "# の数値の引数が大きすぎます"), d) catch return self.fail(loc, "# の数値の引数が大きすぎます");
                ch = (try self.peek()) orelse return self.eof(loc, "# の後でテキストが終わりました");
            }
            self.src.advance(ch);
            switch (syntax.upcase(ch.cp)) {
                '\'' => return try self.wrap(loc, cl_package, "FUNCTION", try self.readRequired(loc, "#' の後")),
                '(' => return try self.readVector(loc, arg),
                '\\' => return try self.readCharacter(loc),
                ':' => {
                    const obj = try self.readToken(.uninterned);
                    return switch (obj) {
                        .datum => |d| d,
                        else => self.fail(loc, "#: の後にシンボル名がありません"),
                    };
                },
                'B' => return try self.readRadix(loc, 2),
                'O' => return try self.readRadix(loc, 8),
                'X' => return try self.readRadix(loc, 16),
                'R' => {
                    const base = arg orelse return self.fail(loc, "#R には基数（2〜36）が必要です");
                    if (base < 2 or base > 36) return self.fail(loc, "#R の基数は 2〜36 です");
                    return try self.readRadix(loc, @intCast(base));
                },
                '|' => {
                    try self.skipBlockComment(loc);
                    return null;
                },
                '+', '-' => {
                    const want = ch.cp == '+';
                    const saved = self.suppress;
                    // 機能式は KEYWORD パッケージで読む（CLHS 24.1.2.1）。
                    // 読み飛ばしの最中でも機能式は評価し、偽なら次の要素をさらに読み飛ばす
                    // （SBCL 2.6.7：#+nosuch #+sbcl a b → B、#+nosuch #-sbcl a b c → C）
                    const value = try self.featureExpr(loc);
                    if (value != want) {
                        self.suppress = true;
                        defer self.suppress = saved;
                        _ = try self.readRequired(loc, "#+ / #- の後");
                    }
                    return null;
                },
                'P', 'S', 'C', 'A', '.', '=', '#' => {
                    if (self.suppress) {
                        if (ch.cp != '#' and ch.cp != '=') _ = try self.readRequired(loc, "# の後");
                        return try self.builder.nil(loc);
                    }
                    return self.fail(loc, switch (syntax.upcase(ch.cp)) {
                        'P' => "#P（パス名）は未実装です（Phase 23 で実装予定）",
                        'S' => "#S（構造体）は未実装です（Phase 26 で実装予定）",
                        'C' => "#C（複素数）は未実装です（Phase 20 で実装予定）",
                        'A' => "#A（配列）は未実装です（Phase 21 で実装予定）",
                        else => "#. #= ## は未実装です（Phase 24 で実装予定）",
                    });
                },
                else => return self.fail(loc, "この # の dispatch 文字は定義されていません"),
            }
        }

        fn readVector(self: *Self, start: SourceLoc, length: ?usize) Error!Datum {
            var list = try self.builder.listBegin(start);
            var count: usize = 0;
            var last: ?Datum = null;
            while (true) {
                const obj = (try self.readObj()) orelse return self.eof(start, "#( が閉じられていません");
                switch (obj) {
                    .close => break,
                    .dot => |loc| return self.fail(loc, "ベクタの中にドット（.）は置けません"),
                    .datum => |d| {
                        try self.builder.listPush(&list, d);
                        last = d;
                        count += 1;
                    },
                }
            }
            if (length) |n| {
                if (count > n) return self.fail(start, "#n( の要素が n より多くあります");
                if (count < n) {
                    // 残りは最後の要素で埋める（CLHS 2.4.8.3）
                    const fill = last orelse return self.fail(start, "#n( の要素がありません");
                    while (count < n) : (count += 1) try self.builder.listPush(&list, fill);
                }
            }
            return self.builder.vectorEnd(&list);
        }

        const char_names = [_]struct { name: []const u8, cp: u21 }{
            .{ .name = "NEWLINE", .cp = '\n' }, .{ .name = "SPACE", .cp = ' ' },
            .{ .name = "TAB", .cp = '\t' },     .{ .name = "PAGE", .cp = 0x0C },
            .{ .name = "RUBOUT", .cp = 0x7F },  .{ .name = "LINEFEED", .cp = '\n' },
            .{ .name = "RETURN", .cp = '\r' },  .{ .name = "BACKSPACE", .cp = 0x08 },
            .{ .name = "NUL", .cp = 0 },        .{ .name = "NULL", .cp = 0 },
        };

        /// #\x、#\Name、#\U+XXXX
        fn readCharacter(self: *Self, start: SourceLoc) Error!Datum {
            const first = (try self.peek()) orelse return self.eof(start, "#\\ の後でテキストが終わりました");
            self.src.advance(first);
            self.scratch.clearRetainingCapacity();
            try self.appendUtf8(&self.scratch, first.cp);
            var len: usize = 1;
            // 続く構成文字を集める（名前の場合）
            while (try self.peek()) |ch| {
                switch (syntax.syntaxType(ch.cp)) {
                    .constituent, .non_terminating_macro => {
                        self.src.advance(ch);
                        try self.appendUtf8(&self.scratch, ch.cp);
                        len += 1;
                    },
                    .whitespace => {
                        if (!self.options.preserve_whitespace) self.src.advance(ch);
                        break;
                    },
                    else => break,
                }
            }
            if (self.suppress) return self.builder.nil(start);
            if (len == 1) return self.builder.character(start, first.cp);
            const name = self.scratch.items;
            for (char_names) |n| {
                if (std.ascii.eqlIgnoreCase(name, n.name)) return self.builder.character(start, n.cp);
            }
            // U+XXXX（SBCL 2.6.7 と同じ形）
            if (name.len > 2 and (name[0] == 'U' or name[0] == 'u') and name[1] == '+') {
                const v = std.fmt.parseInt(u21, name[2..], 16) catch return self.fail(start, "#\\U+ の後は16進の数です");
                if (v > 0x10FFFF) return self.fail(start, "文字コードが範囲外です");
                return self.builder.character(start, v);
            }
            return self.fail(start, "この文字の名前は定義されていません");
        }

        fn readRadix(self: *Self, start: SourceLoc, base: u8) Error!Datum {
            const obj = try self.readToken(.raw);
            _ = obj;
            if (self.suppress) return self.builder.nil(start);
            const tok = self.token.items;
            self.scratch.clearRetainingCapacity();
            for (tok) |c| {
                if (c.escaped or c.cp > 0x7F) return self.fail(start, "基数を指定した数として読めません");
                try self.scratch.append(self.gpa, @intCast(c.cp));
            }
            const text = self.scratch.items;
            // 末尾の小数点の形（10進の整数）と浮動小数は受け付けない
            if (text.len == 0 or text[text.len - 1] == '.') return self.fail(start, "基数を指定した数として読めません");
            try self.scratch2.resize(self.gpa, text.len + 8);
            const parsed = number.parse(text, base, self.options.default_float, self.scratch2.items) catch |err| switch (err) {
                error.DivisionByZero => return self.fail(start, "分母が 0 の比は読めません"),
                error.FloatOverflow => return self.fail(start, "基数を指定した数として読めません"),
            };
            const n = parsed orelse return self.fail(start, "基数を指定した数として読めません");
            return switch (n) {
                .integer => |i| self.builder.integer(&self.diagnostic, start, i.negative, i.digits, i.radix),
                .ratio => |r| self.builder.ratio(&self.diagnostic, start, r.negative, r.numerator, r.denominator, r.radix),
                .float => self.fail(start, "基数を指定した数として読めません"),
            };
        }

        /// #+ / #- の機能式を読んで評価する（CLHS 24.1.2.1）
        fn featureExpr(self: *Self, start: SourceLoc) Error!bool {
            while (true) {
                const ch = (try self.peek()) orelse return self.eof(start, "#+ / #- の機能式がありません");
                switch (syntax.syntaxType(ch.cp)) {
                    .whitespace => self.src.advance(ch),
                    .terminating_macro => {
                        if (ch.cp == ';') {
                            self.src.advance(ch);
                            try self.skipLineComment();
                            continue;
                        }
                        if (ch.cp != '(') return self.fail(self.src.loc(), "機能式として読めません");
                        self.src.advance(ch);
                        return self.featureList(start);
                    },
                    .single_escape, .multiple_escape, .constituent, .non_terminating_macro => {
                        _ = try self.readToken(.raw);
                        return self.featureAtom();
                    },
                    .invalid => return self.fail(self.src.loc(), "この文字はトークンに使えません（Backspace・Rubout）"),
                }
            }
        }

        fn featureAtom(self: *Self) Error!bool {
            var tok = self.token.items;
            // :name と name は同じ（KEYWORD パッケージで読む）。他のパッケージで修飾したものはキーワードではない
            if (tok.len > 0 and !tok[0].escaped and tok[0].cp == ':') tok = tok[1..];
            for (tok) |c| {
                if (!c.escaped and c.cp == ':') return false;
            }
            try self.encode(tok, &self.scratch2);
            return features.contains(self.options.features, self.scratch2.items);
        }

        fn featureList(self: *Self, start: SourceLoc) Error!bool {
            // 演算子
            while (try self.peek()) |ch| {
                if (syntax.syntaxType(ch.cp) != .whitespace) break;
                self.src.advance(ch);
            }
            _ = try self.readToken(.raw);
            var op = self.token.items;
            if (op.len > 0 and op[0].cp == ':') op = op[1..];
            try self.encode(op, &self.scratch2);
            const Op = enum { @"and", @"or", not };
            const kind: Op = if (std.mem.eql(u8, self.scratch2.items, "AND"))
                .@"and"
            else if (std.mem.eql(u8, self.scratch2.items, "OR"))
                .@"or"
            else if (std.mem.eql(u8, self.scratch2.items, "NOT"))
                .not
            else
                return self.fail(start, "機能式の演算子は AND・OR・NOT です");
            var result: bool = kind == .@"and";
            var count: usize = 0;
            while (true) {
                const ch = (try self.peek()) orelse return self.eof(start, "機能式の ( が閉じられていません");
                if (syntax.syntaxType(ch.cp) == .whitespace) {
                    self.src.advance(ch);
                    continue;
                }
                if (ch.cp == ')') {
                    self.src.advance(ch);
                    break;
                }
                const v = try self.featureExpr(start);
                count += 1;
                switch (kind) {
                    .@"and" => result = result and v,
                    .@"or" => result = result or v,
                    .not => result = !v,
                }
            }
            if (kind == .not and count != 1) return self.fail(start, "NOT の機能式には要素を1つだけ書きます");
            return result;
        }

        const TokenMode = enum { normal, uninterned, raw };

        fn readToken(self: *Self, mode: TokenMode) Error!Obj {
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
                    .invalid => {
                        if (self.suppress) {
                            self.src.advance(ch);
                            continue;
                        }
                        return self.fail(self.src.loc(), "この文字はトークンに使えません（Backspace・Rubout）");
                    },
                    .terminating_macro => break,
                    .whitespace => {
                        if (!self.options.preserve_whitespace) self.src.advance(ch);
                        break;
                    },
                }
            }
            if (mode == .raw) return .{ .datum = undefined };
            return self.interpretToken(start, mode);
        }

        fn interpretToken(self: *Self, loc: SourceLoc, mode: TokenMode) Error!Obj {
            const tok = self.token.items;
            var any_escaped = false;
            var all_ascii = true;
            var all_dots = true;
            for (tok) |c| {
                if (c.escaped) any_escaped = true;
                if (c.cp > 0x7F) all_ascii = false;
                if (c.escaped or c.cp != '.') all_dots = false;
            }
            if (all_dots and tok.len == 1 and mode == .normal) return .{ .dot = loc };
            if (self.suppress) return .{ .datum = try self.builder.nil(loc) };
            if (all_dots and tok.len > 1) return self.fail(loc, "ドットだけのトークンは読めません");

            if (mode == .normal and !any_escaped and all_ascii) {
                self.scratch.clearRetainingCapacity();
                for (tok) |c| try self.scratch.append(self.gpa, @intCast(c.cp));
                try self.scratch2.resize(self.gpa, tok.len + 8);
                const parsed = number.parse(self.scratch.items, self.options.read_base, self.options.default_float, self.scratch2.items) catch |err| switch (err) {
                    error.DivisionByZero => return self.fail(loc, "分母が 0 の比は読めません"),
                    error.FloatOverflow => return self.fail(loc, "浮動小数の範囲を超えています"),
                };
                if (parsed) |n| return .{ .datum = switch (n) {
                    .integer => |i| try self.builder.integer(&self.diagnostic, loc, i.negative, i.digits, i.radix),
                    .ratio => |r| try self.builder.ratio(&self.diagnostic, loc, r.negative, r.numerator, r.denominator, r.radix),
                    .float => |f| try self.builder.float(loc, f),
                } };
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
            var pkg: PackageRef = if (mode == .uninterned) .uninterned else .current;
            var name_start: usize = 0;
            if (colon) |ci| {
                if (mode == .uninterned) return self.fail(loc, "#: のシンボルにはパッケージを指定できません");
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
            return .{ .datum = try self.builder.symbol(&self.diagnostic, loc, pkg, self.scratch.items) };
        }

        fn appendUtf8(self: *Self, out: *std.ArrayList(u8), cp: u21) Error!void {
            var b: [4]u8 = undefined;
            const n = std.unicode.utf8Encode(cp, &b) catch return self.fail(self.src.loc(), "文字として表せないコードです");
            try out.appendSlice(self.gpa, b[0..n]);
        }

        fn encode(self: *Self, chars: []const TokenChar, out: *std.ArrayList(u8)) Error!void {
            out.clearRetainingCapacity();
            for (chars) |c| try self.appendUtf8(out, c.cp);
        }
    };
}

// ---------------------------------------------------------------------------
// 試験用の Builder：読んだデータを文字列で表す（Value ができる Phase 05 までの確認用）

const TestBuilder = struct {
    arena: std.mem.Allocator,
    locs: std.ArrayList(SourceLoc) = .empty,

    pub const Datum = []const u8;
    pub const List = struct { items: std.ArrayList([]const u8) = .empty };

    fn note(b: *TestBuilder, loc: SourceLoc) Error!void {
        try b.locs.append(b.arena, loc);
    }
    pub fn integer(b: *TestBuilder, _: *Diagnostic, loc: SourceLoc, negative: bool, digits: []const u8, radix: u8) Error!Datum {
        try b.note(loc);
        return std.fmt.allocPrint(b.arena, "int:{s}{s}@{d}", .{ if (negative) "-" else "", digits, radix });
    }
    pub fn ratio(b: *TestBuilder, _: *Diagnostic, loc: SourceLoc, negative: bool, num: []const u8, den: []const u8, radix: u8) Error!Datum {
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
    pub fn symbol(b: *TestBuilder, _: *Diagnostic, loc: SourceLoc, pkg: PackageRef, name: []const u8) Error!Datum {
        try b.note(loc);
        return switch (pkg) {
            .current => std.fmt.allocPrint(b.arena, "sym:{s}", .{name}),
            .keyword => std.fmt.allocPrint(b.arena, "kw:{s}", .{name}),
            .uninterned => std.fmt.allocPrint(b.arena, "unint:{s}", .{name}),
            .named => |n| if (std.mem.eql(u8, n.name, cl_package))
                std.fmt.allocPrint(b.arena, "cl:{s}", .{name})
            else if (std.mem.eql(u8, n.name, sys_package))
                std.fmt.allocPrint(b.arena, "sys:{s}", .{name})
            else
                std.fmt.allocPrint(b.arena, "sym:{s}{s}{s}", .{ n.name, if (n.external) ":" else "::", name }),
        };
    }
    pub fn nil(b: *TestBuilder, loc: SourceLoc) Error!Datum {
        try b.note(loc);
        return "NIL";
    }
    pub fn string(b: *TestBuilder, loc: SourceLoc, utf8: []const u8) Error!Datum {
        try b.note(loc);
        return std.fmt.allocPrint(b.arena, "\"{s}\"", .{utf8});
    }
    pub fn character(b: *TestBuilder, loc: SourceLoc, cp: u21) Error!Datum {
        try b.note(loc);
        return std.fmt.allocPrint(b.arena, "char:{x}", .{cp});
    }
    pub fn listBegin(b: *TestBuilder, loc: SourceLoc) Error!List {
        try b.note(loc);
        return .{};
    }
    pub fn listPush(b: *TestBuilder, list: *List, item: Datum) Error!void {
        try list.items.append(b.arena, item);
    }
    pub fn listEnd(b: *TestBuilder, list: *List, tail: ?Datum) Error!Datum {
        if (list.items.items.len == 0) return "NIL";
        const body = try std.mem.join(b.arena, " ", list.items.items);
        if (tail) |t| return std.fmt.allocPrint(b.arena, "({s} . {s})", .{ body, t });
        return std.fmt.allocPrint(b.arena, "({s})", .{body});
    }
    pub fn vectorEnd(b: *TestBuilder, list: *List) Error!Datum {
        const body = try std.mem.join(b.arena, " ", list.items.items);
        return std.fmt.allocPrint(b.arena, "#({s})", .{body});
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

fn isStatic(s: []const u8) bool {
    return std.mem.eql(u8, s, "ERROR") or std.mem.eql(u8, s, "EOF-ERROR");
}

fn expectRead(cases: []const Case, options: Options) !void {
    for (cases) |c| {
        const got = try readOne(c.input, options);
        defer if (!isStatic(got)) testing.allocator.free(got);
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

test "lists (SBCL 2.6.7)" {
    try expectRead(&.{
        .{ .input = "(a b c)", .expect = "(sym:A sym:B sym:C)" },
        .{ .input = "()", .expect = "NIL" },
        .{ .input = "( )", .expect = "NIL" },
        .{ .input = "(a . b)", .expect = "(sym:A . sym:B)" },
        .{ .input = "(a b . c)", .expect = "(sym:A sym:B . sym:C)" },
        .{ .input = "(. a)", .expect = "ERROR" },
        .{ .input = "(a . b c)", .expect = "ERROR" },
        .{ .input = "(a .)", .expect = "ERROR" },
        .{ .input = "(a . . b)", .expect = "ERROR" },
        .{ .input = "(a", .expect = "EOF-ERROR" },
        .{ .input = "(a ; c\n b)", .expect = "(sym:A sym:B)" },
        .{ .input = "(a #| c |# b)", .expect = "(sym:A sym:B)" },
        .{ .input = "((a) (b (c)))", .expect = "((sym:A) (sym:B (sym:C)))" },
        .{ .input = "(a))", .expect = "(sym:A)" },
        .{ .input = "(a .b)", .expect = "(sym:A sym:.B)" },
        .{ .input = "(1 . 2)", .expect = "(int:1@10 . int:2@10)" },
    }, .{});
}

test "quote, function, strings (SBCL 2.6.7)" {
    try expectRead(&.{
        .{ .input = "'a", .expect = "(cl:QUOTE sym:A)" },
        .{ .input = "'(a b)", .expect = "(cl:QUOTE (sym:A sym:B))" },
        .{ .input = "''a", .expect = "(cl:QUOTE (cl:QUOTE sym:A))" },
        .{ .input = "'", .expect = "EOF-ERROR" },
        .{ .input = "')", .expect = "ERROR" },
        .{ .input = "\"abc\"", .expect = "\"abc\"" },
        .{ .input = "\"a\\\"b\"", .expect = "\"a\"b\"" },
        .{ .input = "\"a\\nb\"", .expect = "\"anb\"" },
        .{ .input = "\"\\\\\"", .expect = "\"\\\"" },
        .{ .input = "\"abc", .expect = "EOF-ERROR" },
        .{ .input = "\"日本\"", .expect = "\"日本\"" },
        .{ .input = "\"a\nb\"", .expect = "\"a\nb\"" },
        .{ .input = "#'car", .expect = "(cl:FUNCTION sym:CAR)" },
        .{ .input = "#'(lambda (x) x)", .expect = "(cl:FUNCTION (sym:LAMBDA (sym:X) sym:X))" },
    }, .{});
}

test "vectors and characters (SBCL 2.6.7)" {
    try expectRead(&.{
        .{ .input = "#(1 2 3)", .expect = "#(int:1@10 int:2@10 int:3@10)" },
        .{ .input = "#()", .expect = "#()" },
        .{ .input = "#3(a b)", .expect = "#(sym:A sym:B sym:B)" },
        .{ .input = "#2(a b c)", .expect = "ERROR" },
        .{ .input = "#0()", .expect = "#()" },
        .{ .input = "#(a . b)", .expect = "ERROR" },
        .{ .input = "#\\a", .expect = "char:61" },
        .{ .input = "#\\A", .expect = "char:41" },
        .{ .input = "#\\Space", .expect = "char:20" },
        .{ .input = "#\\space", .expect = "char:20" },
        .{ .input = "#\\Newline", .expect = "char:a" },
        .{ .input = "#\\Tab", .expect = "char:9" },
        .{ .input = "#\\Return", .expect = "char:d" },
        .{ .input = "#\\Linefeed", .expect = "char:a" },
        .{ .input = "#\\Page", .expect = "char:c" },
        .{ .input = "#\\Backspace", .expect = "char:8" },
        .{ .input = "#\\Rubout", .expect = "char:7f" },
        .{ .input = "#\\Nul", .expect = "char:0" },
        .{ .input = "#\\(", .expect = "char:28" },
        .{ .input = "#\\)", .expect = "char:29" },
        .{ .input = "#\\;", .expect = "char:3b" },
        .{ .input = "#\\\"", .expect = "char:22" },
        .{ .input = "#\\ ", .expect = "char:20" },
        .{ .input = "#\\λ", .expect = "char:3bb" },
        .{ .input = "#\\あ", .expect = "char:3042" },
        .{ .input = "#\\ab", .expect = "ERROR" },
        .{ .input = "#\\U+3BB", .expect = "char:3bb" },
        .{ .input = "(#\\a #\\b)", .expect = "(char:61 char:62)" },
        .{ .input = "(#\\))", .expect = "(char:29)" },
    }, .{});
}

test "uninterned and radix (SBCL 2.6.7)" {
    try expectRead(&.{
        .{ .input = "#:foo", .expect = "unint:FOO" },
        .{ .input = "#:Foo", .expect = "unint:FOO" },
        .{ .input = "#:a:b", .expect = "ERROR" },
        .{ .input = "#b101", .expect = "int:101@2" },
        .{ .input = "#B-101", .expect = "int:-101@2" },
        .{ .input = "#o17", .expect = "int:17@8" },
        .{ .input = "#xff", .expect = "int:FF@16" },
        .{ .input = "#x-1F", .expect = "int:-1F@16" },
        .{ .input = "#b1/10", .expect = "ratio:1/10@2" },
        .{ .input = "#36rZZ", .expect = "int:ZZ@36" },
        .{ .input = "#2r102", .expect = "ERROR" },
        .{ .input = "#x", .expect = "ERROR" },
        .{ .input = "#xg", .expect = "ERROR" },
        .{ .input = "#x1.5", .expect = "ERROR" },
        .{ .input = "#r10", .expect = "ERROR" },
        .{ .input = "#37r10", .expect = "ERROR" },
    }, .{});
}

test "backquote" {
    try expectRead(&.{
        .{ .input = "`a", .expect = "(sys:QUASIQUOTE sym:A)" },
        .{ .input = "`(a ,b)", .expect = "(sys:QUASIQUOTE (sym:A (sys:UNQUOTE sym:B)))" },
        .{ .input = "`(a ,@b)", .expect = "(sys:QUASIQUOTE (sym:A (sys:UNQUOTE-SPLICING sym:B)))" },
        .{ .input = "`(a ,.b)", .expect = "(sys:QUASIQUOTE (sym:A (sys:UNQUOTE-NSPLICING sym:B)))" },
        .{ .input = ",a", .expect = "ERROR" },
        .{ .input = "`,a", .expect = "(sys:QUASIQUOTE (sys:UNQUOTE sym:A))" },
        .{ .input = "``(a ,,b)", .expect = "(sys:QUASIQUOTE (sys:QUASIQUOTE (sym:A (sys:UNQUOTE (sys:UNQUOTE sym:B)))))" },
        .{ .input = "`(a ,,b)", .expect = "ERROR" },
        .{ .input = "`(a . ,b)", .expect = "(sys:QUASIQUOTE (sym:A . (sys:UNQUOTE sym:B)))" },
    }, .{});
}

test "feature expressions" {
    const opts: Options = .{ .features = &.{ "ZILISP", "WIN32" } };
    try expectRead(&.{
        .{ .input = "#+zilisp a", .expect = "sym:A" },
        .{ .input = "#-zilisp a b", .expect = "sym:B" },
        .{ .input = "#+(or zilisp ccl) a", .expect = "sym:A" },
        .{ .input = "#+(and zilisp (not windows)) a b", .expect = "sym:A" },
        .{ .input = "#+nosuch (a b) c", .expect = "sym:C" },
        .{ .input = "#+nosuch nopkg:x c", .expect = "sym:C" },
        .{ .input = "#-nosuch a", .expect = "sym:A" },
        .{ .input = "#+ zilisp a", .expect = "sym:A" },
        .{ .input = "#+:zilisp a", .expect = "sym:A" },
        .{ .input = "#+nosuch #p\"x\" c", .expect = "sym:C" },
        .{ .input = "#+nosuch #\\NoSuchName c", .expect = "sym:C" },
        .{ .input = "#+nosuch ,a c", .expect = "sym:C" },
        .{ .input = "#+nosuch a.b.c d", .expect = "sym:D" },
        .{ .input = "(a #+nosuch b c)", .expect = "(sym:A sym:C)" },
        .{ .input = "(a #+nosuch b)", .expect = "(sym:A)" },
        .{ .input = "#+nosuch", .expect = "EOF-ERROR" },
        .{ .input = "#+(not a b) x", .expect = "ERROR" },
        .{ .input = "#+(xor a) x", .expect = "ERROR" },
        .{ .input = "#+nosuch #+zilisp a b", .expect = "sym:B" },
        .{ .input = "#+nosuch #-zilisp a b c", .expect = "sym:C" },
        .{ .input = "#+nosuch #+nosuch a b c", .expect = "sym:C" },
        .{ .input = "(x #+nosuch #+zilisp a b c)", .expect = "(sym:X sym:B sym:C)" },
    }, opts);
}

test "unimplemented dispatch is an explicit error" {
    try expectRead(&.{
        .{ .input = "#p\"x\"", .expect = "ERROR" },
        .{ .input = "#s(point)", .expect = "ERROR" },
        .{ .input = "#c(1 2)", .expect = "ERROR" },
        .{ .input = "#2a((1))", .expect = "ERROR" },
        .{ .input = "#.(+ 1 2)", .expect = "ERROR" },
        .{ .input = "#1=a", .expect = "ERROR" },
        .{ .input = "#!", .expect = "ERROR" },
        .{ .input = "#)", .expect = "ERROR" },
        .{ .input = "#< x", .expect = "ERROR" },
        .{ .input = "#", .expect = "EOF-ERROR" },
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

test "list locations" {
    var arena_state = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena_state.deinit();
    var src = Source.init("(defun f\n  (x) x)", 0);
    var b: TestBuilder = .{ .arena = arena_state.allocator() };
    var r = Reader(TestBuilder).init(testing.allocator, &src, &b, .{});
    defer r.deinit();
    _ = (try r.read()).?;
    // ( の位置、defun、f、(x) の ( 、x、x
    const locs = [_]SourceLoc{
        .{ .line = 1, .col = 1 }, .{ .line = 1, .col = 2 }, .{ .line = 1, .col = 8 },
        .{ .line = 2, .col = 3 }, .{ .line = 2, .col = 4 }, .{ .line = 2, .col = 7 },
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
    _ = features;
}
