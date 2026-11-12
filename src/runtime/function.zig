//! 関数オブジェクト（詳細設計 §2.4・§6.2）。
//!
//! - closure と native_function は function タグの Value で表し、ヘッダの直後に**入口アドレス**を置く
//!   （§6.2：すべての関数オブジェクトで同じ位置。呼び出し側は種類を調べずに入口を呼べる）。
//! - code は、同じ lambda から作った closure すべてが共有するバイトコードと定数表（other タグ）。
//!
//! 入口の規約（§6.2 案 A）：主値だけを返す。個数は th.mv_count に書く。
//! エラー・非局所脱出は Value.unwind を返し、理由を th.fault に置く。

const std = @import("std");
const object = @import("../values/object.zig");
const Value = @import("../values/value.zig").Value;
const ObjHeader = object.ObjHeader;
const Thread = @import("thread.zig").Thread;
const Runtime = @import("runtime.zig").Runtime;
const Error = @import("runtime.zig").Error;

/// 汎用の入口（すべての関数オブジェクトで同じ型。§6.2）
pub const Entry = *const fn (th: *Thread, self: Value, args: [*]const Value, nargs: u32) callconv(.c) Value;

/// プリミティブの本体。引数の個数は、入口（nativeEntry）または VM が検査してから呼ぶ。
/// 引数の領域は呼び出し側のもの（VM の値スタックなど）で、GC のルートとして走査される。
pub const Impl = *const fn (th: *Thread, args: []const Value) Value;

/// 関数オブジェクトに共通する先頭の形
pub const FunctionHeader = extern struct {
    header: ObjHeader,
    entry: Entry,
};

pub const GenericFunction = extern struct {
    header: ObjHeader,
    entry: Entry,
    name: Value,
    dispatcher: Value,
    descriptor: Value,
};

pub fn genericPtr(v: Value) *GenericFunction {
    return @ptrCast(@alignCast(v.pointer()));
}

pub fn genericEntry(th: *Thread, self: Value, args: [*]const Value, nargs: u32) callconv(.c) Value {
    return th.call(genericPtr(self).dispatcher, args[0..nargs]);
}

/// バイトコードと定数表。header.len はバイトコードのバイト数
pub const Code = extern struct {
    header: ObjHeader,
    /// バイトコード（allocOwnedBuffer で確保。Code が回収されると解放される）
    bytecode: [*]u8,
    /// 定数表（simple-vector。定数がなければ NIL）
    consts: Value,
    /// 印字用の名前。lambda なら (LAMBDA ラムダリスト)
    name: Value,
    /// 必須の引数の個数
    nparams: u32,
    /// 局所変数の数（引数を含む）
    nlocals: u32,
    /// 捕捉する値の数
    ncaptured: u32,
    /// 値スタックの最大の深さ（局所変数を除く）
    max_stack: u32,
    /// 真なら、必須の引数（nparams 個）の後ろの引数をリストにまとめて、局所変数 nparams に置く（Phase 17）
    rest: bool = false,
    _pad: [7]u8 = @splat(0),

    pub fn code(c: *const Code) []const u8 {
        return c.bytecode[0..c.header.len];
    }
    pub fn constants(c: *const Code) []Value {
        if (c.consts == Value.nil) return &.{};
        return Runtime.vectorPtr(c.consts).items();
    }
};

/// VM の closure。header.len は捕捉した値の数。捕捉した値は構造体の直後に並べる
pub const Closure = extern struct {
    header: ObjHeader,
    entry: Entry,
    code: Value,

    pub fn captured(c: *Closure) []Value {
        const base: [*]Value = @ptrCast(@alignCast(@as([*]u8, @ptrCast(c)) + @sizeOf(Closure)));
        return base[0..c.header.len];
    }
    pub fn codePtr(c: *const Closure) *Code {
        return @ptrCast(@alignCast(c.code.pointer()));
    }
};

/// 引数の個数の上限なし
pub const any_args: u32 = std.math.maxInt(u32);

/// Zig で書いたプリミティブ
pub const NativeFunction = extern struct {
    header: ObjHeader,
    entry: Entry,
    /// 名前（シンボル）
    name: Value,
    /// 本体（Impl。extern struct に Zig の呼び出し規約の関数ポインタを置けないため、アドレスで持つ）
    impl: usize,
    min_args: u32,
    max_args: u32,

    pub fn implFn(n: *const NativeFunction) Impl {
        return @ptrFromInt(n.impl);
    }
};

comptime {
    std.debug.assert(@offsetOf(GenericFunction, "entry") == @offsetOf(FunctionHeader, "entry"));
    std.debug.assert(@offsetOf(Closure, "entry") == @offsetOf(FunctionHeader, "entry"));
    std.debug.assert(@offsetOf(NativeFunction, "entry") == @offsetOf(FunctionHeader, "entry"));
}

pub fn functionHeader(v: Value) *FunctionHeader {
    std.debug.assert(v.isFunctionPointer());
    return @ptrCast(@alignCast(v.pointer()));
}

pub fn kindOfFunction(v: Value) object.ObjKind {
    return functionHeader(v).header.kind;
}

pub fn closurePtr(v: Value) *Closure {
    std.debug.assert(v.isFunctionPointer() and kindOfFunction(v) == .closure);
    return @ptrCast(@alignCast(v.pointer()));
}

pub fn nativePtr(v: Value) *NativeFunction {
    std.debug.assert(v.isFunctionPointer() and kindOfFunction(v) == .native_function);
    return @ptrCast(@alignCast(v.pointer()));
}

pub fn codePtr(v: Value) *Code {
    std.debug.assert(Runtime.kindOf(v) == .code);
    return @ptrCast(@alignCast(v.pointer()));
}

/// プリミティブの汎用の入口：引数の個数を検査してから本体を呼ぶ
pub fn nativeEntry(th: *Thread, self: Value, args: [*]const Value, nargs: u32) callconv(.c) Value {
    const n = nativePtr(self);
    if (nargs < n.min_args or nargs > n.max_args) return th.argCountError(self, nargs);
    // 単値を返すのが普通なので、先に個数を 1 にしておく（多値を返すプリミティブは本体で書き直す：§6.2）
    th.mv_count = 1;
    return n.implFn()(th, args[0..nargs]);
}

pub fn makeNative(rt: *Runtime, name: Value, impl: Impl, min_args: u32, max_args: u32) Error!Value {
    const f = try rt.heap.create(NativeFunction, 0);
    f.* = .{
        .header = .{ .kind = .native_function },
        .entry = &nativeEntry,
        .name = name,
        .impl = @intFromPtr(impl),
        .min_args = min_args,
        .max_args = max_args,
    };
    return Value.fromPointer(f, .function);
}

pub const CodeSpec = struct {
    bytecode: []const u8,
    /// 定数表（simple-vector、または NIL）
    consts: Value,
    name: Value,
    nparams: u32,
    nlocals: u32,
    ncaptured: u32,
    max_stack: u32,
    rest: bool = false,
};

/// Code を作る。spec.consts と spec.name は、呼び出し側が生かしておくこと（引数として生きている）
pub fn makeCode(rt: *Runtime, spec: CodeSpec) Error!Value {
    const c = try rt.heap.create(Code, 0);
    c.* = .{
        .header = .{ .kind = .code, .len = @intCast(spec.bytecode.len) },
        .bytecode = undefined,
        .consts = spec.consts,
        .name = spec.name,
        .nparams = spec.nparams,
        .nlocals = spec.nlocals,
        .ncaptured = spec.ncaptured,
        .max_stack = spec.max_stack,
        .rest = spec.rest,
    };
    // バッファの確保は GC を起こさない（§3.2）。確保に失敗しても Code は空のまま回収される
    c.header.len = 0;
    const buf = try rt.heap.allocOwnedBuffer(c, spec.bytecode.len);
    @memcpy(buf[0..spec.bytecode.len], spec.bytecode);
    c.bytecode = buf.ptr;
    c.header.len = @intCast(spec.bytecode.len);
    return Value.fromPointer(c, .other);
}

/// closure を作る。captured の要素は呼び出し側が生かしておくこと（VM の値スタックの上にある）
pub fn makeClosure(rt: *Runtime, code: Value, entry: Entry, captured: []const Value) Error!Value {
    const c = try rt.heap.create(Closure, captured.len * @sizeOf(Value));
    c.header = .{ .kind = .closure, .len = @intCast(captured.len) };
    c.entry = entry;
    c.code = code;
    @memcpy(c.captured(), captured);
    return Value.fromPointer(c, .function);
}

pub fn makeCell(rt: *Runtime, v: Value) Error!Value {
    const c = try rt.heap.create(object.ValueCell, 0);
    c.* = .{ .header = .{ .kind = .value_cell }, .value = v };
    return Value.fromPointer(c, .other);
}

pub fn cellPtr(v: Value) *object.ValueCell {
    std.debug.assert(Runtime.kindOf(v) == .value_cell);
    return @ptrCast(@alignCast(v.pointer()));
}
