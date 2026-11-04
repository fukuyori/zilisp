//! format（Phase 24。CLHS 22.3「Formatted Output」）。SBCL 2.6.7 の src/code/target-format.lisp・format.lisp・
//! print.lisp（flonum-to-string・%flonum-to-digits。どれも public domain）と同じ動作になるように、Zig で書いた。
//!   - 制御文字列を指示子の並びに分け（tokenize・combine-directives と同じ。~ と改行・~%・~~・~| は文字にする）、
//!     その並びを解釈する。~^ は Zig のエラー（Up・UpUp）で外側の ~{ ~<・format へ抜ける（SBCL の catch と同じ）。
//!   - 出力はいったん Out のバッファに溜め、format の終わりと、ユーザーの関数（~/名前/・関数の制御）を呼ぶ前に
//!     ストリームに書く。~T のため、桁（column）を数える。
//!   - ~F ~E ~G ~$ の桁は、SBCL の flonum-to-string を移植したもの（Burger と Dybvig の方法。多倍長整数で正確に丸める）。
//!   - pretty printer（P24d）：~<…~:> は論理ブロック（引数を pprint-pop と同じに取り出す）、~_ ~I ~:T と pretty stream の上の ~T は
//!     条件付きの改行・字下げ・タブ。*print-pretty* が真なら、オブジェクトはストリームに pretty printer で書く。

const std = @import("std");
const Value = @import("../values/value.zig").Value;
const Thread = @import("../runtime/thread.zig").Thread;
const Runtime = @import("../runtime/runtime.zig").Runtime;
const printer = @import("../printer/printer.zig");
const streams = @import("streams.zig");
const numbers = @import("numbers.zig");
const arrays = @import("arrays.zig");
const unicode = @import("../unicode/unicode.zig");
const Big = std.math.big.int.Managed;
const pretty = @import("../printer/pretty.zig");
const pprint = @import("../printer/pprint.zig");
const Allocator = std.mem.Allocator;

/// Lisp：エラーを記録した（Value.unwind を返す）。Up・UpUp：~^・~:^ で抜ける
const Fail = error{ Lisp, Up, UpUp };

const Param = union(enum) { none, int: i64, char: u21, arg, remaining };

const Dir = struct {
    ch: u21,
    params: []const Param,
    colon: bool,
    at: bool,
    /// 制御文字列の中の位置（~ の位置と、指示子の次の位置）
    start: usize,
    end: usize,
    /// ~/名前/ の名前
    fname: []const u21 = &.{},
};

const Tok = union(enum) { text: []const u21, dir: Dir };

const Args = struct {
    items: []const Value,
    pos: usize = 0,
    /// items を持つ Lisp のベクタ（GC から見えるように、Args と一緒にスタックに置く。リストの引数を写したとき）
    holder: Value = Value.nil,
    /// 論理ブロック（~<…~:>）の引数：元のリスト、まだ取り出していないリスト、pprint-pop の状態（(数 . ストリーム)）。
    /// 論理ブロックでは items を使わず、リストを先頭から必要な分だけたどる（循環するリストでも止まる）
    list: Value = Value.nil,
    tail: Value = Value.nil,
    state: ?Value = null,

    /// 位置 n に移る（~@* ~:* ~@[ の巻き戻し。SBCL の (nthcdr n orig-args)）。範囲の外なら null
    fn seek(a: *Args, n: usize) ?void {
        if (a.state != null) {
            var x = a.list;
            for (0..n) |_| {
                if (!x.isCons()) return null;
                x = Runtime.consPtr(x).cdr;
            }
            a.tail = x;
            a.pos = n;
            return;
        }
        if (n > a.items.len) return null;
        a.pos = n;
    }

    /// 位置 i の引数（i < pos）
    fn at(a: *const Args, i: usize) Value {
        if (a.state != null) {
            var x = a.list;
            for (0..i) |_| x = Runtime.consPtr(x).cdr;
            return Runtime.consPtr(x).car;
        }
        return a.items[i];
    }

    fn remaining(a: *const Args) usize {
        if (a.state != null) {
            var n: usize = 0;
            var x = a.tail;
            while (x.isCons()) : (x = Runtime.consPtr(x).cdr) n += 1;
            return n;
        }
        return a.items.len - a.pos;
    }

    /// 引数が残っていないか（SBCL の (null args)）
    fn empty(a: *const Args) bool {
        if (a.state != null) return a.tail == Value.nil;
        return a.pos >= a.items.len;
    }
};

/// 出力の溜め場所。stream があれば、溜めたものを後でそこに書く。なければ文字列として使う
const Out = struct {
    buf: std.ArrayList(u8) = .empty,
    stream: ?Value = null,
    /// バッファの先頭の桁（わからなければ null）と、行の先頭にいたか
    base_col: ?usize = 0,
    base_line_start: bool = true,
    /// stream が pretty stream：溜めずに直接書く（条件付きの改行などとの順序を保つ）
    direct: bool = false,

    /// 今の桁。direct（pretty stream に直接書いている）ならストリームに聞く（Codex P24 #7）
    fn column(o: *const Out, th: *Thread) ?usize {
        if (o.direct) return streams.columnOf(th, o.stream.?);
        if (std.mem.lastIndexOfScalar(u8, o.buf.items, '\n')) |i| return charCount(o.buf.items[i + 1 ..]);
        const b = o.base_col orelse return null;
        return b + charCount(o.buf.items);
    }

    fn atLineStart(o: *const Out, th: *Thread) bool {
        if (o.direct) return streams.atLineStart(th, o.stream.?);
        if (o.buf.items.len == 0) return o.base_line_start;
        return o.buf.items[o.buf.items.len - 1] == '\n';
    }
};

const Ctx = struct {
    th: *Thread,
    gpa: Allocator,
    arena: Allocator,
    /// エラーの datum にする制御文字列
    control: Value,
    /// ~:{ の外側の引数（~:^ が見る）
    outside: ?*Args = null,
    up_up_allowed: bool = false,

    fn fail(c: *Ctx, msg: []const u8) Fail {
        _ = c.th.signal(.simple_error, msg, c.control, Value.unbound);
        return error.Lisp;
    }

    fn oom(c: *Ctx) Fail {
        _ = c.th.outOfMemory();
        return error.Lisp;
    }

    fn write(c: *Ctx, o: *Out, bytes: []const u8) Fail!void {
        if (o.direct) {
            if (!streams.emit(c.th, o.stream.?, bytes)) return error.Lisp;
            return;
        }
        o.buf.appendSlice(c.gpa, bytes) catch return c.oom();
    }

    fn writeCp(c: *Ctx, o: *Out, cp: u21) Fail!void {
        var b: [4]u8 = undefined;
        const n = std.unicode.utf8Encode(cp, &b) catch return c.write(o, "?");
        return c.write(o, b[0..n]);
    }

    fn writeChars(c: *Ctx, o: *Out, chars: []const u21) Fail!void {
        for (chars) |cp| try c.writeCp(o, cp);
    }

    fn repeat(c: *Ctx, o: *Out, cp: u21, n: i64) Fail!void {
        var i: i64 = 0;
        while (i < n) : (i += 1) try c.writeCp(o, cp);
    }

    /// 溜めた出力をストリームに書く（ユーザーの関数を呼ぶ前と、終わりに）
    fn flush(c: *Ctx, o: *Out) Fail!void {
        const s = o.stream orelse return;
        if (o.buf.items.len > 0) {
            if (!streams.emit(c.th, s, o.buf.items)) return error.Lisp;
            o.buf.clearRetainingCapacity();
        }
        o.base_col = streams.columnOf(c.th, s);
        o.base_line_start = streams.atLineStart(c.th, s);
    }

    fn nextArg(c: *Ctx, a: *Args) Fail!Value {
        if (a.state) |stv| {
            // 論理ブロックの中：pprint-pop と同じく、*print-length*・循環・リストでない尾を確かめてから取り出す
            if (a.tail == Value.nil) return c.fail("FORMAT の引数が足りません");
            if (!(pprint.lengthCheck(c.th, a.tail, stv) catch return error.Lisp)) return error.Up;
            const v = Runtime.consPtr(a.tail).car;
            a.tail = Runtime.consPtr(a.tail).cdr;
            a.pos += 1;
            return v;
        }
        if (a.pos >= a.items.len) return c.fail("FORMAT の引数が足りません");
        const v = a.items[a.pos];
        a.pos += 1;
        return v;
    }

    /// 指示子の引数を n 個まで読む（v は次の引数、# は残りの引数の数。値が NIL なら既定値を使う）
    fn params(c: *Ctx, d: Dir, a: *Args, comptime n: usize) Fail![n]?Value {
        if (d.params.len > n) return c.fail("FORMAT の指示子の引数が多すぎます");
        var out: [n]?Value = @splat(null);
        if (n == 0) return out;
        for (d.params, 0..) |p, i| {
            out[i] = switch (p) {
                .none => null,
                .int => |x| Value.fromFixnum(x),
                .char => |ch| Value.fromChar(ch),
                .arg => blk: {
                    const v = try c.nextArg(a);
                    break :blk if (v == Value.nil) null else v;
                },
                .remaining => Value.fromFixnum(@intCast(a.remaining())),
            };
        }
        return out;
    }

    fn int(c: *Ctx, v: ?Value, default: i64) Fail!i64 {
        const x = v orelse return default;
        if (!x.isFixnum()) return c.typeError(x, "INTEGER");
        return x.asFixnum();
    }

    fn optInt(c: *Ctx, v: ?Value) Fail!?i64 {
        const x = v orelse return null;
        if (!x.isFixnum()) return c.typeError(x, "INTEGER");
        return x.asFixnum();
    }

    fn char(c: *Ctx, v: ?Value, default: u21) Fail!u21 {
        const x = v orelse return default;
        if (!x.isChar()) return c.typeError(x, "CHARACTER");
        return x.asChar();
    }

    /// type-error（SBCL 2.6.7 で type-error になる場合：リストでない ~{ の引数など）
    fn typeError(c: *Ctx, v: Value, type_name: []const u8) Fail {
        _ = c.th.typeError(v, (c.th.rt.findSymbol(c.th.rt.cl, type_name) orelse unreachable).symbol);
        return error.Lisp;
    }

    /// リストの要素（真のリストでなければ type-error）
    fn list(c: *Ctx, v: Value) Fail!ArgList {
        return (listItems(c.th.rt, v) catch return c.oom()) orelse c.typeError(v, "LIST");
    }

    /// リストの引数から Args を作る（~? ~{ の引数）
    fn listArgs(c: *Ctx, v: Value) Fail!Args {
        const l = try c.list(v);
        return .{ .items = l.items, .holder = l.holder };
    }

    fn optChar(c: *Ctx, v: ?Value) Fail!?u21 {
        const x = v orelse return null;
        if (!x.isChar()) return c.typeError(x, "CHARACTER");
        return x.asChar();
    }

    /// 今の印字の変数に従って印字した UTF-8（arena）。base があれば *print-base* をそれに、*print-radix* を NIL にする
    fn printed(c: *Ctx, v: Value, escape: ?bool, base: ?u8) Fail![]const u8 {
        if (prettyOn(c.th)) {
            // pretty printer：新しい文字列のストリームに書く（SBCL の princ-to-string と同じ）
            const th = c.th;
            const depth = th.binding_depth;
            defer th.unbindTo(depth);
            if (base) |b| {
                if (th.bind(th.rt.syms.@"*print-base*", Value.fromFixnum(b)) == Value.unwind) return error.Lisp;
                if (th.bind(th.rt.syms.@"*print-radix*", Value.nil) == Value.unwind) return error.Lisp;
            }
            const ss = streams.makeStringOutput(th) orelse return error.Lisp;
            if (!streams.printPretty(th, ss, v, escape)) return error.Lisp;
            // takeStringOutput は gpa で確保するので、arena に写して解放する
            var bytes: std.ArrayList(u8) = .empty;
            defer bytes.deinit(c.gpa);
            if (!streams.takeStringOutput(th, ss, &bytes)) return error.Lisp;
            return c.arena.dupe(u8, bytes.items) catch c.oom();
        }
        var buf: std.Io.Writer.Allocating = .init(c.arena);
        var s = printer.Settings.current(c.th.rt, escape);
        if (base) |b| {
            s.base = b;
            s.radix = false;
        }
        var bad: Value = Value.nil;
        printer.writeObject(c.th.rt, &buf.writer, v, s, &bad) catch |err| switch (err) {
            error.NotReadable => {
                _ = c.th.signal(.print_not_readable, "読み戻せる形で印字できません", bad, Value.unbound);
                return error.Lisp;
            },
            error.WriteFailed => return c.oom(),
        };
        return buf.written();
    }
};

fn prettyOn(th: *Thread) bool {
    return th.rt.symbolPtr(th.rt.syms.@"*print-pretty*").value != Value.nil;
}

/// オブジェクトを出力に書く（~A ~S ~W）。*print-pretty* が真なら、ストリームに pretty printer で書く（SBCL の princ・prin1 と同じ）
fn printObj(c: *Ctx, o: *Out, v: Value, escape: ?bool) Fail!void {
    if (prettyOn(c.th)) {
        if (o.stream) |s| {
            try c.flush(o);
            if (!streams.printPretty(c.th, s, v, escape)) return error.Lisp;
            try c.flush(o);
            return;
        }
    }
    try c.write(o, try c.printed(v, escape, null));
}

/// pretty printing を行うストリームなら、その状態（pretty stream で、*print-pretty* が真。SBCL の print-pretty-on-stream-p）
fn prettyStream(c: *Ctx, o: *Out) Fail!?*pretty.State {
    const s = o.stream orelse return null;
    const ps = streams.prettyStateOf(s) orelse return null;
    if (!prettyOn(c.th)) return null;
    try c.flush(o);
    return ps;
}

fn charCount(bytes: []const u8) usize {
    var n: usize = 0;
    for (bytes) |b| if (b & 0xC0 != 0x80) {
        n += 1;
    };
    return n;
}

fn isStringValue(v: Value) bool {
    return arrays.isStringLike(v);
}

/// Lisp の文字列の文字（arena）
fn stringChars(arena: Allocator, v: Value) error{OutOfMemory}![]u21 {
    const view = arrays.vectorView(v).?;
    const s = Runtime.stringPtr(view.data);
    const out = try arena.alloc(u21, view.len);
    for (out, 0..) |*ch, i| ch.* = s.charAt(i);
    return out;
}

/// リストの引数を写したもの（holder は items を持つ Lisp の単純ベクタ）
const ArgList = struct { items: []const Value, holder: Value };

/// リストの要素を Lisp の単純ベクタに写す。真のリストでなければ null。
/// arena に写すと GC から見えず、ユーザーの関数（~/名前/ など）が元のリストを変えると要素が回収される（Codex P24 #1）
fn listItems(rt: *Runtime, v: Value) error{OutOfMemory}!?ArgList {
    var n: usize = 0;
    var x = v;
    while (x.isCons()) : (x = Runtime.consPtr(x).cdr) n += 1;
    if (x != Value.nil) return null;
    const vec = try rt.makeVectorFromList(v, n);
    return .{ .items = Runtime.vectorPtr(vec).items(), .holder = vec };
}

// ---------------------------------------------------------------------------
// 制御文字列を指示子に分ける（SBCL の %tokenize-control-string・parse-directive・combine-directives）

fn tokenize(c: *Ctx, s: []const u21) Fail![]const Tok {
    var raw: std.ArrayList(Tok) = .empty;
    var i: usize = 0;
    while (i < s.len) {
        const next = std.mem.indexOfScalarPos(u21, s, i, '~') orelse s.len;
        if (next > i) raw.append(c.arena, .{ .text = s[i..next] }) catch return c.oom();
        if (next == s.len) break;
        const d = try parseDirective(c, s, next);
        raw.append(c.arena, .{ .dir = d }) catch return c.oom();
        i = d.end;
    }
    return combine(c, raw.items);
}

fn parseDirective(c: *Ctx, s: []const u21, start: usize) Fail!Dir {
    var posn = start + 1;
    var ps: std.ArrayList(Param) = .empty;
    var colon = false;
    var at = false;
    const getChar = struct {
        fn f(cc: *Ctx, str: []const u21, p: usize) Fail!u21 {
            if (p >= str.len) return cc.fail("FORMAT の制御文字列が指示子の途中で終わっています");
            return str[p];
        }
    }.f;
    while (true) {
        const ch = try getChar(c, s, posn);
        if ((ch >= '0' and ch <= '9') or ch == '+' or ch == '-') {
            if (colon or at) return c.fail("FORMAT の指示子の : や @ の後に引数があります");
            // parse-integer の :junk-allowed t と同じ（符号と数字）
            var p = posn;
            var neg = false;
            if (s[p] == '+' or s[p] == '-') {
                neg = s[p] == '-';
                p += 1;
            }
            const digits_start = p;
            var val: i64 = 0;
            while (p < s.len and s[p] >= '0' and s[p] <= '9') : (p += 1) {
                val = std.math.mul(i64, val, 10) catch return c.fail("FORMAT の指示子の引数が大きすぎます");
                val = std.math.add(i64, val, s[p] - '0') catch return c.fail("FORMAT の指示子の引数が大きすぎます");
            }
            if (p == digits_start) {
                ps.append(c.arena, .none) catch return c.oom();
                // 数字のない符号：parse-integer は位置を進めない
                p = posn;
            } else ps.append(c.arena, .{ .int = if (neg) -val else val }) catch return c.oom();
            posn = p;
            const c2 = try getChar(c, s, posn);
            if (c2 == ',') {} else if (c2 == ':' or c2 == '@') {
                posn -= 1;
            } else break;
        } else if (ch == 'v' or ch == 'V' or ch == '#') {
            if (colon or at) return c.fail("FORMAT の指示子の : や @ の後に引数があります");
            ps.append(c.arena, if (ch == '#') .remaining else .arg) catch return c.oom();
            posn += 1;
            const c2 = try getChar(c, s, posn);
            if (c2 == ',') {} else if (c2 == ':' or c2 == '@') {
                posn -= 1;
            } else break;
        } else if (ch == '\'') {
            if (colon or at) return c.fail("FORMAT の指示子の : や @ の後に引数があります");
            posn += 1;
            ps.append(c.arena, .{ .char = try getChar(c, s, posn) }) catch return c.oom();
            posn += 1;
            if ((try getChar(c, s, posn)) != ',') posn -= 1;
        } else if (ch == ',') {
            if (colon or at) return c.fail("FORMAT の指示子の : や @ の後に引数があります");
            ps.append(c.arena, .none) catch return c.oom();
        } else if (ch == ':') {
            if (colon) return c.fail("FORMAT の指示子に : が多すぎます");
            colon = true;
        } else if (ch == '@') {
            if (at) return c.fail("FORMAT の指示子に @ が多すぎます");
            at = true;
        } else {
            if (s[posn - 1] == ',' and (posn < 2 or s[posn - 2] != '\'')) {
                if (colon or at) return c.fail("FORMAT の指示子の : や @ の後に引数があります");
                ps.append(c.arena, .none) catch return c.oom();
            }
            break;
        }
        posn += 1;
    }
    const ch = try getChar(c, s, posn);
    var fname: []const u21 = &.{};
    if (ch == '/') {
        const close = std.mem.indexOfScalarPos(u21, s, posn + 1, '/') orelse return c.fail("FORMAT の ~/ に閉じる / がありません");
        fname = s[posn + 1 .. close];
        posn = close;
    }
    return .{ .ch = if (ch < 0x80) std.ascii.toUpper(@intCast(ch)) else ch, .params = ps.items, .colon = colon, .at = at, .start = start, .end = posn + 1, .fname = fname };
}

fn combine(c: *Ctx, raw: []const Tok) Fail![]const Tok {
    var out: std.ArrayList(Tok) = .empty;
    var i: usize = 0;
    while (i < raw.len) : (i += 1) {
        switch (raw[i]) {
            .text => |t| try emitText(c, &out, t),
            .dir => |d| {
                switch (d.ch) {
                    '\n' => if (d.params.len == 0 and !(d.colon and d.at)) {
                        // ~ と改行：@ は改行を残し、: でなければ続く空白を読み飛ばす
                        var s: std.ArrayList(u21) = .empty;
                        if (d.at) s.append(c.arena, '\n') catch return c.oom();
                        if (!d.colon and i + 1 < raw.len and raw[i + 1] == .text) {
                            const t = raw[i + 1].text;
                            var k: usize = 0;
                            while (k < t.len and (t[k] == ' ' or t[k] == '\t' or t[k] == '\n')) k += 1;
                            s.appendSlice(c.arena, t[k..]) catch return c.oom();
                            i += 1;
                        }
                        if (s.items.len > 0 or placeholder(out.items)) try emitText(c, &out, s.items);
                        continue;
                    },
                    '%', '~', '|' => {
                        const n: ?i64 = if (d.params.len == 0) 1 else if (d.params.len == 1 and d.params[0] == .int) d.params[0].int else if (d.params.len == 1 and d.params[0] == .none) 1 else null;
                        if (!(d.colon or d.at) and n != null and n.? >= 0 and n.? < 128) {
                            if (n.? > 0 or placeholder(out.items)) {
                                const chars = c.arena.alloc(u21, @intCast(n.?)) catch return c.oom();
                                @memset(chars, switch (d.ch) {
                                    '%' => '\n',
                                    '|' => 0x0C,
                                    else => '~',
                                });
                                try emitText(c, &out, chars);
                            }
                            continue;
                        }
                    },
                    else => {},
                }
                // 空の文字列の後ろの指示子は、その場所を使う（~} は除く）
                if (out.items.len > 0 and out.items[out.items.len - 1] == .text and out.items[out.items.len - 1].text.len == 0 and d.ch != '}') {
                    out.items[out.items.len - 1] = .{ .dir = d };
                } else out.append(c.arena, .{ .dir = d }) catch return c.oom();
            },
        }
    }
    return out.items;
}

fn placeholder(out: []const Tok) bool {
    return out.len > 0 and out[out.len - 1] == .dir and out[out.len - 1].dir.ch == '{';
}

fn emitText(c: *Ctx, out: *std.ArrayList(Tok), t: []const u21) Fail!void {
    if (out.items.len > 0 and out.items[out.items.len - 1] == .text) {
        const prev = out.items[out.items.len - 1].text;
        const joined = c.arena.alloc(u21, prev.len + t.len) catch return c.oom();
        @memcpy(joined[0..prev.len], prev);
        @memcpy(joined[prev.len..], t);
        out.items[out.items.len - 1] = .{ .text = joined };
        return;
    }
    out.append(c.arena, .{ .text = t }) catch return c.oom();
}

/// 対応する閉じの指示子（入れ子の ( < [ { を飛ばす）。stop_at_semi なら ~; でも止まる（SBCL の find-directive）
fn findDirective(toks: []const Tok, kind: u21, stop_at_semi: bool) ?usize {
    var i: usize = 0;
    while (i < toks.len) {
        switch (toks[i]) {
            .text => i += 1,
            .dir => |d| {
                if (d.ch == kind or (stop_at_semi and d.ch == ';')) return i;
                const close: ?u21 = switch (d.ch) {
                    '(' => ')',
                    '<' => '>',
                    '[' => ']',
                    '{' => '}',
                    else => null,
                };
                if (close) |cl| {
                    const j = findDirective(toks[i + 1 ..], cl, false) orelse return null;
                    i += j + 2;
                } else i += 1;
            },
        }
    }
    return null;
}

// ---------------------------------------------------------------------------
// 解釈

fn interpret(c: *Ctx, o: *Out, toks: []const Tok, a: *Args) Fail!void {
    var i: usize = 0;
    while (i < toks.len) {
        switch (toks[i]) {
            .text => |t| {
                try c.writeChars(o, t);
                i += 1;
            },
            .dir => |d| i = try directive(c, o, d, toks, i, a),
        }
    }
}

/// 1つの指示子を解釈して、次の位置を返す
fn directive(c: *Ctx, o: *Out, d: Dir, toks: []const Tok, i: usize, a: *Args) Fail!usize {
    switch (d.ch) {
        'A', 'S' => try dirAS(c, o, d, a),
        'C' => try dirC(c, o, d, a),
        'W' => {
            _ = try c.params(d, a, 0);
            const th = c.th;
            const depth = th.binding_depth;
            defer th.unbindTo(depth);
            if (d.colon and th.bind(th.rt.syms.@"*print-pretty*", th.rt.t) == Value.unwind) return error.Lisp;
            if (d.at) {
                if (th.bind(th.rt.syms.@"*print-level*", Value.nil) == Value.unwind) return error.Lisp;
                if (th.bind(th.rt.syms.@"*print-length*", Value.nil) == Value.unwind) return error.Lisp;
            }
            try printObj(c, o, try c.nextArg(a), null);
        },
        'D' => try dirInteger(c, o, d, a, 10),
        'B' => try dirInteger(c, o, d, a, 2),
        'O' => try dirInteger(c, o, d, a, 8),
        'X' => try dirInteger(c, o, d, a, 16),
        'R' => try dirR(c, o, d, a),
        'P' => try dirP(c, o, d, a),
        'F' => {
            if (d.colon) return c.fail("FORMAT の ~F に : は使えません");
            const p = try c.params(d, a, 5);
            try formatFixed(c, o, try c.nextArg(a), try c.optInt(p[0]), try c.optInt(p[1]), try c.optInt(p[2]), try c.optChar(p[3]), try c.char(p[4], ' '), d.at);
        },
        'E' => {
            if (d.colon) return c.fail("FORMAT の ~E に : は使えません");
            const p = try c.params(d, a, 7);
            try formatExponential(c, o, try c.nextArg(a), try c.optInt(p[0]), try c.optInt(p[1]), try c.optInt(p[2]), try c.int(p[3], 1), try c.optChar(p[4]), try c.char(p[5], ' '), try c.optChar(p[6]), d.at);
        },
        'G' => {
            if (d.colon) return c.fail("FORMAT の ~G に : は使えません");
            const p = try c.params(d, a, 7);
            try formatGeneral(c, o, try c.nextArg(a), try c.optInt(p[0]), try c.optInt(p[1]), try c.optInt(p[2]), try c.optInt(p[3]), try c.optChar(p[4]), try c.char(p[5], ' '), try c.optChar(p[6]), d.at);
        },
        '$' => {
            const p = try c.params(d, a, 4);
            try formatDollars(c, o, try c.nextArg(a), try c.int(p[0], 2), try c.int(p[1], 1), try c.int(p[2], 0), try c.char(p[3], ' '), d.colon, d.at);
        },
        '%', '&', '|', '~' => {
            if (d.colon or d.at) return c.fail("FORMAT のこの指示子に : や @ は使えません");
            const p = try c.params(d, a, 1);
            const n = try c.int(p[0], 1);
            switch (d.ch) {
                '%' => try c.repeat(o, '\n', n),
                '|' => try c.repeat(o, 0x0C, n),
                '~' => try c.repeat(o, '~', n),
                else => if (n > 0) {
                    if (!o.atLineStart(c.th)) try c.write(o, "\n");
                    try c.repeat(o, '\n', n - 1);
                },
            }
        },
        '\n' => {
            if (d.colon and d.at) return c.fail("FORMAT の ~ と改行に : と @ の両方は使えません");
            _ = try c.params(d, a, 0);
        },
        'T' => try dirT(c, o, d, a),
        '_' => {
            // 条件付きの改行（~_ linear、~:_ fill、~@_ miser、~:@_ mandatory）。pretty printing のストリームでなければ何もしない
            _ = try c.params(d, a, 0);
            if (try prettyStream(c, o)) |ps| ps.enqueueNewline(if (d.colon) (if (d.at) .mandatory else .fill) else (if (d.at) .miser else .linear)) catch return error.Lisp;
        },
        'I' => {
            if (d.at) return c.fail("FORMAT の ~I に @ は使えません");
            const p = try c.params(d, a, 1);
            const n = try c.int(p[0], 0);
            if (try prettyStream(c, o)) |ps| ps.enqueueIndent(if (d.colon) .current else .block, n) catch return error.Lisp;
        },
        '*' => try dirStar(c, d, a),
        '?' => {
            if (d.colon) return c.fail("FORMAT の ~? に : は使えません");
            _ = try c.params(d, a, 0);
            const ctl = try c.nextArg(a);
            if (d.at) {
                try formatControl(c, o, ctl, a);
            } else {
                var sub: Args = try c.listArgs(try c.nextArg(a));
                try formatControl(c, o, ctl, &sub);
            }
        },
        '(' => return dirCase(c, o, d, toks, i, a),
        '[' => return dirConditional(c, o, d, toks, i, a),
        '{' => return dirIterate(c, o, d, toks, i, a),
        '<' => return dirJustify(c, o, d, toks, i, a),
        '^' => try dirUp(c, d, a),
        '/' => try dirCall(c, o, d, a),
        ')' => return c.fail("FORMAT の ~) に対応する ~( がありません"),
        ']' => return c.fail("FORMAT の ~] に対応する ~[ がありません"),
        '}' => return c.fail("FORMAT の ~} に対応する ~{ がありません"),
        '>' => return c.fail("FORMAT の ~> に対応する ~< がありません"),
        ';' => return c.fail("FORMAT の ~; が ~[…~] や ~<…~> の中にありません"),
        else => return c.fail("FORMAT の指示子が正しくありません"),
    }
    return i + 1;
}

/// 欄に書く（SBCL の format-write-field）
fn writeField(c: *Ctx, o: *Out, str: []const u8, mincol: i64, colinc: i64, minpad: i64, padchar: u21, padleft: bool) Fail!void {
    if (colinc <= 0) return c.fail("FORMAT の colinc は正の整数です");
    if (mincol < 0) return c.fail("FORMAT の mincol は負でない整数です");
    if (!padleft) try c.write(o, str);
    try c.repeat(o, padchar, minpad);
    var chars: i64 = @as(i64, @intCast(charCount(str))) + @max(minpad, 0);
    while (chars < mincol) : (chars += colinc) try c.repeat(o, padchar, colinc);
    if (padleft) try c.write(o, str);
}

fn dirAS(c: *Ctx, o: *Out, d: Dir, a: *Args) Fail!void {
    const escape = d.ch == 'S';
    if (d.params.len > 0) {
        const p = try c.params(d, a, 4);
        const arg = try c.nextArg(a);
        const s = if (arg != Value.nil or !d.colon) try c.printed(arg, escape, null) else "()";
        return writeField(c, o, s, try c.int(p[0], 0), try c.int(p[1], 1), try c.int(p[2], 0), try c.char(p[3], ' '), d.at);
    }
    const arg = try c.nextArg(a);
    if (d.colon and arg == Value.nil) return c.write(o, "()");
    try printObj(c, o, arg, escape);
}

/// 名前のある文字の名前（SBCL 2.6.7 の char-name と同じ。ASCII の制御文字）
fn charName(cp: u21) ?[]const u8 {
    const names = [_][]const u8{ "Nul", "Soh", "Stx", "Etx", "Eot", "Enq", "Ack", "Bel", "Backspace", "Tab", "Newline", "Vt", "Page", "Return", "So", "Si", "Dle", "Dc1", "Dc2", "Dc3", "Dc4", "Nak", "Syn", "Etb", "Can", "Em", "Sub", "Esc", "Fs", "Gs", "Rs", "Us" };
    if (cp < 32) return names[cp];
    if (cp == ' ') return "Space";
    if (cp == 0x7F) return "Rubout";
    return null;
}

fn isGraphic(cp: u21) bool {
    return cp >= 0x20 and cp != 0x7F and !(cp >= 0x80 and cp < 0xA0);
}

fn dirC(c: *Ctx, o: *Out, d: Dir, a: *Args) Fail!void {
    _ = try c.params(d, a, 0);
    const arg = try c.nextArg(a);
    if (!arg.isChar()) return c.fail("FORMAT の ~C の引数は文字です");
    const cp = arg.asChar();
    if (d.colon) {
        // 印字される文字（空白でない図形文字）はそのまま、ほかは名前（string-capitalize した char-name）
        if (cp != ' ' and isGraphic(cp)) return c.writeCp(o, cp);
        if (charName(cp)) |n| return c.write(o, n);
        var buf: [16]u8 = undefined;
        return c.write(o, std.fmt.bufPrint(&buf, "U+{X}", .{cp}) catch unreachable);
    }
    if (d.at) return c.write(o, try c.printed(arg, true, null));
    try c.writeCp(o, cp);
}

/// ~D ~B ~O ~X（SBCL の format-print-integer）
fn dirInteger(c: *Ctx, o: *Out, d: Dir, a: *Args, base: u8) Fail!void {
    if (!(d.colon or d.at or d.params.len > 0)) return c.write(o, try c.printed(try c.nextArg(a), false, base));
    const p = try c.params(d, a, 4);
    try printInteger(c, o, try c.nextArg(a), d.colon, d.at, base, try c.int(p[0], 0), try c.char(p[1], ' '), try c.char(p[2], ','), try c.int(p[3], 3));
}

fn isInteger(v: Value) bool {
    return v.isFixnum() or (v.isOther() and Runtime.kindOf(v) == .bignum);
}

fn printInteger(c: *Ctx, o: *Out, v: Value, commas: bool, sign: bool, base: u8, mincol: i64, padchar: u21, commachar: u21, interval: i64) Fail!void {
    if (!isInteger(v)) return c.write(o, try c.printed(v, false, base));
    const text = try c.printed(v, false, base);
    const neg = text.len > 0 and text[0] == '-';
    const digits = if (neg) text[1..] else text;
    var buf: std.ArrayList(u8) = .empty;
    if (neg) buf.append(c.arena, '-') catch return c.oom() else if (sign) buf.append(c.arena, '+') catch return c.oom();
    if (commas) {
        if (interval <= 0) return c.typeError(Value.fromFixnum(interval), "INTEGER");
        const iv: usize = @intCast(interval);
        const first = (digits.len - 1) % iv + 1;
        buf.appendSlice(c.arena, digits[0..first]) catch return c.oom();
        var k = first;
        while (k < digits.len) : (k += iv) {
            var cb: [4]u8 = undefined;
            const n = std.unicode.utf8Encode(commachar, &cb) catch 0;
            buf.appendSlice(c.arena, cb[0..n]) catch return c.oom();
            buf.appendSlice(c.arena, digits[k .. k + iv]) catch return c.oom();
        }
    } else buf.appendSlice(c.arena, digits) catch return c.oom();
    try writeField(c, o, buf.items, mincol, 1, 0, padchar, true);
}

fn dirR(c: *Ctx, o: *Out, d: Dir, a: *Args) Fail!void {
    const p = try c.params(d, a, 5);
    const arg = try c.nextArg(a);
    if (p[0]) |b| {
        if (!b.isFixnum() or b.asFixnum() < 2 or b.asFixnum() > 36) return c.fail("FORMAT の ~R の基数は 2〜36 の整数です");
        return printInteger(c, o, arg, d.colon, d.at, @intCast(b.asFixnum()), try c.int(p[1], 0), try c.char(p[2], ' '), try c.char(p[3], ','), try c.int(p[4], 3));
    }
    if (!isInteger(arg)) return c.fail("FORMAT の ~R の引数は整数です");
    const text = try c.printed(arg, false, 10);
    if (d.at) {
        const max: i64 = if (d.colon) 5000 else 4000;
        if (!arg.isFixnum() or arg.asFixnum() <= 0 or arg.asFixnum() >= max) return c.fail("ローマ数字で書けない数です");
        return roman(c, o, @intCast(arg.asFixnum()), !d.colon);
    }
    if (d.colon) return ordinal(c, o, text);
    return cardinal(c, o, text);
}

const ones = [_][]const u8{ "", "one", "two", "three", "four", "five", "six", "seven", "eight", "nine" };
const teens = [_][]const u8{ "ten", "eleven", "twelve", "thirteen", "fourteen", "fifteen", "sixteen", "seventeen", "eighteen", "nineteen" };
const tens = [_][]const u8{ "", "", "twenty", "thirty", "forty", "fifty", "sixty", "seventy", "eighty", "ninety" };
const periods = [_][]const u8{ "", " thousand", " million", " billion", " trillion", " quadrillion", " quintillion", " sextillion", " septillion", " octillion", " nonillion", " decillion", " undecillion", " duodecillion", " tredecillion", " quattuordecillion", " quindecillion", " sexdecillion", " septendecillion", " octodecillion", " novemdecillion", " vigintillion" };

fn smallCardinal(c: *Ctx, o: *Out, n: usize) Fail!void {
    const hundreds = n / 100;
    const rem = n % 100;
    if (hundreds > 0) {
        try c.write(o, ones[hundreds]);
        try c.write(o, " hundred");
        if (rem > 0) try c.write(o, " ");
    }
    if (rem > 0) {
        const t = rem / 10;
        const u = rem % 10;
        if (t > 1) {
            try c.write(o, tens[t]);
            if (u > 0) {
                try c.write(o, "-");
                try c.write(o, ones[u]);
            }
        } else if (t == 1) {
            try c.write(o, teens[u]);
        } else if (u > 0) try c.write(o, ones[u]);
    }
}

/// 10 進の数字の文字列（符号なし）の [0, len) を 3 桁ずつの値にする
fn groupValue(digits: []const u8, end: usize) usize {
    const start = if (end >= 3) end - 3 else 0;
    var v: usize = 0;
    for (digits[start..end]) |ch| v = v * 10 + (ch - '0');
    return v;
}

/// 基数（英語。SBCL の format-print-cardinal）
fn cardinal(c: *Ctx, o: *Out, text: []const u8) Fail!void {
    const neg = text[0] == '-';
    const digits = if (neg) text[1..] else text;
    if (digits.len == 1 and digits[0] == '0') return c.write(o, "zero");
    if (neg) try c.write(o, "negative ");
    return cardinalAux(c, o, digits);
}

fn cardinalAux(c: *Ctx, o: *Out, digits: []const u8) Fail!void {
    const groups = (digits.len + 2) / 3;
    if (groups > periods.len) return c.fail("英語で書くには大きすぎる数です");
    var first = true;
    var g = groups;
    while (g > 0) {
        g -= 1;
        const end = digits.len - g * 3;
        const v = groupValue(digits, end);
        if (v == 0) continue;
        if (!first) try c.write(o, " ");
        first = false;
        try smallCardinal(c, o, v);
        try c.write(o, periods[g]);
    }
}

/// 序数（英語。SBCL の format-print-ordinal）
fn ordinal(c: *Ctx, o: *Out, text: []const u8) Fail!void {
    const ord_ones = [_][]const u8{ "", "first", "second", "third", "fourth", "fifth", "sixth", "seventh", "eighth", "ninth" };
    const ord_tens = [_][]const u8{ "", "tenth", "twentieth", "thirtieth", "fortieth", "fiftieth", "sixtieth", "seventieth", "eightieth", "ninetieth" };
    const neg = text[0] == '-';
    const digits = if (neg) text[1..] else text;
    if (neg) try c.write(o, "negative ");
    // top = 100 以上の部分、bot = 下 2 桁
    const bot: usize = groupValue(digits, digits.len) % 100;
    const top_digits = if (digits.len > 2) digits[0 .. digits.len - 2] else "";
    const has_top = blk: {
        for (top_digits) |ch| if (ch != '0') break :blk true;
        break :blk false;
    };
    if (has_top) {
        // number - bot（下 2 桁を 0 にした数）の基数
        const t = c.arena.alloc(u8, digits.len) catch return c.oom();
        @memcpy(t, digits);
        t[t.len - 1] = '0';
        t[t.len - 2] = '0';
        try cardinalAux(c, o, t);
    }
    if (has_top and bot > 0) try c.write(o, " ");
    const t10 = bot / 10;
    const u = bot % 10;
    if (bot == 12) {
        try c.write(o, "twelfth");
    } else if (t10 == 1) {
        try c.write(o, teens[u]);
        try c.write(o, "th");
    } else if (t10 == 0 and u > 0) {
        try c.write(o, ord_ones[u]);
    } else if (u == 0 and t10 > 0) {
        try c.write(o, ord_tens[t10]);
    } else if (bot > 0) {
        try c.write(o, tens[t10]);
        try c.write(o, "-");
        try c.write(o, ord_ones[u]);
    } else if (has_top) {
        try c.write(o, "th");
    } else try c.write(o, "zeroth");
}

fn roman(c: *Ctx, o: *Out, n0: usize, new_style: bool) Fail!void {
    const chars = [_]u8{ 'M', 'D', 'C', 'L', 'X', 'V', 'I' };
    const vals = [_]usize{ 1000, 500, 100, 50, 10, 5, 1 };
    const sub_chars = [_]u8{ 'C', 'C', 'X', 'X', 'I', 'I', 0 };
    const sub_vals = [_]usize{ 100, 100, 10, 10, 1, 1, 0 };
    var n = n0;
    for (chars, 0..) |ch, k| {
        while (n >= vals[k]) {
            try c.write(o, &.{ch});
            n -= vals[k];
        }
        if (new_style and sub_vals[k] != 0 and n >= vals[k] - sub_vals[k]) {
            try c.write(o, &.{ sub_chars[k], ch });
            n -= vals[k] - sub_vals[k];
        }
    }
}

fn dirP(c: *Ctx, o: *Out, d: Dir, a: *Args) Fail!void {
    _ = try c.params(d, a, 0);
    const arg = if (d.colon) blk: {
        if (a.pos == 0) return c.fail("FORMAT の ~:P の前の引数がありません");
        break :blk a.at(a.pos - 1);
    } else try c.nextArg(a);
    const one = arg == Value.fromFixnum(1);
    if (d.at) return c.write(o, if (one) "y" else "ies");
    if (!one) try c.write(o, "s");
}

fn dirT(c: *Ctx, o: *Out, d: Dir, a: *Args) Fail!void {
    const p = try c.params(d, a, 2);
    if (d.colon) {
        // ~:T・~:@T は pprint-tab の :section・:section-relative（pretty printing のストリームでなければ何もしない）
        if (try prettyStream(c, o)) |ps| ps.enqueueTab(if (d.at) .section_relative else .section, try c.int(p[0], 1), try c.int(p[1], 1)) catch return error.Lisp;
        return;
    }
    // pretty stream の上では pprint-tab の :line・:line-relative（SBCL の format-absolute-tab・format-relative-tab）
    if (o.stream) |s| if (streams.prettyStateOf(s)) |ps| {
        try c.flush(o);
        ps.enqueueTab(if (d.at) .line_relative else .line, try c.int(p[0], 1), try c.int(p[1], 1)) catch return error.Lisp;
        return;
    };
    if (d.at) {
        const colrel = try c.int(p[0], 1);
        const colinc = try c.int(p[1], 1);
        const spaces = if (o.column(c.th)) |cur| blk: {
            if (colinc <= 0) break :blk colrel;
            const cu: i64 = @intCast(cur);
            break :blk @divFloor(cu + colrel + colinc - 1, colinc) * colinc - cu;
        } else colrel;
        return c.repeat(o, ' ', spaces);
    }
    const colnum = try c.int(p[0], 1);
    const colinc = try c.int(p[1], 1);
    const cur0 = o.column(c.th) orelse return c.write(o, "  ");
    const cur: i64 = @intCast(cur0);
    if (cur < colnum) return c.repeat(o, ' ', colnum - cur);
    if (colinc != 0) try c.repeat(o, ' ', colinc - @rem(cur - colnum, colinc));
}

fn dirStar(c: *Ctx, d: Dir, a: *Args) Fail!void {
    if (d.colon and d.at) return c.fail("FORMAT の ~* に : と @ の両方は使えません");
    const p = try c.params(d, a, 1);
    if (d.at) {
        const posn = try c.int(p[0], 0);
        if (posn < 0) return c.fail("FORMAT の ~@* の位置が引数の範囲の外です");
        a.seek(@intCast(posn)) orelse return c.fail("FORMAT の ~@* の位置が引数の範囲の外です");
    } else if (d.colon) {
        const n = try c.int(p[0], 1);
        const np = @as(i64, @intCast(a.pos)) - n;
        if (np < 0) return c.fail("FORMAT の ~:* の位置が引数の範囲の外です");
        a.seek(@intCast(np)) orelse return c.fail("FORMAT の ~:* の位置が引数の範囲の外です");
    } else {
        var n = try c.int(p[0], 1);
        while (n > 0) : (n -= 1) _ = try c.nextArg(a);
    }
}

/// 制御（文字列か関数）を、引数 a で解釈する（~? ~{ の中身が空のとき）
fn formatControl(c: *Ctx, o: *Out, ctl: Value, a: *Args) Fail!void {
    if (isStringValue(ctl)) {
        const chars = stringChars(c.arena, ctl) catch return c.oom();
        const saved = c.control;
        c.control = ctl;
        defer c.control = saved;
        const toks = try tokenize(c, chars);
        interpret(c, o, toks, a) catch |err| switch (err) {
            error.Up => {},
            else => return err,
        };
        return;
    }
    if (ctl.isFunctionPointer()) {
        // 関数の制御（formatter が作る）：(apply 関数 ストリーム 引数) を呼び、残りの引数を返す
        if (a.state != null) {
            // 論理ブロックの中：残りのリストを渡し、返った残りのリストから続ける
            var rest_items: std.ArrayList(Value) = .empty;
            var x = a.tail;
            while (x.isCons()) : (x = Runtime.consPtr(x).cdr) rest_items.append(c.arena, Runtime.consPtr(x).car) catch return c.oom();
            const before = rest_items.items.len;
            const rest = try callWithStream(c, o, ctl, rest_items.items, &.{});
            var n: usize = 0;
            x = rest;
            while (x.isCons()) : (x = Runtime.consPtr(x).cdr) n += 1;
            _ = a.seek(a.pos + (before - @min(n, before)));
            return;
        }
        const rest = try callWithStream(c, o, ctl, a.items[a.pos..], &.{});
        var n: usize = 0;
        var x = rest;
        while (x.isCons()) : (x = Runtime.consPtr(x).cdr) n += 1;
        // 残りの引数（rest は a.items の後ろの部分のはず）に合わせて位置を進める
        a.pos = a.items.len - @min(n, a.items.len - a.pos);
        return;
    }
    _ = c.th.typeError(ctl, (c.th.rt.findSymbol(c.th.rt.cl, "STRING") orelse unreachable).symbol);
    return error.Lisp;
}

/// 関数を (関数 ストリーム 引数…) で呼ぶ。出力先が文字列なら、文字列のストリームを渡して結果を取り込む
fn callWithStream(c: *Ctx, o: *Out, f: Value, args: []const Value, extra: []const Value) Fail!Value {
    const th = c.th;
    var argv: [64]Value = undefined;
    if (1 + args.len + extra.len > argv.len) return c.fail("FORMAT から関数に渡す引数が多すぎます");
    const s = if (o.stream) |st| blk: {
        try c.flush(o);
        break :blk st;
    } else streams.makeStringOutput(th) orelse return error.Lisp;
    argv[0] = s;
    @memcpy(argv[1 .. 1 + args.len], args);
    @memcpy(argv[1 + args.len .. 1 + args.len + extra.len], extra);
    const r = th.call(f, argv[0 .. 1 + args.len + extra.len]);
    if (r == Value.unwind) return error.Lisp;
    if (o.stream != null) {
        o.base_col = streams.columnOf(th, s);
        o.base_line_start = streams.atLineStart(th, s);
    } else if (!streams.takeStringOutput(th, s, &o.buf)) return error.Lisp;
    return r;
}

/// ~/名前/（SBCL の extract-user-fun-name：大文字にし、パッケージの指定がなければ CL-USER に intern する）
fn dirCall(c: *Ctx, o: *Out, d: Dir, a: *Args) Fail!void {
    const rt = c.th.rt;
    var name: std.ArrayList(u8) = .empty;
    for (d.fname) |cp| {
        var b: [4]u8 = undefined;
        const n = std.unicode.utf8Encode(unicode.upcase(cp), &b) catch 0;
        name.appendSlice(c.arena, b[0..n]) catch return c.oom();
    }
    const full = name.items;
    var sym_name = full;
    var pkg = rt.findPackage("COMMON-LISP-USER") orelse return c.fail("CL-USER がありません");
    if (std.mem.indexOfScalar(u8, full, ':')) |i| {
        pkg = rt.findPackage(full[0..i]) orelse return c.fail("FORMAT の ~/ のパッケージがありません");
        sym_name = if (i + 1 < full.len and full[i + 1] == ':') full[i + 2 ..] else full[i + 1 ..];
    }
    const sym = rt.intern(pkg, sym_name) catch return c.oom();
    // 関数の引数：ストリーム、対象の引数、: の有無、@ の有無、指示子の引数（v は次の引数、# は残りの数）。
    // 指示子の引数は、対象の引数より先に読む（SBCL と同じ順）
    var extra: [16]Value = undefined;
    if (d.params.len + 2 > extra.len) return c.fail("FORMAT の ~/ の引数が多すぎます");
    extra[0] = if (d.colon) rt.t else Value.nil;
    extra[1] = if (d.at) rt.t else Value.nil;
    for (d.params, 0..) |p, k| {
        extra[k + 2] = switch (p) {
            .none => Value.nil,
            .int => |x| Value.fromFixnum(x),
            .char => |ch| Value.fromChar(ch),
            .arg => try c.nextArg(a),
            .remaining => Value.fromFixnum(@intCast(a.remaining())),
        };
    }
    const arg = try c.nextArg(a);
    _ = try callWithStream(c, o, sym, &.{arg}, extra[0 .. d.params.len + 2]);
}

/// ~( ~)：中の出力の大文字・小文字を変える（SBCL の case-frob-stream と同じ結果）
fn dirCase(c: *Ctx, o: *Out, d: Dir, toks: []const Tok, i: usize, a: *Args) Fail!usize {
    const rest = toks[i + 1 ..];
    const close = findDirective(rest, ')', false) orelse return c.fail("FORMAT の ~( に対応する ~) がありません");
    _ = try c.params(d, a, 0);
    var inner: Out = .{ .base_col = o.column(c.th), .base_line_start = o.atLineStart(c.th) };
    defer inner.buf.deinit(c.gpa);
    const r = interpret(c, &inner, rest[0..close], a);
    // ~^ で抜けたときも、それまでの出力は変換して書く
    const mode: enum { down, cap, cap_first, up } = if (d.colon) (if (d.at) .up else .cap) else (if (d.at) .cap_first else .down);
    var view = std.unicode.Utf8View.initUnchecked(inner.buf.items);
    var it = view.iterator();
    var inside_word = false;
    var first_done = false;
    while (it.nextCodepoint()) |cp| {
        const out_cp = switch (mode) {
            .down => unicode.downcase(cp),
            .up => unicode.upcase(cp),
            .cap => blk: {
                if (!unicode.isAlnum(cp)) {
                    inside_word = false;
                    break :blk cp;
                }
                if (inside_word) break :blk unicode.downcase(cp);
                inside_word = true;
                break :blk unicode.upcase(cp);
            },
            .cap_first => blk: {
                if (first_done) break :blk unicode.downcase(cp);
                if (unicode.isAlnum(cp)) {
                    first_done = true;
                    break :blk unicode.upcase(cp);
                }
                break :blk cp;
            },
        };
        try c.writeCp(o, out_cp);
    }
    try r;
    return i + 1 + close + 1;
}

/// ~[ ~; ~]（SBCL の parse-conditional-directive）
fn dirConditional(c: *Ctx, o: *Out, d: Dir, toks: []const Tok, i: usize, a: *Args) Fail!usize {
    if (d.colon and d.at) return c.fail("FORMAT の ~[ に : と @ の両方は使えません");
    var sections: std.ArrayList([]const Tok) = .empty;
    var last_semi_colon = false;
    var pos = i + 1;
    while (true) {
        const rest = toks[pos..];
        const k = findDirective(rest, ']', true) orelse return c.fail("FORMAT の ~[ に対応する ~] がありません");
        sections.append(c.arena, rest[0..k]) catch return c.oom();
        const closer = rest[k].dir;
        pos += k + 1;
        if (closer.ch == ']') break;
        last_semi_colon = closer.colon;
    }
    const secs = sections.items;
    if (d.at) {
        if (secs.len != 1) return c.fail("FORMAT の ~@[ の節は1つだけです");
        _ = try c.params(d, a, 0);
        const prev = a.pos;
        const arg = try c.nextArg(a);
        if (arg != Value.nil) {
            _ = a.seek(prev);
            try interpret(c, o, secs[0], a);
        }
    } else if (d.colon) {
        if (secs.len != 2) return c.fail("FORMAT の ~:[ の節は2つです");
        _ = try c.params(d, a, 0);
        try interpret(c, o, if ((try c.nextArg(a)) != Value.nil) secs[1] else secs[0], a);
    } else {
        const p = try c.params(d, a, 1);
        const index_v = p[0] orelse try c.nextArg(a);
        if (!index_v.isFixnum() and !isInteger(index_v)) return c.fail("FORMAT の ~[ の引数は整数です");
        const n_plain = if (last_semi_colon) secs.len - 1 else secs.len;
        const chosen: ?[]const Tok = if (index_v.isFixnum() and index_v.asFixnum() >= 0 and index_v.asFixnum() < n_plain)
            secs[@intCast(index_v.asFixnum())]
        else if (last_semi_colon) secs[secs.len - 1] else null;
        if (chosen) |s| try interpret(c, o, s, a);
    }
    return pos;
}

/// ~{ ~}（SBCL の ~{ の解釈）
fn dirIterate(c: *Ctx, o: *Out, d: Dir, toks: []const Tok, i: usize, a: *Args) Fail!usize {
    const rest = toks[i + 1 ..];
    const close = findDirective(rest, '}', false) orelse return c.fail("FORMAT の ~{ に対応する ~} がありません");
    const closed_with_colon = rest[close].dir.colon;
    const p = try c.params(d, a, 1);
    var max_count = try c.optInt(p[0]);
    // 中身が空なら、制御は次の引数
    const insides_ctl: ?Value = if (close == 0) try c.nextArg(a) else null;
    const insides = rest[0..close];
    const saved_allowed = c.up_up_allowed;
    c.up_up_allowed = d.colon;
    defer c.up_up_allowed = saved_allowed;

    var list_args: Args = undefined;
    const loop_args: *Args = if (d.at) a else blk: {
        list_args = try c.listArgs(try c.nextArg(a));
        break :blk &list_args;
    };
    const guts = struct {
        fn run(cc: *Ctx, oo: *Out, ins: []const Tok, ctl: ?Value, args: *Args) Fail!void {
            if (ctl) |cv| return formatControl(cc, oo, cv, args);
            return interpret(cc, oo, ins, args);
        }
    }.run;
    loop: while (true) {
        if (!closed_with_colon and loop_args.empty()) break;
        if (max_count) |*m| {
            m.* -= 1;
            if (m.* < 0) break;
        }
        if (d.colon) {
            var sub: Args = try c.listArgs(try c.nextArg(loop_args));
            const saved_outside = c.outside;
            c.outside = loop_args;
            defer c.outside = saved_outside;
            guts(c, o, insides, insides_ctl, &sub) catch |err| switch (err) {
                error.Up => {},
                error.UpUp => break :loop,
                else => return err,
            };
        } else {
            guts(c, o, insides, insides_ctl, loop_args) catch |err| switch (err) {
                error.Up => break :loop,
                else => return err,
            };
        }
        if (closed_with_colon and loop_args.empty()) break;
    }
    return i + 1 + close + 1;
}

/// ~^（SBCL の ~^ の解釈）
fn dirUp(c: *Ctx, d: Dir, a: *Args) Fail!void {
    if (d.at) return c.fail("FORMAT の ~^ に @ は使えません");
    if (d.colon and !c.up_up_allowed) return c.fail("FORMAT の ~:^ は ~:{…~} の中だけで使えます");
    const p = try c.params(d, a, 3);
    const up = if (p[2]) |a3| blk: {
        const x = try c.int(p[0], 0);
        const y = try c.int(p[1], 0);
        break :blk x <= y and y <= try c.int(a3, 0);
    } else if (p[1]) |a2| (p[0] != null and lispEql(p[0].?, a2)) else if (p[0]) |a1| a1 == Value.fromFixnum(0) else if (d.colon) (if (c.outside) |out| out.empty() else true) else a.empty();
    if (up) return if (d.colon) error.UpUp else error.Up;
}

fn lispEql(x: Value, y: Value) bool {
    return @import("lists.zig").eql2(x, y);
}

/// ~< ~>（左右揃え。~<…~:> は pretty printer の論理ブロック：P24d）
fn dirJustify(c: *Ctx, o: *Out, d: Dir, toks: []const Tok, i: usize, a: *Args) Fail!usize {
    var segments: std.ArrayList([]const Tok) = .empty;
    var semis: std.ArrayList(Dir) = .empty;
    var pos = i + 1;
    var close: Dir = undefined;
    while (true) {
        const rest = toks[pos..];
        const k = findDirective(rest, '>', true) orelse return c.fail("FORMAT の ~< に対応する ~> がありません");
        segments.append(c.arena, rest[0..k]) catch return c.oom();
        pos += k + 1;
        if (rest[k].dir.ch == '>') {
            close = rest[k].dir;
            break;
        }
        semis.append(c.arena, rest[k].dir) catch return c.oom();
    }
    if (close.colon) {
        try dirLogicalBlock(c, o, d, segments.items, semis.items, close, a);
        return pos;
    }
    if (close.at) return c.fail("FORMAT の左右揃えの ~> に @ は使えません");
    // 左右揃えの中では使えない指示子（CLHS 22.3.5.2）
    for (segments.items) |seg| for (seg) |t| if (t == .dir) switch (t.dir.ch) {
        'W', 'I', '_' => return c.fail("FORMAT の左右揃えの中に使えない指示子があります"),
        'T' => if (t.dir.colon) return c.fail("FORMAT の左右揃えの中に使えない指示子があります"),
        else => {},
    };
    const p = try c.params(d, a, 4);
    const mincol = try c.int(p[0], 0);
    const colinc = try c.int(p[1], 1);
    const minpad = try c.int(p[2], 0);
    const padchar = try c.char(p[3], ' ');

    var newline_prefix: ?[]const u8 = null;
    var extra_space: i64 = 0;
    var line_len: i64 = 72;
    var strings: std.ArrayList([]const u8) = .empty;
    var segs: []const []const Tok = segments.items;
    const body = struct {
        fn run(cc: *Ctx, oo: *Out, dd: Dir, sgs: *[]const []const Tok, sms: []const Dir, args: *Args, nlp: *?[]const u8, extra: *i64, ll: *i64, strs: *std.ArrayList([]const u8)) Fail!void {
            _ = dd;
            if (sms.len > 0 and sms[0].colon) {
                const sp = try cc.params(sms[0], args, 2);
                extra.* = try cc.int(sp[0], 0);
                ll.* = try cc.int(sp[1], 72);
                var sub: Out = .{ .base_col = null };
                defer sub.buf.deinit(cc.gpa);
                try interpret(cc, &sub, sgs.*[0], args);
                nlp.* = cc.arena.dupe(u8, sub.buf.items) catch return cc.oom();
                sgs.* = sgs.*[1..];
            }
            for (sgs.*) |seg| {
                var sub: Out = .{ .base_col = null };
                defer sub.buf.deinit(cc.gpa);
                const r = interpret(cc, &sub, seg, args);
                if (r) {
                    strs.append(cc.arena, cc.arena.dupe(u8, sub.buf.items) catch return cc.oom()) catch return cc.oom();
                } else |err| {
                    // ~^ で抜けた節は使わない（SBCL も、その節の文字列は push しない）
                    return err;
                }
            }
            _ = oo;
        }
    }.run;
    body(c, o, d, &segs, semis.items, a, &newline_prefix, &extra_space, &line_len, &strings) catch |err| switch (err) {
        error.Up => {},
        else => return err,
    };
    try justify(c, o, newline_prefix, extra_space, line_len, strings.items, d.colon, d.at, mincol, colinc, minpad, padchar);
    return pos;
}

/// ~<…~:>：論理ブロック（SBCL の interpret-format-logical-block）。節が2つなら接頭辞と本体、3つなら接頭辞・本体・接尾辞。
/// ~@; なら行ごとの接頭辞、~:@> なら本体の文字の空白の後に ~:_ を入れる。~@< は残りの引数のすべてを1つのリストとして使う
fn dirLogicalBlock(c: *Ctx, o: *Out, d: Dir, segments: []const []const Tok, semis: []const Dir, close: Dir, a: *Args) Fail!void {
    var prefix: []const u21 = if (d.colon) &.{'('} else &.{};
    var suffix: []const u21 = if (d.colon) &.{')'} else &.{};
    var per_line = false;
    var insides: []const Tok = undefined;
    switch (segments.len) {
        1 => insides = segments[0],
        2, 3 => {
            prefix = try segmentText(c, segments[0]);
            per_line = semis[0].at;
            insides = segments[1];
            if (segments.len == 3) suffix = try segmentText(c, segments[2]);
        },
        else => return c.fail("FORMAT の ~<…~:> の節が多すぎます"),
    }
    _ = try c.params(d, a, 0);
    if (close.at) insides = try addFillStyleNewlines(c, insides);
    // 引数：~@< なら残りの引数（リストにする）、そうでなければ次の引数
    const arg: Value = if (d.at) blk: {
        if (a.state != null) {
            const t = a.tail;
            a.tail = Value.nil;
            break :blk t;
        }
        var list = Value.nil;
        var k = a.items.len;
        while (k > a.pos) {
            k -= 1;
            list = c.th.rt.cons(a.items[k], list) catch return c.oom();
        }
        a.pos = a.items.len;
        break :blk list;
    } else try c.nextArg(a);

    const Body = struct {
        c: *Ctx,
        insides: []const Tok,
        arg: Value,
        fn run(ctx: *anyopaque, th: *Thread, ps: Value, state: Value) pprint.Fail!void {
            const b: *@This() = @ptrCast(@alignCast(ctx));
            _ = th;
            var inner: Out = .{ .stream = ps, .direct = true };
            // 引数は pprint-pop と同じく、リストを先頭から1つずつ取り出す（循環するリストでも *print-circle* で止まる）
            var args: Args = .{ .items = &.{}, .list = b.arg, .tail = b.arg, .state = state };
            interpret(b.c, &inner, b.insides, &args) catch |err| switch (err) {
                error.Up => {},
                error.UpUp, error.Lisp => return error.Lisp,
            };
        }
    };
    var body: Body = .{ .c = c, .insides = insides, .arg = arg };
    const block_body: pprint.BlockBody = .{ .zig = .{ .ctx = &body, .f = Body.run } };
    if (o.stream) |s| {
        try c.flush(o);
        pprint.formatLogicalBlock(c.th, s, arg, prefix, per_line, suffix, block_body) catch return error.Lisp;
        try c.flush(o);
        return;
    }
    // 文字列に書いている（~( の中など）：文字列のストリームに書いて取り込む
    const ss = streams.makeStringOutput(c.th) orelse return error.Lisp;
    pprint.formatLogicalBlock(c.th, ss, arg, prefix, per_line, suffix, block_body) catch return error.Lisp;
    if (!streams.takeStringOutput(c.th, ss, &o.buf)) return error.Lisp;
}

/// 接頭辞・接尾辞の節（文字だけ）
fn segmentText(c: *Ctx, seg: []const Tok) Fail![]const u21 {
    if (seg.len == 0) return &.{};
    if (seg.len != 1 or seg[0] != .text) return c.fail("FORMAT の ~<…~:> の接頭辞・接尾辞に指示子は書けません");
    return seg[0].text;
}

/// 文字の空白の並びの後に ~:_ を入れる（SBCL の add-fill-style-newlines-aux。上の段の文字だけ）
fn addFillStyleNewlines(c: *Ctx, toks: []const Tok) Fail![]const Tok {
    var out: std.ArrayList(Tok) = .empty;
    const fill_nl: Tok = .{ .dir = .{ .ch = '_', .params = &.{}, .colon = true, .at = false, .start = 0, .end = 0 } };
    for (toks) |t| switch (t) {
        .dir => out.append(c.arena, t) catch return c.oom(),
        .text => |lit| {
            var posn: usize = 0;
            while (true) {
                const blank = std.mem.indexOfScalarPos(u21, lit, posn, ' ') orelse {
                    if (posn < lit.len) out.append(c.arena, .{ .text = lit[posn..] }) catch return c.oom();
                    break;
                };
                var non_blank = blank;
                while (non_blank < lit.len and lit[non_blank] == ' ') non_blank += 1;
                out.append(c.arena, .{ .text = lit[posn..non_blank] }) catch return c.oom();
                out.append(c.arena, fill_nl) catch return c.oom();
                posn = non_blank;
                if (posn == lit.len) break;
            }
        },
    };
    return out.items;
}

fn justify(c: *Ctx, o: *Out, newline_prefix: ?[]const u8, extra_space: i64, line_len: i64, strings: []const []const u8, pad_left: bool, pad_right: bool, mincol: i64, colinc: i64, minpad: i64, padchar: u21) Fail!void {
    var num_gaps: i64 = @as(i64, @intCast(strings.len)) - 1 + @as(i64, @intFromBool(pad_left)) + @as(i64, @intFromBool(pad_right));
    var chars: i64 = num_gaps * minpad;
    for (strings) |s| chars += @intCast(charCount(s));
    // colinc が 0 なら、SBCL と同じく division-by-zero（panic にしない。Codex のレビュー 0.3 #2）
    if (chars > mincol and colinc == 0) {
        _ = c.th.signal(.division_by_zero, "FORMAT の ~< の colinc が 0 です", c.control, Value.unbound);
        return error.Lisp;
    }
    const length = if (chars > mincol) mincol + @divFloor(chars - mincol + colinc - 1, colinc) * colinc else mincol;
    var padding = length - chars + num_gaps * minpad;
    if (newline_prefix) |nl| {
        const cur: i64 = @intCast(o.column(c.th) orelse 0);
        if (cur + length + extra_space > line_len) try c.write(o, nl);
    }
    const doPadding = struct {
        fn f(cc: *Ctx, oo: *Out, pad: *i64, gaps: *i64, pc: u21) Fail!void {
            const pad_len = if (gaps.* == 0) pad.* else @divTrunc(pad.*, gaps.*);
            pad.* -= pad_len;
            gaps.* -= 1;
            try cc.repeat(oo, pc, pad_len);
        }
    }.f;
    if (pad_left or (!pad_right and strings.len <= 1)) try doPadding(c, o, &padding, &num_gaps, padchar);
    if (strings.len > 0) {
        try c.write(o, strings[0]);
        for (strings[1..]) |s| {
            try doPadding(c, o, &padding, &num_gaps, padchar);
            try c.write(o, s);
        }
    }
    if (pad_right) try doPadding(c, o, &padding, &num_gaps, padchar);
}

// ---------------------------------------------------------------------------
// 浮動小数（SBCL の format-fixed-aux・format-exp-aux・format-general-aux・format-dollars・flonum-to-string）

const Flo = struct {
    x: f64,
    single: bool,

    fn isZero(f: Flo) bool {
        return f.x == 0;
    }
};

/// 数を浮動小数にする（有理数は single-float。CLHS 22.3.3）。数でなければ null
fn toFlo(c: *Ctx, v: Value) Fail!?Flo {
    if (v.isSingleFloat()) return .{ .x = v.asSingle(), .single = true };
    if (v.isOther() and Runtime.kindOf(v) == .double_float) return .{ .x = Runtime.doubleValue(v), .single = false };
    if (isInteger(v) or (v.isOther() and Runtime.kindOf(v) == .ratio)) {
        const f = numbers.toSingleFloat(c.th, v) orelse return error.Lisp;
        return .{ .x = f, .single = true };
    }
    return null;
}

fn floatSpecial(f: Flo) bool {
    return std.math.isNan(f.x) or std.math.isInf(f.x);
}

fn signBit(f: Flo) bool {
    return std.math.signbit(f.x);
}

fn formatFixed(c: *Ctx, o: *Out, v: Value, w: ?i64, d: ?i64, k: ?i64, ovf: ?u21, pad: u21, atsign: bool) Fail!void {
    const f = (try toFlo(c, v)) orelse {
        // 数でないもの：*print-base* 10 で ~A と同じ（mincol は w）
        return writeField(c, o, try c.printed(v, false, 10), w orelse 0, 1, 0, pad, false);
    };
    _ = try fixedAux(c, o, f, w, d, k, ovf, pad, atsign, v);
}

/// 欄が溢れたら真（~G が使う）
fn fixedAux(c: *Ctx, o: *Out, f: Flo, w: ?i64, d: ?i64, k: ?i64, ovf: ?u21, pad: u21, atsign: bool, v: Value) Fail!bool {
    if (floatSpecial(f)) {
        try c.write(o, try c.printed(v, true, null));
        return false;
    }
    var spaceleft = w;
    if (w != null and (atsign or signBit(f))) spaceleft.? -= 1;
    var r = try flonumToString(c, .{ .x = @abs(f.x), .single = f.single }, spaceleft, d, k, null, null);
    if (d != null and d.? == 0) r.tpoint = false;
    if (w != null) {
        spaceleft.? -= @intCast(r.str.len);
        if (r.lpoint) {
            if (spaceleft.? > 0 or r.tpoint) spaceleft.? -= 1 else r.lpoint = false;
        }
        if (r.tpoint) {
            if (spaceleft.? > 0) spaceleft.? -= 1 else r.tpoint = false;
        }
    }
    if (w != null and spaceleft.? < 0 and ovf != null) {
        try c.repeat(o, ovf.?, w.?);
        return true;
    }
    if (w != null) try c.repeat(o, pad, spaceleft.?);
    if (signBit(f)) try c.write(o, "-") else if (atsign) try c.write(o, "+");
    if (r.lpoint) try c.write(o, "0");
    try c.write(o, r.str);
    if (r.tpoint) try c.write(o, "0");
    return false;
}

fn formatExponential(c: *Ctx, o: *Out, v: Value, w: ?i64, d: ?i64, e: ?i64, k: i64, ovf: ?u21, pad: u21, marker: ?u21, atsign: bool) Fail!void {
    const f = (try toFlo(c, v)) orelse return writeField(c, o, try c.printed(v, false, 10), w orelse 0, 1, 0, pad, false);
    try expAux(c, o, f, w, d, e, k, ovf, pad, marker, atsign, v);
}

fn exponentMarker(c: *Ctx, f: Flo) u21 {
    const rt = c.th.rt;
    const fmt = rt.symbolPtr(rt.syms.@"*read-default-float-format*").value;
    const default_double = fmt == rt.syms.@"double-float" or fmt == rt.syms.@"long-float";
    if (f.single != default_double) return 'e';
    return if (f.single) 'f' else 'd';
}

fn expAux(c: *Ctx, o: *Out, f: Flo, w: ?i64, d: ?i64, e: ?i64, k: i64, ovf: ?u21, pad: u21, marker: ?u21, atsign: bool, v: Value) Fail!void {
    if (floatSpecial(f)) return c.write(o, try c.printed(v, true, null));
    const num: Flo = .{ .x = @abs(f.x), .single = f.single };
    const num_expt = try flonumExponent(c, num);
    const expt = num_expt - k;
    var ebuf: [24]u8 = undefined;
    const estr = std.fmt.bufPrint(&ebuf, "{d}", .{@abs(expt)}) catch unreachable;
    const elen: i64 = if (e) |ee| @max(@as(i64, @intCast(estr.len)), ee) else @intCast(estr.len);
    var spaceleft: ?i64 = null;
    if (w) |ww| {
        spaceleft = ww - 2 - elen;
        if (atsign or signBit(f)) spaceleft.? -= 1;
    }
    if (w != null and ovf != null and e != null and elen > e.?) return c.repeat(o, ovf.?, w.?);
    const fdig: ?i64 = if (d) |dd| (if (k > 0) dd - k + 1 else dd) else null;
    const fmin: ?i64 = if (k < 0) 1 else fdig;
    var r = try flonumToString(c, num, spaceleft, fdig, k, fmin, num_expt);
    if (fdig != null and fdig.? == 0) r.tpoint = false;
    if (w != null) {
        spaceleft.? -= @intCast(r.str.len);
        if (r.lpoint) {
            if (spaceleft.? > 0 or r.tpoint) spaceleft.? -= 1 else r.lpoint = false;
        }
        if (r.tpoint) {
            if (spaceleft.? <= 0) r.tpoint = false else spaceleft.? -= 1;
        }
    }
    if (w != null and spaceleft.? < 0 and ovf != null) return c.repeat(o, ovf.?, w.?);
    if (w != null) try c.repeat(o, pad, spaceleft.?);
    if (signBit(f)) try c.write(o, "-") else if (atsign) try c.write(o, "+");
    if (r.lpoint) try c.write(o, "0");
    try c.write(o, r.str);
    if (r.tpoint) try c.write(o, "0");
    try c.writeCp(o, marker orelse exponentMarker(c, f));
    try c.write(o, if (expt < 0) "-" else "+");
    if (e) |ee| try c.repeat(o, '0', ee - @as(i64, @intCast(estr.len)));
    try c.write(o, estr);
}

fn formatGeneral(c: *Ctx, o: *Out, v: Value, w: ?i64, d0: ?i64, e: ?i64, k: ?i64, ovf: ?u21, pad: u21, marker: ?u21, atsign: bool) Fail!void {
    const f = (try toFlo(c, v)) orelse return writeField(c, o, try c.printed(v, false, 10), w orelse 0, 1, 0, pad, false);
    if (floatSpecial(f)) return c.write(o, try c.printed(v, true, null));
    const abs: Flo = .{ .x = @abs(f.x), .single = f.single };
    const n = try flonumExponent(c, abs);
    var d = d0;
    if (d == null) {
        const r = try flonumToString(c, abs, null, null, null, null, null);
        const len: i64 = @intCast(r.str.len);
        const q: i64 = if (len == 1) 1 else len - 1;
        d = @max(q, @min(n, 7));
    }
    const ee: i64 = if (e) |x| x + 2 else 4;
    const ww: ?i64 = if (w) |x| x - ee else null;
    const dd = d.? - n;
    if (0 <= dd and dd <= d.?) {
        const overflow = try fixedAux(c, o, f, ww, dd, null, ovf, pad, atsign, v);
        try c.repeat(o, if (overflow) ovf.? else ' ', ee);
    } else try expAux(c, o, f, w, d, e, k orelse 1, ovf, pad, marker, atsign, v);
}

fn formatDollars(c: *Ctx, o: *Out, v: Value, d: i64, n: i64, w: i64, pad: u21, colon: bool, atsign: bool) Fail!void {
    const f = (try toFlo(c, v)) orelse return writeField(c, o, try c.printed(v, false, 10), w, 1, 0, ' ', true);
    if (floatSpecial(f)) return writeField(c, o, try c.printed(v, false, 10), w, 1, 0, ' ', true);
    const signstr: []const u8 = if (signBit(f)) "-" else if (atsign) "+" else "";
    const r = try flonumToString(c, .{ .x = @abs(f.x), .single = f.single }, null, d, null, null, null);
    if (colon) try c.write(o, signstr);
    try c.repeat(o, pad, w - @as(i64, @intCast(signstr.len)) - @max(n, r.point) - 1 - d);
    if (!colon) try c.write(o, signstr);
    try c.repeat(o, '0', n - r.point);
    try c.write(o, r.str);
}

const FloStr = struct {
    str: []const u8,
    lpoint: bool,
    tpoint: bool,
    /// 小数点の位置
    point: i64,
};

/// SBCL の flonum-to-string（x は正か 0）
fn flonumToString(c: *Ctx, x: Flo, width: ?i64, fdigits: ?i64, scale: ?i64, fmin: ?i64, exponent_zero: ?i64) Fail!FloStr {
    var dg: Digits = undefined;
    if (fdigits) |fd| {
        dg = try flonumToDigits(c, x, @min(-(fd + (scale orelse 0)), -(fmin orelse 0)) + (exponent_zero orelse 0), false);
    } else if (width != null and width.? > 1) {
        const wd = try flonumToDigits(c, x, @max(1, width.? - 1 + (if (scale != null and scale.? < 0) scale.? else 0)), true);
        const fd = try flonumToDigits(c, x, -((fmin orelse 0) + (scale orelse 0)), false);
        dg = if (wd.digits.len >= fd.digits.len) wd else fd;
    } else dg = try flonumToDigits(c, x, null, false);

    var e = dg.k;
    if (exponent_zero) |ez| e = if (x.isZero()) 0 else e - ez;
    if (!x.isZero()) e += scale orelse 0;
    const s = dg.digits;
    const slen: i64 = @intCast(s.len);
    var out: std.ArrayList(u8) = .empty;
    const al = c.arena;
    if ((e == 0 and exponent_zero != null) or e > 0) {
        const m: usize = @intCast(@min(slen, e));
        out.appendSlice(al, s[0..m]) catch return c.oom();
        var z = e - slen;
        while (z > 0) : (z -= 1) out.append(al, '0') catch return c.oom();
        out.append(al, '.') catch return c.oom();
        out.appendSlice(al, s[m..]) catch return c.oom();
        if (fdigits) |fd| {
            var zz = fd - (slen - @as(i64, @intCast(m)));
            while (zz > 0) : (zz -= 1) out.append(al, '0') catch return c.oom();
        }
    } else {
        out.append(al, '.') catch return c.oom();
        var z = -e;
        while (z > 0) : (z -= 1) out.append(al, '0') catch return c.oom();
        const end: usize = if (fdigits) |fd| @intCast(@max(0, @min(slen, @max(fmin orelse 0, fd + e)))) else s.len;
        out.appendSlice(al, s[0..end]) catch return c.oom();
        if (fdigits) |fd| {
            var zz = fd + e - slen;
            while (zz > 0) : (zz -= 1) out.append(al, '0') catch return c.oom();
        }
    }
    const str = out.items;
    return .{
        .str = str,
        .lpoint = str[0] == '.',
        .tpoint = str[str.len - 1] == '.',
        .point = @intCast(std.mem.indexOfScalar(u8, str, '.').?),
    };
}

const Digits = struct { k: i64, digits: []const u8 };

fn flonumExponent(c: *Ctx, x: Flo) Fail!i64 {
    if (x.isZero()) return 1;
    return (try flonumToDigits(c, x, null, false)).k;
}

/// 浮動小数の仮数と指数（SBCL の integer-decode-float。非正規化数は、single は指数 -149、double は -1074）
fn integerDecode(x: Flo) struct { f: u64, e: i64 } {
    if (x.single) {
        const bits: u32 = @bitCast(@as(f32, @floatCast(x.x)));
        const frac: u64 = bits & 0x7FFFFF;
        const ex: i64 = @intCast((bits >> 23) & 0xFF);
        if (ex == 0) return .{ .f = frac, .e = if (frac == 0) 0 else -149 };
        return .{ .f = frac | (1 << 23), .e = ex - 126 - 24 };
    }
    const bits: u64 = @bitCast(x.x);
    const frac: u64 = bits & ((1 << 52) - 1);
    const ex: i64 = @intCast((bits >> 52) & 0x7FF);
    if (ex == 0) return .{ .f = frac, .e = if (frac == 0) 0 else -1074 };
    return .{ .f = frac | (1 << 52), .e = ex - 1022 - 53 };
}

fn bitLen(x: u64) i64 {
    return 64 - @as(i64, @clz(x));
}

/// SBCL の %flonum-to-digits（Burger と Dybvig 1996 の図1に、桁の位置での丸めを加えたもの）。
/// position があれば、その位置（10 の冪）で丸める。relativep なら position は有効な桁の数
fn flonumToDigits(c: *Ctx, x: Flo, position0: ?i64, relativep: bool) Fail!Digits {
    if (x.isZero()) return .{ .k = 0, .digits = "0" };
    return flonumToDigitsBig(c, x, position0, relativep) catch c.oom();
}

fn flonumToDigitsBig(c: *Ctx, x: Flo, position0: ?i64, relativep: bool) !Digits {
    const gpa = c.gpa;
    const float_digits: i64 = if (x.single) 24 else 53;
    const min_e: i64 = if (x.single) 2 - 126 - 24 else 2 - 1022 - 53;
    const dec = integerDecode(x);
    var f = dec.f;
    var e = dec.e;
    const precision = bitLen(f);
    if (precision < float_digits) {
        const shift = float_digits - bitLen(f);
        f <<= @intCast(shift);
        e -= shift;
    }
    var high_ok = f % 2 == 0;
    var low_ok = high_ok;
    const hidden: u64 = @as(u64, 1) << @intCast(float_digits - 1);

    var r = try Big.init(gpa);
    defer r.deinit();
    var s = try Big.init(gpa);
    defer s.deinit();
    var mp = try Big.init(gpa);
    defer mp.deinit();
    var mm = try Big.init(gpa);
    defer mm.deinit();
    var t = try Big.init(gpa);
    defer t.deinit();
    var t2 = try Big.init(gpa);
    defer t2.deinit();

    if (e >= 0) {
        try mm.set(1);
        try mm.shiftLeft(&mm, @intCast(e)); // be
        if (f != hidden) {
            try r.set(f);
            try r.shiftLeft(&r, @intCast(e + 1));
            try s.set(2);
            try mp.copy(mm.toConst());
        } else {
            try mp.set(1);
            try mp.shiftLeft(&mp, @intCast(e + 1));
            try r.set(f);
            try r.shiftLeft(&r, @intCast(e + 2));
            try s.set(4);
        }
    } else if (e == min_e or f != hidden) {
        try r.set(f);
        try r.shiftLeft(&r, 1);
        try s.set(1);
        try s.shiftLeft(&s, @intCast(1 - e));
        try mp.set(1);
        try mm.set(1);
    } else {
        try r.set(f);
        try r.shiftLeft(&r, 2);
        try s.set(1);
        try s.shiftLeft(&s, @intCast(2 - e));
        try mp.set(2);
        try mm.set(1);
    }

    var digits: std.ArrayList(u8) = .empty;
    var k: i64 = 0;
    if (position0) |pos0| {
        // scale-p
        var position = pos0;
        if (relativep) {
            std.debug.assert(position > 0);
            var kk: i64 = 0;
            var l = try Big.initSet(gpa, 1);
            defer l.deinit();
            // (* s l) >= (+ r m+) になるまで
            while (true) {
                try t.mul(&s, &l);
                try t2.add(&r, &mp);
                if (t.order(t2) != .lt) break;
                kk += 1;
                try mulSmall(&l, 10);
            }
            // (< (+ r (* s (/ (expt 10 (- k position)) 2))) (* s l))
            const q = kk - position;
            if (q >= 0) {
                // 2r + s*10^q < 2*s*l
                try pow10(&t, q);
                try t.mul(&t, &s);
                try t2.add(&r, &r);
                try t2.add(&t2, &t);
                try t.mul(&s, &l);
                try t.shiftLeft(&t, 1);
            } else {
                // 2r*10^-q + s < 2*s*l*10^-q
                var p10 = try Big.init(gpa);
                defer p10.deinit();
                try pow10(&p10, -q);
                try t2.add(&r, &r);
                try t2.mul(&t2, &p10);
                try t2.add(&t2, &s);
                try t.mul(&s, &l);
                try t.shiftLeft(&t, 1);
                try t.mul(&t, &p10);
            }
            position = if (t2.order(t) == .lt) kk - position else kk - position - 1;
        }
        // x = s * 10^position / 2。すべてを F = 2 * 10^max(0, -position) 倍して整数にする
        const neg: i64 = @max(0, -position);
        var xv = try Big.init(gpa);
        defer xv.deinit();
        try pow10(&xv, position + neg);
        try xv.mul(&xv, &s);
        var factor = try Big.init(gpa);
        defer factor.deinit();
        try pow10(&factor, neg);
        try factor.shiftLeft(&factor, 1);
        try r.mul(&r, &factor);
        try s.mul(&s, &factor);
        try mp.mul(&mp, &factor);
        try mm.mul(&mm, &factor);
        if (mm.order(xv) == .lt) try mm.copy(xv.toConst());
        low_ok = true;
        if (mp.order(xv) == .lt) try mp.copy(xv.toConst());
        high_ok = true;
        // 外側の do：r+m+ は最初の値のまま
        var rpm = try Big.init(gpa);
        defer rpm.deinit();
        try rpm.add(&r, &mp);
        k = 0;
        while (true) {
            const o = rpm.order(s);
            if (!(o == .gt or (high_ok and o == .eq))) break;
            k += 1;
            try mulSmall(&s, 10);
        }
        // 内側の do
        while (true) {
            if (r.order(mm) != .gt) break;
            try t.add(&r, &mp);
            try mulSmall(&t, 10);
            const o = t.order(s);
            if (!(o == .lt or (!high_ok and o == .eq))) break;
            k -= 1;
            try mulSmall(&r, 10);
            try mulSmall(&mp, 10);
            try mulSmall(&mm, 10);
        }
    } else {
        // scale
        const est_f = @as(f64, @floatFromInt(e + bitLen(f) - 1)) * (std.math.log10(2.0)) - 1.0e-10;
        const est: i64 = @intFromFloat(@ceil(est_f));
        if (est >= 0) {
            try pow10(&t, est);
            try s.mul(&s, &t);
        } else {
            try pow10(&t, -est);
            try r.mul(&r, &t);
            try mp.mul(&mp, &t);
            try mm.mul(&mm, &t);
        }
        k = est;
        // fixup
        try t.add(&r, &mp);
        const o = t.order(s);
        if (if (high_ok) o != .lt else o == .gt) {
            k += 1;
            try mulSmall(&s, 10);
        }
    }
    // generate
    var q = try Big.init(gpa);
    defer q.deinit();
    while (true) {
        try mulSmall(&r, 10);
        try q.divTrunc(&t, &r, &s);
        try r.copy(t.toConst());
        const dgt: u8 = @intCast(try q.toInt(u32));
        try mulSmall(&mp, 10);
        try mulSmall(&mm, 10);
        const o1 = r.order(mm);
        const tc1 = o1 == .lt or (low_ok and o1 == .eq);
        try t.add(&r, &mp);
        const o2 = t.order(s);
        const tc2 = o2 == .gt or (high_ok and o2 == .eq);
        if (tc1 or tc2) {
            const last: u8 = if (!tc1 and tc2) dgt + 1 else if (tc1 and !tc2) dgt else blk: {
                try t.add(&r, &r);
                break :blk if (t.order(s) == .lt) dgt else dgt + 1;
            };
            try digits.append(c.arena, '0' + last);
            break;
        }
        try digits.append(c.arena, '0' + dgt);
    }
    return .{ .k = k, .digits = digits.items };
}

fn mulSmall(x: *Big, n: u32) !void {
    var m = try Big.initSet(x.allocator, n);
    defer m.deinit();
    try x.mul(x, &m);
}

fn pow10(out: *Big, n: i64) !void {
    try out.set(1);
    var ten = try Big.initSet(out.allocator, 10);
    defer ten.deinit();
    try out.pow(&ten, @intCast(n));
}

// ---------------------------------------------------------------------------
// 入口

/// (format 出力先 制御 引数...)。出力先は T（*standard-output*）・NIL（文字列を返す）・ストリーム
pub fn format(th: *Thread, args: []const Value) Value {
    const rt = th.rt;
    const dest = args[0];
    const control = args[1];
    const out_stream: ?Value = if (dest == Value.nil) null else if (dest == rt.t) (streams.outputDesignator(th, Value.nil) orelse return Value.unwind) else if (streams.isStream(dest)) (streams.outputDesignator(th, dest) orelse return Value.unwind) else {
        if (arrays.isStringLike(dest))
            return th.signal(.unimplemented, "FORMAT の出力先に文字列を使うのは未実装です", dest, Value.unbound);
        return th.typeError(dest, (rt.findSymbol(rt.cl, "STREAM") orelse unreachable).symbol);
    };
    const to_string = out_stream == null and prettyOn(th);
    const target: ?Value = if (to_string) (streams.makeStringOutput(th) orelse return Value.unwind) else out_stream;
    var o: Out = .{ .stream = target };
    defer o.buf.deinit(rt.gpa);
    if (target) |s| {
        o.base_col = streams.columnOf(th, s);
        o.base_line_start = streams.atLineStart(th, s);
        o.direct = streams.prettyStateOf(s) != null;
    }
    var a: Args = .{ .items = args[2..] };
    if (run(th, &o, control, &a)) |_| {} else |err| switch (err) {
        error.Lisp => return Value.unwind,
        else => unreachable,
    }
    if (target) |s| {
        if (o.buf.items.len > 0 and !streams.emit(th, s, o.buf.items)) return Value.unwind;
        if (to_string) return streams.getOutputStreamString(th, &.{s});
        return Value.nil;
    }
    return rt.makeString(o.buf.items) catch th.outOfMemory();
}

fn run(th: *Thread, o: *Out, control: Value, a: *Args) error{Lisp}!void {
    var arena_state = std.heap.ArenaAllocator.init(th.rt.gpa);
    defer arena_state.deinit();
    var c: Ctx = .{ .th = th, .gpa = th.rt.gpa, .arena = arena_state.allocator(), .control = control };
    if (!isStringValue(control) and !control.isFunctionPointer()) {
        _ = th.typeError(control, (th.rt.findSymbol(th.rt.cl, "STRING") orelse unreachable).symbol);
        return error.Lisp;
    }
    formatControl(&c, o, control, a) catch |err| switch (err) {
        error.Up, error.UpUp => {},
        error.Lisp => return error.Lisp,
    };
}

/// (zilisp-system:%format-rest ストリーム 制御文字列 引数のリスト)：formatter が作る関数の本体。
/// 制御文字列を解釈して、使わなかった残りの引数のリストを返す
pub fn formatRest(th: *Thread, args: []const Value) Value {
    const rt = th.rt;
    const s = args[0];
    var arena_state = std.heap.ArenaAllocator.init(rt.gpa);
    defer arena_state.deinit();
    const items = (listItems(rt, args[2]) catch return th.outOfMemory()) orelse return th.typeError(args[2], rt.syms.list);
    var o: Out = .{ .stream = s, .base_col = streams.columnOf(th, s), .base_line_start = streams.atLineStart(th, s), .direct = streams.prettyStateOf(s) != null };
    defer o.buf.deinit(rt.gpa);
    var a: Args = .{ .items = items.items, .holder = items.holder };
    run(th, &o, args[1], &a) catch return Value.unwind;
    if (o.buf.items.len > 0 and !streams.emit(th, s, o.buf.items)) return Value.unwind;
    // 残りの引数：元のリストの、使った数だけ進めた尾
    var x = args[2];
    for (0..a.pos) |_| x = Runtime.consPtr(x).cdr;
    return x;
}

/// Zig から制御文字列（UTF-8）を引数 args で解釈してストリームに書く（pretty printer の標準の印字関数が使う。
/// SBCL の (funcall (formatter "…") stream …)）
pub fn formatToStream(th: *Thread, s: Value, control: []const u8, args: []const Value) bool {
    const rt = th.rt;
    var arena_state = std.heap.ArenaAllocator.init(rt.gpa);
    defer arena_state.deinit();
    var c: Ctx = .{ .th = th, .gpa = rt.gpa, .arena = arena_state.allocator(), .control = Value.nil };
    var chars: std.ArrayList(u21) = .empty;
    var it = std.unicode.Utf8View.initUnchecked(control).iterator();
    while (it.nextCodepoint()) |cp| chars.append(c.arena, cp) catch return th.outOfMemory() != Value.unwind;
    const toks = tokenize(&c, chars.items) catch return false;
    var o: Out = .{ .stream = s, .base_col = streams.columnOf(th, s), .base_line_start = streams.atLineStart(th, s), .direct = streams.prettyStateOf(s) != null };
    defer o.buf.deinit(rt.gpa);
    var a: Args = .{ .items = args };
    interpret(&c, &o, toks, &a) catch |err| switch (err) {
        error.Up, error.UpUp => {},
        error.Lisp => return false,
    };
    if (o.buf.items.len > 0 and !streams.emit(th, s, o.buf.items)) return false;
    return true;
}
