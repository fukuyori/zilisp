//! OS から、大きな境界にそろえたメモリを取得する（ヒープのチャンク用。詳細設計 §3.1）。
//!
//! Zig 0.17.0 の std.heap.page_allocator は、Windows でページより大きい境界（4 MiB など）にそろえた確保を
//! 求めると、最初の確保がたまたまそろわなかった場合に、プレースホルダーとして予約した領域を
//! NtAllocateVirtualMemory(COMMIT) で確定しようとして失敗し、OutOfMemory を返す
//! （lib/std/heap/PageAllocator.zig 66〜107 行目。docs/zig-std-usage.md に記録）。
//! そこで Windows では、大きめの範囲を予約（RESERVE）だけしておき、その中のそろった部分だけを確定する。
//! 予約しただけの範囲はアドレス空間を使うだけで、メモリは消費しない。
//! Windows 以外では page_allocator を使う（mmap で多めに取り、余りを返す方式）。領域は OS が 0 で埋めたもの。

const std = @import("std");
const builtin = @import("builtin");

pub const Region = struct {
    /// そろえた領域（ヒープが使う）
    mem: []u8,
    /// 解放に使う、予約した範囲の先頭（Windows のみ）
    reserve_base: usize,

    pub fn base(r: Region) usize {
        return @intFromPtr(r.mem.ptr);
    }
};

pub fn allocAligned(size: usize, comptime alignment: usize) error{OutOfMemory}!Region {
    if (builtin.os.tag == .windows) {
        const windows = std.os.windows;
        const ntdll = windows.ntdll;
        const process = windows.GetCurrentProcess();
        var reserve_base: ?*anyopaque = null;
        var reserve_size: windows.SIZE_T = size + alignment;
        if (ntdll.NtAllocateVirtualMemory(process, @ptrCast(&reserve_base), 0, &reserve_size, .{ .RESERVE = true }, .{ .NOACCESS = true }) != .SUCCESS)
            return error.OutOfMemory;
        const aligned = std.mem.alignForward(usize, @intFromPtr(reserve_base), alignment);
        var commit_base: ?*anyopaque = @ptrFromInt(aligned);
        var commit_size: windows.SIZE_T = size;
        if (ntdll.NtAllocateVirtualMemory(process, @ptrCast(&commit_base), 0, &commit_size, .{ .COMMIT = true }, .{ .READWRITE = true }) != .SUCCESS) {
            var b = reserve_base;
            var s: windows.SIZE_T = 0;
            _ = ntdll.NtFreeVirtualMemory(process, @ptrCast(&b), &s, .{ .RELEASE = true });
            return error.OutOfMemory;
        }
        const p: [*]u8 = @ptrFromInt(aligned);
        return .{ .mem = p[0..size], .reserve_base = @intFromPtr(reserve_base) };
    }
    // alignedAlloc は Debug ビルドで領域を未定義の印（0xAA）で埋めるので、OS が 0 で埋めた領域をそのまま使えるよう
    // rawAlloc で直接取る（Linux の試験で確認：CI を加えたとき）
    const p = std.heap.page_allocator.rawAlloc(size, .fromByteUnits(alignment), @returnAddress()) orelse return error.OutOfMemory;
    return .{ .mem = p[0..size], .reserve_base = 0 };
}

pub fn free(r: Region, comptime alignment: usize) void {
    if (builtin.os.tag == .windows) {
        const windows = std.os.windows;
        var b: ?*anyopaque = @ptrFromInt(r.reserve_base);
        var s: windows.SIZE_T = 0;
        _ = windows.ntdll.NtFreeVirtualMemory(windows.GetCurrentProcess(), @ptrCast(&b), &s, .{ .RELEASE = true });
        return;
    }
    std.heap.page_allocator.rawFree(r.mem, .fromByteUnits(alignment), @returnAddress());
}

test "aligned regions are aligned, writable and zeroed" {
    const a = 4 * 1024 * 1024;
    var regions: [8]Region = undefined;
    for (&regions) |*r| {
        r.* = try allocAligned(a, a);
        try std.testing.expectEqual(@as(usize, 0), r.base() % a);
        try std.testing.expectEqual(@as(u8, 0), r.mem[0]);
        r.mem[0] = 1;
        r.mem[a - 1] = 2;
    }
    for (regions) |r| free(r, a);
}
