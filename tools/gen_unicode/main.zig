//! Unicode の文字の表の生成器（Phase 21.5。詳細設計 §11.2）。
//!
//!   gen-unicode <UnicodeData.txt> <SpecialCasing.txt> <out.zig> [--check]
//!
//! data/unicode/ の UCD（Unicode 15.0.0。SBCL 2.6.7 と同じ版）から、CL の文字の関数が使う表を
//! src/unicode/tables.zig に書き出す。--check のときは書き出さず、いまのファイルと同じかを確かめる
//! （違えば終了コード 1。zig build test で実行する）。
//!
//! 表の作り方は SBCL 2.6.7 の tools-for-build/ucd.lisp と同じ：
//! - 文字の性質：一般カテゴリが L*（Lu・Ll・Lt・Lm・Lo）か、Nd か、10進数字の値（UnicodeData の 6 番目と 7 番目の欄が同じもの）。
//! - 大文字・小文字：SpecialCasing.txt の条件のない項目で UnicodeData.txt の単純な対応を上書きし、
//!   1 文字から 1 文字への対応で、行き来が往復するもの（Lu は小文字の大文字が自分、Ll は大文字の小文字が自分）だけを
//!   「大文字・小文字のある文字」にする（ucd.lisp の second-pass）。表には、大文字と小文字の両方が
//!   「大文字・小文字のある文字」である項目を入れる。
//! - SBCL との違い：大文字でも小文字でもない文字（タイトルケースの U+01C5 などの4文字）は表に入れない
//!   （CLHS 13.1.4.3：大文字・小文字のある文字は大文字か小文字のどちらか。SBCL 2.6.7 は表に入れるので、
//!   both-case-p が T、char-upcase が大文字を返す。tests/differential/impl-dependent.toml）。

const std = @import("std");
const Io = std.Io;

const n_cp = 0x110000;

const Gc = enum { other, lu, ll, lt, lm, lo, nd };

/// 大文字・小文字の対応の片方（len が 2 以上なら複数の文字への対応）
const Map = struct { len: u8 = 0, cp: u21 = 0 };

const Data = struct {
    gc: []Gc,
    decimal: []i8, // 10進数字の値（なければ -1）
    has_map: []bool,
    upper: []Map,
    lower: []Map,
    both: []bool, // CL の意味で大文字・小文字のある文字（ucd.lisp の cl-both-case-p）

    fn init(a: std.mem.Allocator) !Data {
        const d: Data = .{
            .gc = try a.alloc(Gc, n_cp),
            .decimal = try a.alloc(i8, n_cp),
            .has_map = try a.alloc(bool, n_cp),
            .upper = try a.alloc(Map, n_cp),
            .lower = try a.alloc(Map, n_cp),
            .both = try a.alloc(bool, n_cp),
        };
        @memset(d.gc, .other);
        @memset(d.decimal, -1);
        @memset(d.has_map, false);
        @memset(d.upper, .{});
        @memset(d.lower, .{});
        @memset(d.both, false);
        return d;
    }
};

fn parseCodepoints(field: []const u8) !Map {
    var it = std.mem.tokenizeScalar(u8, std.mem.trim(u8, field, " "), ' ');
    var m: Map = .{};
    while (it.next()) |tok| {
        const cp = try std.fmt.parseInt(u21, tok, 16);
        if (m.len == 0) m.cp = cp;
        m.len += 1;
    }
    return m;
}

fn gcOf(s: []const u8) Gc {
    const names = [_]struct { []const u8, Gc }{ .{ "Lu", .lu }, .{ "Ll", .ll }, .{ "Lt", .lt }, .{ "Lm", .lm }, .{ "Lo", .lo }, .{ "Nd", .nd } };
    for (names) |n| if (std.mem.eql(u8, s, n[0])) return n[1];
    return .other;
}

/// SpecialCasing.txt の条件のない項目（欄が 5 つの行：符号; 小文字; タイトル; 大文字; # 注釈）
fn readSpecialCasing(d: *Data, text: []const u8) !void {
    var lines = std.mem.splitScalar(u8, text, '\n');
    while (lines.next()) |raw| {
        const line = std.mem.trimEnd(u8, raw, "\r");
        const hash = std.mem.indexOfScalar(u8, line, '#') orelse continue;
        if (hash == 0) continue;
        var fields: [8][]const u8 = undefined;
        var n: usize = 0;
        var it = std.mem.splitScalar(u8, line, ';');
        while (it.next()) |f| : (n += 1) {
            if (n == fields.len) return error.BadSpecialCasing;
            fields[n] = f;
        }
        if (n != 5) continue; // 条件のある項目（欄が 6 つ）は使わない
        const cp = try std.fmt.parseInt(u21, std.mem.trim(u8, fields[0], " "), 16);
        d.has_map[cp] = true;
        d.lower[cp] = try parseCodepoints(fields[1]);
        d.upper[cp] = try parseCodepoints(fields[3]);
    }
}

fn readUnicodeData(d: *Data, text: []const u8) !void {
    var lines = std.mem.splitScalar(u8, text, '\n');
    var first: ?u21 = null;
    while (lines.next()) |raw| {
        const line = std.mem.trimEnd(u8, raw, "\r");
        if (line.len == 0) continue;
        var f: [15][]const u8 = undefined;
        var n: usize = 0;
        var it = std.mem.splitScalar(u8, line, ';');
        while (it.next()) |x| : (n += 1) {
            if (n == f.len) return error.BadUnicodeData;
            f[n] = x;
        }
        if (n != 15) return error.BadUnicodeData;
        const cp = try std.fmt.parseInt(u21, f[0], 16);
        const name = f[1];
        if (std.mem.endsWith(u8, name, ", First>")) {
            first = cp;
            continue;
        }
        const lo: u21 = if (std.mem.endsWith(u8, name, ", Last>")) (first orelse return error.BadUnicodeData) else cp;
        first = null;
        const gc = gcOf(f[2]);
        const dec: i8 = if (f[7].len != 0 and std.mem.eql(u8, f[6], f[7])) try std.fmt.parseInt(i8, f[7], 10) else -1;
        var c: u21 = lo;
        while (true) : (c += 1) {
            d.gc[c] = gc;
            d.decimal[c] = dec;
            if (c == cp) break;
        }
        const up: ?u21 = if (f[12].len != 0) try std.fmt.parseInt(u21, f[12], 16) else null;
        const down: ?u21 = if (f[13].len != 0) try std.fmt.parseInt(u21, f[13], 16) else null;
        d.both[cp] = (gc == .lu and down != null) or (gc == .ll and up != null);
        if (!d.has_map[cp] and (up != null or down != null)) {
            d.has_map[cp] = true;
            d.upper[cp] = .{ .len = 1, .cp = up orelse cp };
            d.lower[cp] = .{ .len = 1, .cp = down orelse cp };
        }
    }
}

/// ucd.lisp の second-pass：往復しない文字を「大文字・小文字のある文字」から外す
fn secondPass(d: *Data) void {
    for (0..n_cp) |i| {
        if (!d.has_map[i] or !d.both[i]) continue;
        const cp: u21 = @intCast(i);
        const up = d.upper[i];
        const lo = d.lower[i];
        const clear = up.len != 1 or lo.len != 1 or
            (d.gc[i] == .lu and !(d.has_map[lo.cp] and d.upper[lo.cp].len == 1 and d.upper[lo.cp].cp == cp)) or
            (d.gc[i] == .ll and !(d.has_map[up.cp] and d.lower[up.cp].len == 1 and d.lower[up.cp].cp == cp));
        if (clear) d.both[i] = false;
    }
}

/// 性質の 1 バイト：0x80 英字（L*）、0x40 Nd、0x20 10進数字の値がある、下位 4 ビットはその値
fn propByte(d: *const Data, cp: usize) u8 {
    var b: u8 = 0;
    switch (d.gc[cp]) {
        .lu, .ll, .lt, .lm, .lo => b |= 0x80,
        .nd => b |= 0x40,
        .other => {},
    }
    if (d.decimal[cp] >= 0) b |= 0x20 | @as(u8, @intCast(d.decimal[cp]));
    return b;
}

fn writeArray(w: *Io.Writer, comptime T: type, name: []const u8, doc: []const u8, items: []const T, per_line: usize) !void {
    try w.print("/// {s}\npub const {s} = [{d}]{s}{{\n", .{ doc, name, items.len, @typeName(T) });
    for (items, 0..) |x, i| {
        if (i % per_line == 0) try w.writeAll("   ");
        try w.print(" {d},", .{x});
        if (i % per_line == per_line - 1 or i == items.len - 1) try w.writeByte('\n');
    }
    try w.writeAll("};\n\n");
}

fn generate(a: std.mem.Allocator, w: *Io.Writer, unicode_data: []const u8, special_casing: []const u8) !void {
    var d = try Data.init(a);
    try readSpecialCasing(&d, special_casing);
    try readUnicodeData(&d, unicode_data);
    secondPass(&d);

    // 性質の 2 段の表（256 文字のページ。同じ中身のページは 1 つにまとめる）
    var prop_index: std.ArrayList(u8) = .empty;
    var prop_pages: std.ArrayList(u8) = .empty;
    var page: [256]u8 = undefined;
    var p: usize = 0;
    while (p < n_cp) : (p += 256) {
        for (0..256) |j| page[j] = propByte(&d, p + j);
        var found: ?usize = null;
        var k: usize = 0;
        while (k * 256 < prop_pages.items.len) : (k += 1) {
            if (std.mem.eql(u8, prop_pages.items[k * 256 ..][0..256], &page)) {
                found = k;
                break;
            }
        }
        const idx = found orelse blk: {
            try prop_pages.appendSlice(a, &page);
            break :blk prop_pages.items.len / 256 - 1;
        };
        if (idx > 255) return error.TooManyPages;
        try prop_index.append(a, @intCast(idx));
    }

    // 大文字・小文字の表（64 文字のページ。項目のないページは 255）
    var n_entries: usize = 0;
    var last_page: usize = 0;
    const entry = try a.alloc(bool, n_cp);
    @memset(entry, false);
    for (0..n_cp) |i| {
        if (!d.has_map[i]) continue;
        const up = d.upper[i];
        const lo = d.lower[i];
        if (up.len != 1 or lo.len != 1 or !d.both[up.cp] or !d.both[lo.cp]) continue;
        // CLHS 13.1.4.3：大文字でも小文字でもない文字は入れない（SBCL 2.6.7 との違い）
        if (up.cp != i and lo.cp != i) continue;
        entry[i] = true;
        n_entries += 1;
        last_page = i >> 6;
    }
    var case_index: std.ArrayList(u8) = .empty;
    var case_lower: std.ArrayList(u32) = .empty;
    var case_upper: std.ArrayList(u32) = .empty;
    for (0..last_page + 1) |pg| {
        var any = false;
        for (0..64) |j| any = any or entry[pg * 64 + j];
        if (!any) {
            try case_index.append(a, 255);
            continue;
        }
        const idx = case_lower.items.len / 64;
        if (idx >= 255) return error.TooManyPages;
        try case_index.append(a, @intCast(idx));
        for (0..64) |j| {
            const c = pg * 64 + j;
            try case_lower.append(a, if (entry[c]) d.lower[c].cp else 0);
            try case_upper.append(a, if (entry[c]) d.upper[c].cp else 0);
        }
    }

    try w.writeAll(
        \\//! 生成したファイル（手で編集しない）。tools/gen_unicode/main.zig が data/unicode/ の UCD から作る：
        \\//!   zig build gen-unicode
        \\//! UCD のファイルは Unicode License v3（data/unicode/LICENSE.txt）。表の作り方は tools/gen_unicode/main.zig を参照。
        \\
        \\pub const unicode_version = "15.0.0";
        \\
        \\
    );
    try w.print("/// 大文字・小文字のある文字の数\npub const case_entries = {d};\n\n", .{n_entries});
    try writeArray(w, u8, "prop_index", "性質の表の上段：prop_index[cp >> 8] がページの番号", prop_index.items, 32);
    try writeArray(w, u8, "prop_pages", "性質の表の下段：prop_pages[ページ * 256 + (cp & 0xFF)]。0x80 英字（一般カテゴリ L*）、0x40 Nd、0x20 10進数字の値がある、下位 4 ビットはその値", prop_pages.items, 32);
    try writeArray(w, u8, "case_index", "大文字・小文字の表の上段：case_index[cp >> 6] がページの番号（255 は項目なし。範囲の外も項目なし）", case_index.items, 32);
    try writeArray(w, u32, "case_lower", "大文字・小文字の表の下段：小文字の符号（0 は項目なし）", case_lower.items, 16);
    try writeArray(w, u32, "case_upper", "大文字・小文字の表の下段：大文字の符号（0 は項目なし）", case_upper.items, 16);
}

pub fn main(init: std.process.Init) !u8 {
    const arena = init.arena.allocator();
    const io = init.io;
    const args = try init.minimal.args.toSlice(arena);

    var err_buf: [1024]u8 = undefined;
    var err_fw: Io.File.Writer = .init(.stderr(), io, &err_buf);
    const stderr = &err_fw.interface;
    defer stderr.flush() catch {};

    const check = args.len == 5 and std.mem.eql(u8, args[4], "--check");
    if (args.len != 4 and !check) {
        try stderr.writeAll("usage: gen-unicode <UnicodeData.txt> <SpecialCasing.txt> <out.zig> [--check]\n");
        return 2;
    }
    const cwd = Io.Dir.cwd();
    const ud = try cwd.readFileAlloc(io, args[1], arena, .limited(16 * 1024 * 1024));
    const sc = try cwd.readFileAlloc(io, args[2], arena, .limited(1024 * 1024));
    var raw: Io.Writer.Allocating = .init(arena);
    try generate(arena, &raw.writer, ud, sc);
    // zig fmt と同じ形に整える（zig fmt --check を通すため）
    const src = try arena.dupeSentinel(u8, raw.written(), 0);
    const tree = try std.zig.Ast.parse(arena, src, .{});
    if (tree.errors.len != 0) return error.GeneratedSourceDoesNotParse;
    const formatted = try tree.renderAlloc(arena);
    if (check) {
        const now = cwd.readFileAlloc(io, args[3], arena, .limited(16 * 1024 * 1024)) catch |err| {
            try stderr.print("gen-unicode: {s} を読めません（{s}）。zig build gen-unicode で作ってください\n", .{ args[3], @errorName(err) });
            return 1;
        };
        // チェックアウトの改行が CRLF でも同じとみなす
        var lf: std.ArrayList(u8) = .empty;
        for (now) |c| if (c != '\r') try lf.append(arena, c);
        if (!std.mem.eql(u8, lf.items, formatted)) {
            try stderr.print("gen-unicode: {s} が data/unicode/ の UCD から作った表と違います。zig build gen-unicode で作り直してください\n", .{args[3]});
            return 1;
        }
        return 0;
    }
    try cwd.writeFile(io, .{ .sub_path = args[3], .data = formatted });
    return 0;
}
