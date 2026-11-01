//! 管理ヒープ（Phase 05 の仮の実装）。
//!
//! Phase 06 で、ページ単位のヒープ（詳細設計 §3.1）に置き換える。それまでは、確保するだけで
//! 解放しない簡単な実装とする（ArenaAllocator の上に置き、Heap.deinit でまとめて解放する）。
//! 他の層は、このファイルの関数（cons、create、allocBytes）だけを通して確保すること。
//! 置き換えのときに、呼び出し側を変えずに済むようにするためである。

const std = @import("std");
const values = @import("../values/value.zig");
const object = @import("../values/object.zig");
const Value = values.Value;

pub const Heap = struct {
    arena: std.heap.ArenaAllocator,

    pub fn init(backing: std.mem.Allocator) Heap {
        return .{ .arena = std.heap.ArenaAllocator.init(backing) };
    }

    pub fn deinit(h: *Heap) void {
        h.arena.deinit();
    }

    fn allocator(h: *Heap) std.mem.Allocator {
        return h.arena.allocator();
    }

    pub fn cons(h: *Heap, car: Value, cdr: Value) error{OutOfMemory}!Value {
        const mem = try h.allocator().alignedAlloc(object.Cons, .@"16", 1);
        mem[0] = .{ .car = car, .cdr = cdr };
        return Value.fromPointer(&mem[0], .cons);
    }

    /// ヘッダ付きのオブジェクトを確保する。`extra` は型の大きさの後ろに続ける領域のバイト数。
    pub fn create(h: *Heap, comptime T: type, extra: usize) error{OutOfMemory}!*T {
        const size = @sizeOf(T) + extra;
        const mem = try h.allocator().alignedAlloc(u8, .@"16", size);
        return @ptrCast(@alignCast(mem.ptr));
    }

    /// オブジェクトが別に持つバッファ（文字列の中身など）を確保する。
    pub fn allocBytes(h: *Heap, n: usize) error{OutOfMemory}![]u8 {
        return h.allocator().alignedAlloc(u8, .@"8", @max(n, 1));
    }
};

test "cons is 16-byte aligned and tagged" {
    var h = Heap.init(std.testing.allocator);
    defer h.deinit();
    const c = try h.cons(Value.fromFixnum(1), Value.nil);
    try std.testing.expect(c.isCons());
    try std.testing.expectEqual(@as(usize, 0), @intFromPtr(c.pointer()) & 0xF);
    const cell: *object.Cons = @ptrCast(@alignCast(c.pointer()));
    try std.testing.expectEqual(@as(i64, 1), cell.car.asFixnum());
}
