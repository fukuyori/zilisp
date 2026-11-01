//! 明示的なルートと FFI handle（詳細設計 §3.5・§3.6）。
//!
//! ネイティブのスタック以外の場所（Zig のヒープ上の構造体、static 変数、C ライブラリに渡す構造体など）に
//! Lisp の値を保持する場合だけ、ここに登録する。登録した値は GC のルートとして正確に走査する（Phase 07）。
//!
//! handle は「表の番号」と「世代番号」の組。解放済みの handle や、番号が再利用された後の古い handle を使うと
//! null を返す（§3.6）。C 側へは Lisp オブジェクトのアドレスではなく handle（64 ビットの整数）を渡す。

const std = @import("std");
const Value = @import("../values/value.zig").Value;

pub const Handle = packed struct(u64) {
    index: u32,
    generation: u32,

    pub fn toInt(h: Handle) u64 {
        return @bitCast(h);
    }
    pub fn fromInt(x: u64) Handle {
        return @bitCast(x);
    }
};

pub const Roots = struct {
    gpa: std.mem.Allocator,
    values: std.ArrayList(Value) = .empty,
    /// 番号ごとの世代。使用中は奇数、空きは偶数
    generations: std.ArrayList(u32) = .empty,
    free_list: std.ArrayList(u32) = .empty,
    live: usize = 0,

    pub fn init(gpa: std.mem.Allocator) Roots {
        return .{ .gpa = gpa };
    }

    pub fn deinit(r: *Roots) void {
        r.values.deinit(r.gpa);
        r.generations.deinit(r.gpa);
        r.free_list.deinit(r.gpa);
    }

    pub fn register(r: *Roots, v: Value) error{OutOfMemory}!Handle {
        if (r.free_list.pop()) |i| {
            r.generations.items[i] +%= 1; // 偶数 → 奇数（使用中）
            r.values.items[i] = v;
            r.live += 1;
            return .{ .index = i, .generation = r.generations.items[i] };
        }
        const i: u32 = @intCast(r.values.items.len);
        try r.values.append(r.gpa, v);
        errdefer _ = r.values.pop();
        try r.generations.append(r.gpa, 1);
        r.live += 1;
        return .{ .index = i, .generation = 1 };
    }

    fn valid(r: *const Roots, h: Handle) bool {
        return h.index < r.values.items.len and r.generations.items[h.index] == h.generation and h.generation % 2 == 1;
    }

    pub fn get(r: *const Roots, h: Handle) ?Value {
        if (!r.valid(h)) return null;
        return r.values.items[h.index];
    }

    pub fn set(r: *Roots, h: Handle, v: Value) bool {
        if (!r.valid(h)) return false;
        r.values.items[h.index] = v;
        return true;
    }

    /// 登録を解除する。既に解除済み・古い handle なら false
    pub fn unregister(r: *Roots, h: Handle) bool {
        if (!r.valid(h)) return false;
        r.generations.items[h.index] +%= 1; // 奇数 → 偶数（空き）
        r.values.items[h.index] = Value.nil;
        r.live -= 1;
        r.free_list.append(r.gpa, h.index) catch {
            // 空きの一覧に入れられなくても、その番号を使わないだけで正しさは保たれる
        };
        return true;
    }

    /// 登録中の値をすべて渡す（GC のルートの走査用）
    pub fn forEach(r: *const Roots, ctx: anytype, comptime f: fn (@TypeOf(ctx), Value) void) void {
        for (r.values.items, r.generations.items) |v, g| {
            if (g % 2 == 1) f(ctx, v);
        }
    }
};

const testing = std.testing;

test "register, get, unregister" {
    var r = Roots.init(testing.allocator);
    defer r.deinit();
    const a = try r.register(Value.fromFixnum(1));
    const b = try r.register(Value.fromFixnum(2));
    try testing.expectEqual(@as(i64, 1), r.get(a).?.asFixnum());
    try testing.expectEqual(@as(i64, 2), r.get(b).?.asFixnum());
    try testing.expect(r.unregister(a));
    try testing.expect(r.get(a) == null);
    try testing.expect(!r.unregister(a)); // 二重の解除
    // 番号は再利用されるが、古い handle は無効のまま
    const c = try r.register(Value.fromFixnum(3));
    try testing.expectEqual(a.index, c.index);
    try testing.expect(r.get(a) == null);
    try testing.expectEqual(@as(i64, 3), r.get(c).?.asFixnum());
    try testing.expectEqual(@as(usize, 2), r.live);
}

test "handle round trips through an integer (for C)" {
    var r = Roots.init(testing.allocator);
    defer r.deinit();
    const h = try r.register(Value.nil);
    const back = Handle.fromInt(h.toInt());
    try testing.expectEqual(h, back);
    try testing.expectEqual(Value.nil, r.get(back).?);
    try testing.expect(r.get(Handle.fromInt(0xFFFF_FFFF_0000_0000)) == null);
}

test "forEach visits only live roots" {
    var r = Roots.init(testing.allocator);
    defer r.deinit();
    _ = try r.register(Value.fromFixnum(10));
    const b = try r.register(Value.fromFixnum(20));
    _ = try r.register(Value.fromFixnum(30));
    _ = r.unregister(b);
    var sum: i64 = 0;
    r.forEach(&sum, struct {
        fn f(s: *i64, v: Value) void {
            s.* += v.asFixnum();
        }
    }.f);
    try testing.expectEqual(@as(i64, 40), sum);
}
