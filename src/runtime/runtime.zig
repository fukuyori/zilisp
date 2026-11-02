//! 処理系の実行時の状態（ヒープ、パッケージ、よく使うシンボル）と、オブジェクトを扱う基本の関数。
//! パッケージは詳細設計 §8.2・§8.3。名前の衝突の検出（use-package・import 等）は Phase 22 で実装する。

const std = @import("std");
const value_mod = @import("../values/value.zig");
const object = @import("../values/object.zig");
const heap_mod = @import("heap.zig");
const roots_mod = @import("roots.zig");
const cl_symbols = @import("cl_symbols.zig");
const thread_mod = @import("thread.zig");
const primitives = @import("../primitives/primitives.zig");

pub const Value = value_mod.Value;
pub const ObjKind = object.ObjKind;
pub const Symbol = object.Symbol;
pub const SymbolFlags = object.SymbolFlags;

pub const Error = error{OutOfMemory};

/// 処理系がよく使う CL のシンボル（起動時に引いておく）。フィールド名と CL の名前の対応は sym_names
pub const Syms = struct {
    quote: Value,
    @"if": Value,
    progn: Value,
    let: Value,
    @"let*": Value,
    setq: Value,
    lambda: Value,
    function: Value,
    declare: Value,
    defun: Value,
    defmacro: Value,
    @"eval-when": Value,
    values: Value,
    @"multiple-value-bind": Value,
    @"multiple-value-list": Value,
    @"multiple-value-prog1": Value,
    @"multiple-value-call": Value,
    setf: Value,
    compile: Value,
    load: Value,
    eval: Value,
    @"destructuring-bind": Value,
    defvar: Value,
    defparameter: Value,
    progv: Value,
    boundp: Value,
    flet: Value,
    labels: Value,
    block: Value,
    @"return-from": Value,
    @"catch": Value,
    throw: Value,
    @"unwind-protect": Value,
    tagbody: Value,
    go: Value,
    // ラムダリストのキーワード
    @"&optional": Value,
    @"&rest": Value,
    @"&key": Value,
    @"&aux": Value,
    @"&body": Value,
    @"&whole": Value,
    @"&environment": Value,
    @"&allow-other-keys": Value,
    // 宣言
    special: Value,
    ignore: Value,
    ignorable: Value,
    type: Value,
    ftype: Value,
    optimize: Value,
    @"inline": Value,
    notinline: Value,
    @"dynamic-extent": Value,
    // 型の名前（type-error の期待する型）
    list: Value,
    number: Value,
    real: Value,
    symbol: Value,
    integer: Value,
    cons: Value,
    // 高速経路にする関数（§7.4）
    car: Value,
    cdr: Value,
    eq: Value,
    null: Value,
    not: Value,
    @"+": Value,
    @"-": Value,
    @"<": Value,
    @">": Value,
    @"<=": Value,
    @">=": Value,
    @"=": Value,
    @"1+": Value,
    @"1-": Value,
    funcall: Value,
};

/// main が記録するスタックの先頭（Windows 以外で、GC の保守的走査の範囲に使う。§3.4）
pub var main_stack_top: usize = 0;

const gc = @import("gc.zig");

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
    /// 明示的なルート（§3.5）
    roots: roots_mod.Roots,
    /// FFI handle（§3.6）
    handles: roots_mod.Roots,
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
    /// GC の停止時間の計測に使う（null なら計測しない）
    io: ?std.Io = null,
    /// GC の保守的走査の範囲の上端（0 なら OS から取得する。試験で明示的に設定する）
    stack_top: usize = 0,
    /// よく使う CL のシンボル
    syms: Syms = undefined,
    /// ZILISP-SYSTEM::%DEFUN（defun の展開先。関数をシンボルの関数セルに置く）
    sys_defun: Value = Value.nil,
    /// ZILISP-SYSTEM::%PROCLAIM-SPECIAL（defvar・defparameter の展開先。実行した時点で特殊変数と宣言する）
    sys_proclaim_special: Value = Value.nil,
    /// ZILISP-SYSTEM::%DEFMACRO（defmacro の展開先）
    sys_defmacro: Value = Value.nil,
    /// ZILISP-SYSTEM::%SET-FDEFINITION（(defun (setf 名前) ...) の展開先）
    sys_set_fdefinition: Value = Value.nil,
    /// ZILISP-SYSTEM:QUASIQUOTE（Reader が backquote を読んだ形）
    sys_quasiquote: Value = Value.nil,
    /// ZILISP-SYSTEM::%MISSING（分解束縛で、キーワード引数がないことを表す印）
    sys_missing: Value = Value.nil,
    /// ZILISP-SYSTEM::%TOMBSTONE（ハッシュ表の削除した枠の印）
    sys_tombstone: Value = Value.nil,
    /// 標準ライブラリ（src/lisp/boot.lisp）を読み込んでいる間は真（CL のシンボルにマクロ・関数を定義してよい）
    booting: bool = false,
    /// 実行中のスレッド（GC のルートとして走査する。1.0 は単一スレッド）
    thread: ?*thread_mod.Thread = null,

    pub fn create(gpa: std.mem.Allocator) Error!*Runtime {
        const rt = try gpa.create(Runtime);
        errdefer gpa.destroy(rt);
        rt.* = .{
            .gpa = gpa,
            .heap = heap_mod.Heap.init(gpa),
            .roots = roots_mod.Roots.init(gpa),
            .handles = roots_mod.Roots.init(gpa),
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
        // 起動時の初期化が終わってから GC を有効にする
        rt.heap.gc_hook = .{ .ctx = rt, .collect = collectThunk };
        return rt;
    }

    fn collectThunk(ctx: *anyopaque) void {
        gc.collect(@ptrCast(@alignCast(ctx)));
    }

    /// GC を行う
    pub fn collect(rt: *Runtime) void {
        gc.collect(rt);
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
        rt.roots.deinit();
        rt.handles.deinit();
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
                .function => so.header.flags |= SymbolFlags.unimplemented,
                // マクロと特殊演算子は、種類の印も付ける（Resolver が「未実装」の理由を示すため）
                .macro => so.header.flags |= SymbolFlags.unimplemented | SymbolFlags.macro,
                .special_operator => so.header.flags |= SymbolFlags.unimplemented | SymbolFlags.special_operator,
                .other => {},
            }
        }
        rt.t = (rt.findSymbol(rt.cl, "T") orelse unreachable).symbol;
        rt.symbolPtr(rt.t).value = rt.t;

        inline for (@typeInfo(Syms).@"struct".field_names) |field| {
            const name = comptime upperName(field);
            @field(rt.syms, field) = (rt.findSymbol(rt.cl, name) orelse @panic("CL のシンボルがありません: " ++ name)).symbol;
        }
        try primitives.install(rt);
        try rt.setStandardConstants();

        for ([_][]const u8{ "QUASIQUOTE", "UNQUOTE", "UNQUOTE-SPLICING", "UNQUOTE-NSPLICING" }) |n| {
            const s = try rt.intern(rt.sys, n);
            try rt.exportSymbol(rt.sys, s);
        }
    }

    /// 必要な確保をすべて済ませてから、パッケージの一覧に登録する（途中で失敗しても一覧は変わらない）
    fn makePackage(rt: *Runtime, name: []const u8, nicknames: []const []const u8) Error!*PackageData {
        const p = try rt.gpa.create(PackageData);
        errdefer rt.gpa.destroy(p);
        const name_copy = try rt.gpa.dupe(u8, name);
        errdefer rt.gpa.free(name_copy);
        const nicks = try rt.gpa.alloc([]const u8, nicknames.len);
        errdefer rt.gpa.free(nicks);
        var copied: usize = 0;
        errdefer for (nicks[0..copied]) |n| rt.gpa.free(n);
        for (nicknames, 0..) |n, i| {
            nicks[i] = try rt.gpa.dupe(u8, n);
            copied = i + 1;
        }
        try rt.packages.ensureUnusedCapacity(rt.gpa, 1);
        const obj = try rt.heap.create(object.Package, 0);
        p.* = .{ .name = name_copy, .nicknames = nicks };
        obj.* = .{ .header = .{ .kind = .package }, .data = p };
        p.obj = Value.fromPointer(obj, .other);
        rt.packages.appendAssumeCapacity(p);
        return p;
    }

    /// 表に名前とシンボルを入れる。キーは表が所有する複製。失敗しても表は変わらない
    fn putSymbol(rt: *Runtime, table: *std.StringHashMapUnmanaged(Value), name: []const u8, sym: Value) Error!void {
        if (table.getPtr(name)) |v| {
            v.* = sym;
            return;
        }
        const key = try rt.gpa.dupe(u8, name);
        errdefer rt.gpa.free(key);
        try table.put(rt.gpa, key, sym);
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

    /// 値の表現で決まる CL の定数に値を置く（他の定数・変数は、その機能を実装する Phase で設定する）。
    /// 値は処理系依存（tests/differential/impl-dependent.toml に SBCL との違いを記録）
    fn setStandardConstants(rt: *Runtime) Error!void {
        const thread_mod2 = @import("thread.zig");
        const fixnums = [_]struct { []const u8, i64 }{
            .{ "MOST-POSITIVE-FIXNUM", value_mod.most_positive_fixnum },
            .{ "MOST-NEGATIVE-FIXNUM", value_mod.most_negative_fixnum },
            .{ "CALL-ARGUMENTS-LIMIT", thread_mod2.call_arguments_limit },
            .{ "LAMBDA-PARAMETERS-LIMIT", 1024 },
            .{ "MULTIPLE-VALUES-LIMIT", thread_mod2.mv_limit },
            .{ "CHAR-CODE-LIMIT", 0x110000 },
        };
        for (fixnums) |c| rt.symbolPtr((rt.findSymbol(rt.cl, c[0]) orelse unreachable).symbol).value = Value.fromFixnum(c[1]);
        // pi は long-float。Zilisp の long-float は double-float と同じ（CLHS 12.1.4.1.1 で許される）
        rt.symbolPtr((rt.findSymbol(rt.cl, "PI") orelse unreachable).symbol).value = try rt.makeDouble(std.math.pi);
    }

    /// Zig の真偽値を T・NIL にする
    pub inline fn boolean(rt: *const Runtime, b: bool) Value {
        return if (b) rt.t else Value.nil;
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
        // 先にオブジェクトを作り、そのオブジェクトが持つバッファを確保する（バッファの確保では GC は起きない）
        const s = try rt.heap.create(object.String, 0);
        s.* = .{ .header = .{ .kind = .string, .aux = width, .len = @intCast(count) }, .data = undefined };
        const buf = try rt.heap.allocOwnedBuffer(s, count * width);
        s.data = buf.ptr;
        it = (std.unicode.Utf8View.init(utf8) catch unreachable).iterator();
        var i: usize = 0;
        while (it.nextCodepoint()) |cp| : (i += 1) {
            if (wide) {
                const p: [*]u32 = @ptrCast(@alignCast(buf.ptr));
                p[i] = cp;
            } else buf[i] = @intCast(cp);
        }
        return Value.fromPointer(s, .other);
    }

    /// 長さ n の文字列を作り、文字 cp で埋める（make-array :element-type 'character）
    pub fn makeStringFilled(rt: *Runtime, n: usize, cp: u21) Error!Value {
        const width: u16 = if (cp > 0xFF) 4 else 1;
        const s = try rt.heap.create(object.String, 0);
        s.* = .{ .header = .{ .kind = .string, .aux = width, .len = @intCast(n) }, .data = undefined };
        const buf = try rt.heap.allocOwnedBuffer(s, n * width);
        s.data = buf.ptr;
        var i: usize = 0;
        while (i < n) : (i += 1) {
            if (width == 4) {
                const p: [*]u32 = @ptrCast(@alignCast(buf.ptr));
                p[i] = cp;
            } else buf[i] = @intCast(cp);
        }
        return Value.fromPointer(s, .other);
    }

    /// 文字列の i 番目の文字を cp にする。幅 1 の文字列に #xFF を超える文字を書くときは、幅 4 のバッファに写す
    /// （古いバッファは、文字列が回収されるときに一緒に解放される）
    pub fn stringSetChar(rt: *Runtime, v: Value, i: usize, cp: u21) Error!void {
        const s = stringPtr(v);
        if (s.width() == 1 and cp > 0xFF) {
            const n = s.length();
            const buf = try rt.heap.allocOwnedBuffer(s, n * 4);
            const p: [*]u32 = @ptrCast(@alignCast(buf.ptr));
            for (0..n) |k| p[k] = s.data[k];
            s.data = buf.ptr;
            s.header.aux = 4;
        }
        if (s.width() == 4) {
            const p: [*]u32 = @ptrCast(@alignCast(s.data));
            p[i] = cp;
        } else s.data[i] = @intCast(cp);
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

    /// リスト `list`（長さ `len`）の要素からベクタを作る。確保の間、list は呼び出し側が保持していること
    /// （この関数の引数として生きているので、ネイティブのスタックかレジスタにある：§3.4）
    pub fn makeVectorFromList(rt: *Runtime, list: Value, len: usize) Error!Value {
        const v = try rt.heap.create(object.SimpleVector, len * @sizeOf(Value));
        v.header = .{ .kind = .simple_vector, .len = @intCast(len) };
        var x = list;
        for (v.items()) |*it| {
            const c = consPtr(x);
            it.* = c.car;
            x = c.cdr;
        }
        std.debug.assert(x == Value.nil);
        return Value.fromPointer(v, .other);
    }

    /// 長さ n の単純ベクタを作り、v で埋める
    pub fn makeVectorFilled(rt: *Runtime, n: usize, v: Value) Error!Value {
        const vec = try rt.heap.create(object.SimpleVector, n * @sizeOf(Value));
        vec.header = .{ .kind = .simple_vector, .len = @intCast(n) };
        @memset(vec.items(), v);
        return Value.fromPointer(vec, .other);
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
        // 外部の表に入れてから内部の表から除く（途中で失敗してもシンボルを失わない）
        try rt.putSymbol(&pkg.external, name, sym);
        if (pkg.internal.fetchRemove(name)) |kv| rt.gpa.free(kv.key);
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
    // 実装済みのプリミティブは「未実装」の印が外れ、まだのものは残る
    try testing.expect(!rt.symbolPtr(car.symbol).hasFlag(SymbolFlags.unimplemented));
    try testing.expect(rt.symbolPtr(rt.findSymbol(rt.cl, "MAPCAR").?.symbol).hasFlag(SymbolFlags.unimplemented));
    try testing.expect(rt.symbolPtr(rt.syms.let).hasFlag(SymbolFlags.special_operator));
    try testing.expectEqual(Value.nil, rt.findSymbol(rt.cl_user, "NIL").?.symbol);
    try testing.expect(rt.symbolPtr(rt.t).value == rt.t);
}

fn createAndDestroy(gpa: std.mem.Allocator) !void {
    const rt = try Runtime.create(gpa);
    rt.destroy();
}

test "allocation failure at any point of bootstrap frees everything" {
    try testing.checkAllAllocationFailures(testing.allocator, createAndDestroy, .{});
}

fn internAndExport(gpa: std.mem.Allocator, rt: *Runtime) !void {
    _ = gpa;
    const s = try rt.intern(rt.cl_user, "NEW-SYMBOL-FOR-OOM-TEST");
    try rt.exportSymbol(rt.cl_user, s);
}

test "allocation failure in intern and export keeps the tables consistent" {
    var i: usize = 0;
    while (true) : (i += 1) {
        var failing = testing.FailingAllocator.init(testing.allocator, .{ .fail_index = std.math.maxInt(usize) });
        const rt = try Runtime.create(failing.allocator());
        defer rt.destroy();
        // 起動が終わってから i 回目の確保を失敗させる
        failing.fail_index = failing.alloc_index + i;
        internAndExport(failing.allocator(), rt) catch |err| {
            try testing.expectEqual(error.OutOfMemory, err);
            // 失敗しても、表は壊れていない（あるなら正しいシンボルを指す）
            if (rt.findSymbol(rt.cl_user, "NEW-SYMBOL-FOR-OOM-TEST")) |f| {
                try testing.expect(Runtime.kindOf(f.symbol) == .symbol);
            }
            continue;
        };
        try testing.expectEqual(SymbolStatus.external, rt.findSymbol(rt.cl_user, "NEW-SYMBOL-FOR-OOM-TEST").?.status);
        break;
    }
    try testing.expect(i > 0);
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

/// Syms のフィールド名を CL のシンボル名にする（大文字に）
fn upperName(comptime name: []const u8) []const u8 {
    comptime {
        @setEvalBranchQuota(10000);
        var buf: [name.len]u8 = undefined;
        for (name, 0..) |c, i| buf[i] = std.ascii.toUpper(c);
        const out = buf;
        return &out;
    }
}
