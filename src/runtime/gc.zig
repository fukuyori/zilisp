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
const function = @import("function.zig");

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
                .code => {
                    const c: *function.Code = @ptrFromInt(e);
                    m.markValue(c.consts);
                    m.markValue(c.name);
                },
                .closure => {
                    const c: *function.Closure = @ptrFromInt(e);
                    m.markValue(c.code);
                    for (c.captured()) |x| m.markValue(x);
                },
                .native_function => {
                    const f: *function.NativeFunction = @ptrFromInt(e);
                    m.markValue(f.name);
                },
                .value_cell => {
                    const c: *object.ValueCell = @ptrFromInt(e);
                    m.markValue(c.value);
                },
                .hash_table => {
                    const t: *object.HashTable = @ptrFromInt(e);
                    m.markValue(t.entries);
                },
                // 文字列の中身はバッファ（finalize 待ちの一覧で管理）、double-float は値だけ、
                // パッケージの本体は Runtime.packages が持つ（ルートとして別に走査する）
                .ratio => {
                    const r: *object.Ratio = @ptrFromInt(e);
                    m.markValue(r.numerator);
                    m.markValue(r.denominator);
                },
                .string, .double_float, .package, .bignum => {},
                _ => {},
            }
        }
    }
};

fn markValueCb(m: *Marker, v: Value) void {
    m.markValue(v);
}

/// スタックの先頭（最も高いアドレス）。
/// Windows はスレッド情報のブロック、Linux は /proc/self/maps の [stack]、macOS は pthread_get_stackaddr_np から得る
/// （1.0 は単一スレッドで、メインスレッドで動く。§6.1）。main が記録した位置は、それができない OS のための予備
fn stackTop(rt: *Runtime) usize {
    if (rt.stack_top != 0) return rt.stack_top;
    switch (builtin.os.tag) {
        .windows => return @intFromPtr(std.os.windows.teb().NtTib.StackBase),
        .linux => if (linuxStackTop()) |top| return top,
        .macos => return @intFromPtr(pthread_get_stackaddr_np(std.c.pthread_self())),
        else => {},
    }
    if (@import("runtime.zig").main_stack_top != 0) return @import("runtime.zig").main_stack_top;
    @panic("zilisp: スタックの先頭が分かりません（Runtime.stack_top を設定してください）");
}

extern "c" fn pthread_get_stackaddr_np(thread: std.c.pthread_t) *anyopaque;

/// Linux のメインスレッドのスタックの先頭（一度読んだら覚えておく。スタックの領域は動かない）
var linux_stack_top: usize = 0;

fn linuxStackTop() ?usize {
    if (linux_stack_top != 0) return linux_stack_top;
    const linux = std.os.linux;
    const rc = linux.open("/proc/self/maps", .{ .ACCMODE = .RDONLY }, 0);
    if (linux.errno(rc) != .SUCCESS) return null;
    const fd: linux.fd_t = @intCast(rc);
    defer _ = linux.close(fd);
    // 1行ずつ調べる。行は "開始-終了 権限 ... [stack]"
    var buf: [8192]u8 = undefined;
    var len: usize = 0;
    const here = @frameAddress();
    while (true) {
        const n = linux.read(fd, buf[len..].ptr, buf.len - len);
        if (linux.errno(n) != .SUCCESS) return null;
        len += n;
        var start: usize = 0;
        while (std.mem.indexOfScalarPos(u8, buf[0..len], start, '\n')) |nl| : (start = nl + 1) {
            if (parseStackLine(buf[start..nl], here)) |top| {
                linux_stack_top = top;
                return top;
            }
        }
        if (n == 0) return null;
        // 残りの途中の行を先頭に寄せる（1行がバッファより長ければ捨てる）
        if (start == 0 and len == buf.len) {
            len = 0;
        } else {
            std.mem.copyForwards(u8, buf[0 .. len - start], buf[start..len]);
            len -= start;
        }
    }
}

/// /proc/self/maps の1行が、今のフレームを含む領域なら、その終わりを返す。
/// [stack] の行だけを見るのではなく、今のフレームのアドレスを含む行を選ぶ（[stack] の名前がない環境にも対応する）
fn parseStackLine(line: []const u8, here: usize) ?usize {
    const dash = std.mem.indexOfScalar(u8, line, '-') orelse return null;
    const space = std.mem.indexOfScalarPos(u8, line, dash, ' ') orelse return null;
    const lo = std.fmt.parseInt(usize, line[0..dash], 16) catch return null;
    const hi = std.fmt.parseInt(usize, line[dash + 1 .. space], 16) catch return null;
    if (here >= lo and here < hi) return hi;
    return null;
}

test "parseStackLine picks the region that contains the frame" {
    try std.testing.expectEqual(@as(?usize, 0x7ffd0000), parseStackLine("7ffc0000-7ffd0000 rw-p 00000000 00:00 0 [stack]", 0x7ffc1234));
    try std.testing.expectEqual(@as(?usize, null), parseStackLine("7ffc0000-7ffd0000 rw-p 00000000 00:00 0 [stack]", 0x1000));
    try std.testing.expectEqual(@as(?usize, null), parseStackLine("garbage", 0x1000));
}

/// 退避させるレジスタの数（64 ビットの語の数）。
/// x86_64：rbx rbp rdi rsi r12–r15（rdi・rsi は Windows で callee-saved）＋ Windows の xmm6–xmm15（下位 64 ビット）
/// aarch64：x19–x29 ＋ d8–d15
const saved_words = switch (builtin.cpu.arch) {
    .x86_64 => 8 + 10,
    .aarch64 => 11 + 8,
    else => 0,
};

/// callee-saved レジスタの値を `regs` に書き出し、現在のスタックポインタを返す（§3.4 手順1）。
/// 呼び出し側のフレームにある値は、レジスタに残っていても、途中の関数がスタックに退避していても見つかる。
/// メモリを指す書き方を使わず、レジスタを指定した出力だけで読む（Zig の x86_64 バックエンドでも使えるように）。
inline fn saveRegisters(regs: *[saved_words]usize) usize {
    switch (builtin.cpu.arch) {
        .x86_64 => {
            regs[0] = asm volatile (""
                : [v] "={rbx}" (-> usize),
            );
            regs[1] = asm volatile ("movq %%rbp, %[v]"
                : [v] "=r" (-> usize),
            );
            regs[2] = asm volatile (""
                : [v] "={rdi}" (-> usize),
            );
            regs[3] = asm volatile (""
                : [v] "={rsi}" (-> usize),
            );
            regs[4] = asm volatile (""
                : [v] "={r12}" (-> usize),
            );
            regs[5] = asm volatile (""
                : [v] "={r13}" (-> usize),
            );
            regs[6] = asm volatile (""
                : [v] "={r14}" (-> usize),
            );
            regs[7] = asm volatile (""
                : [v] "={r15}" (-> usize),
            );
            if (builtin.os.tag == .windows) {
                regs[8] = asm volatile ("movq %%xmm6, %[v]"
                    : [v] "=r" (-> usize),
                );
                regs[9] = asm volatile ("movq %%xmm7, %[v]"
                    : [v] "=r" (-> usize),
                );
                regs[10] = asm volatile ("movq %%xmm8, %[v]"
                    : [v] "=r" (-> usize),
                );
                regs[11] = asm volatile ("movq %%xmm9, %[v]"
                    : [v] "=r" (-> usize),
                );
                regs[12] = asm volatile ("movq %%xmm10, %[v]"
                    : [v] "=r" (-> usize),
                );
                regs[13] = asm volatile ("movq %%xmm11, %[v]"
                    : [v] "=r" (-> usize),
                );
                regs[14] = asm volatile ("movq %%xmm12, %[v]"
                    : [v] "=r" (-> usize),
                );
                regs[15] = asm volatile ("movq %%xmm13, %[v]"
                    : [v] "=r" (-> usize),
                );
                regs[16] = asm volatile ("movq %%xmm14, %[v]"
                    : [v] "=r" (-> usize),
                );
                regs[17] = asm volatile ("movq %%xmm15, %[v]"
                    : [v] "=r" (-> usize),
                );
            }
            return asm volatile ("movq %%rsp, %[sp]"
                : [sp] "=r" (-> usize),
            );
        },
        .aarch64 => {
            regs[0] = asm volatile (""
                : [v] "={x19}" (-> usize),
            );
            regs[1] = asm volatile (""
                : [v] "={x20}" (-> usize),
            );
            regs[2] = asm volatile (""
                : [v] "={x21}" (-> usize),
            );
            regs[3] = asm volatile (""
                : [v] "={x22}" (-> usize),
            );
            regs[4] = asm volatile (""
                : [v] "={x23}" (-> usize),
            );
            regs[5] = asm volatile (""
                : [v] "={x24}" (-> usize),
            );
            regs[6] = asm volatile (""
                : [v] "={x25}" (-> usize),
            );
            regs[7] = asm volatile (""
                : [v] "={x26}" (-> usize),
            );
            regs[8] = asm volatile (""
                : [v] "={x27}" (-> usize),
            );
            regs[9] = asm volatile (""
                : [v] "={x28}" (-> usize),
            );
            regs[10] = asm volatile ("mov %[v], x29"
                : [v] "=r" (-> usize),
            );
            regs[11] = asm volatile ("fmov %[v], d8"
                : [v] "=r" (-> usize),
            );
            regs[12] = asm volatile ("fmov %[v], d9"
                : [v] "=r" (-> usize),
            );
            regs[13] = asm volatile ("fmov %[v], d10"
                : [v] "=r" (-> usize),
            );
            regs[14] = asm volatile ("fmov %[v], d11"
                : [v] "=r" (-> usize),
            );
            regs[15] = asm volatile ("fmov %[v], d12"
                : [v] "=r" (-> usize),
            );
            regs[16] = asm volatile ("fmov %[v], d13"
                : [v] "=r" (-> usize),
            );
            regs[17] = asm volatile ("fmov %[v], d14"
                : [v] "=r" (-> usize),
            );
            regs[18] = asm volatile ("fmov %[v], d15"
                : [v] "=r" (-> usize),
            );
            return asm volatile ("mov %[sp], sp"
                : [sp] "=r" (-> usize),
            );
        },
        else => {
            // 未対応のアーキテクチャ：ローカル変数の位置を下端とする（レジスタは読めない）
            var marker: usize = 0;
            std.mem.doNotOptimizeAway(&marker);
            return @intFromPtr(&marker);
        },
    }
}

/// callee-saved レジスタを書き出して走査し、現在のスタックポインタから上端までを走査する
noinline fn scanStack(m: *Marker, top: usize) void {
    var regs: [saved_words]usize = @splat(0);
    const sp = saveRegisters(&regs);
    for (regs) |w| m.markWord(w);
    var p = std.mem.alignForward(usize, sp, @sizeOf(usize));
    while (p + @sizeOf(usize) <= top) : (p += @sizeOf(usize)) {
        const w = @as(*const usize, @ptrFromInt(p)).*;
        m.markWord(w);
    }
    std.mem.doNotOptimizeAway(&regs);
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
    if (rt.thread) |th| th.forEachRoot(&m, markValueCb);
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

/// ゴミを作る関数を、余白（8 KiB）を挟んだ深いフレームで呼ぶ。その関数のフレームに残った古い値が、後で呼ぶ
/// collect のフレームの書き込まれない枠と重なり、保守的走査で見つかって回収されないことがあるため
/// （clobberStack は、呼び出した直後の位置のフレームの先頭部分を消さない。x86_64-linux の CI の AVX2 のビルドで発見）
noinline fn deep(comptime f: anytype, args: anytype) @typeInfo(@TypeOf(f)).@"fn".return_type.? {
    var pad: [8192]u8 = undefined;
    @memset(&pad, 0);
    std.mem.doNotOptimizeAway(&pad);
    return @call(.never_inline, f, args);
}

/// スタックに残った古い値を消す（保守的走査で古い参照が見つかるのを減らす）。
/// 2段にする：呼んだ直後の位置（後で呼ぶ collect のフレームが重なる位置）は、この関数自身のフレームが占めるので、
/// その局所変数を 0 で埋めてフレームの全体を覆い、さらに深い位置を clobberDeeper が消す
/// （1段だと、この関数のフレームの先頭部分の枠に古い値が残り、collect のフレームの書き込まれない枠として走査された。
/// x86_64-linux の CI の AVX2 のビルドで発見）
noinline fn clobberStack() void {
    var guard: [64]usize = @splat(0);
    std.mem.doNotOptimizeAway(&guard);
    clobberDeeper();
    std.mem.doNotOptimizeAway(&guard);
}

noinline fn clobberDeeper() void {
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
            try deep(makeGarbageCycles, .{ rt, hidden.len, &hidden });
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
            try deep(makeGarbageStrings, .{ rt, 500 });
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
            const hidden = try deep(makeGarbageVector, .{rt});
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

fn collectFromAsm(rt: *Runtime) callconv(.c) void {
    collect(rt);
}

/// 100 個の cons のリストを作り、先頭のアドレスを反転して返す（参照はこの関数の中にしか残らない）
noinline fn makeHiddenList(rt: *Runtime) !usize {
    var list = Value.nil;
    for (0..100) |i| list = try rt.cons(Value.fromFixnum(@intCast(i)), list);
    return hide(@intFromPtr(list.pointer()));
}

/// `hidden` を元に戻したアドレスを callee-saved レジスタ（x86_64：r12、aarch64：x19）にだけ置いて GC を呼び、
/// 戻ったときのそのレジスタの値を反転して返す。スタックにはアドレスが残らない
noinline fn collectWithRegisterRoot(rt: *Runtime, hidden: usize) usize {
    const f: *const fn (*Runtime) callconv(.c) void = &collectFromAsm;
    switch (builtin.cpu.arch) {
        .x86_64 => {
            const arg = if (builtin.os.tag == .windows) "rcx" else "rdi";
            // r15 にスタックポインタを保存し、red zone を避けて 16 バイト境界にそろえ、Windows の shadow space を空ける
            return asm volatile ("movq %[h], %%r12\n" ++
                    "notq %%r12\n" ++
                    "movq %[rt], %%" ++ arg ++ "\n" ++
                    "movq %%rsp, %%r15\n" ++
                    "subq $128, %%rsp\n" ++
                    "andq $-16, %%rsp\n" ++
                    "subq $32, %%rsp\n" ++
                    "callq *%[f]\n" ++
                    "movq %%r15, %%rsp\n" ++
                    "movq %%r12, %[out]\n" ++
                    "notq %[out]\n"
                : [out] "=r" (-> usize),
                : [h] "r" (hidden),
                  [rt] "r" (rt),
                  [f] "r" (f),
                : .{ .rax = true, .rcx = true, .rdx = true, .rsi = true, .rdi = true, .r8 = true, .r9 = true, .r10 = true, .r11 = true, .r12 = true, .r15 = true, .xmm0 = true, .xmm1 = true, .xmm2 = true, .xmm3 = true, .xmm4 = true, .xmm5 = true, .xmm6 = true, .xmm7 = true, .xmm8 = true, .xmm9 = true, .xmm10 = true, .xmm11 = true, .xmm12 = true, .xmm13 = true, .xmm14 = true, .xmm15 = true, .memory = true, .cc = true });
        },
        .aarch64 => {
            return asm volatile (
                \\mov x19, %[h]
                \\mvn x19, x19
                \\mov x0, %[rt]
                \\blr %[f]
                \\mvn %[out], x19
                : [out] "=r" (-> usize),
                : [h] "r" (hidden),
                  [rt] "r" (rt),
                  [f] "r" (f),
                : .{ .x0 = true, .x1 = true, .x2 = true, .x3 = true, .x4 = true, .x5 = true, .x6 = true, .x7 = true, .x8 = true, .x9 = true, .x10 = true, .x11 = true, .x12 = true, .x13 = true, .x14 = true, .x15 = true, .x16 = true, .x17 = true, .x19 = true, .x30 = true, .v0 = true, .v1 = true, .v2 = true, .v3 = true, .v4 = true, .v5 = true, .v6 = true, .v7 = true, .v16 = true, .v17 = true, .v18 = true, .v19 = true, .v20 = true, .v21 = true, .v22 = true, .v23 = true, .v24 = true, .v25 = true, .v26 = true, .v27 = true, .v28 = true, .v29 = true, .v30 = true, .v31 = true, .memory = true, .nzcv = true });
        },
        else => unreachable,
    }
}

/// 反転したアドレスのリストが、回収されずに元の内容のまま残っているか
noinline fn hiddenListIntact(rt: *Runtime, hidden: usize) bool {
    var x = Value.fromPointer(@ptrFromInt(unhide(hidden)), .cons);
    var i: i64 = 99;
    while (x != Value.nil) : (i -= 1) {
        if (!isLive(rt, x)) return false;
        const c = Runtime.consPtr(x);
        if (c.car != Value.fromFixnum(i)) return false;
        x = c.cdr;
    }
    return i == -1;
}

test "objects referenced only from a callee-saved register survive" {
    if (builtin.cpu.arch != .x86_64 and builtin.cpu.arch != .aarch64) return error.SkipZigTest;
    try withRuntime(struct {
        fn body(rt: *Runtime) !void {
            const hidden = try makeHiddenList(rt);
            clobberStack();
            const back = collectWithRegisterRoot(rt, hidden);
            try testing.expectEqual(hidden, back);
            rt.heap.finishSweep();
            try testing.expect(hiddenListIntact(rt, hidden));
            // 対照：どこからも参照しなければ回収される
            clobberStack();
            collect(rt);
            rt.heap.finishSweep();
            try testing.expect(!presentHidden(rt, hidden));
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
            try deep(makeGarbageCycles, .{ rt, 1000, &hidden });
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
