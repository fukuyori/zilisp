//! mark-and-sweep GC（詳細設計 §3）。
//!
//! 手順
//!   1. 前回の GC の後に掃除していないページを掃除する（heap.finishSweep）
//!   2. ルートをマークする
//!        正確に走査：パッケージの表（全シンボル）、NIL のシンボルの実体、明示的なルート、FFI handle
//!        保守的に走査：ネイティブのスタックとレジスタ（§3.4）
//!   3. マークスタックが空になるまで、オブジェクトの中身をたどる
//!   4. heap.afterMark：finalize 待ちの一覧の処理、大きいオブジェクトの回収、小さいページを未掃除の一覧へ
//! 小さいページの掃除は、その後の確保のときに少しずつ行う（遅延スイープ）。

const std = @import("std");
const builtin = @import("builtin");
const heap_mod = @import("heap.zig");
const object = @import("../values/object.zig");
const Value = @import("../values/value.zig").Value;
const Runtime = @import("runtime.zig").Runtime;

const Heap = heap_mod.Heap;

const Marker = struct {
    heap: *Heap,
    gpa: std.mem.Allocator,
    /// マークしたが中身をまだたどっていないオブジェクトの先頭のアドレス（cons なら最下位ビットを 1 にする）
    stack: std.ArrayList(usize) = .empty,
    live_bytes: u64 = 0,
    live_objects: u64 = 0,
    conservative_refs: u64 = 0,
    lo: usize,
    hi: usize,

    fn markRef(m: *Marker, ref: heap_mod.ObjectRef) void {
        if (!Heap.mark(ref)) return;
        m.live_objects += 1;
        m.live_bytes += if (ref.page.kind == .large_head)
            @as(u64, ref.page.large) * heap_mod.page_size
        else
            ref.page.slot_size;
        m.stack.append(m.gpa, ref.start | @intFromBool(ref.is_cons)) catch
            @panic("zilisp: GC のマークスタックを確保できません（メモリ不足）");
    }

    /// 正確な参照（Value）をマークする
    fn markValue(m: *Marker, v: Value) void {
        if (!(v.isCons() or v.isOther() or v.isFunctionPointer())) return;
        const addr = @intFromPtr(v.pointer());
        const ref = m.heap.findObject(addr) orelse return;
        m.markRef(ref);
    }

    /// 保守的な参照（任意の語）をマークする
    fn markWord(m: *Marker, w: usize) void {
        if (w < m.lo or w >= m.hi) return;
        const ref = m.heap.findObject(w) orelse return;
        if (!Heap.isMarked(ref)) m.conservative_refs += 1;
        m.markRef(ref);
    }

    fn drain(m: *Marker) void {
        while (m.stack.pop()) |e| {
            if (e & 1 != 0) {
                const c: *object.Cons = @ptrFromInt(e & ~@as(usize, 1));
                m.markValue(c.car);
                m.markValue(c.cdr);
                continue;
            }
            const h: *object.ObjHeader = @ptrFromInt(e);
            switch (h.kind) {
                .symbol => {
                    const s: *object.Symbol = @ptrFromInt(e);
                    m.markValue(s.name);
                    m.markValue(s.package);
                    m.markValue(s.value);
                    m.markValue(s.function);
                    m.markValue(s.setf_function);
                    m.markValue(s.plist);
                },
                .simple_vector => {
                    const v: *object.SimpleVector = @ptrFromInt(e);
                    for (v.items()) |x| m.markValue(x);
                },
                // 文字列の中身はバッファ（finalize 待ちの一覧で管理）、double-float は値だけ、
                // パッケージの本体は Runtime.packages が持つ（ルートとして別に走査する）
                .string, .double_float, .package => {},
                _ => {},
            }
        }
    }
};

fn markValueCb(m: *Marker, v: Value) void {
    m.markValue(v);
}

/// スタックの先頭（最も高いアドレス）
fn stackTop(rt: *Runtime) usize {
    if (rt.stack_top != 0) return rt.stack_top;
    if (builtin.os.tag == .windows) return @intFromPtr(std.os.windows.teb().NtTib.StackBase);
    if (@import("runtime.zig").main_stack_top != 0) return @import("runtime.zig").main_stack_top;
    @panic("zilisp: スタックの先頭が分かりません（Runtime.stack_top を設定してください）");
}

/// callee-saved レジスタをスタックに退避させてから、スタックを走査する（§3.4 手順1）
noinline fn scanStack(m: *Marker, top: usize) void {
    switch (builtin.cpu.arch) {
        .x86_64 => asm volatile ("" ::: .{ .rbx = true, .rbp = true, .r12 = true, .r13 = true, .r14 = true, .r15 = true, .memory = true }),
        .aarch64 => asm volatile ("" ::: .{ .x19 = true, .x20 = true, .x21 = true, .x22 = true, .x23 = true, .x24 = true, .x25 = true, .x26 = true, .x27 = true, .x28 = true, .memory = true }),
        else => {},
    }
    var marker: usize = 0;
    std.mem.doNotOptimizeAway(&marker);
    var p = std.mem.alignForward(usize, @intFromPtr(&marker), @sizeOf(usize));
    while (p + @sizeOf(usize) <= top) : (p += @sizeOf(usize)) {
        const w = @as(*const usize, @ptrFromInt(p)).*;
        m.markWord(w);
    }
}

pub fn collect(rt: *Runtime) void {
    const h = &rt.heap;
    if (h.in_gc) return;
    h.in_gc = true;
    defer h.in_gc = false;

    const start = if (rt.io) |io| std.Io.Timestamp.now(io, .awake) else null;

    h.finishSweep();

    var lo: usize = std.math.maxInt(usize);
    var hi: usize = 0;
    for (h.chunks.items) |c| {
        lo = @min(lo, @intFromPtr(c.mem.ptr));
        hi = @max(hi, @intFromPtr(c.mem.ptr) + c.mem.len);
    }
    var m: Marker = .{ .heap = h, .gpa = rt.gpa, .lo = lo, .hi = hi };
    defer m.stack.deinit(rt.gpa);

    // 正確なルート
    m.markValue(Value.fromPointer(rt.nil_symbol, .other));
    m.markValue(rt.t);
    for (rt.packages.items) |p| {
        m.markValue(p.obj);
        var it = p.internal.valueIterator();
        while (it.next()) |v| m.markValue(v.*);
        var et = p.external.valueIterator();
        while (et.next()) |v| m.markValue(v.*);
    }
    rt.roots.forEach(&m, markValueCb);
    rt.handles.forEach(&m, markValueCb);
    // 保守的なルート（ネイティブのスタックとレジスタ）
    scanStack(&m, stackTop(rt));

    m.drain();
    h.afterMark(m.live_bytes, m.live_objects);

    h.stats.collections += 1;
    h.stats.conservative_refs = m.conservative_refs;
    if (start) |s| {
        const ns: u64 = @intCast(@max(0, s.untilNow(rt.io.?, .awake).nanoseconds));
        h.stats.pause_ns_total += ns;
        h.stats.pause_ns_max = @max(h.stats.pause_ns_max, ns);
    }
}

// ---------------------------------------------------------------------------

const testing = std.testing;

/// 試験の本体を呼ぶ。この関数のフレームの位置をスタックの上端として記録し、
/// Lisp の値を扱う本体は、inline 展開しない別の関数（このフレームより下）で実行する。
/// 値を持つ関数自身の @frameAddress() は上端に使えない（最適化ありのビルドでは、
/// その関数のローカル変数が @frameAddress() より高いアドレスに置かれることがある）。
fn withRuntime(comptime body: fn (*Runtime) anyerror!void) !void {
    const rt = try Runtime.create(testing.allocator);
    defer rt.destroy();
    rt.stack_top = @frameAddress();
    try @call(.never_inline, body, .{rt});
}

fn isLive(rt: *Runtime, v: Value) bool {
    return rt.heap.findObject(@intFromPtr(v.pointer())) != null;
}

/// 回収されたかを確かめるために持つアドレスは、ビットを反転して持つ（保守的な走査でポインタと見なされないように）
fn hide(addr: usize) usize {
    return ~addr;
}
fn unhide(h: usize) usize {
    return ~h;
}

/// ゴミを作る（この関数の中だけで参照し、戻ったら参照が残らないようにする）
noinline fn makeGarbageCycles(rt: *Runtime, n: usize, out_hidden: []usize) !void {
    for (0..n) |i| {
        const a = try rt.cons(Value.fromFixnum(@intCast(i)), Value.nil);
        const b = try rt.cons(Value.fromFixnum(@intCast(i)), a);
        Runtime.consPtr(a).cdr = b; // 循環
        out_hidden[i] = hide(@intFromPtr(a.pointer()));
    }
}

/// スタックに残った古い値を消す（保守的走査で古い参照が見つかるのを減らす）
noinline fn clobberStack() void {
    var buf: [16 * 1024]u8 = undefined;
    @memset(&buf, 0);
    std.mem.doNotOptimizeAway(&buf);
}

test "unreachable cycles are collected, reachable data survives" {
    try withRuntime(struct {
        fn body(rt: *Runtime) !void {
            // 生きているデータ：明示的なルートに登録したリスト
            var keep = Value.nil;
            for (0..1000) |i| keep = try rt.cons(Value.fromFixnum(@intCast(i)), keep);
            const h = try rt.roots.register(keep);
            keep = Value.nil;

            var hidden: [1000]usize = undefined;
            try makeGarbageCycles(rt, hidden.len, &hidden);
            clobberStack();
            collect(rt);
            rt.heap.finishSweep();

            var freed: usize = 0;
            for (hidden) |a| {
                if (rt.heap.findObject(unhide(a)) == null) freed += 1;
            }
            // 保守的な走査のため、スタックに偶然残った値で一部が残ることがある。99% 以上が回収されればよい
            try testing.expect(freed >= 990);

            // ルートから届くリストは残り、中身も壊れていない
            var x = rt.roots.get(h).?;
            var k: i64 = 999;
            while (x != Value.nil) : (k -= 1) {
                try testing.expect(isLive(rt, x));
                try testing.expectEqual(k, Runtime.consPtr(x).car.asFixnum());
                x = Runtime.consPtr(x).cdr;
            }
            try testing.expectEqual(@as(i64, -1), k);
            try testing.expect(rt.heap.stats.collections == 1);
        }
    }.body);
}

test "symbols in packages survive and strings are kept" {
    try withRuntime(struct {
        fn body(rt: *Runtime) !void {
            _ = try rt.intern(rt.cl_user, "SURVIVOR");
            collect(rt);
            rt.heap.finishSweep();
            const s = rt.findSymbol(rt.cl_user, "SURVIVOR").?.symbol;
            try testing.expect(isLive(rt, s));
            const name = rt.symbolPtr(s).name;
            try testing.expect(isLive(rt, name));
            try testing.expectEqual(@as(u21, 'S'), Runtime.stringPtr(name).charAt(0));
            // CL のシンボルも残る
            const car = rt.findSymbol(rt.cl, "CAR").?.symbol;
            try testing.expect(isLive(rt, car));
        }
    }.body);
}

noinline fn makeGarbageStrings(rt: *Runtime, n: usize) !void {
    for (0..n) |_| _ = try rt.makeString("garbage string 日本語");
}

test "string buffers of dead strings are freed" {
    try withRuntime(struct {
        fn body(rt: *Runtime) !void {
            const before = rt.heap.finalizable.items.len;
            try makeGarbageStrings(rt, 500);
            try testing.expectEqual(before + 500, rt.heap.finalizable.items.len);
            clobberStack();
            collect(rt);
            try testing.expect(rt.heap.finalizable.items.len <= before + 5);
        }
    }.body);
}

noinline fn makeGarbageVector(rt: *Runtime) !usize {
    const items = try testing.allocator.alloc(Value, 100_000);
    defer testing.allocator.free(items);
    @memset(items, Value.nil);
    const v = try rt.makeVector(items);
    return hide(@intFromPtr(v.pointer()));
}

/// 反転して持っているアドレスにオブジェクトがあるか。元に戻したアドレスが呼び出し側のスタックや
/// レジスタに残らないよう、inline 展開しない別の関数で確かめる
noinline fn presentHidden(rt: *Runtime, hidden: usize) bool {
    return rt.heap.findObject(unhide(hidden)) != null;
}

test "large objects are collected" {
    try withRuntime(struct {
        fn body(rt: *Runtime) !void {
            const hidden = try makeGarbageVector(rt);
            try testing.expect(presentHidden(rt, hidden));
            clobberStack();
            collect(rt);
            try testing.expect(rt.heap.findObject(unhide(hidden)) == null);
        }
    }.body);
}

test "objects referenced only from the native stack survive (conservative scan)" {
    try withRuntime(struct {
        fn body(rt: *Runtime) !void {
            var list = Value.nil;
            for (0..100) |i| list = try rt.cons(Value.fromFixnum(@intCast(i)), list);
            std.mem.doNotOptimizeAway(&list);
            collect(rt);
            rt.heap.finishSweep();
            var x = list;
            var n: usize = 0;
            while (x != Value.nil) : (n += 1) {
                try testing.expect(isLive(rt, x));
                x = Runtime.consPtr(x).cdr;
            }
            try testing.expectEqual(@as(usize, 100), n);
            try testing.expect(rt.heap.stats.conservative_refs >= 1);
            std.mem.doNotOptimizeAway(&list);
        }
    }.body);
}

test "the OS stack base is used when no stack top is given (Windows)" {
    if (builtin.os.tag != .windows) return error.SkipZigTest;
    const rt = try Runtime.create(testing.allocator);
    defer rt.destroy();
    var list = Value.nil;
    for (0..100) |i| list = try rt.cons(Value.fromFixnum(@intCast(i)), list);
    std.mem.doNotOptimizeAway(&list);
    collect(rt);
    rt.heap.finishSweep();
    var x = list;
    while (x != Value.nil) {
        try testing.expect(isLive(rt, x));
        x = Runtime.consPtr(x).cdr;
    }
    std.mem.doNotOptimizeAway(&list);
}

test "freed slots are reused after sweeping" {
    try withRuntime(struct {
        fn body(rt: *Runtime) !void {
            var hidden: [1000]usize = undefined;
            try makeGarbageCycles(rt, 1000, &hidden);
            const chunks_before = rt.heap.stats.chunks;
            clobberStack();
            collect(rt);
            // 回収した枠を使うので、チャンクは増えない
            for (0..2000) |_| _ = try rt.cons(Value.nil, Value.nil);
            try testing.expectEqual(chunks_before, rt.heap.stats.chunks);
            try testing.expect(rt.heap.stats.objects_freed >= 1900);
        }
    }.body);
}

test "gc stress: allocation with a collection every time keeps data intact" {
    try withRuntime(struct {
        fn body(rt: *Runtime) !void {
            rt.heap.stress = true;
            var list = Value.nil;
            for (0..300) |i| {
                const s = try rt.makeString("x");
                list = try rt.cons(s, list);
                list = try rt.cons(Value.fromFixnum(@intCast(i)), list);
            }
            try testing.expect(rt.heap.stats.collections >= 600);
            var x = list;
            var k: i64 = 299;
            while (x != Value.nil) : (k -= 1) {
                try testing.expectEqual(k, Runtime.consPtr(x).car.asFixnum());
                x = Runtime.consPtr(x).cdr;
                const s = Runtime.consPtr(x).car;
                try testing.expectEqual(@as(u21, 'x'), Runtime.stringPtr(s).charAt(0));
                x = Runtime.consPtr(x).cdr;
            }
            std.mem.doNotOptimizeAway(&list);
        }
    }.body);
}
