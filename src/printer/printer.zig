//! 印字（prin1 相当。*print-escape* が真、*print-pretty* が偽、*print-readably* は偽の場合）。
//! 規則は SBCL 2.6.7 の出力に合わせる（CLHS 22.1.3「Default Print-Object Methods」）。
//! Phase 05 の範囲：fixnum、文字、single-float・double-float、シンボル、文字列、リスト、単純ベクタ。

const std = @import("std");
const rt_mod = @import("../runtime/runtime.zig");
const syntax = @import("../reader/syntax.zig");
const number = @import("../reader/number.zig");
const Runtime = rt_mod.Runtime;
const Value = rt_mod.Value;
const Writer = std.Io.Writer;

pub const Error = Writer.Error;

pub fn prin1(rt: *Runtime, w: *Writer, v: Value) Error!void {
    if (v.isFixnum()) return w.print("{d}", .{v.asFixnum()});
    if (v == Value.nil) return w.writeAll("NIL");
    if (v.isChar()) return printChar(w, v.asChar());
    if (v.isSingleFloat()) return printFloat(w, f32, v.asSingle());
    if (v == Value.unbound) return w.writeAll("#<unbound>");
    if (v == Value.unwind) return w.writeAll("#<unwind>");
    if (v.isCons()) return printList(rt, w, v);
    if (v.isFunctionPointer()) return printFunction(rt, w, v);
    switch (Runtime.kindOf(v) orelse return w.print("#<object {x}>", .{v.raw()})) {
        .symbol => return printSymbol(rt, w, v),
        .string => return printString(w, v),
        .double_float => return printFloat(w, f64, Runtime.doubleValue(v)),
        .simple_vector => {
            try w.writeAll("#(");
            for (Runtime.vectorPtr(v).items(), 0..) |x, i| {
                if (i > 0) try w.writeByte(' ');
                try prin1(rt, w, x);
            }
            return w.writeByte(')');
        },
        .package => return w.print("#<PACKAGE \"{s}\">", .{Runtime.packageData(v).name}),
        .closure, .native_function => return w.print("#<object {x}>", .{v.raw()}),
        .code => return w.print("#<CODE {{{X}}}>", .{v.raw() & ~@as(u64, 7)}),
        .value_cell => return w.print("#<VALUE-CELL {{{X}}}>", .{v.raw() & ~@as(u64, 7)}),
        .hash_table => {
            const object = @import("../values/object.zig");
            const t: *object.HashTable = @ptrCast(@alignCast(v.pointer()));
            const name = switch (@as(object.HashTest, @fromBackingInt(t.header.aux))) {
                .eq => "EQ",
                .eql => "EQL",
                .equal => "EQUAL",
            };
            // SBCL 2.6.7 と同じ形：#<HASH-TABLE :TEST EQL :COUNT 2 {…}>
            return w.print("#<HASH-TABLE :TEST {s} :COUNT {d} {{{X}}}>", .{ name, t.count, v.raw() & ~@as(u64, 7) });
        },
        _ => return w.print("#<object {x}>", .{v.raw()}),
    }
}

/// 関数（SBCL 2.6.7 と同じ形：#<FUNCTION CAR>、#<FUNCTION (LAMBDA (X)) {アドレス}>）
fn printFunction(rt: *Runtime, w: *Writer, v: Value) Error!void {
    const function = @import("../runtime/function.zig");
    switch (function.kindOfFunction(v)) {
        .native_function => {
            try w.writeAll("#<FUNCTION ");
            try prin1(rt, w, function.nativePtr(v).name);
            try w.writeByte('>');
        },
        .closure => {
            const name = function.closurePtr(v).codePtr().name;
            try w.writeAll("#<FUNCTION ");
            try printCodeName(rt, w, name);
            // 名前の付いた大域の関数（defun）はアドレスを書かない（SBCL 2.6.7：#<FUNCTION FACT>、#<FUNCTION (SETF F)>）
            if (!name.isCons() or Runtime.consPtr(name).car == rt.syms.setf) return w.writeByte('>');
            try w.print(" {{{X}}}>", .{v.raw() & ~@as(u64, 7)});
        },
        else => try w.print("#<FUNCTION {{{X}}}>", .{v.raw() & ~@as(u64, 7)}),
    }
}

/// 関数の名前（Code の name）を書く：FACT、(LAMBDA (X))、(FLET F)。トップレベルのフォーム（NIL）は「トップレベル」
pub fn printCodeName(rt: *Runtime, w: *Writer, name: Value) Error!void {
    if (name == Value.nil) return w.writeAll("（トップレベル）");
    if (name.isCons() and Runtime.consPtr(name).car == rt.syms.lambda) {
        // 空のラムダリストは () と書く（SBCL 2.6.7：#<FUNCTION (LAMBDA ()) {…}>）
        const ll = Runtime.consPtr(Runtime.consPtr(name).cdr).car;
        try w.writeAll("(LAMBDA ");
        if (ll == Value.nil) try w.writeAll("()") else try prin1(rt, w, ll);
        return w.writeByte(')');
    }
    try prin1(rt, w, name);
}

fn printList(rt: *Runtime, w: *Writer, v: Value) Error!void {
    try w.writeByte('(');
    var x = v;
    var first = true;
    while (x.isCons()) {
        if (!first) try w.writeByte(' ');
        first = false;
        const c = Runtime.consPtr(x);
        try prin1(rt, w, c.car);
        x = c.cdr;
    }
    if (x != Value.nil) {
        try w.writeAll(" . ");
        try prin1(rt, w, x);
    }
    try w.writeByte(')');
}

fn printString(w: *Writer, v: Value) Error!void {
    const s = Runtime.stringPtr(v);
    try w.writeByte('"');
    var i: usize = 0;
    while (i < s.length()) : (i += 1) {
        const cp = s.charAt(i);
        if (cp == '"' or cp == '\\') try w.writeByte('\\');
        try writeCp(w, cp);
    }
    try w.writeByte('"');
}

fn writeCp(w: *Writer, cp: u21) Error!void {
    var b: [4]u8 = undefined;
    const n = std.unicode.utf8Encode(cp, &b) catch return w.print("\\u{x}", .{cp});
    try w.writeAll(b[0..n]);
}

fn printChar(w: *Writer, cp: u21) Error!void {
    try w.writeAll("#\\");
    const name: ?[]const u8 = switch (cp) {
        '\n' => "Newline",
        '\t' => "Tab",
        0x0C => "Page",
        '\r' => "Return",
        0x7F => "Rubout",
        0x08 => "Backspace",
        0 => "Nul",
        else => null,
    };
    if (name) |n| return w.writeAll(n);
    // 名前のない制御文字は U+XXXX で書く（Zilisp の Reader で読み戻せる形。SBCL は #\Soh のような名前を使う）
    if (cp < 0x20 or (cp >= 0x80 and cp < 0xA0)) return w.print("U+{X}", .{cp});
    return writeCp(w, cp);
}

/// 浮動小数（SBCL 2.6.7 と同じ形）：
///   0.001 ≦ |x| < 1e7 は小数点の形（1.5、100000.0）、それ以外は指数の形（1.0e7、1.0e-4）。
///   桁数は読み戻せる最短の桁数。double-float には d を付ける（1.5d0、1.0d7）。
fn printFloat(w: *Writer, comptime T: type, x: T) Error!void {
    if (std.math.isNan(x)) return w.writeAll(if (T == f32) "#<single-float quiet NaN>" else "#<double-float quiet NaN>");
    if (std.math.isInf(x)) return w.print("#<{s}-float {s}infinity>", .{ if (T == f32) "single" else "double", if (x < 0) "-" else "+" });
    const suffix_fixed: []const u8 = if (T == f32) "" else "d0";
    const marker: u8 = if (T == f32) 'e' else 'd';
    if (std.math.signbit(x)) try w.writeByte('-');
    const a = @abs(x);
    if (a == 0) return w.print("0.0{s}", .{suffix_fixed});

    // 最短の桁と10進の指数を得る（Zig の {e} は最短の桁で "d.ddde±x" を出す）
    var buf: [64]u8 = undefined;
    const s = std.fmt.bufPrint(&buf, "{e}", .{a}) catch unreachable;
    const e_pos = std.mem.indexOfScalar(u8, s, 'e').?;
    const exp10 = std.fmt.parseInt(i32, s[e_pos + 1 ..], 10) catch unreachable;
    var digits_buf: [40]u8 = undefined;
    var nd: usize = 0;
    for (s[0..e_pos]) |c| {
        if (c != '.') {
            digits_buf[nd] = c;
            nd += 1;
        }
    }
    const digits = digits_buf[0..nd]; // 値 = 0.d1d2... × 10^(exp10+1)

    if (a >= 1e-3 and a < 1e7) {
        const point: i32 = exp10 + 1; // 小数点の前の桁数
        if (point <= 0) {
            try w.writeAll("0.");
            var z: i32 = 0;
            while (z < -point) : (z += 1) try w.writeByte('0');
            try w.writeAll(digits);
        } else {
            const p: usize = @intCast(point);
            if (p >= digits.len) {
                try w.writeAll(digits);
                var z: usize = digits.len;
                while (z < p) : (z += 1) try w.writeByte('0');
                try w.writeAll(".0");
            } else {
                try w.writeAll(digits[0..p]);
                try w.writeByte('.');
                try w.writeAll(digits[p..]);
            }
        }
        return w.writeAll(suffix_fixed);
    }
    try w.writeByte(digits[0]);
    try w.writeByte('.');
    if (digits.len > 1) try w.writeAll(digits[1..]) else try w.writeByte('0');
    return w.print("{c}{d}", .{ marker, exp10 });
}

fn printSymbol(rt: *Runtime, w: *Writer, v: Value) Error!void {
    const sym = rt.symbolPtr(v);
    var name_buf: Writer.Allocating = .init(rt.gpa);
    defer name_buf.deinit();
    Runtime.writeStringUtf8(sym.name, &name_buf.writer) catch return error.WriteFailed;
    const name = name_buf.written();

    if (sym.package == Value.nil) {
        try w.writeAll("#:");
    } else {
        const home = Runtime.packageData(sym.package);
        if (home == rt.keyword) {
            try w.writeByte(':');
        } else {
            // 今のパッケージから同じシンボルが見えれば修飾しない
            const visible = if (rt.findSymbol(rt.current, name)) |f| f.symbol == v else false;
            if (!visible) {
                try writeSymbolName(w, home.name);
                const external = if (home.external.get(name)) |s| s == v else false;
                try w.writeAll(if (external) ":" else "::");
            }
        }
    }
    try writeSymbolName(w, name);
}

/// シンボル名を、必要なら |…| で囲んで書く（CLHS 22.1.3.3.1）
fn writeSymbolName(w: *Writer, name: []const u8) Error!void {
    if (!needsEscape(name)) return w.writeAll(name);
    try w.writeByte('|');
    for (name) |c| {
        if (c == '|' or c == '\\') try w.writeByte('\\');
        try w.writeByte(c);
    }
    try w.writeByte('|');
}

fn needsEscape(name: []const u8) bool {
    if (name.len == 0) return true;
    var all_dots = true;
    var all_ascii = true;
    var it = (std.unicode.Utf8View.init(name) catch return true).iterator();
    while (it.nextCodepoint()) |cp| {
        if (cp != '.') all_dots = false;
        if (cp > 0x7F) all_ascii = false;
        // 読み取りで大文字に変わる文字（Zilisp の Reader は ASCII だけを変換する）
        if (syntax.upcase(cp) != cp) return true;
        switch (syntax.syntaxType(cp)) {
            .constituent => {},
            // # は先頭以外なら囲まなくても読み戻せるが、SBCL 2.6.7 は位置にかかわらず囲む（A#B → |A#B|）ので合わせる
            .non_terminating_macro => return true,
            else => return true,
        }
        if (cp == ':') return true;
    }
    if (all_dots) return true;
    if (all_ascii) {
        var buf: [256]u8 = undefined;
        if (name.len + 8 <= buf.len) {
            if (number.parse(name, 10, .single, &buf) catch return true) |_| return true;
        }
        if (number.isPotentialNumber(name, 10)) return true;
    }
    return false;
}

// ---------------------------------------------------------------------------

const testing = std.testing;
const vb = @import("../reader/value_builder.zig");

fn readPrint(rt: *Runtime, text: []const u8) ![]u8 {
    var diag: @import("../reader/reader.zig").Diagnostic = .{};
    var x = try vb.readAll(rt, testing.allocator, text, &diag);
    var out: Writer.Allocating = .init(testing.allocator);
    defer out.deinit();
    var first = true;
    while (x != Value.nil) : (x = Runtime.consPtr(x).cdr) {
        if (!first) try out.writer.writeByte('\n');
        first = false;
        try prin1(rt, &out.writer, Runtime.consPtr(x).car);
    }
    return out.toOwnedSlice();
}

fn expectPrint(rt: *Runtime, input: []const u8, expected: []const u8) !void {
    const got = try readPrint(rt, input);
    defer testing.allocator.free(got);
    testing.expectEqualStrings(expected, got) catch |e| {
        std.debug.print("input: {s}\n", .{input});
        return e;
    };
}

test "floats print like SBCL 2.6.7" {
    const rt = try Runtime.create(testing.allocator);
    defer rt.destroy();
    const cases = [_][2][]const u8{
        .{ "1.5", "1.5" },                                       .{ "100000.0", "100000.0" },         .{ "1234567.0", "1234567.0" },
        .{ "9999999.0", "9999999.0" },                           .{ "10000000.0", "1.0e7" },          .{ "1.5e10", "1.5e10" },
        .{ "0.001", "0.001" },                                   .{ "0.0001", "1.0e-4" },             .{ "123.456", "123.456" },
        .{ "0.1", "0.1" },                                       .{ "-0.0", "-0.0" },                 .{ "0.0", "0.0" },
        .{ "1.0", "1.0" },                                       .{ "1.5d0", "1.5d0" },               .{ "1.0d7", "1.0d7" },
        .{ "1.0d-4", "1.0d-4" },                                 .{ "0.1d0", "0.1d0" },               .{ "100000.0d0", "100000.0d0" },
        .{ "1d100", "1.0d100" },                                 .{ "3.4028235e38", "3.4028235e38" }, .{ "0.33333334", "0.33333334" },
        .{ "1.7976931348623157d308", "1.7976931348623157d308" },
    };
    for (cases) |c| try expectPrint(rt, c[0], c[1]);
}

test "symbols print like SBCL 2.6.7" {
    const rt = try Runtime.create(testing.allocator);
    defer rt.destroy();
    const cases = [_][2][]const u8{
        .{ "foo", "FOO" },                 .{ "|foo|", "|foo|" },     .{ "|Foo|", "|Foo|" },
        .{ "|a b|", "|a b|" },             .{ "|1|", "|1|" },         .{ "|1.5|", "|1.5|" },
        .{ "1+", "1+" },                   .{ "+", "+" },             .{ "|.|", "|.|" },
        .{ "|..|", "|..|" },               .{ "|a.b|", "|a.b|" },     .{ "-", "-" },
        .{ "|a:b|", "|a:b|" },             .{ "|(|", "|(|" },         .{ "|a\\|b|", "|a\\|b|" },
        .{ "|a\\\\b|", "|a\\\\b|" },       .{ "|#a|", "|#a|" },       .{ "|a#|", "|a#|" },
        .{ "||", "||" },                   .{ ":kw", ":KW" },         .{ ":|kw|", ":|kw|" },
        .{ "#:u", "#:U" },                 .{ "#:|u|", "#:|u|" },     .{ "cl:car", "CAR" },
        .{ "日本語", "日本語" },
        .{ "|1E|", "|1E|" },               .{ "|1E5|", "|1E5|" },     .{ "+.", "+." },
        .{ "|1/2|", "|1/2|" },             .{ "|1/2/3|", "|1/2/3|" }, .{ "^", "^" },
        .{ "|A;B|", "|A;B|" },             .{ "nil", "NIL" },         .{ "t", "T" },
        .{ "1ab", "1AB" },                 .{ "|1A|", "|1A|" },       .{ "zl-sys::quasiquote", "ZILISP-SYSTEM:QUASIQUOTE" },
        .{ "zilisp::foo", "ZILISP::FOO" },
        // 空のエスケープ（||）もエスケープとして扱う（SBCL 2.6.7 と同じ）
        .{ "1||", "|1|" },         .{ ":||", ":||" },
        .{ "(a .|| b)", "(A |.| B)" },     .{ "..||", "|..|" },       .{ "||1", "|1|" },
        .{ "cl-user::||", "||" },
    };
    for (cases) |c| try expectPrint(rt, c[0], c[1]);
}

test "other objects print like SBCL 2.6.7" {
    const rt = try Runtime.create(testing.allocator);
    defer rt.destroy();
    const cases = [_][2][]const u8{
        .{ "\"abc\"", "\"abc\"" },                         .{ "\"a\\\"b\"", "\"a\\\"b\"" },                     .{ "\"a\\\\b\"", "\"a\\\\b\"" },
        .{ "\"日本\"", "\"日本\"" },
        .{ "\"\"", "\"\"" },                               .{ "#\\a", "#\\a" },                                 .{ "#\\A", "#\\A" },
        .{ "#\\Space", "#\\ " },                           .{ "#\\Newline", "#\\Newline" },                     .{ "#\\Tab", "#\\Tab" },
        .{ "#\\Return", "#\\Return" },                     .{ "#\\Page", "#\\Page" },                           .{ "#\\Rubout", "#\\Rubout" },
        .{ "#\\Backspace", "#\\Backspace" },               .{ "#\\Nul", "#\\Nul" },                             .{ "#\\(", "#\\(" },
        .{ "#\\\"", "#\\\"" },                             .{ "(1 2 3)", "(1 2 3)" },                           .{ "(1 . 2)", "(1 . 2)" },
        .{ "(1 2 . 3)", "(1 2 . 3)" },                     .{ "'a", "(QUOTE A)" },                              .{ "#'f", "(FUNCTION F)" },
        .{ "((a) (b))", "((A) (B))" },                     .{ "#(1 2)", "#(1 2)" },                             .{ "#()", "#()" },
        .{ "(nil)", "(NIL)" },                             .{ "0", "0" },                                       .{ "-5", "-5" },
        .{ "2305843009213693951", "2305843009213693951" }, .{ "-2305843009213693952", "-2305843009213693952" },
        // 読み飛ばしの最中の #n= は値を返さず、続くオブジェクトが読み飛ばされる（SBCL 2.6.7）
        .{ "#+nosuch #1=(a b) c", "C" },
        .{ "(#+nosuch #1=(a b) c)", "(C)" },               .{ "#+nosuch #1=#2=(a) c", "C" },                    .{ "#+nosuch ## c", "C" },
    };
    for (cases) |c| try expectPrint(rt, c[0], c[1]);
}

test "read errors from the value builder" {
    const rt = try Runtime.create(testing.allocator);
    defer rt.destroy();
    var diag: @import("../reader/reader.zig").Diagnostic = .{};
    for ([_][]const u8{ "nosuchpkg:x", "cl:nosuchsym123", "2305843009213693952", "1/2", "||:x", "cl-user:" }) |t| {
        testing.expectError(error.ReaderError, vb.readAll(rt, testing.allocator, t, &diag)) catch |e| {
            std.debug.print("input: {s}\n", .{t});
            return e;
        };
    }
}

test "round trip: read, print, read gives an equal structure" {
    const rt = try Runtime.create(testing.allocator);
    defer rt.destroy();
    const inputs = [_][]const u8{
        "(defun fact (n) (if (<= n 1) 1 (* n (fact (- n 1)))))",
        "(a |b c| \"s\\\"t\" #\\x #\\Space 1.5 2.5d0 -3 :k #(1 (2)) (x . y))",
        "(cl-user::foo zl-sys:quasiquote |1E5| |.| \\1)",
    };
    for (inputs) |text| {
        const once = try readPrint(rt, text);
        defer testing.allocator.free(once);
        const twice = try readPrint(rt, once);
        defer testing.allocator.free(twice);
        try testing.expectEqualStrings(once, twice);
    }
}

test "interned symbols are eq after reading" {
    const rt = try Runtime.create(testing.allocator);
    defer rt.destroy();
    var diag: @import("../reader/reader.zig").Diagnostic = .{};
    var x = try vb.readAll(rt, testing.allocator, "foo FOO |FOO| cl-user::foo #:foo car cl:car", &diag);
    var v: [7]Value = undefined;
    for (&v) |*it| {
        it.* = Runtime.consPtr(x).car;
        x = Runtime.consPtr(x).cdr;
    }
    try testing.expect(v[0] == v[1] and v[1] == v[2] and v[2] == v[3]);
    try testing.expect(v[4] != v[0]);
    try testing.expect(v[5] == v[6]);
}
