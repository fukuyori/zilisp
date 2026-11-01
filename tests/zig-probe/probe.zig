//! Zig 0.17.0 の言語機能・std API の照合用（Zilisp 詳細設計書 §1.3 の要検証項目）
const std = @import("std");
const builtin = @import("builtin");
const testing = std.testing;

// --- @addWithOverflow（§2.2 fixnum の高速経路）
test "addWithOverflow on tagged fixnum" {
    const a: i64 = (1 << 61) - 1; // most-positive-fixnum (raw, untagged)
    const tag_a: i64 = a << 2;
    // タグ付き（2ビット左シフト）のまま加算すると、62ビット範囲の超過がそのまま i64 の溢れになる
    const r = @addWithOverflow(tag_a, @as(i64, 1 << 2));
    try testing.expect(r[1] == 1);
    const r1 = @addWithOverflow(tag_a - 4, @as(i64, 1 << 2));
    try testing.expect(r1[1] == 0 and r1[0] == tag_a);
    const big: i64 = std.math.maxInt(i64) - 3;
    const r2 = @addWithOverflow(big, @as(i64, 8));
    try testing.expect(r2[1] == 1);
}

// --- ラベル付き switch + continue（§7.1 VM の分岐）
fn runVm(code: []const u8) u32 {
    var pc: usize = 0;
    var acc: u32 = 0;
    vm: switch (code[pc]) {
        0 => return acc,
        1 => {
            acc += 1;
            pc += 1;
            continue :vm code[pc];
        },
        2 => {
            acc *= 2;
            pc += 1;
            continue :vm code[pc];
        },
        else => unreachable,
    }
}
test "labeled switch continue" {
    try testing.expectEqual(@as(u32, 6), runVm(&.{ 1, 1, 1, 2, 0 }));
}

// --- @call(.always_tail)（§7A.3）
fn countDown(n: u64, acc: u64) u64 {
    if (n == 0) return acc;
    return @call(.always_tail, countDown, .{ n - 1, acc + 1 });
}
test "always_tail" {
    try testing.expectEqual(@as(u64, 10_000_000), countDown(10_000_000, 0));
}

// --- @"..." 識別子（§7A.5 C1）
fn @"cl-user::foo-bar?"(x: i32) i32 {
    return x + 1;
}
test "arbitrary identifier" {
    try testing.expectEqual(@as(i32, 2), @"cl-user::foo-bar?"(1));
}

// --- std.mem.doNotOptimizeAway（§3.4 生存の契約）
test "doNotOptimizeAway exists" {
    var x: u64 = 42;
    std.mem.doNotOptimizeAway(&x);
    std.mem.doNotOptimizeAway(x);
}

// --- callee-saved レジスタの退避（§3.4 手順1）
noinline fn spillRegistersAndGetSp() usize {
    switch (builtin.cpu.arch) {
        .x86_64 => asm volatile ("" ::: .{ .rbx = true, .rbp = true, .r12 = true, .r13 = true, .r14 = true, .r15 = true, .memory = true }),
        .aarch64 => asm volatile ("" ::: .{ .x19 = true, .x20 = true, .x21 = true, .x22 = true, .x23 = true, .x24 = true, .x25 = true, .x26 = true, .x27 = true, .x28 = true, .memory = true }),
        else => {},
    }
    var marker: usize = 0;
    std.mem.doNotOptimizeAway(&marker);
    return @intFromPtr(&marker);
}
test "register spill via clobber" {
    try testing.expect(spillRegistersAndGetSp() != 0);
}

// --- Error!Ret と extern struct（§6.2）
const Value = extern struct { raw: u64 };
const Ret = extern struct { primary: Value, count: usize };
const Error = error{ LispUnwind, OutOfMemory, VmInternal };
fn retTwo(x: u64) Error!Ret {
    if (x == 0) return error.LispUnwind;
    return .{ .primary = .{ .raw = x }, .count = 2 };
}
test "error union of extern struct" {
    const r = try retTwo(5);
    try testing.expectEqual(@as(usize, 2), r.count);
    try testing.expectError(error.LispUnwind, retTwo(0));
}
// C 呼び出し規約の境界（§6.2 共有ライブラリとの境界）
const BoundaryRet = extern struct { primary: Value, count: usize, err: u32 };
fn boundaryEntry(x: u64) callconv(.c) BoundaryRet {
    return .{ .primary = .{ .raw = x }, .count = 1, .err = 0 };
}
test "callconv c with extern struct" {
    try testing.expectEqual(@as(u32, 0), boundaryEntry(3).err);
}

// --- std.math.big.int（§1.3 多倍長整数）
test "big int Managed" {
    const gpa = testing.allocator;
    var a = try std.math.big.int.Managed.initSet(gpa, @as(u128, 1) << 100);
    defer a.deinit();
    var b = try std.math.big.int.Managed.initSet(gpa, @as(u128, 1) << 100);
    defer b.deinit();
    try a.add(&a, &b);
    try testing.expect(a.toConst().eql(b.toConst()) == false);
}

// --- ハッシュ（§1.3）
test "wyhash and crc32" {
    const h = std.hash.Wyhash.hash(0, "zilisp");
    try testing.expect(h != 0);
    const c = std.hash.Crc32.hash("zilisp");
    try testing.expect(c != 0);
}

// --- アロケータ（§1.3）
test "allocators" {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const p = try arena.allocator().alloc(u8, 100);
    try testing.expectEqual(@as(usize, 100), p.len);
    var dbg: std.heap.DebugAllocator(.{}) = .init;
    defer _ = dbg.deinit();
    const q = try dbg.allocator().alloc(u8, 10);
    dbg.allocator().free(q);
    const pg = try std.heap.page_allocator.alloc(u8, 32 * 1024);
    std.heap.page_allocator.free(pg);
}

// --- 集合（§1.3）
test "containers" {
    const gpa = testing.allocator;
    var list: std.ArrayList(u32) = .empty;
    defer list.deinit(gpa);
    try list.append(gpa, 1);
    var map: std.StringHashMapUnmanaged(u32) = .empty;
    defer map.deinit(gpa);
    try map.put(gpa, "car", 1);
    try testing.expectEqual(@as(?u32, 1), map.get("car"));
}

// --- UTF-16 変換（§1.3 Windows 境界）
test "utf16" {
    const gpa = testing.allocator;
    const w = try std.unicode.utf8ToUtf16LeAllocZ(gpa, "λ");
    defer gpa.free(w);
    try testing.expectEqual(@as(usize, 1), w.len);
}
