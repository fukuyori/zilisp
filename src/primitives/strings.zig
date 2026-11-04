//! 文字と文字列の関数（Phase 21。CLHS 13 章・16 章）。
//!
//! 文字：characterp・char-code・code-char・char-int・char-upcase・char-downcase・upper-case-p・lower-case-p・both-case-p・
//!   alpha-char-p・alphanumericp・digit-char-p・digit-char・graphic-char-p・standard-char-p、
//!   char=・char/=・char<・char>・char<=・char>=、char-equal・char-not-equal・char-lessp・char-greaterp・
//!   char-not-greaterp・char-not-lessp
//! 文字列：string、string=・string/=・string<・string>・string<=・string>=、string-equal・string-not-equal・
//!   string-lessp・string-greaterp・string-not-greaterp・string-not-lessp、string-upcase・string-downcase・
//!   string-capitalize・nstring-upcase・nstring-downcase・nstring-capitalize、string-trim・string-left-trim・
//!   string-right-trim、make-string、parse-integer
//!
//! 大文字・小文字と、文字の種類（英字・数字）は Unicode 15.0.0 に従う（Phase 21.5。src/unicode/unicode.zig。
//! SBCL 2.6.7 と同じ。大文字でも小文字でもない4文字だけ違う：tests/differential/impl-dependent.toml）。
//! 文字列の引数は、単純でない文字列（fill-pointer のあるものなど）も受け取り、有効な部分を使う。

const std = @import("std");
const Value = @import("../values/value.zig").Value;
const Thread = @import("../runtime/thread.zig").Thread;
const Runtime = @import("../runtime/runtime.zig").Runtime;
const keyargs = @import("keyargs.zig");
const arrays = @import("arrays.zig");
const numbers = @import("numbers.zig");
const most_positive_fixnum = @import("../values/value.zig").most_positive_fixnum;
const unicode = @import("../unicode/unicode.zig");

fn cl(th: *Thread, name: []const u8) Value {
    return (th.rt.findSymbol(th.rt.cl, name) orelse unreachable).symbol;
}

fn isSymbol(v: Value) bool {
    return v == Value.nil or (v.isOther() and Runtime.kindOf(v) == .symbol);
}

// ---------------------------------------------------------------------------
// 文字の種類（Unicode 15.0.0。src/unicode/unicode.zig）

const isUpper = unicode.isUpper;
const isLower = unicode.isLower;
const hasCase = unicode.hasCase;
const isAlpha = unicode.isAlpha;
const isAlnum = unicode.isAlnum;
pub const upcase = unicode.upcase;
pub const downcase = unicode.downcase;
fn isWhitespace(c: u21) bool {
    return c == ' ' or c == '\t' or c == '\n' or c == '\r' or c == 0x0C or c == 0x0B;
}

/// 数字の重み（基数 radix の数字でなければ null）
const digitWeight = unicode.digitWeight;

fn charArg(th: *Thread, v: Value) ?u21 {
    if (v.isChar()) return v.asChar();
    _ = th.typeError(v, cl(th, "CHARACTER"));
    return null;
}

/// 基数（2 から 36 の整数）
fn radixArg(th: *Thread, v: ?Value) ?u32 {
    const r = v orelse return 10;
    if (r.isFixnum() and r.asFixnum() >= 2 and r.asFixnum() <= 36) return @intCast(r.asFixnum());
    const rt = th.rt;
    var t = rt.cons(Value.fromFixnum(36), Value.nil) catch {
        _ = th.outOfMemory();
        return null;
    };
    t = rt.cons(Value.fromFixnum(2), t) catch {
        _ = th.outOfMemory();
        return null;
    };
    t = rt.cons(rt.syms.integer, t) catch {
        _ = th.outOfMemory();
        return null;
    };
    _ = th.typeError(r, t);
    return null;
}

// ---------------------------------------------------------------------------
// 文字の関数

pub fn characterp(th: *Thread, args: []const Value) Value {
    return th.rt.boolean(args[0].isChar());
}

pub fn charCode(th: *Thread, args: []const Value) Value {
    const c = charArg(th, args[0]) orelse return Value.unwind;
    return Value.fromFixnum(c);
}

/// (code-char 符号)：char-code-limit は #x110000（SBCL 2.6.7 と同じ）
pub fn codeChar(th: *Thread, args: []const Value) Value {
    const v = args[0];
    if (!v.isFixnum() or v.asFixnum() < 0 or v.asFixnum() >= 0x110000) {
        const rt = th.rt;
        var t = rt.cons(Value.fromFixnum(0x10FFFF), Value.nil) catch return th.outOfMemory();
        t = rt.cons(Value.fromFixnum(0), t) catch return th.outOfMemory();
        t = rt.cons(rt.syms.integer, t) catch return th.outOfMemory();
        return th.typeError(v, t);
    }
    return Value.fromChar(@intCast(v.asFixnum()));
}

pub fn charUpcase(th: *Thread, args: []const Value) Value {
    const c = charArg(th, args[0]) orelse return Value.unwind;
    return Value.fromChar(upcase(c));
}

pub fn charDowncase(th: *Thread, args: []const Value) Value {
    const c = charArg(th, args[0]) orelse return Value.unwind;
    return Value.fromChar(downcase(c));
}

fn charPredicate(comptime pred: fn (u21) bool) fn (*Thread, []const Value) Value {
    return struct {
        fn f(th: *Thread, args: []const Value) Value {
            const c = charArg(th, args[0]) orelse return Value.unwind;
            return th.rt.boolean(pred(c));
        }
    }.f;
}

fn isGraphic(c: u21) bool {
    return c >= 0x20 and c != 0x7F and !(c >= 0x80 and c < 0xA0);
}
fn isStandard(c: u21) bool {
    return (c >= 0x20 and c < 0x7F) or c == '\n';
}

pub const upperCaseP = charPredicate(isUpper);
pub const lowerCaseP = charPredicate(isLower);
pub const bothCaseP = charPredicate(hasCase);
pub const alphaCharP = charPredicate(isAlpha);
pub const alphanumericp = charPredicate(isAlnum);
pub const graphicCharP = charPredicate(isGraphic);
pub const standardCharP = charPredicate(isStandard);

/// (digit-char-p 文字 &optional (基数 10))：数字の重み、数字でなければ NIL
pub fn digitCharP(th: *Thread, args: []const Value) Value {
    const c = charArg(th, args[0]) orelse return Value.unwind;
    const radix = radixArg(th, if (args.len > 1) args[1] else null) orelse return Value.unwind;
    const w = digitWeight(c, radix) orelse return Value.nil;
    return Value.fromFixnum(w);
}

/// (digit-char 重み &optional (基数 10))：数字の文字（大文字）、重みが基数以上なら NIL
pub fn digitChar(th: *Thread, args: []const Value) Value {
    const w = args[0];
    if (!w.isFixnum() or w.asFixnum() < 0) {
        if (w.isOther() and Runtime.kindOf(w) == .bignum and Runtime.bignumPtr(w).positive()) return Value.nil;
        return th.typeError(w, cl(th, "UNSIGNED-BYTE"));
    }
    const radix = radixArg(th, if (args.len > 1) args[1] else null) orelse return Value.unwind;
    const n: u64 = @intCast(w.asFixnum());
    if (n >= radix) return Value.nil;
    return Value.fromChar(@intCast(if (n < 10) '0' + n else 'A' + n - 10));
}

pub fn charInt(th: *Thread, args: []const Value) Value {
    return charCode(th, args);
}

const CharCmp = enum { eq, ne, lt, gt, le, ge };

fn charCompare(comptime cmp: CharCmp, comptime fold: bool) fn (*Thread, []const Value) Value {
    return struct {
        fn f(th: *Thread, args: []const Value) Value {
            for (args) |a| _ = charArg(th, a) orelse return Value.unwind;
            const key = struct {
                fn k(v: Value) u21 {
                    return if (fold) downcase(v.asChar()) else v.asChar();
                }
            }.k;
            if (cmp == .ne) {
                // すべての組が異なる
                for (args, 0..) |a, i| for (args[i + 1 ..]) |b| if (key(a) == key(b)) return Value.nil;
                return th.rt.t;
            }
            for (args[0 .. args.len - 1], args[1..]) |a, b| {
                const x = key(a);
                const y = key(b);
                const ok = switch (cmp) {
                    .eq => x == y,
                    .lt => x < y,
                    .gt => x > y,
                    .le => x <= y,
                    .ge => x >= y,
                    .ne => unreachable,
                };
                if (!ok) return Value.nil;
            }
            return th.rt.t;
        }
    }.f;
}

pub const charEq = charCompare(.eq, false);
pub const charNe = charCompare(.ne, false);
pub const charLt = charCompare(.lt, false);
pub const charGt = charCompare(.gt, false);
pub const charLe = charCompare(.le, false);
pub const charGe = charCompare(.ge, false);
pub const charEqual = charCompare(.eq, true);
pub const charNotEqual = charCompare(.ne, true);
pub const charLessp = charCompare(.lt, true);
pub const charGreaterp = charCompare(.gt, true);
pub const charNotGreaterp = charCompare(.le, true);
pub const charNotLessp = charCompare(.ge, true);

// ---------------------------------------------------------------------------
// 文字列指定子

/// 文字列として見たもの：単純な文字列 data の [0, len)
const Str = struct {
    data: Value,
    len: usize,
    fn at(s: Str, i: usize) u21 {
        return Runtime.stringPtr(s.data).charAt(i);
    }
};

/// 文字列指定子（文字列・シンボル・文字）を文字列として見る。文字なら1文字の文字列を作る
fn designator(th: *Thread, v: Value) ?Str {
    if (arrays.isStringLike(v)) {
        const view = arrays.vectorView(v).?;
        return .{ .data = view.data, .len = view.len };
    }
    if (isSymbol(v)) {
        const name = if (v == Value.nil) th.rt.nil_symbol.name else th.rt.symbolPtr(v).name;
        return .{ .data = name, .len = Runtime.stringPtr(name).length() };
    }
    if (v.isChar()) {
        const s = th.rt.makeStringFilled(1, v.asChar()) catch {
            _ = th.outOfMemory();
            return null;
        };
        return .{ .data = s, .len = 1 };
    }
    _ = th.typeError(v, cl(th, "STRING"));
    return null;
}

/// (string x)：文字列はそのまま、シンボルは名前、文字は1文字の文字列
pub fn string(th: *Thread, args: []const Value) Value {
    if (arrays.isStringLike(args[0])) return args[0];
    const s = designator(th, args[0]) orelse return Value.unwind;
    return s.data;
}

/// :start・:end を [start, end) にする（end が NIL なら長さ）。範囲が正しくなければ null（エラーを記録済み）
pub fn bounds(th: *Thread, start: ?Value, end: ?Value, len: usize) ?[2]usize {
    var s: usize = 0;
    var e: usize = len;
    if (start) |v| {
        if (!v.isFixnum() or v.asFixnum() < 0) {
            _ = th.typeError(v, cl(th, "UNSIGNED-BYTE"));
            return null;
        }
        s = @intCast(v.asFixnum());
    }
    if (end) |v| if (v != Value.nil) {
        if (!v.isFixnum() or v.asFixnum() < 0) {
            _ = th.typeError(v, cl(th, "UNSIGNED-BYTE"));
            return null;
        }
        e = @intCast(v.asFixnum());
    };
    // 範囲の誤りは type-error（SBCL 2.6.7 の bounding-indices-bad-error は type-error の一種）。型は (integer 0 上限)
    if (e > len or s > e) {
        const bad: usize = if (e > len) e else s;
        const top: usize = if (e > len) len else e;
        const rt = th.rt;
        var t = rt.cons(Value.fromFixnum(@intCast(top)), Value.nil) catch {
            _ = th.outOfMemory();
            return null;
        };
        t = rt.cons(Value.fromFixnum(0), t) catch {
            _ = th.outOfMemory();
            return null;
        };
        t = rt.cons(rt.syms.integer, t) catch {
            _ = th.outOfMemory();
            return null;
        };
        _ = th.typeError(Value.fromFixnum(@intCast(bad)), t);
        return null;
    }
    return .{ s, e };
}

// ---------------------------------------------------------------------------
// 文字列の比較

/// 比べた結果：最初に違う位置（string1 の添字）と、その位置での大小
const Mismatch = struct { index: usize, order: std.math.Order };

fn compareStrings(th: *Thread, args: []const Value, fold: bool) ?Mismatch {
    var kv: [4]?Value = undefined;
    if (!keyargs.parse(th, args[2..], &.{ "START1", "END1", "START2", "END2" }, &kv)) return null;
    const a = designator(th, args[0]) orelse return null;
    const b = designator(th, args[1]) orelse return null;
    const ra = bounds(th, kv[0], kv[1], a.len) orelse return null;
    const rb = bounds(th, kv[2], kv[3], b.len) orelse return null;
    var i = ra[0];
    var j = rb[0];
    while (i < ra[1] and j < rb[1]) : ({
        i += 1;
        j += 1;
    }) {
        var x = a.at(i);
        var y = b.at(j);
        if (fold) {
            x = downcase(x);
            y = downcase(y);
        }
        if (x != y) return .{ .index = i, .order = std.math.order(x, y) };
    }
    const la = ra[1] - ra[0];
    const lb = rb[1] - rb[0];
    return .{ .index = i, .order = std.math.order(la, lb) };
}

fn stringCompare(comptime cmp: CharCmp, comptime fold: bool) fn (*Thread, []const Value) Value {
    return struct {
        fn f(th: *Thread, args: []const Value) Value {
            const m = compareStrings(th, args, fold) orelse return Value.unwind;
            if (cmp == .eq) return th.rt.boolean(m.order == .eq);
            const ok = switch (cmp) {
                .ne => m.order != .eq,
                .lt => m.order == .lt,
                .gt => m.order == .gt,
                .le => m.order != .gt,
                .ge => m.order != .lt,
                .eq => unreachable,
            };
            return if (ok) Value.fromFixnum(@intCast(m.index)) else Value.nil;
        }
    }.f;
}

pub const stringEq = stringCompare(.eq, false);
pub const stringNe = stringCompare(.ne, false);
pub const stringLt = stringCompare(.lt, false);
pub const stringGt = stringCompare(.gt, false);
pub const stringLe = stringCompare(.le, false);
pub const stringGe = stringCompare(.ge, false);
pub const stringEqual = stringCompare(.eq, true);
pub const stringNotEqual = stringCompare(.ne, true);
pub const stringLessp = stringCompare(.lt, true);
pub const stringGreaterp = stringCompare(.gt, true);
pub const stringNotGreaterp = stringCompare(.le, true);
pub const stringNotLessp = stringCompare(.ge, true);

// ---------------------------------------------------------------------------
// 大文字・小文字の変換

const CaseMode = enum { up, down, capitalize };

/// data の [start, end) を変換する。capitalize は、英数字の並び（語）の先頭を大文字、残りを小文字にする
fn convertRange(th: *Thread, data: Value, start: usize, end: usize, mode: CaseMode) bool {
    var in_word = false;
    for (start..end) |i| {
        const c = Runtime.stringPtr(data).charAt(i);
        const out = switch (mode) {
            .up => upcase(c),
            .down => downcase(c),
            .capitalize => blk: {
                const r = if (in_word) downcase(c) else upcase(c);
                in_word = isAlnum(c);
                break :blk r;
            },
        };
        if (out != c) th.rt.stringSetChar(data, i, out) catch {
            _ = th.outOfMemory();
            return false;
        };
    }
    return true;
}

fn caseConverter(comptime mode: CaseMode) fn (*Thread, []const Value) Value {
    return struct {
        fn f(th: *Thread, args: []const Value) Value {
            var kv: [2]?Value = undefined;
            if (!keyargs.parse(th, args[1..], &.{ "START", "END" }, &kv)) return Value.unwind;
            const src = designator(th, args[0]) orelse return Value.unwind;
            const r = bounds(th, kv[0], kv[1], src.len) orelse return Value.unwind;
            const out = th.rt.makeStringFilled(src.len, ' ') catch return th.outOfMemory();
            for (0..src.len) |i| th.rt.stringSetChar(out, i, src.at(i)) catch return th.outOfMemory();
            if (!convertRange(th, out, r[0], r[1], mode)) return Value.unwind;
            return out;
        }
    }.f;
}

/// nstring-*：文字列そのものを書き換えて返す
fn destructiveCaseConverter(comptime mode: CaseMode) fn (*Thread, []const Value) Value {
    return struct {
        fn f(th: *Thread, args: []const Value) Value {
            var kv: [2]?Value = undefined;
            if (!keyargs.parse(th, args[1..], &.{ "START", "END" }, &kv)) return Value.unwind;
            if (!arrays.isStringLike(args[0])) return th.typeError(args[0], cl(th, "STRING"));
            const view = arrays.vectorView(args[0]).?;
            const r = bounds(th, kv[0], kv[1], view.len) orelse return Value.unwind;
            if (!convertRange(th, view.data, r[0], r[1], mode)) return Value.unwind;
            return args[0];
        }
    }.f;
}

pub const stringUpcase = caseConverter(.up);
pub const stringDowncase = caseConverter(.down);
pub const stringCapitalize = caseConverter(.capitalize);
pub const nstringUpcase = destructiveCaseConverter(.up);
pub const nstringDowncase = destructiveCaseConverter(.down);
pub const nstringCapitalize = destructiveCaseConverter(.capitalize);

// ---------------------------------------------------------------------------
// string-trim

/// 文字の集まり（リスト・ベクタ・文字列）に c があるか
fn inBag(bag: Value, c: u21) bool {
    if (bag.isList()) {
        var x = bag;
        while (x.isCons()) : (x = Runtime.consPtr(x).cdr) {
            const e = Runtime.consPtr(x).car;
            if (e.isChar() and e.asChar() == c) return true;
        }
        return false;
    }
    const view = arrays.vectorView(bag).?;
    for (0..view.len) |i| {
        const e = arrays.storageGet(view.data, i);
        if (e.isChar() and e.asChar() == c) return true;
    }
    return false;
}

fn trimmer(comptime left: bool, comptime right: bool) fn (*Thread, []const Value) Value {
    return struct {
        fn f(th: *Thread, args: []const Value) Value {
            const bag = args[0];
            if (!bag.isList() and arrays.vectorView(bag) == null) return th.typeError(bag, cl(th, "SEQUENCE"));
            const s = designator(th, args[1]) orelse return Value.unwind;
            var start: usize = 0;
            var end: usize = s.len;
            if (left) {
                while (start < end and inBag(bag, s.at(start))) start += 1;
            }
            if (right) {
                while (end > start and inBag(bag, s.at(end - 1))) end -= 1;
            }
            const out = th.rt.makeStringFilled(end - start, ' ') catch return th.outOfMemory();
            for (start..end) |i| th.rt.stringSetChar(out, i - start, s.at(i)) catch return th.outOfMemory();
            return out;
        }
    }.f;
}

pub const stringTrim = trimmer(true, true);
pub const stringLeftTrim = trimmer(true, false);
pub const stringRightTrim = trimmer(false, true);

// ---------------------------------------------------------------------------

/// (make-string 長さ &key initial-element element-type)：既定の要素は符号 0 の文字（SBCL 2.6.7 と同じ）
pub fn makeString(th: *Thread, args: []const Value) Value {
    var kv: [2]?Value = undefined;
    if (!keyargs.parse(th, args[1..], &.{ "INITIAL-ELEMENT", "ELEMENT-TYPE" }, &kv)) return Value.unwind;
    const n = args[0];
    if (!n.isFixnum() or n.asFixnum() < 0) return th.typeError(n, cl(th, "UNSIGNED-BYTE"));
    // :element-type は文字の型だけ（character・base-char・standard-char。SBCL と同じく、それ以外は simple-error。
    // Codex のレビュー 0.3 #12）
    if (kv[1]) |et| {
        // NIL（空の型）も受け付ける（SBCL と同じ。Codex のレビュー 0.3 修正の修正 #4）
        var ok = et == Value.nil;
        for ([_][]const u8{ "CHARACTER", "BASE-CHAR", "STANDARD-CHAR" }) |name| if (et == cl(th, name)) {
            ok = true;
        };
        if (!ok) return th.signal(.simple_error, "MAKE-STRING の :element-type は文字の型でなければなりません", et, Value.unbound);
    }
    var c: u21 = 0;
    if (kv[0]) |v| c = charArg(th, v) orelse return Value.unwind;
    return th.rt.makeStringFilled(@intCast(n.asFixnum()), c) catch th.outOfMemory();
}

/// (parse-integer 文字列 &key start end radix junk-allowed)：整数と、読み終えた位置の2つの値。
/// 前後の空白は読み飛ばす。数字がない・余分な文字がある場合は parse-error（junk-allowed なら NIL）
pub fn parseInteger(th: *Thread, args: []const Value) Value {
    var kv: [4]?Value = undefined;
    if (!keyargs.parse(th, args[1..], &.{ "START", "END", "RADIX", "JUNK-ALLOWED" }, &kv)) return Value.unwind;
    if (!arrays.isStringLike(args[0])) return th.typeError(args[0], cl(th, "STRING"));
    const view = arrays.vectorView(args[0]).?;
    const s: Str = .{ .data = view.data, .len = view.len };
    const r = bounds(th, kv[0], kv[1], s.len) orelse return Value.unwind;
    const radix = radixArg(th, kv[2]) orelse return Value.unwind;
    const junk = kv[3] != null and kv[3].? != Value.nil;
    var i = r[0];
    const end = r[1];
    while (i < end and isWhitespace(s.at(i))) i += 1;
    var negative = false;
    if (i < end and (s.at(i) == '+' or s.at(i) == '-')) {
        negative = s.at(i) == '-';
        i += 1;
    }
    // 数字は fixnum の範囲で足し込み、溢れたら整数の演算に切り替える
    var acc: i64 = 0;
    var big: ?Value = null;
    var digits: usize = 0;
    while (i < end) : (i += 1) {
        const w = digitWeight(s.at(i), radix) orelse break;
        digits += 1;
        if (big) |b| {
            const m = numbers.mul2(th, b, Value.fromFixnum(radix));
            if (m == Value.unwind) return m;
            const sum = numbers.add2(th, m, Value.fromFixnum(w));
            if (sum == Value.unwind) return sum;
            big = sum;
            continue;
        }
        const m = @mulWithOverflow(acc, @as(i64, radix));
        const a = @addWithOverflow(m[0], @as(i64, w));
        if (m[1] != 0 or a[1] != 0 or a[0] > most_positive_fixnum) {
            const m2 = numbers.mul2(th, Value.fromFixnum(acc), Value.fromFixnum(radix));
            if (m2 == Value.unwind) return m2;
            const sum = numbers.add2(th, m2, Value.fromFixnum(w));
            if (sum == Value.unwind) return sum;
            big = sum;
            continue;
        }
        acc = a[0];
    }
    const digits_end = i;
    while (i < end and isWhitespace(s.at(i))) i += 1;
    const ok = digits > 0 and i == end;
    if (!ok and !junk) {
        return th.signal(.parse_error, "整数として読めません", args[0], Value.unbound);
    }
    th.mv[1] = Value.fromFixnum(@intCast(if (junk) digits_end else i));
    th.mv_count = 2;
    if (digits == 0) return Value.nil;
    var result = big orelse Value.fromFixnum(acc);
    if (negative) {
        result = numbers.sub2(th, Value.fromFixnum(0), result);
        if (result == Value.unwind) return result;
        th.mv[1] = Value.fromFixnum(@intCast(if (junk) digits_end else i));
        th.mv_count = 2;
    }
    return result;
}
