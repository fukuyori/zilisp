//! Reader が読んだものから Lisp の値（Value）を作る Builder（詳細設計 §5、§8）。
//!
//! 整数は fixnum の範囲を超えれば bignum に、比は約分して ratio（分母が 1 なら整数）にする（Phase 20）。

const std = @import("std");
const reader = @import("reader.zig");
const rt_mod = @import("../runtime/runtime.zig");
const Runtime = rt_mod.Runtime;
const Value = rt_mod.Value;
const Diagnostic = reader.Diagnostic;
const SourceLoc = reader.SourceLoc;
const Error = reader.Error;

pub const ValueBuilder = struct {
    rt: *Runtime,
    /// 真なら、パッケージ修飾のパッケージがなければ空のパッケージを作る（ネイティブの定数を起動時に読むとき。Phase 22）
    create_packages: bool = false,

    pub const Datum = Value;
    /// 組み立て中のリスト（先頭と最後の cons）
    pub const List = struct { head: Value = Value.nil, last: Value = Value.nil, count: usize = 0 };

    fn fail(diag: *Diagnostic, loc: SourceLoc, message: []const u8) Error {
        diag.* = .{ .loc = loc, .message = message };
        return error.ReaderError;
    }

    pub fn integer(b: *ValueBuilder, diag: *Diagnostic, loc: SourceLoc, negative: bool, digits: []const u8, radix: u8) Error!Value {
        _ = diag;
        _ = loc;
        var acc: i64 = 0;
        var small = true;
        for (digits) |c| {
            const m = @mulWithOverflow(acc, @as(i64, radix));
            const s = @addWithOverflow(m[0], digitValue(c));
            if (m[1] != 0 or s[1] != 0) {
                small = false;
                break;
            }
            acc = s[0];
        }
        if (small) {
            const v = if (negative) -acc else acc;
            if (Value.fixnumFits(v)) return Value.fromFixnum(v);
        }
        var m = try std.math.big.int.Managed.init(b.rt.gpa);
        defer m.deinit();
        m.setString(radix, digits) catch |e| switch (e) {
            error.OutOfMemory => return error.OutOfMemory,
            else => unreachable, // 数字は number.parse が確かめている
        };
        if (negative) m.negate();
        return b.rt.makeInteger(m.toConst());
    }

    fn digitValue(c: u8) i64 {
        return switch (c) {
            '0'...'9' => c - '0',
            'a'...'z' => c - 'a' + 10,
            'A'...'Z' => c - 'A' + 10,
            else => unreachable,
        };
    }

    /// 比：約分して、分母が 1 なら整数にする。分母が 0 なら division-by-zero（SBCL 2.6.7 は reader-error）
    pub fn ratio(b: *ValueBuilder, diag: *Diagnostic, loc: SourceLoc, negative: bool, num: []const u8, den: []const u8, radix: u8) Error!Value {
        const big = std.math.big.int;
        const gpa = b.rt.gpa;
        var n = try big.Managed.init(gpa);
        defer n.deinit();
        var d = try big.Managed.init(gpa);
        defer d.deinit();
        n.setString(radix, num) catch |e| switch (e) {
            error.OutOfMemory => return error.OutOfMemory,
            else => unreachable,
        };
        d.setString(radix, den) catch |e| switch (e) {
            error.OutOfMemory => return error.OutOfMemory,
            else => unreachable,
        };
        if (d.eqlZero()) return fail(diag, loc, "比の分母が 0 です");
        if (negative) n.negate();
        var g = try big.Managed.init(gpa);
        defer g.deinit();
        try g.gcd(&n, &d);
        var q = try big.Managed.init(gpa);
        defer q.deinit();
        var r = try big.Managed.init(gpa);
        defer r.deinit();
        try q.divTrunc(&r, &n, &g);
        try n.copy(q.toConst());
        try q.divTrunc(&r, &d, &g);
        try d.copy(q.toConst());
        const nv = try b.rt.makeInteger(n.toConst());
        if (d.toConst().orderAgainstScalar(1) == .eq) return nv;
        // 分子の値（bignum なら確保したもの）は、分母の確保の間、この関数のスタックにあるので GC から守られる
        const dv = try b.rt.makeInteger(d.toConst());
        const v = try b.rt.makeRatioRaw(nv, dv);
        std.mem.doNotOptimizeAway(nv);
        return v;
    }

    pub fn float(b: *ValueBuilder, loc: SourceLoc, value: reader.number.Float) Error!Value {
        _ = loc;
        return switch (value) {
            .single => |f| Value.fromSingle(f),
            .double => |f| try b.rt.makeDouble(f),
        };
    }

    pub fn symbol(b: *ValueBuilder, diag: *Diagnostic, loc: SourceLoc, pkg: reader.PackageRef, name: []const u8) Error!Value {
        const rt = b.rt;
        return switch (pkg) {
            .current => try rt.intern(rt.currentPackage() orelse return fail(diag, loc, "*PACKAGE* の値がパッケージではありません"), name),
            .keyword => try rt.internKeyword(name),
            .uninterned => try rt.makeSymbol(name),
            .named => |n| blk: {
                const p = rt.findPackage(n.name) orelse (if (b.create_packages)
                    // ネイティブのプログラムが起動時に定数を読むとき：まだ作られていないパッケージは、一覧に入れない仮のパッケージにする
                    // （後で make-package・defpackage が同じ名前で作るときに登録する。Codex のレビュー P22 #1）
                    try rt.pendingPackage(n.name)
                else
                    return fail(diag, loc, "そのパッケージはありません"));
                if (n.external) {
                    const f = rt.findSymbol(p, name) orelse return fail(diag, loc, "そのパッケージにシンボルがありません");
                    if (f.status != .external) return fail(diag, loc, "そのシンボルは外部シンボルではありません（:: で指定してください）");
                    break :blk f.symbol;
                }
                break :blk try rt.intern(p, name);
            },
        };
    }

    pub fn nil(b: *ValueBuilder, loc: SourceLoc) Error!Value {
        _ = .{ b, loc };
        return Value.nil;
    }

    /// #P"..."：文字列をパス名にする（Phase 23）
    pub fn pathname(b: *ValueBuilder, diag: *Diagnostic, loc: SourceLoc, obj: Value) Error!Value {
        const pathnames = @import("../primitives/pathnames.zig");
        if (!(obj.isOther() and Runtime.kindOf(obj) == .string)) return fail(diag, loc, "#P の後には文字列が必要です");
        const text = try pathnames.stringUtf8(b.rt.gpa, obj);
        defer b.rt.gpa.free(text);
        return pathnames.parse(b.rt, text);
    }

    pub fn string(b: *ValueBuilder, loc: SourceLoc, utf8: []const u8) Error!Value {
        _ = loc;
        return b.rt.makeString(utf8);
    }

    pub fn character(b: *ValueBuilder, loc: SourceLoc, cp: u21) Error!Value {
        _ = .{ b, loc };
        return Value.fromChar(cp);
    }

    pub fn listBegin(b: *ValueBuilder, loc: SourceLoc) Error!List {
        _ = .{ b, loc };
        return .{};
    }

    pub fn listPush(b: *ValueBuilder, list: *List, item: Value) Error!void {
        const c = try b.rt.cons(item, Value.nil);
        if (list.head == Value.nil) {
            list.head = c;
        } else {
            Runtime.consPtr(list.last).cdr = c;
        }
        list.last = c;
        list.count += 1;
    }

    pub fn listEnd(b: *ValueBuilder, list: *List, tail: ?Value) Error!Value {
        _ = b;
        if (tail) |t| {
            std.debug.assert(list.head != Value.nil);
            Runtime.consPtr(list.last).cdr = t;
        }
        return list.head;
    }

    pub fn vectorEnd(b: *ValueBuilder, list: *List) Error!Value {
        // 要素を Zig のヒープに写さず、ベクタを確保してからリストから直接埋める
        // （写した先は GC が走査しないため。§3.5）
        return b.rt.makeVectorFromList(list.head, list.count);
    }
};

/// テキストから全てのデータを読み、読んだ順のリスト（Lisp の値）で返す（試験用）。
/// 読んでいる間は、それまでに読んだデータを明示的なルートに登録しておく（Zig のヒープには置かない：§3.5）。
/// 返したリストは、呼び出し側が生かしておくこと（ネイティブのスタックにある値は GC のルートになる）。
pub fn readAll(rt: *Runtime, gpa: std.mem.Allocator, text: []const u8, diag: *Diagnostic) Error!Value {
    var src = reader.Source.init(text, 0);
    var b: ValueBuilder = .{ .rt = rt };
    var r = reader.Reader(ValueBuilder).init(gpa, &src, &b, .{});
    defer r.deinit();
    const root = try rt.roots.register(Value.nil);
    defer _ = rt.roots.unregister(root);
    var last = Value.nil;
    while (true) {
        const v = r.read() catch |err| {
            diag.* = r.diagnostic;
            return err;
        } orelse break;
        const c = try rt.cons(v, Value.nil);
        if (last == Value.nil) {
            _ = rt.roots.set(root, c);
        } else {
            Runtime.consPtr(last).cdr = c;
        }
        last = c;
    }
    return rt.roots.get(root).?;
}

const testing = std.testing;

test "vectors and lists of heap objects survive collection during reading (gc stress)" {
    const rt = try Runtime.create(testing.allocator);
    defer rt.destroy();
    // 走査の上端はこの関数のフレーム。値を扱う本体は inline 展開しない別の関数で行う（gc.zig の withRuntime と同じ）
    rt.stack_top = @frameAddress();
    try @call(.never_inline, readVectorsUnderStress, .{rt});
}

fn readVectorsUnderStress(rt: *Runtime) !void {
    rt.heap.stress = true;
    defer rt.heap.stress = false;
    var diag: Diagnostic = .{};
    const text = "#(\"a\" #:b (c \"d\") 1.5d0 #(\"e\")) (\"f\" #:g) \"h\"";
    var x = try readAll(rt, testing.allocator, text, &diag);
    rt.heap.stress = false;
    rt.collect();
    rt.heap.finishSweep();
    var out: std.Io.Writer.Allocating = .init(testing.allocator);
    defer out.deinit();
    const printer = @import("../printer/printer.zig");
    while (x != Value.nil) : (x = Runtime.consPtr(x).cdr) {
        try printer.prin1(rt, &out.writer, Runtime.consPtr(x).car);
        try out.writer.writeByte(' ');
    }
    try testing.expectEqualStrings("#(\"a\" #:B (C \"d\") 1.5d0 #(\"e\")) (\"f\" #:G) \"h\" ", out.written());
}
