//! 戻り値の返し方（レジスタかメモリか）を確かめるための試験（docs/zig-std-usage.md §3）。
//! 実行方法（ターゲットごとにアセンブリを出力して zl_ で始まる関数を見る）:
//!   zig build-obj -target x86_64-windows -OReleaseFast -fno-emit-bin -femit-asm=abi.s tests/zig-probe/abi.zig

const ValueS = extern struct { raw: u64 };
const ValueE = enum(u64) { _ };
const RetS = extern struct { primary: ValueS, count: usize };
const RetE = struct { primary: ValueE, count: usize };
const Error = error{ LispUnwind, OutOfMemory, VmInternal };

/// Error!Ret（詳細設計 §6.2 の当初案）
noinline fn zl_err_ret(x: u64) Error!RetS {
    if (x == 0) return error.LispUnwind;
    return .{ .primary = .{ .raw = x }, .count = 2 };
}
/// エラーなしの 16 バイト構造体（Zig の既定の呼び出し規約）
noinline fn zl_ret_auto(x: u64) RetE {
    if (x == 0) return .{ .primary = @fromBackingInt(@intCast(0)), .count = ~@as(usize, 0) };
    return .{ .primary = @fromBackingInt(@intCast(x)), .count = 2 };
}
/// エラーなしの 16 バイト構造体（C の呼び出し規約）
noinline fn zl_ret_c(x: u64) callconv(.c) RetS {
    if (x == 0) return .{ .primary = .{ .raw = 0 }, .count = ~@as(usize, 0) };
    return .{ .primary = .{ .raw = x }, .count = 2 };
}
/// 8 バイトの extern struct
noinline fn zl_value_struct(x: u64) ValueS {
    return .{ .raw = x + 4 };
}
/// 8 バイトの enum(u64)
noinline fn zl_value_enum(x: u64) ValueE {
    return @fromBackingInt(@intCast(x + 4));
}
/// Error!Value（enum）
noinline fn zl_err_value(x: u64) Error!ValueE {
    if (x == 0) return error.LispUnwind;
    return @fromBackingInt(@intCast(x + 4));
}

export fn zl_probe(x: u64) u64 {
    const a = zl_err_ret(x) catch return 0;
    const b = zl_ret_auto(x);
    const c = zl_ret_c(x);
    const d = zl_value_struct(x);
    const e = zl_value_enum(x);
    const f = zl_err_value(x) catch return 1;
    return a.primary.raw + a.count + @backingInt(b.primary) + b.count + c.primary.raw + c.count +
        d.raw + @backingInt(e) + @backingInt(f);
}
