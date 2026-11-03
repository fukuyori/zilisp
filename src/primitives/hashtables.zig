//! ハッシュ表（Phase 16。詳細設計 §2.6）：make-hash-table・gethash・%puthash・remhash・clrhash・maphash・
//! hash-table-count・hash-table-p。比較は eq・eql・equal・equalp（equalp は Phase 21）。sxhash（Phase 21）。
//!
//! 表の並べ方は SBCL 2.6.7 と同じ（Phase 21.6。詳細設計 §2.6）：キーと値の配列（枠の番号の順に使う）、バケットの表と
//! next の鎖、空き枠の一覧、equal・equalp の表だけが持つハッシュ値の配列（object.HashTable）。削除は鎖から外して
//! 空き枠の一覧に積むだけで、墓標は残らない。maphash は枠の番号の順（削除がなければ入れた順）にたどる。
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
    var i: u32 = 1;
    while (i <= a.hwm) : (i += 1) {
        const k = kvOf(a)[2 * i];
        if (k == Value.unbound) continue;
        const j = (find(th, b, k) catch return null) orelse return false;
        if (!(equalp_mod.equalp2(th, kvOf(a)[2 * i + 1], kvOf(b)[2 * j + 1]) orelse return null)) return false;
    }
    return true;
}

/// (sxhash オブジェクト)：equal で等しいものは同じ値になる、負でない fixnum（CLHS sxhash）
pub fn sxhash(th: *Thread, args: []const Value) Value {
    _ = th;
    return Value.fromFixnum(@intCast(hashEqual(args[0], 4) & ((1 << 60) - 1)));
}

// ---------------------------------------------------------------------------
// 表の並べ方（object.HashTable の説明を参照。SBCL 2.6.7 の src/code/target-hash-table.lisp と同じ方式）

fn kvOf(t: *const HashTable) []Value {
    return Runtime.vectorPtr(t.kv).items();
}

/// バケットの表（links の先頭の header.len 個）
fn indexOf(t: *const HashTable) []u32 {
    return Runtime.rawVectorPtr(t.links).items(u32)[0..t.header.len];
}

/// 鎖（links のバケットの表の後ろ。size + 1 個）
fn nextOf(t: *const HashTable) []u32 {
    return Runtime.rawVectorPtr(t.links).items(u32)[t.header.len..];
}

/// equal・equalp の表の枠のハッシュ値（eq・eql の表は null）
fn hashesOf(t: *const HashTable) ?[]u64 {
    if (t.hashes == Value.nil) return null;
    return Runtime.rawVectorPtr(t.hashes).items(u64);
}

fn storesHash(test_kind: HashTest) bool {
    return test_kind == .equal or test_kind == .equalp;
}

const Unwind = error{Unwind};

/// キーの枠の番号（なければ null）。equalp の比較でメモリが足りなければ error.Unwind（エラーを記録済み）
fn find(th: *Thread, t: *const HashTable, k: Value) Unwind!?u32 {
    const h = hashOf(th, t, k) orelse return error.Unwind;
    return findH(th, t, k, h);
}

fn findH(th: *Thread, t: *const HashTable, k: Value, h: u64) Unwind!?u32 {
    const index = indexOf(t);
    const next = nextOf(t);
    const hashes = hashesOf(t);
    var i = index[@intCast(h & (index.len - 1))];
    while (i != 0) : (i = next[i]) {
        if (hashes) |hs| if (hs[i] != h) continue;
        if (same(th, t, kvOf(t)[2 * i], k) orelse return error.Unwind) return i;
    }
    return null;
}

/// バケットの数（size 以上の 2 の冪）
fn bucketsFor(size: usize) usize {
    return std.math.ceilPowerOfTwoAssert(usize, @max(size, 1));
}

/// 枠の数 size の配列を作って表に付ける。古い表の枠 1〜hwm を同じ番号に写し、鎖を作り直す。
/// table は呼び出し側の引数として生きている（GC が起きても回収されない）。メモリが足りなければ偽（エラーを記録済み）
fn resize(th: *Thread, table: Value, size: usize) bool {
    const rt = th.rt;
    const test_kind = testOf(tablePtr(table));
    // 作った配列はローカル変数だけが持つ（保守的なスタックの走査で守られる）
    const kv = rt.makeVectorFilled(2 * (size + 1), Value.unbound) catch {
        _ = th.outOfMemory();
        return false;
    };
    // バケットの表と鎖は 1 つの配列にまとめる（確保の回数を減らす）
    const buckets = bucketsFor(size);
    const links = rt.makeRawVector(u32, buckets + size + 1) catch {
        _ = th.outOfMemory();
        return false;
    };
    const hashes = if (storesHash(test_kind)) rt.makeRawVector(u64, size + 1) catch {
        _ = th.outOfMemory();
        return false;
    } else Value.nil;
    const t = tablePtr(table);
    const hwm = t.hwm;
    std.debug.assert(hwm <= size);
    if (t.kv != Value.nil) {
        @memcpy(Runtime.vectorPtr(kv).items()[0 .. 2 * (hwm + 1)], kvOf(t)[0 .. 2 * (hwm + 1)]);
        if (hashesOf(t)) |old| @memcpy(Runtime.rawVectorPtr(hashes).items(u64)[0 .. hwm + 1], old[0 .. hwm + 1]);
    }
    t.kv = kv;
    t.links = links;
    t.header.len = @intCast(buckets);
    t.hashes = hashes;
    t.size = @intCast(size);
    // 鎖を作り直す。番号の大きい方から積むので、鎖は番号の小さい順になる。空きの枠は空き枠の一覧に積む（SBCL の rehash と同じ）
    t.free = 0;
    const nx = nextOf(t);
    const ix = indexOf(t);
    var i: u32 = hwm;
    while (i >= 1) : (i -= 1) {
        const k = kvOf(t)[2 * i];
        if (k == Value.unbound) {
            nx[i] = t.free;
            t.free = i;
            continue;
        }
        // 保存したハッシュ値を使う（eq・eql の計算は失敗しない）
        const h = if (hashesOf(t)) |hs| hs[i] else (hashOf(th, t, k) orelse unreachable);
        const b: usize = @intCast(h & (ix.len - 1));
        nx[i] = ix[b];
        ix[b] = i;
    }
    std.mem.doNotOptimizeAway(table);
    return true;
}

// ---------------------------------------------------------------------------
// 枠の数の決め方（SBCL 2.6.7 と同じ。maphash の順序をそろえるため。target-hash-table.lisp の
// %recompute-ht-vector-sizes・grow-hash-table・define-puthash/flat）
//
// - 初めの枠の数は :size（7 未満なら 7。省略すると 7）。
// - 小さい eq・eql の表（:size が eq は 32 以下、eql は 16 以下）は flat の表として始める（SBCL は線形に探す形。
//   Zilisp は鎖も使って探す）。flat の表は、削除した枠を空き枠の一覧に積まず、挿入では空いている枠のうち
//   いちばん番号の大きいものを使う。:size を省いた flat の表の枠の数は 8。
// - 枠が埋まったら大きくする：新しい数は 1.5 倍（少なくとも 1 増やす）で、2 の冪のバケット数に対する割合が
//   0.9 を超えれば 0.85、0.55 未満なら 0.65 にする。flat の表は、バケット数が上限以下なら枠の数をバケット数にして
//   flat のまま、超えたら flat でない表にする。

const default_size = 7;
const flat_flag: u8 = 1;

fn flatLimit(test_kind: HashTest) u32 {
    return switch (test_kind) {
        .eq => 32,
        .eql => 16,
        .equal, .equalp => 0,
    };
}

fn isFlat(t: *const HashTable) bool {
    return t.header.flags & flat_flag != 0;
}

/// 大きくしたときの枠の数とバケット数（SBCL の %recompute-ht-vector-sizes。rehash-size は既定の 1.5）
fn grownSizes(old: u32) struct { size: u32, buckets: u32 } {
    const f: f32 = 1.5 * @as(f32, @floatFromInt(old));
    var size: u32 = @max(@as(u32, @intFromFloat(@trunc(f))), old + 1);
    const buckets = std.math.ceilPowerOfTwoAssert(u32, size);
    const lf = @as(f32, @floatFromInt(size)) / @as(f32, @floatFromInt(buckets));
    if (lf > 0.9) {
        size = @intFromFloat(@floor(0.85 * @as(f32, @floatFromInt(buckets))));
    } else if (lf < 0.55) {
        size = @intFromFloat(@floor(0.65 * @as(f32, @floatFromInt(buckets))));
    }
    return .{ .size = size, .buckets = buckets };
}

/// 枠が埋まった表を大きくする
fn grow(th: *Thread, table: Value) bool {
    const t = tablePtr(table);
    const g = grownSizes(t.size);
    if (isFlat(t) and g.buckets <= flatLimit(testOf(t))) return resize(th, table, g.buckets);
    t.header.flags &= ~flat_flag;
    return resize(th, table, g.size);
}

/// キーがないことを確かめてから、新しい項目を入れる。h はキーのハッシュ値。メモリが足りなければ偽（エラーを記録済み）
fn insertNew(th: *Thread, table: Value, k: Value, v: Value, h: u64) bool {
    var t = tablePtr(table);
    var i: u32 = undefined;
    if (isFlat(t) and t.count < t.hwm) {
        // flat の表：空いている枠のうち、いちばん番号の大きいもの
        i = t.hwm;
        while (kvOf(t)[2 * i] != Value.unbound) i -= 1;
    } else if (t.free != 0) {
        // 削除した枠を、後に削除したものから使う
        i = t.free;
        t.free = nextOf(t)[i];
    } else {
        if (t.hwm == t.size) {
            if (!grow(th, table)) return false;
            t = tablePtr(table);
        }
        t.hwm += 1;
        i = t.hwm;
    }
    const kv = kvOf(t);
    kv[2 * i] = k;
    kv[2 * i + 1] = v;
    if (hashesOf(t)) |hs| hs[i] = h;
    const ix = indexOf(t);
    const b: usize = @intCast(h & (ix.len - 1));
    nextOf(t)[i] = ix[b];
    ix[b] = i;
    t.count += 1;
    return true;
}

/// size は :size の値（省略なら null）
pub fn makeTable(th: *Thread, test_kind: HashTest, size_arg: ?usize) Value {
    const n: usize = @max(size_arg orelse default_size, default_size);
    const flat = n <= flatLimit(test_kind);
    // :size を省いた（または 7 を指定した）flat の表の枠の数はバケット数の 8（SBCL は最初の挿入で 8 にする）
    const size = if (flat and n == default_size) bucketsFor(n) else n;
    const t = th.rt.heap.create(HashTable, 0) catch return th.outOfMemory();
    t.* = .{
        .header = .{ .kind = .hash_table, .flags = if (flat) flat_flag else 0, .aux = @backingInt(test_kind) },
        .kv = Value.nil,
        .links = Value.nil,
        .hashes = Value.nil,
        .count = 0,
        .hwm = 0,
        .free = 0,
        .size = 0,
    };
    const table = Value.fromPointer(t, .other);
    if (!resize(th, table, size)) return Value.unwind;
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
    var size: ?usize = null;
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
        return kvOf(t)[2 * i + 1];
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
    const h = hashOf(th, t, k) orelse return Value.unwind;
    if (findH(th, t, k, h) catch return Value.unwind) |i| {
        kvOf(t)[2 * i + 1] = v;
        return v;
    }
    if (!insertNew(th, table, k, v, h)) return Value.unwind;
    return v;
}

pub fn remhash(th: *Thread, args: []const Value) Value {
    if (checkTable(th, args[1])) |e| return e;
    const t = tablePtr(args[1]);
    const k = args[0];
    const h = hashOf(th, t, k) orelse return Value.unwind;
    const index = indexOf(t);
    const next = nextOf(t);
    const hashes = hashesOf(t);
    const b: usize = @intCast(h & (index.len - 1));
    var prev: u32 = 0;
    var i = index[b];
    while (i != 0) : ({
        prev = i;
        i = next[i];
    }) {
        if (hashes) |hs| if (hs[i] != h) continue;
        if (!(same(th, t, kvOf(t)[2 * i], k) orelse return Value.unwind)) continue;
        // 鎖から外し、空き枠の一覧の先頭に積む（flat の表は積まない：挿入で空いている枠を探す）
        if (prev == 0) index[b] = next[i] else next[prev] = next[i];
        const kv = kvOf(t);
        kv[2 * i] = Value.unbound;
        kv[2 * i + 1] = Value.nil;
        if (!isFlat(t)) {
            next[i] = t.free;
            t.free = i;
        }
        t.count -= 1;
        return th.rt.t;
    }
    return Value.nil;
}

pub fn clrhash(th: *Thread, args: []const Value) Value {
    if (checkTable(th, args[0])) |e| return e;
    const t = tablePtr(args[0]);
    @memset(kvOf(t), Value.unbound);
    @memset(Runtime.rawVectorPtr(t.links).items(u32), 0);
    t.count = 0;
    t.hwm = 0;
    t.free = 0;
    return args[0];
}

/// maphash 関数 表：各項目について、枠の番号の順に (関数 キー 値) を呼ぶ（SBCL 2.6.7 と同じ順序）。
/// 呼び出しの中で許される変更は、その項目の setf・remhash だけ（CLHS 3.6）
pub fn maphash(th: *Thread, args: []const Value) Value {
    if (checkTable(th, args[1])) |e| return e;
    const table = args[1];
    // 項目を加えることは許されないので、使った枠の最大の番号は最初に読んだものでよい（SBCL と同じ）
    const limit = tablePtr(table).hwm;
    var i: u32 = 1;
    while (i <= limit) : (i += 1) {
        // 呼び出しの中で表が作り直されても（未定義の動作）壊れないよう、毎回引き直す
        const kv = kvOf(tablePtr(table));
        if (2 * i + 1 >= kv.len) break;
        const k = kv[2 * i];
        if (k == Value.unbound) continue;
        const argv = [_]Value{ k, kv[2 * i + 1] };
        if (th.call(args[0], &argv) == Value.unwind) return Value.unwind;
    }
    std.mem.doNotOptimizeAway(table);
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

/// ZILISP-SYSTEM::%HASH-PAIRS 表：((キー . 値) ...) のリスト。枠の番号の順（maphash と同じ。loop の being the hash-keys・
/// hash-values が使う。Phase 19）
pub fn sysHashPairs(th: *Thread, args: []const Value) Value {
    if (checkTable(th, args[0])) |e| return e;
    const table = args[0];
    var list = Value.nil;
    // 後ろから前に積むと、リストは枠の番号の順になる。確保で GC が起きても表は動かないが、配列は毎回引き直す
    var i: u32 = tablePtr(table).hwm;
    while (i >= 1) : (i -= 1) {
        const kv = kvOf(tablePtr(table));
        const k = kv[2 * i];
        if (k == Value.unbound) continue;
        const pair = th.rt.cons(k, kv[2 * i + 1]) catch return th.outOfMemory();
        list = th.rt.cons(pair, list) catch return th.outOfMemory();
    }
    std.mem.doNotOptimizeAway(table);
    return list;
}
