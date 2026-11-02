//! 管理ヒープ（詳細設計 §3.1）。
//!
//! 構成
//!   - OS から 4 MiB 単位（チャンク）で取得し、チャンクは 4 MiB 境界にそろえる。
//!     4 MiB を超えるオブジェクトには、その大きさに合わせた専用のチャンクを使う。
//!   - チャンクを 32 KiB のページに分ける（SBCL の x86-64 の gencgc-page-bytes と同じ大きさ）。
//!   - ページは次のどれかに使う
//!       cons ページ ：16 バイトの cons だけを置く（cons にはヘッダがないので、ページの種類で見分ける）
//!       小さいページ：同じサイズクラスの、ヘッダ付きのオブジェクトを置く
//!       大きいオブジェクト：8 KiB を超えるオブジェクト。連続したページを使う
//!   - ページごとの情報（使用中ビット・マークビット）はページの外（Zig のヒープ）に置く。
//!
//! GC（詳細設計 §3.2、Phase 07）との分担
//!   - マーク（gc.zig）：ルートからたどり、マークビットを立てる。
//!   - afterMark（このファイル）：finalize 待ちの一覧のうちマークされていないオブジェクトのバッファを解放し、
//!     大きいオブジェクトをその場で回収し、小さいページをすべて「未掃除」の一覧に入れる。
//!   - 遅延スイープ：確保のときに未掃除のページを1つずつ掃除する（使用中ビット ← マークビット）。
//!     次の GC の前に、残りをすべて掃除する（finishSweep）。空になったページは空きページに戻す。

const std = @import("std");
const builtin = @import("builtin");
const object = @import("../values/object.zig");
const Value = @import("../values/value.zig").Value;
const os_memory = @import("../support/os_memory.zig");

pub const page_size: usize = 32 * 1024;
pub const chunk_size: usize = 4 * 1024 * 1024;
pub const pages_per_chunk: usize = chunk_size / page_size;
pub const granule: usize = 16;
const max_slots: usize = page_size / granule;
const bitmap_words: usize = max_slots / 64;

/// 小さいオブジェクトのサイズクラス（すべて 16 の倍数）。これを超えるものは大きいオブジェクトとして扱う
pub const size_classes = [_]u32{
    16,  32,  48,  64,  80,   96,   112,  128,  160,  192,  224,  256,  320,  384,
    448, 512, 640, 768, 1024, 1280, 1536, 2048, 2560, 3072, 4096, 5120, 6144, 8192,
};
pub const max_small: usize = size_classes[size_classes.len - 1];
/// cons ページの「サイズクラス」の番号（size_classes の次）
const cons_class: usize = size_classes.len;

pub const PageKind = enum(u8) { free, cons, small, large_head, large_tail };

pub const Page = struct {
    kind: PageKind = .free,
    class: u8 = 0,
    slot_size: u32 = 0,
    slots: u32 = 0,
    used: u32 = 0,
    /// 次に空きを探し始める位置
    cursor: u32 = 0,
    /// large_head：ページ数。large_tail：先頭のページまでの距離
    large: u32 = 0,
    /// ページの先頭のアドレス
    addr: usize = 0,
    alloc_bits: [bitmap_words]u64 = @splat(0),
    mark_bits: [bitmap_words]u64 = @splat(0),

    inline fn testBit(bits: *const [bitmap_words]u64, i: usize) bool {
        return bits[i / 64] & (@as(u64, 1) << @intCast(i % 64)) != 0;
    }
    inline fn setBit(bits: *[bitmap_words]u64, i: usize) void {
        bits[i / 64] |= @as(u64, 1) << @intCast(i % 64);
    }
    inline fn clearBit(bits: *[bitmap_words]u64, i: usize) void {
        bits[i / 64] &= ~(@as(u64, 1) << @intCast(i % 64));
    }

    /// cursor から空きの枠を探す
    fn findFree(p: *Page) ?u32 {
        var i: usize = p.cursor;
        while (i < p.slots) {
            const w = p.alloc_bits[i / 64];
            const bit = i % 64;
            const free = ~w >> @intCast(bit);
            if (free != 0) {
                const slot = i + @ctz(free);
                if (slot < p.slots) return @intCast(slot);
                return null;
            }
            i = (i / 64 + 1) * 64;
        }
        return null;
    }
};

const Chunk = struct {
    region: os_memory.Region,
    mem: []u8,
    pages: []Page,

    fn base(c: *const Chunk) usize {
        return @intFromPtr(c.mem.ptr);
    }
    fn contains(c: *const Chunk, addr: usize) bool {
        return addr >= c.base() and addr < c.base() + c.mem.len;
    }
};

pub const Stats = struct {
    /// これまでに確保したバイト数（オブジェクトの枠と、別に確保したバッファの合計）
    bytes_allocated: u64 = 0,
    /// 前回の GC 以降に確保したバイト数（GC の契機の判定に使う。§3.1）
    bytes_since_gc: u64 = 0,
    objects_allocated: u64 = 0,
    chunks: usize = 0,
    /// GC の回数
    collections: u64 = 0,
    /// GC の停止時間の合計と最大（ns。時刻を取れる場合だけ）
    pause_ns_total: u64 = 0,
    pause_ns_max: u64 = 0,
    /// 直前の GC で生き残ったバイト数・オブジェクト数
    live_bytes: u64 = 0,
    live_objects: u64 = 0,
    /// 直前の GC で、保守的な走査で見つかった参照の数
    conservative_refs: u64 = 0,
    /// 回収したオブジェクトの累計（掃除の時点で数える）
    objects_freed: u64 = 0,
};

/// オブジェクトが別に持つバッファ（文字列の中身など）。持ち主が回収されたら解放する（§3.2）
const Finalizable = struct {
    owner: usize,
    buffer: []align(8) u8,
};

/// GC を起動する処理（Runtime が登録する）
pub const GcHook = struct {
    ctx: *anyopaque,
    collect: *const fn (ctx: *anyopaque) void,
};

/// GC を始める確保量の下限（§3.1）
pub const min_threshold: u64 = 8 * 1024 * 1024;

/// アドレスから求めたオブジェクト
pub const ObjectRef = struct {
    start: usize,
    page: *Page,
    slot: u32,
    is_cons: bool,
};

pub const Heap = struct {
    gpa: std.mem.Allocator,
    chunks: std.ArrayList(*Chunk) = .empty,
    current: [size_classes.len + 1]?*Page = @splat(null),
    /// サイズクラスごとの、空きの枠があるページ（Phase 07 のスイープで追加する）
    partial: [size_classes.len + 1]std.ArrayList(*Page) = @splat(.empty),
    /// 空きページ（1 ページずつ使う場合）。新しいチャンクのページは、アドレスの若い順に取り出せるよう積む
    free_pages: std.ArrayList(*Page) = .empty,
    /// GC の後、まだ掃除していないページ（サイズクラスごと）
    unswept: [size_classes.len + 1]std.ArrayList(*Page) = @splat(.empty),
    finalizable: std.ArrayList(Finalizable) = .empty,
    stats: Stats = .{},
    /// 次の GC を始める確保量
    threshold: u64 = min_threshold,
    gc_hook: ?GcHook = null,
    in_gc: bool = false,
    /// --gc-stress：確保のたびに GC を行う（ルートの登録漏れの検出用。§3.7）
    stress: bool = false,
    /// 回収した領域を 0xAA で埋める（デバッグビルドの既定。§3.7）
    poison: bool = builtin.mode == .debug,

    pub fn init(gpa: std.mem.Allocator) Heap {
        return .{ .gpa = gpa };
    }

    pub fn deinit(h: *Heap) void {
        for (h.chunks.items) |c| {
            os_memory.free(c.region, chunk_size);
            h.gpa.free(c.pages);
            h.gpa.destroy(c);
        }
        h.chunks.deinit(h.gpa);
        for (&h.partial) |*l| l.deinit(h.gpa);
        for (&h.unswept) |*l| l.deinit(h.gpa);
        h.free_pages.deinit(h.gpa);
        for (h.finalizable.items) |f| h.gpa.free(f.buffer);
        h.finalizable.deinit(h.gpa);
    }

    // ------------------------------------------------------------------
    // 確保

    inline fn maybeCollect(h: *Heap) void {
        if (h.gc_hook) |hook| {
            if (!h.in_gc and (h.stress or h.stats.bytes_since_gc >= h.threshold)) hook.collect(hook.ctx);
        }
    }

    pub fn cons(h: *Heap, car: Value, cdr: Value) error{OutOfMemory}!Value {
        h.maybeCollect();
        const addr = try h.allocSmall(cons_class);
        const c: *object.Cons = @ptrFromInt(addr);
        c.* = .{ .car = car, .cdr = cdr };
        return Value.fromPointer(c, .cons);
    }

    /// ヘッダ付きのオブジェクトを確保する。`extra` は型の大きさの後ろに続ける領域のバイト数。
    /// 中身は呼び出し側が初期化すること（初期化する前に、確保を伴う処理を呼ばないこと）。
    pub fn create(h: *Heap, comptime T: type, extra: usize) error{OutOfMemory}!*T {
        h.maybeCollect();
        const size = @sizeOf(T) + extra;
        const addr = if (size <= max_small) try h.allocSmall(classOf(size)) else try h.allocLarge(size);
        return @ptrFromInt(addr);
    }

    /// オブジェクト `owner` が別に持つバッファを確保する。owner が回収されたときに解放する（§3.2）。
    /// GC は起こさない（owner を確保した直後に呼べるようにするため）。確保量は GC の契機に数える（§3.1）。
    pub fn allocOwnedBuffer(h: *Heap, owner: *const anyopaque, n: usize) error{OutOfMemory}![]u8 {
        const b = try h.gpa.alignedAlloc(u8, .@"8", @max(n, 1));
        errdefer h.gpa.free(b);
        try h.finalizable.append(h.gpa, .{ .owner = @intFromPtr(owner), .buffer = b });
        h.count(b.len);
        return b;
    }

    fn count(h: *Heap, n: usize) void {
        h.stats.bytes_allocated += n;
        h.stats.bytes_since_gc += n;
    }

    pub fn classOf(size: usize) usize {
        std.debug.assert(size <= max_small);
        if (size <= 128) return (@max(size, 1) + 15) / 16 - 1;
        for (size_classes, 0..) |s, i| {
            if (size <= s) return i;
        }
        unreachable;
    }

    inline fn allocSmall(h: *Heap, class: usize) error{OutOfMemory}!usize {
        if (h.current[class]) |p| {
            if (p.findFree()) |slot| return h.take(p, slot);
        }
        return h.allocSmallSlow(class);
    }

    inline fn take(h: *Heap, p: *Page, slot: u32) usize {
        Page.setBit(&p.alloc_bits, slot);
        p.used += 1;
        p.cursor = slot + 1;
        h.stats.objects_allocated += 1;
        h.count(p.slot_size);
        return p.addr + @as(usize, slot) * p.slot_size;
    }

    fn allocSmallSlow(h: *Heap, class: usize) error{OutOfMemory}!usize {
        // 同じサイズクラスで空きの枠があるページ（Phase 07 のスイープで一覧に入る）
        while (h.partial[class].pop()) |p| {
            p.cursor = 0;
            if (p.findFree()) |slot| {
                h.current[class] = p;
                return h.take(p, slot);
            }
        }
        // GC の後、まだ掃除していないページを掃除して使う（遅延スイープ）
        while (h.unswept[class].pop()) |p| {
            if (h.sweepPage(p)) {
                p.cursor = 0;
                if (p.findFree()) |slot| {
                    h.current[class] = p;
                    return h.take(p, slot);
                }
            }
        }
        const p = try h.freePages(1);
        const slot_size: u32 = if (class == cons_class) 16 else size_classes[class];
        p[0].kind = if (class == cons_class) .cons else .small;
        p[0].class = @intCast(class);
        p[0].slot_size = slot_size;
        p[0].slots = @intCast(page_size / slot_size);
        p[0].used = 0;
        p[0].cursor = 0;
        p[0].alloc_bits = @splat(0);
        p[0].mark_bits = @splat(0);
        h.current[class] = &p[0];
        return h.take(&p[0], 0);
    }

    fn allocLarge(h: *Heap, size: usize) error{OutOfMemory}!usize {
        const n = (size + page_size - 1) / page_size;
        const p = try h.freePages(n);
        for (p, 0..) |*pg, i| {
            pg.kind = if (i == 0) .large_head else .large_tail;
            pg.large = if (i == 0) @intCast(n) else @intCast(i);
            pg.alloc_bits = @splat(0);
            pg.mark_bits = @splat(0);
            pg.slots = 1;
            pg.slot_size = @intCast(@min(size, std.math.maxInt(u32)));
            pg.used = 0;
        }
        Page.setBit(&p[0].alloc_bits, 0);
        p[0].used = 1;
        h.stats.objects_allocated += 1;
        h.count(n * page_size);
        return p[0].addr;
    }

    /// 連続した n 個の空きページを返す。なければ新しいチャンクを取得する
    fn freePages(h: *Heap, n: usize) error{OutOfMemory}![]Page {
        if (n == 1) {
            while (h.free_pages.pop()) |p| {
                if (p.kind == .free) return @as([*]Page, @ptrCast(p))[0..1];
            }
            const c = try h.newChunk(pages_per_chunk);
            // 先頭のページを返し、残りを空きページの一覧に（若い順に取り出せるよう逆順で）積む
            try h.free_pages.ensureUnusedCapacity(h.gpa, c.pages.len - 1);
            var i: usize = c.pages.len;
            while (i > 1) : (i -= 1) h.free_pages.appendAssumeCapacity(&c.pages[i - 1]);
            return c.pages[0..1];
        }
        // 複数ページ：既存のチャンクの中から連続した空きを探す（大きいオブジェクトは少ないため単純に探す）
        for (h.chunks.items) |c| {
            var run: usize = 0;
            for (c.pages, 0..) |pg, i| {
                run = if (pg.kind == .free) run + 1 else 0;
                if (run == n) return c.pages[i + 1 - n .. i + 1];
            }
        }
        const c = try h.newChunk(@max(n, pages_per_chunk));
        if (c.pages.len > n) {
            try h.free_pages.ensureUnusedCapacity(h.gpa, c.pages.len - n);
            var i: usize = c.pages.len;
            while (i > n) : (i -= 1) h.free_pages.appendAssumeCapacity(&c.pages[i - 1]);
        }
        return c.pages[0..n];
    }

    fn newChunk(h: *Heap, pages: usize) error{OutOfMemory}!*Chunk {
        const bytes = std.mem.alignForward(usize, pages * page_size, chunk_size);
        const region = try os_memory.allocAligned(bytes, chunk_size);
        errdefer os_memory.free(region, chunk_size);
        const mem = region.mem;
        const page_infos = try h.gpa.alloc(Page, bytes / page_size);
        errdefer h.gpa.free(page_infos);
        for (page_infos, 0..) |*p, i| p.* = .{ .addr = @intFromPtr(mem.ptr) + i * page_size };
        const c = try h.gpa.create(Chunk);
        errdefer h.gpa.destroy(c);
        c.* = .{ .region = region, .mem = mem, .pages = page_infos };
        // アドレスの順に並べる（findObject の二分探索のため）
        var idx: usize = h.chunks.items.len;
        while (idx > 0 and h.chunks.items[idx - 1].base() > c.base()) : (idx -= 1) {}
        try h.chunks.insert(h.gpa, idx, c);
        h.stats.chunks += 1;
        return c;
    }

    // ------------------------------------------------------------------
    // アドレスからオブジェクトを求める（詳細設計 §3.4 の保守的走査）

    fn findChunk(h: *Heap, addr: usize) ?*Chunk {
        var lo: usize = 0;
        var hi: usize = h.chunks.items.len;
        while (lo < hi) {
            const mid = (lo + hi) / 2;
            const c = h.chunks.items[mid];
            if (addr < c.base()) {
                hi = mid;
            } else if (addr >= c.base() + c.mem.len) {
                lo = mid + 1;
            } else return c;
        }
        return null;
    }

    /// `addr` が確保済みのオブジェクトの範囲（先頭から末尾の直前まで）を指していれば、そのオブジェクトを返す。
    /// オブジェクトの途中を指すアドレスも、そのオブジェクトへの参照とみなす（§3.4）。
    pub fn findObject(h: *Heap, addr: usize) ?ObjectRef {
        const c = h.findChunk(addr) orelse return null;
        const pi = (addr - c.base()) / page_size;
        var p = &c.pages[pi];
        switch (p.kind) {
            .free => return null,
            .cons, .small => {
                const slot: u32 = @intCast((addr - p.addr) / p.slot_size);
                if (slot >= p.slots or !Page.testBit(&p.alloc_bits, slot)) return null;
                return .{ .start = p.addr + @as(usize, slot) * p.slot_size, .page = p, .slot = slot, .is_cons = p.kind == .cons };
            },
            .large_head, .large_tail => {
                if (p.kind == .large_tail) p = &c.pages[pi - p.large];
                if (!Page.testBit(&p.alloc_bits, 0)) return null;
                if (addr >= p.addr + p.slot_size) return null; // オブジェクトの末尾より後ろ
                return .{ .start = p.addr, .page = p, .slot = 0, .is_cons = false };
            },
        }
    }

    // ------------------------------------------------------------------
    // マークビット（Phase 07 の GC で使う）

    pub fn isMarked(ref: ObjectRef) bool {
        return Page.testBit(&ref.page.mark_bits, ref.slot);
    }

    /// マークする。既にマークされていれば false を返す
    pub fn mark(ref: ObjectRef) bool {
        if (Page.testBit(&ref.page.mark_bits, ref.slot)) return false;
        Page.setBit(&ref.page.mark_bits, ref.slot);
        return true;
    }

    pub fn clearMarks(h: *Heap) void {
        for (h.chunks.items) |c| {
            for (c.pages) |*p| p.mark_bits = @splat(0);
        }
    }

    // ------------------------------------------------------------------
    // 回収（詳細設計 §3.2）

    /// GC のマークを始める前に呼ぶ。前回の GC の後に掃除していないページをすべて掃除する
    /// （マークビットを次の GC で使い回すため）。
    pub fn finishSweep(h: *Heap) void {
        for (&h.unswept) |*list| {
            while (list.pop()) |p| _ = h.sweepPage(p);
        }
    }

    /// 1ページを掃除する。マークされていない枠を空きにし、マークビットを消す。
    /// 空きの枠ができれば true。ページが空になったら空きページに戻す。
    fn sweepPage(h: *Heap, p: *Page) bool {
        var used: u32 = 0;
        const words = (p.slots + 63) / 64;
        for (0..words) |wi| {
            const dead = p.alloc_bits[wi] & ~p.mark_bits[wi];
            if (dead != 0) {
                h.stats.objects_freed += @popCount(dead);
                if (h.poison) {
                    var d = dead;
                    while (d != 0) {
                        const bit = @ctz(d);
                        d &= d - 1;
                        const slot = wi * 64 + bit;
                        const ptr: [*]u8 = @ptrFromInt(p.addr + slot * p.slot_size);
                        @memset(ptr[0..p.slot_size], 0xAA);
                    }
                }
            }
            p.alloc_bits[wi] &= p.mark_bits[wi];
            p.mark_bits[wi] = 0;
            used += @popCount(p.alloc_bits[wi]);
        }
        p.used = used;
        p.cursor = 0;
        if (used == 0) {
            p.kind = .free;
            h.free_pages.append(h.gpa, p) catch {}; // 一覧に入れられなくても、確保の時に連続した空きとして見つかる
            return false;
        }
        return used < p.slots;
    }

    /// マークが終わった直後に呼ぶ（GC の停止時間の中で行う処理）
    pub fn afterMark(h: *Heap, live_bytes: u64, live_objects: u64) void {
        // finalize 待ちの一覧：持ち主がマークされていなければバッファを解放する
        var i: usize = 0;
        var live_buffer_bytes: u64 = 0;
        while (i < h.finalizable.items.len) {
            const f = h.finalizable.items[i];
            const alive = if (h.findObject(f.owner)) |ref| isMarked(ref) else false;
            if (alive) {
                live_buffer_bytes += f.buffer.len;
                i += 1;
            } else {
                h.gpa.free(f.buffer);
                _ = h.finalizable.swapRemove(i);
            }
        }
        // 大きいオブジェクトはその場で回収し、小さいページは未掃除の一覧に入れる
        for (&h.partial) |*l| l.clearRetainingCapacity();
        h.current = @splat(null);
        for (h.chunks.items) |c| {
            for (c.pages) |*p| switch (p.kind) {
                .free, .large_tail => {},
                .cons, .small => h.unswept[p.class].append(h.gpa, p) catch {
                    _ = h.sweepPage(p);
                },
                .large_head => {
                    if (Page.testBit(&p.mark_bits, 0)) {
                        p.mark_bits = @splat(0);
                    } else {
                        h.stats.objects_freed += 1;
                        const n = p.large;
                        const head_index = (p.addr - c.base()) / page_size;
                        for (c.pages[head_index .. head_index + n]) |*pg| {
                            if (h.poison) @memset(@as([*]u8, @ptrFromInt(pg.addr))[0..page_size], 0xAA);
                            pg.kind = .free;
                            pg.alloc_bits = @splat(0);
                            h.free_pages.append(h.gpa, pg) catch {};
                        }
                    }
                },
            };
        }
        const live = live_bytes + live_buffer_bytes;
        h.stats.live_bytes = live;
        h.stats.live_objects = live_objects;
        h.stats.bytes_since_gc = 0;
        h.threshold = @max(min_threshold, live * 2);
    }
};

// ---------------------------------------------------------------------------

const testing = std.testing;

test "size classes" {
    try testing.expectEqual(@as(usize, 0), Heap.classOf(1));
    try testing.expectEqual(@as(usize, 0), Heap.classOf(16));
    try testing.expectEqual(@as(usize, 1), Heap.classOf(17));
    try testing.expectEqual(@as(usize, 3), Heap.classOf(64));
    try testing.expectEqual(@as(usize, 8), Heap.classOf(129));
    try testing.expectEqual(size_classes.len - 1, Heap.classOf(8192));
    for (size_classes) |s| try testing.expect(s % 16 == 0 and page_size % 16 == 0);
}

test "cons is 16-byte aligned, tagged, and on a cons page" {
    var h = Heap.init(testing.allocator);
    defer h.deinit();
    const c = try h.cons(Value.fromFixnum(1), Value.nil);
    try testing.expect(c.isCons());
    const addr = @intFromPtr(c.pointer());
    try testing.expectEqual(@as(usize, 0), addr & 0xF);
    const cell: *object.Cons = @ptrFromInt(addr);
    try testing.expectEqual(@as(i64, 1), cell.car.asFixnum());
    const ref = h.findObject(addr).?;
    try testing.expect(ref.is_cons);
    try testing.expectEqual(addr, ref.start);
    // タグ付きのアドレス（+1）も、cons の途中（+8）も、同じ cons を指す
    try testing.expectEqual(addr, h.findObject(c.raw()).?.start);
    try testing.expectEqual(addr, h.findObject(addr + 8).?.start);
}

test "objects of different sizes and interior pointers" {
    var h = Heap.init(testing.allocator);
    defer h.deinit();
    const s = try h.create(object.Symbol, 0); // 64 バイト
    const v = try h.create(object.SimpleVector, 100 * 8); // 808 → 1024 のクラス
    const d = try h.create(object.DoubleFloat, 0); // 16 バイト（cons とは別のページ）
    const sa = @intFromPtr(s);
    const va = @intFromPtr(v);
    try testing.expectEqual(sa, h.findObject(sa + 63).?.start);
    try testing.expect(!h.findObject(sa).?.is_cons);
    try testing.expectEqual(va, h.findObject(va + 800).?.start);
    try testing.expect(!h.findObject(@intFromPtr(d)).?.is_cons);
    // 確保していない枠はオブジェクトではない
    try testing.expect(h.findObject(sa + 64) == null or h.findObject(sa + 64).?.start != sa);
    try testing.expect(h.findObject(0x1000) == null);
}

test "large objects span pages" {
    var h = Heap.init(testing.allocator);
    defer h.deinit();
    const n = 20_000; // 160 KB 程度 → 5 ページ
    const v = try h.create(object.SimpleVector, n * 8);
    const va = @intFromPtr(v);
    try testing.expectEqual(va, h.findObject(va).?.start);
    try testing.expectEqual(va, h.findObject(va + n * 8).?.start);
    try testing.expectEqual(@as(usize, 0), va % page_size);
    // 4 MiB を超えるオブジェクトは専用のチャンクに置く
    const big = try h.create(object.SimpleVector, 1_000_000 * 8);
    const ba = @intFromPtr(big);
    try testing.expectEqual(ba, h.findObject(ba + 7_999_999).?.start);
    try testing.expect(h.stats.chunks >= 2);
}

test "many conses fill multiple pages and chunks" {
    var h = Heap.init(testing.allocator);
    defer h.deinit();
    var list = Value.nil;
    var i: i64 = 0;
    while (i < 300_000) : (i += 1) list = try h.cons(Value.fromFixnum(i), list);
    // 300,000 × 16 バイト ＝ 4.8 MB → 2 チャンク以上
    try testing.expect(h.stats.chunks >= 2);
    var x = list;
    var k: i64 = 299_999;
    while (x != Value.nil) : (k -= 1) {
        const c: *object.Cons = @ptrCast(@alignCast(x.pointer()));
        try testing.expectEqual(k, c.car.asFixnum());
        try testing.expect(h.findObject(x.raw()).?.is_cons);
        x = c.cdr;
    }
    try testing.expectEqual(@as(i64, -1), k);
}

test "mark bits" {
    var h = Heap.init(testing.allocator);
    defer h.deinit();
    const c = try h.cons(Value.nil, Value.nil);
    const ref = h.findObject(c.raw()).?;
    try testing.expect(!Heap.isMarked(ref));
    try testing.expect(Heap.mark(ref));
    try testing.expect(!Heap.mark(ref));
    try testing.expect(Heap.isMarked(h.findObject(c.raw()).?));
    h.clearMarks();
    try testing.expect(!Heap.isMarked(h.findObject(c.raw()).?));
}
