//! 処理系の実行時の状態（ヒープ、パッケージ、よく使うシンボル）と、オブジェクトを扱う基本の関数。
//! パッケージは詳細設計 §8.2・§8.3。名前の衝突の検出（use-package・import 等）は Phase 22 で実装する。

const std = @import("std");
const value_mod = @import("../values/value.zig");
const object = @import("../values/object.zig");
const heap_mod = @import("heap.zig");
const cl_symbols = @import("cl_symbols.zig");

pub const Value = value_mod.Value;
pub const ObjKind = object.ObjKind;
pub const Symbol = object.Symbol;
pub const SymbolFlags = object.SymbolFlags;

pub const Error = error{OutOfMemory};

pub const PackageData = struct {
    name: []const u8,
    nicknames: []const []const u8,
    internal: std.StringHashMapUnmanaged(Value) = .empty,
    external: std.StringHashMapUnmanaged(Value) = .empty,
    use_list: std.ArrayList(*PackageData) = .empty,
    /// このパッケージを表す Lisp のオブジェクト
    obj: Value = Value.nil,
};

pub const SymbolStatus = enum { internal, external, inherited };

pub const Found = struct { symbol: Value, status: SymbolStatus };

pub const Runtime = struct {
    gpa: std.mem.Allocator,
    heap: heap_mod.Heap,
    packages: std.ArrayList(*PackageData) = .empty,
    /// NIL の名前・属性リストなどを持つシンボルの実体（値としての NIL は即値 Value.nil）
    nil_symbol: *Symbol,
    t: Value,
    cl: *PackageData,
    cl_user: *PackageData,
    keyword: *PackageData,
    zilisp: *PackageData,
    sys: *PackageData,
    /// *package*
    current: *PackageData,

    pub fn create(gpa: std.mem.Allocator) Error!*Runtime {
        const rt = try gpa.create(Runtime);
        errdefer gpa.destroy(rt);
        rt.* = .{
            .gpa = gpa,
            .heap = heap_mod.Heap.init(gpa),
            .nil_symbol = undefined,
            .t = Value.nil,
            .cl = undefined,
            .cl_user = undefined,
            .keyword = undefined,
            .zilisp = undefined,
            .sys = undefined,
            .current = undefined,
        };
        errdefer rt.destroy0();
        try rt.bootstrap();
        return rt;
    }

    fn destroy0(rt: *Runtime) void {
        for (rt.packages.items) |p| {
            freeTable(rt.gpa, &p.internal);
            freeTable(rt.gpa, &p.external);
            p.use_list.deinit(rt.gpa);
            for (p.nicknames) |n| rt.gpa.free(n);
            rt.gpa.free(p.nicknames);
            rt.gpa.free(p.name);
            rt.gpa.destroy(p);
        }
        rt.packages.deinit(rt.gpa);
        rt.heap.deinit();
    }

    pub fn destroy(rt: *Runtime) void {
        const gpa = rt.gpa;
        rt.destroy0();
        gpa.destroy(rt);
    }

    fn freeTable(gpa: std.mem.Allocator, t: *std.StringHashMapUnmanaged(Value)) void {
        var it = t.keyIterator();
        while (it.next()) |k| gpa.free(k.*);
        t.deinit(gpa);
    }

    // ------------------------------------------------------------------
    // 起動時の初期化（詳細設計 §11.1 の 2〜3）

    fn bootstrap(rt: *Runtime) Error!void {
        rt.cl = try rt.makePackage("COMMON-LISP", &.{"CL"});
        rt.cl_user = try rt.makePackage("COMMON-LISP-USER", &.{"CL-USER"});
        rt.keyword = try rt.makePackage("KEYWORD", &.{});
        rt.zilisp = try rt.makePackage("ZILISP", &.{"ZL"});
        rt.sys = try rt.makePackage("ZILISP-SYSTEM", &.{"ZL-SYS"});
        for ([_]*PackageData{ rt.cl_user, rt.zilisp, rt.sys }) |p| try p.use_list.append(rt.gpa, rt.cl);
        rt.current = rt.cl_user;

        // NIL のシンボルの実体（パッケージの表には即値の Value.nil を入れる）
        const nil_name = try rt.makeString("NIL");
        rt.nil_symbol = try rt.heap.create(Symbol, 0);
        rt.nil_symbol.* = .{
            .header = .{ .kind = .symbol, .flags = SymbolFlags.constant },
            .name = nil_name,
            .package = rt.cl.obj,
            .value = Value.nil,
            .function = Value.unbound,
            .setf_function = Value.unbound,
            .plist = Value.nil,
            .fast_entry = 0,
        };

        for (cl_symbols.symbols) |e| {
            const s = if (std.mem.eql(u8, e.name, "NIL")) blk: {
                try rt.putSymbol(&rt.cl.external, "NIL", Value.nil);
                break :blk Value.nil;
            } else blk: {
                const sym = try rt.makeSymbolWithPackage(e.name, rt.cl.obj);
                try rt.putSymbol(&rt.cl.external, e.name, sym);
                break :blk sym;
            };
            const so = rt.symbolPtr(s);
            switch (e.kind) {
                .constant => so.header.flags |= SymbolFlags.constant,
                .variable => so.header.flags |= SymbolFlags.special,
                // 関数・マクロ・特殊演算子は、実装するまで「未実装」とする（詳細設計 §8.1）
                .function, .macro, .special_operator => so.header.flags |= SymbolFlags.unimplemented,
                .other => {},
            }
        }
        rt.t = (rt.findSymbol(rt.cl, "T") orelse unreachable).symbol;
        rt.symbolPtr(rt.t).value = rt.t;

        for ([_][]const u8{ "QUASIQUOTE", "UNQUOTE", "UNQUOTE-SPLICING", "UNQUOTE-NSPLICING" }) |n| {
            const s = try rt.intern(rt.sys, n);
            try rt.exportSymbol(rt.sys, s);
        }
    }

    fn makePackage(rt: *Runtime, name: []const u8, nicknames: []const []const u8) Error!*PackageData {
        const p = try rt.gpa.create(PackageData);
        errdefer rt.gpa.destroy(p);
        const nicks = try rt.gpa.alloc([]const u8, nicknames.len);
        for (nicknames, 0..) |n, i| nicks[i] = try rt.gpa.dupe(u8, n);
        p.* = .{ .name = try rt.gpa.dupe(u8, name), .nicknames = nicks };
        try rt.packages.append(rt.gpa, p);
        const obj = try rt.heap.create(object.Package, 0);
        obj.* = .{ .header = .{ .kind = .package }, .data = p };
        p.obj = Value.fromPointer(obj, .other);
        return p;
    }

    fn putSymbol(rt: *Runtime, table: *std.StringHashMapUnmanaged(Value), name: []const u8, sym: Value) Error!void {
        const gop = try table.getOrPut(rt.gpa, name);
        if (!gop.found_existing) gop.key_ptr.* = try rt.gpa.dupe(u8, name);
        gop.value_ptr.* = sym;
    }

    // ------------------------------------------------------------------
    // オブジェクト

    pub fn kindOf(v: Value) ?ObjKind {
        if (!v.isOther()) return null;
        const h: *object.ObjHeader = @ptrCast(@alignCast(v.pointer()));
        return h.kind;
    }

    pub fn cons(rt: *Runtime, car: Value, cdr: Value) Error!Value {
        return rt.heap.cons(car, cdr);
    }

    pub fn consPtr(v: Value) *object.Cons {
        return @ptrCast(@alignCast(v.pointer()));
    }

    pub fn makeDouble(rt: *Runtime, f: f64) Error!Value {
        const d = try rt.heap.create(object.DoubleFloat, 0);
        d.* = .{ .header = .{ .kind = .double_float }, .value = f };
        return Value.fromPointer(d, .other);
    }

    pub fn doubleValue(v: Value) f64 {
        const d: *object.DoubleFloat = @ptrCast(@alignCast(v.pointer()));
        return d.value;
    }

    /// UTF-8 から文字列を作る（呼び出し側で UTF-8 として正しいことを保証する）
    pub fn makeString(rt: *Runtime, utf8: []const u8) Error!Value {
        var count: usize = 0;
        var wide = false;
        var it = (std.unicode.Utf8View.init(utf8) catch unreachable).iterator();
        while (it.nextCodepoint()) |cp| {
            count += 1;
            if (cp > 0xFF) wide = true;
        }
        const width: u16 = if (wide) 4 else 1;
        const buf = try rt.heap.allocBytes(count * width);
        it = (std.unicode.Utf8View.init(utf8) catch unreachable).iterator();
        var i: usize = 0;
        while (it.nextCodepoint()) |cp| : (i += 1) {
            if (wide) {
                const p: [*]u32 = @ptrCast(@alignCast(buf.ptr));
                p[i] = cp;
            } else buf[i] = @intCast(cp);
        }
        const s = try rt.heap.create(object.String, 0);
        s.* = .{ .header = .{ .kind = .string, .aux = width, .len = @intCast(count) }, .data = buf.ptr };
        return Value.fromPointer(s, .other);
    }

    pub fn stringPtr(v: Value) *object.String {
        return @ptrCast(@alignCast(v.pointer()));
    }

    /// 文字列の内容を UTF-8 で書き出す
    pub fn writeStringUtf8(v: Value, w: *std.Io.Writer) std.Io.Writer.Error!void {
        const s = stringPtr(v);
        var i: usize = 0;
        while (i < s.length()) : (i += 1) {
            var b: [4]u8 = undefined;
            const n = std.unicode.utf8Encode(s.charAt(i), &b) catch unreachable;
            try w.writeAll(b[0..n]);
        }
    }

    pub fn makeVector(rt: *Runtime, items: []const Value) Error!Value {
        const v = try rt.heap.create(object.SimpleVector, items.len * @sizeOf(Value));
        v.header = .{ .kind = .simple_vector, .len = @intCast(items.len) };
        @memcpy(v.items(), items);
        return Value.fromPointer(v, .other);
    }

    pub fn vectorPtr(v: Value) *object.SimpleVector {
        return @ptrCast(@alignCast(v.pointer()));
    }

    // ------------------------------------------------------------------
    // シンボル

    pub fn isSymbol(v: Value) bool {
        return v == Value.nil or kindOf(v) == .symbol;
    }

    pub fn symbolPtr(rt: *Runtime, v: Value) *Symbol {
        if (v == Value.nil) return rt.nil_symbol;
        std.debug.assert(kindOf(v) == .symbol);
        return @ptrCast(@alignCast(v.pointer()));
    }

    fn makeSymbolWithPackage(rt: *Runtime, name: []const u8, pkg: Value) Error!Value {
        const n = try rt.makeString(name);
        const s = try rt.heap.create(Symbol, 0);
        s.* = .{
            .header = .{ .kind = .symbol },
            .name = n,
            .package = pkg,
            .value = Value.unbound,
            .function = Value.unbound,
            .setf_function = Value.unbound,
            .plist = Value.nil,
            .fast_entry = 0,
        };
        return Value.fromPointer(s, .other);
    }

    /// uninterned のシンボル（make-symbol、#:name）
    pub fn makeSymbol(rt: *Runtime, name: []const u8) Error!Value {
        return rt.makeSymbolWithPackage(name, Value.nil);
    }

    // ------------------------------------------------------------------
    // パッケージ

    pub fn packageData(v: Value) *PackageData {
        const p: *object.Package = @ptrCast(@alignCast(v.pointer()));
        return @ptrCast(@alignCast(p.data));
    }

    /// 名前または別名でパッケージを探す（大文字小文字を区別する）
    pub fn findPackage(rt: *Runtime, name: []const u8) ?*PackageData {
        for (rt.packages.items) |p| {
            if (std.mem.eql(u8, p.name, name)) return p;
            for (p.nicknames) |n| if (std.mem.eql(u8, n, name)) return p;
        }
        return null;
    }

    /// find-symbol（CLHS 11.1.1.2 の探索順序）
    pub fn findSymbol(rt: *Runtime, pkg: *PackageData, name: []const u8) ?Found {
        _ = rt;
        if (pkg.external.get(name)) |s| return .{ .symbol = s, .status = .external };
        if (pkg.internal.get(name)) |s| return .{ .symbol = s, .status = .internal };
        for (pkg.use_list.items) |u| {
            if (u.external.get(name)) |s| return .{ .symbol = s, .status = .inherited };
        }
        return null;
    }

    /// intern。見つからなければ、そのパッケージの内部シンボルとして作る
    pub fn intern(rt: *Runtime, pkg: *PackageData, name: []const u8) Error!Value {
        if (rt.findSymbol(pkg, name)) |f| return f.symbol;
        if (pkg == rt.keyword) return rt.internKeyword(name);
        const s = try rt.makeSymbolWithPackage(name, pkg.obj);
        try rt.putSymbol(&pkg.internal, name, s);
        return s;
    }

    /// キーワード（KEYWORD の外部シンボル。値は自分自身の定数）
    pub fn internKeyword(rt: *Runtime, name: []const u8) Error!Value {
        if (rt.keyword.external.get(name)) |s| return s;
        const s = try rt.makeSymbolWithPackage(name, rt.keyword.obj);
        const so = rt.symbolPtr(s);
        so.value = s;
        so.header.flags |= SymbolFlags.constant | SymbolFlags.keyword;
        try rt.putSymbol(&rt.keyword.external, name, s);
        return s;
    }

    /// export（名前の衝突の検査は Phase 22 で追加する）
    pub fn exportSymbol(rt: *Runtime, pkg: *PackageData, sym: Value) Error!void {
        const name_v = rt.symbolPtr(sym).name;
        var buf: std.Io.Writer.Allocating = .init(rt.gpa);
        defer buf.deinit();
        writeStringUtf8(name_v, &buf.writer) catch return error.OutOfMemory;
        const name = buf.written();
        if (pkg.internal.fetchRemove(name)) |kv| rt.gpa.free(kv.key);
        try rt.putSymbol(&pkg.external, name, sym);
    }
};

const testing = std.testing;

test "bootstrap creates standard packages and 978 CL symbols" {
    const rt = try Runtime.create(testing.allocator);
    defer rt.destroy();
    try testing.expectEqual(@as(u32, 978), rt.cl.external.count());
    try testing.expect(rt.findPackage("CL") == rt.cl);
    try testing.expect(rt.findPackage("CL-USER") == rt.cl_user);
    try testing.expect(rt.findPackage("cl") == null);
    const car = rt.findSymbol(rt.cl_user, "CAR").?;
    try testing.expectEqual(SymbolStatus.inherited, car.status);
    try testing.expect(rt.symbolPtr(car.symbol).hasFlag(SymbolFlags.unimplemented));
    try testing.expectEqual(Value.nil, rt.findSymbol(rt.cl_user, "NIL").?.symbol);
    try testing.expect(rt.symbolPtr(rt.t).value == rt.t);
}

test "intern identity (eq)" {
    const rt = try Runtime.create(testing.allocator);
    defer rt.destroy();
    const a = try rt.intern(rt.cl_user, "FOO");
    const b = try rt.intern(rt.cl_user, "FOO");
    try testing.expectEqual(a, b);
    const c = try rt.intern(rt.cl_user, "foo");
    try testing.expect(a != c);
    try testing.expectEqual(SymbolStatus.internal, rt.findSymbol(rt.cl_user, "FOO").?.status);
    const uninterned = try rt.makeSymbol("FOO");
    try testing.expect(uninterned != a);
    const k1 = try rt.internKeyword("KW");
    try testing.expectEqual(k1, try rt.intern(rt.keyword, "KW"));
    try testing.expectEqual(k1, rt.symbolPtr(k1).value);
}

test "export makes symbol external" {
    const rt = try Runtime.create(testing.allocator);
    defer rt.destroy();
    const s = try rt.intern(rt.zilisp, "EXIT");
    try rt.exportSymbol(rt.zilisp, s);
    try testing.expectEqual(SymbolStatus.external, rt.findSymbol(rt.zilisp, "EXIT").?.status);
    try testing.expect(rt.findSymbol(rt.cl_user, "EXIT") == null);
}

test "strings narrow and wide" {
    const rt = try Runtime.create(testing.allocator);
    defer rt.destroy();
    const a = try rt.makeString("abc");
    try testing.expectEqual(@as(u16, 1), Runtime.stringPtr(a).width());
    const b = try rt.makeString("日本λ");
    try testing.expectEqual(@as(u16, 4), Runtime.stringPtr(b).width());
    try testing.expectEqual(@as(usize, 3), Runtime.stringPtr(b).length());
    try testing.expectEqual(@as(u21, 'λ'), Runtime.stringPtr(b).charAt(2));
}
