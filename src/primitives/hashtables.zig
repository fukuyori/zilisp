//! ハッシュ表（Phase 16 の最小版。詳細設計 §2.6）：make-hash-table・gethash・%puthash・remhash・clrhash・maphash・
//! hash-table-count・hash-table-p。比較は eq・eql・equal（equalp は Phase 21）。
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

/// equal のハッシュ値。equal で等しいものは同じ値になる（cons は深さ 4 まで、文字列は中身から）
fn hashEqual(v: Value, depth: u32) u64 {
    if (v.isCons()) {
        if (depth == 0) return 0x9e3779b97f4a7c15;
        const c = Runtime.consPtr(v);
        return mix(hashEqual(c.car, depth - 1) *% 31 +% hashEqual(c.cdr, depth - 1));
    }
    if (v.isOther() and Runtime.kindOf(v) == .string) {
        const s = Runtime.stringPtr(v);
        var h: u64 = 0xcbf29ce484222325;
        for (0..s.length()) |i| h = (h ^ s.charAt(i)) *% 0x100000001b3;
        return mix(h);
    }
    return hashEql(v);
}

fn hashOf(t: *const HashTable, k: Value) u64 {
    return switch (testOf(t)) {
        .eq => mix(k.raw()),
        .eql => hashEql(k),
        .equal => hashEqual(k, 4),
    };
}

fn same(t: *const HashTable, a: Value, b: Value) bool {
    return switch (testOf(t)) {
        .eq => a == b,
        .eql => lists.eql2(a, b),
        .equal => lists.equal2(a, b),
    };
}

fn tombstone(th: *Thread) Value {
    return th.rt.sys_tombstone;
}

fn entries(t: *const HashTable) []Value {
    return Runtime.vectorPtr(t.entries).items();
}

/// キーの枠の番号（なければ null）
fn find(th: *Thread, t: *const HashTable, k: Value) ?usize {
    const e = entries(t);
    const cap = e.len / 2;
    var i: usize = @intCast(hashOf(t, k) & (cap - 1));
    var n: usize = 0;
    while (n < cap) : (n += 1) {
        const key = e[2 * i];
        if (key == Value.unbound) return null;
        if (key != tombstone(th) and same(t, key, k)) return i;
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
            if (oe[i] != Value.unbound and oe[i] != tombstone(th)) insertNew(th, t, oe[i], oe[i + 1]);
        }
    }
    return true;
}

/// 空きの枠に入れる（キーがないことと、空きがあることは呼び出し側で確かめてある）
fn insertNew(th: *Thread, t: *HashTable, k: Value, v: Value) void {
    const e = entries(t);
    const cap = e.len / 2;
    var i: usize = @intCast(hashOf(t, k) & (cap - 1));
    while (e[2 * i] != Value.unbound and e[2 * i] != tombstone(th)) i = (i + 1) & (cap - 1);
    if (e[2 * i] == tombstone(th)) t.tombstones -= 1;
    e[2 * i] = k;
    e[2 * i + 1] = v;
    t.count += 1;
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
    const names = [_]struct { []const u8, HashTest }{ .{ "EQ", .eq }, .{ "EQL", .eql }, .{ "EQUAL", .equal } };
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
        test_kind = testFromDesignator(th, t) orelse {
            const rt = th.rt;
            const equalp = (rt.findSymbol(rt.cl, "EQUALP") orelse unreachable).symbol;
            if (t == equalp or t == rt.symbolPtr(equalp).function)
                return th.signal(.unimplemented, "equalp のハッシュ表は未実装です（Phase 21 で実装予定）", t, Value.unbound);
            return th.signal(.simple_error, "ハッシュ表の比較関数は eq・eql・equal・equalp のどれかです", t, Value.unbound);
        };
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
    if (find(th, t, args[0])) |i| {
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
    if (find(th, t, k)) |i| {
        entries(t)[2 * i + 1] = v;
        return v;
    }
    const cap = entries(t).len / 2;
    if ((t.count + t.tombstones + 1) * 4 > cap * 3) {
        // 削除した枠が多ければ同じ大きさで作り直し、そうでなければ倍にする
        const new_cap = if (t.count * 2 < cap) cap else cap * 2;
        if (!rehash(th, table, new_cap)) return Value.unwind;
    }
    insertNew(th, tablePtr(table), k, v);
    return v;
}

pub fn remhash(th: *Thread, args: []const Value) Value {
    if (checkTable(th, args[1])) |e| return e;
    const t = tablePtr(args[1]);
    if (find(th, t, args[0])) |i| {
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
