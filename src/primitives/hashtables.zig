//! ハッシュ表（Phase 16 の最小版。詳細設計 §2.6）：make-hash-table・gethash・%puthash・remhash・clrhash・maphash・
//! hash-table-count・hash-table-p。比較は eq・eql・equal・equalp（equalp は Phase 21）。sxhash（Phase 21）。
//!
//! 表は simple-vector の (キー 値) の組の並び。開番地法（線形探査）。容量は 2 の冪。
//! 空きの枠はキーが unbound、削除した枠はキーが墓標（ZILISP-SYSTEM::%TOMBSTONE）。
//! 非移動型の GC なので、eq・eql のハッシュ値にアドレスを使える。

const std = @import("std");
const Value = @import("../values/value.zig").Value;
const object = @import("../values/object.zig");
const HashTable = object.HashTable;
const HashTest = object.HashTest;
const Thread = @import("../runtime/thread.zig").Thread;
const Runtime = @import("../runtime/runtime.zig").Runtime;
const lists = @import("lists.zig");
const arrays = @import("arrays.zig");
const numbers = @import("numbers.zig");
const equalp_mod = @import("equalp.zig");
const keyargs = @import("keyargs.zig");

pub fn isHashTable(v: Value) bool {
    return v.isOther() and Runtime.kindOf(v) == .hash_table;
}

fn tablePtr(v: Value) *HashTable {
    return @ptrCast(@alignCast(v.pointer()));
}

fn testOf(t: *const HashTable) HashTest {
    return @fromBackingInt(t.header.aux);
}

fn mix(x: u64) u64 {
    // splitmix64 の最後の混ぜ方
    var z = x;
    z = (z ^ (z >> 30)) *% 0xbf58476d1ce4e5b9;
    z = (z ^ (z >> 27)) *% 0x94d049bb133111eb;
    return z ^ (z >> 31);
}

fn hashEql(v: Value) u64 {
    if (v.isOther()) switch (Runtime.kindOf(v).?) {
        .double_float => return mix(@bitCast(Runtime.doubleValue(v))),
        // bignum・比は値からハッシュを計算する（eql で等しいものは同じ値。Phase 20）
        .bignum => {
            const b = Runtime.bignumPtr(v);
            var h: u64 = @intFromBool(b.positive());
            for (b.limbs()) |l| h = mix(h ^ l);
            return h;
        },
        .ratio => return mix(hashEql(Runtime.ratioPtr(v).numerator) *% 31 +% hashEql(Runtime.ratioPtr(v).denominator)),
        else => {},
    };
    return mix(v.raw());
}

/// equal のハッシュ値。equal で等しいものは同じ値になる（cons は深さ 4 まで、文字列は中身から。
/// 単純でない文字列も、有効な部分の中身から求める：Phase 21）
pub fn hashEqual(v: Value, depth: u32) u64 {
    if (v.isCons()) {
        if (depth == 0) return 0x9e3779b97f4a7c15;
        const c = Runtime.consPtr(v);
        return mix(hashEqual(c.car, depth - 1) *% 31 +% hashEqual(c.cdr, depth - 1));
    }
    if (arrays.isStringLike(v)) {
        const view = arrays.vectorView(v).?;
        const s = Runtime.stringPtr(view.data);
        var h: u64 = 0xcbf29ce484222325;
        for (0..view.len) |i| h = (h ^ s.charAt(i)) *% 0x100000001b3;
        return mix(h);
    }
    return hashEql(v);
}

/// equalp のハッシュ値。equalp で等しいものは同じ値になる（Phase 21）：
/// 数は正しく丸めた f64 から（= で等しい数は同じ f64 になる）、文字は大文字・小文字をそろえて、
/// 配列は大きさと先頭の要素から、ハッシュ表は項目の数から求める。メモリが足りなければ null（エラーを記録済み）
fn hashEqualp(th: *Thread, v: Value, depth: u32) ?u64 {
    if (v.isCons()) {
        if (depth == 0) return 0x9e3779b97f4a7c15;
        const c = Runtime.consPtr(v);
        const a = hashEqualp(th, c.car, depth - 1) orelse return null;
        const d = hashEqualp(th, c.cdr, depth - 1) orelse return null;
        return mix(a *% 31 +% d);
    }
    if (v.isChar()) return mix(0x51ed270b ^ @as(u64, equalp_mod.foldChar(v.asChar())));
    if (numbers.isNumber(v)) {
        var f = numbers.hashF64(th, v) orelse return null;
        if (f == 0) f = 0; // -0.0 と 0.0
        return mix(@as(u64, @bitCast(f)) ^ 0x2545f4914f6cdd1d);
    }
    if (arrays.isArray(v)) {
        if (arrays.vectorView(v)) |view| {
            var h: u64 = mix(view.len +% 0x7f4a7c15);
            if (depth == 0) return h;
            for (0..@min(view.len, 16)) |i| {
                h = mix(h *% 31 +% (hashEqualp(th, arrays.storageGet(view.data, i), depth - 1) orelse return null));
            }
            return h;
        }
        const data = arrays.dataOf(v);
        return mix(arrays.storageLen(data) +% 0x3c6ef372);
    }
    if (isHashTable(v)) return mix(tablePtr(v).count +% 0xa54ff53a);
    return mix(v.raw());
}

fn hashOf(th: *Thread, t: *const HashTable, k: Value) ?u64 {
    return switch (testOf(t)) {
        .eq => mix(k.raw()),
        .eql => hashEql(k),
        .equal => hashEqual(k, 4),
        .equalp => hashEqualp(th, k, 4),
    };
}

fn same(th: *Thread, t: *const HashTable, a: Value, b: Value) ?bool {
    return switch (testOf(t)) {
        .eq => a == b,
        .eql => lists.eql2(a, b),
        .equal => lists.equal2(a, b),
        .equalp => equalp_mod.equalp2(th, a, b),
    };
}

/// 2つのハッシュ表が equalp か（比較の種類と項目の数が同じで、一方の各キーがもう一方にあり、値が equalp。CLHS equalp）
pub fn tablesEqualp(th: *Thread, x: Value, y: Value) ?bool {
    const a = tablePtr(x);
    const b = tablePtr(y);
    if (testOf(a) != testOf(b) or a.count != b.count) return false;
    const e = entries(a);
    var i: usize = 0;
    while (i < e.len) : (i += 2) {
        const k = e[i];
        if (k == Value.unbound or k == tombstone(th)) continue;
        const j = (find(th, b, k) catch return null) orelse return false;
        if (!(equalp_mod.equalp2(th, e[i + 1], entries(b)[2 * j + 1]) orelse return null)) return false;
    }
    return true;
}

/// (sxhash オブジェクト)：equal で等しいものは同じ値になる、負でない fixnum（CLHS sxhash）
pub fn sxhash(th: *Thread, args: []const Value) Value {
    _ = th;
    return Value.fromFixnum(@intCast(hashEqual(args[0], 4) & ((1 << 60) - 1)));
}

fn tombstone(th: *Thread) Value {
    return th.rt.sys_tombstone;
}

fn entries(t: *const HashTable) []Value {
    return Runtime.vectorPtr(t.entries).items();
}

const Unwind = error{Unwind};

/// キーの枠の番号（なければ null）。equalp の比較でメモリが足りなければ error.Unwind（エラーを記録済み）
fn find(th: *Thread, t: *const HashTable, k: Value) Unwind!?usize {
    const e = entries(t);
    const cap = e.len / 2;
    var i: usize = @intCast((hashOf(th, t, k) orelse return error.Unwind) & (cap - 1));
    var n: usize = 0;
    while (n < cap) : (n += 1) {
        const key = e[2 * i];
        if (key == Value.unbound) return null;
        if (key != tombstone(th) and (same(th, t, key, k) orelse return error.Unwind)) return i;
        i = (i + 1) & (cap - 1);
    }
    return null;
}

/// 新しい容量の表に入れ直す。table は呼び出し側の引数として生きている（GC が起きても回収されない）
fn rehash(th: *Thread, table: Value, cap: usize) bool {
    const t = tablePtr(table);
    const fresh = th.rt.makeVectorFilled(2 * cap, Value.unbound) catch {
        _ = th.outOfMemory();
        return false;
    };
    const old = t.entries;
    t.entries = fresh;
    t.count = 0;
    t.tombstones = 0;
    if (old != Value.nil) {
        const oe = Runtime.vectorPtr(old).items();
        var i: usize = 0;
        while (i < oe.len) : (i += 2) {
            if (oe[i] != Value.unbound and oe[i] != tombstone(th)) {
                if (!insertNew(th, t, oe[i], oe[i + 1])) return false;
            }
        }
    }
    return true;
}

/// 空きの枠に入れる（キーがないことと、空きがあることは呼び出し側で確かめてある）。
/// ハッシュ値を求めるのにメモリが足りなければ偽（エラーを記録済み）
fn insertNew(th: *Thread, t: *HashTable, k: Value, v: Value) bool {
    const e = entries(t);
    const cap = e.len / 2;
    var i: usize = @intCast((hashOf(th, t, k) orelse return false) & (cap - 1));
    while (e[2 * i] != Value.unbound and e[2 * i] != tombstone(th)) i = (i + 1) & (cap - 1);
    if (e[2 * i] == tombstone(th)) t.tombstones -= 1;
    e[2 * i] = k;
    e[2 * i + 1] = v;
    t.count += 1;
    return true;
}

pub fn makeTable(th: *Thread, test_kind: HashTest, size: usize) Value {
    const t = th.rt.heap.create(HashTable, 0) catch return th.outOfMemory();
    t.* = .{ .header = .{ .kind = .hash_table, .aux = @backingInt(test_kind) }, .entries = Value.nil, .count = 0, .tombstones = 0 };
    const table = Value.fromPointer(t, .other);
    var cap: usize = 8;
    while (cap * 3 < size * 4) cap *= 2;
    if (!rehash(th, table, cap)) return Value.unwind;
    return table;
}

fn testFromDesignator(th: *Thread, v: Value) ?HashTest {
    const rt = th.rt;
    const names = [_]struct { []const u8, HashTest }{ .{ "EQ", .eq }, .{ "EQL", .eql }, .{ "EQUAL", .equal }, .{ "EQUALP", .equalp } };
    for (names) |n| {
        const sym = (rt.findSymbol(rt.cl, n[0]) orelse unreachable).symbol;
        if (v == sym or v == rt.symbolPtr(sym).function) return n[1];
    }
    return null;
}

/// make-hash-table &key test size rehash-size rehash-threshold weakness
pub fn makeHashTable(th: *Thread, args: []const Value) Value {
    var kv: [5]?Value = undefined;
    if (!keyargs.parse(th, args, &.{ "TEST", "SIZE", "REHASH-SIZE", "REHASH-THRESHOLD", "WEAKNESS" }, &kv)) return Value.unwind;
    var test_kind: HashTest = .eql;
    if (kv[0]) |t| {
        test_kind = testFromDesignator(th, t) orelse
            return th.signal(.simple_error, "ハッシュ表の比較関数は eq・eql・equal・equalp のどれかです", t, Value.unbound);
    }
    var size: usize = 8;
    if (kv[1]) |s| {
        if (!s.isFixnum() or s.asFixnum() < 0) return th.typeError(s, th.rt.syms.integer);
        size = @intCast(@min(s.asFixnum(), 1 << 24));
    }
    if (kv[4]) |w| if (w != Value.nil) return th.signal(.unimplemented, "弱いハッシュ表は未実装です", w, Value.unbound);
    return makeTable(th, test_kind, size);
}

fn checkTable(th: *Thread, v: Value) ?Value {
    if (isHashTable(v)) return null;
    const sym = (th.rt.findSymbol(th.rt.cl, "HASH-TABLE") orelse unreachable).symbol;
    return th.typeError(v, sym);
}

/// gethash キー 表 [既定値]：値と、あったかどうか（2つ目の値）
pub fn gethash(th: *Thread, args: []const Value) Value {
    if (checkTable(th, args[1])) |e| return e;
    const t = tablePtr(args[1]);
    if (find(th, t, args[0]) catch return Value.unwind) |i| {
        th.mv[1] = th.rt.t;
        th.mv_count = 2;
        return entries(t)[2 * i + 1];
    }
    th.mv[1] = Value.nil;
    th.mv_count = 2;
    return if (args.len > 2) args[2] else Value.nil;
}

/// ZILISP-SYSTEM::%PUTHASH キー 表 [既定値] 値：(setf (gethash キー 表 [既定値]) 値) の展開先。値を返す
pub fn sysPuthash(th: *Thread, args: []const Value) Value {
    if (checkTable(th, args[1])) |e| return e;
    const k = args[0];
    const table = args[1];
    const v = args[args.len - 1];
    const t = tablePtr(table);
    if (find(th, t, k) catch return Value.unwind) |i| {
        entries(t)[2 * i + 1] = v;
        return v;
    }
    const cap = entries(t).len / 2;
    if ((t.count + t.tombstones + 1) * 4 > cap * 3) {
        // 削除した枠が多ければ同じ大きさで作り直し、そうでなければ倍にする
        const new_cap = if (t.count * 2 < cap) cap else cap * 2;
        if (!rehash(th, table, new_cap)) return Value.unwind;
    }
    if (!insertNew(th, tablePtr(table), k, v)) return Value.unwind;
    return v;
}

pub fn remhash(th: *Thread, args: []const Value) Value {
    if (checkTable(th, args[1])) |e| return e;
    const t = tablePtr(args[1]);
    if (find(th, t, args[0]) catch return Value.unwind) |i| {
        const e = entries(t);
        e[2 * i] = tombstone(th);
        e[2 * i + 1] = Value.nil;
        t.count -= 1;
        t.tombstones += 1;
        return th.rt.t;
    }
    return Value.nil;
}

pub fn clrhash(th: *Thread, args: []const Value) Value {
    if (checkTable(th, args[0])) |e| return e;
    const t = tablePtr(args[0]);
    @memset(entries(t), Value.unbound);
    t.count = 0;
    t.tombstones = 0;
    return args[0];
}

/// maphash 関数 表：各項目について (関数 キー 値) を呼ぶ。呼び出しの中で許される変更は、その項目の setf・remhash だけ（CLHS 3.6）
pub fn maphash(th: *Thread, args: []const Value) Value {
    if (checkTable(th, args[1])) |e| return e;
    const t = tablePtr(args[1]);
    // 呼び出しの中の remhash・setf は今の表の vector を書き換えるだけなので、vector を順にたどってよい
    const vec = t.entries;
    const e = Runtime.vectorPtr(vec).items();
    var i: usize = 0;
    while (i < e.len) : (i += 2) {
        const k = e[i];
        if (k == Value.unbound or k == tombstone(th)) continue;
        const argv = [_]Value{ k, e[i + 1] };
        if (th.call(args[0], &argv) == Value.unwind) return Value.unwind;
    }
    std.mem.doNotOptimizeAway(vec);
    th.mv_count = 1;
    return Value.nil;
}

pub fn hashTableCount(th: *Thread, args: []const Value) Value {
    if (checkTable(th, args[0])) |e| return e;
    return Value.fromFixnum(tablePtr(args[0]).count);
}

pub fn hashTableP(th: *Thread, args: []const Value) Value {
    return th.rt.boolean(isHashTable(args[0]));
}

/// ZILISP-SYSTEM::%HASH-PAIRS 表：((キー . 値) ...) のリスト（loop の being the hash-keys・hash-values が使う。Phase 19）
pub fn sysHashPairs(th: *Thread, args: []const Value) Value {
    if (checkTable(th, args[0])) |e| return e;
    const vec = tablePtr(args[0]).entries;
    var list = Value.nil;
    var i: usize = 0;
    while (i < Runtime.vectorPtr(vec).items().len) : (i += 2) {
        // 確保で GC が起きても表の vector は動かないので、毎回 items() を引き直さなくてよいが、念のため引き直す
        const e = Runtime.vectorPtr(vec).items();
        const k = e[i];
        if (k == Value.unbound or k == tombstone(th)) continue;
        const pair = th.rt.cons(k, e[i + 1]) catch return th.outOfMemory();
        list = th.rt.cons(pair, list) catch return th.outOfMemory();
    }
    std.mem.doNotOptimizeAway(vec);
    return list;
}
