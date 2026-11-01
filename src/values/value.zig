//! Lisp の値（詳細設計 §2）。8 バイトの 1 語で、下位ビットに型のタグを置く。
//! ビット操作はこのファイル（と object.zig）の中だけで行う。他の層はメソッド経由で扱う。
//!
//!   ...xx00  fixnum（62 ビット。値は 2 ビット左にずらして格納）
//!   ...x001  cons へのポインタ
//!   ...x011  ヘッダ付きオブジェクトへのポインタ
//!   ...x101  関数オブジェクトへのポインタ
//!   ...x111  即値（下位 8 ビットで種類を区別する）
//!
//! 即値の内訳（下位 8 ビット = 種類 << 3 | 0b111）
//!   0x07 NIL、0x0F 未束縛（unbound）、0x17 unwind（関数の戻り値として、非局所脱出・エラーの途中を表す）、
//!   0x1F 文字（ビット 8〜28 にコードポイント）、0x27 single-float（ビット 32〜63 に f32）

const std = @import("std");

pub const Tag = enum(u3) {
    cons = 0b001,
    other = 0b011,
    function = 0b101,
    immediate = 0b111,
};

const imm_nil: u64 = 0x07;
const imm_unbound: u64 = 0x0F;
const imm_unwind: u64 = 0x17;
const imm_char: u64 = 0x1F;
const imm_single: u64 = 0x27;

pub const most_positive_fixnum: i64 = (1 << 61) - 1;
pub const most_negative_fixnum: i64 = -(1 << 61);

pub const Value = enum(u64) {
    _,

    pub const nil: Value = @fromBackingInt(imm_nil);
    pub const unbound: Value = @fromBackingInt(imm_unbound);
    pub const unwind: Value = @fromBackingInt(imm_unwind);

    pub inline fn raw(v: Value) u64 {
        return @backingInt(v);
    }
    pub inline fn fromRaw(r: u64) Value {
        return @fromBackingInt(r);
    }

    // --- fixnum
    pub inline fn isFixnum(v: Value) bool {
        return v.raw() & 0b11 == 0;
    }
    pub inline fn fixnumFits(i: i64) bool {
        return i >= most_negative_fixnum and i <= most_positive_fixnum;
    }
    /// `i` は fixnum の範囲に入っていること（fixnumFits で確かめる）
    pub inline fn fromFixnum(i: i64) Value {
        std.debug.assert(fixnumFits(i));
        return fromRaw(@bitCast(i << 2));
    }
    pub inline fn asFixnum(v: Value) i64 {
        std.debug.assert(v.isFixnum());
        return @as(i64, @bitCast(v.raw())) >> 2;
    }

    // --- ポインタ
    pub inline fn lowTag(v: Value) u3 {
        return @truncate(v.raw());
    }
    pub inline fn isCons(v: Value) bool {
        return v.lowTag() == @backingInt(Tag.cons);
    }
    pub inline fn isOther(v: Value) bool {
        return v.lowTag() == @backingInt(Tag.other);
    }
    pub inline fn isFunctionPointer(v: Value) bool {
        return v.lowTag() == @backingInt(Tag.function);
    }
    pub inline fn isImmediate(v: Value) bool {
        return v.lowTag() == @backingInt(Tag.immediate);
    }
    pub inline fn fromPointer(ptr: *const anyopaque, tag: Tag) Value {
        const addr = @intFromPtr(ptr);
        std.debug.assert(addr & 0b111 == 0);
        return fromRaw(addr | @backingInt(tag));
    }
    pub inline fn pointer(v: Value) *anyopaque {
        return @ptrFromInt(v.raw() & ~@as(u64, 0b111));
    }

    // --- NIL・特別な値
    pub inline fn isNil(v: Value) bool {
        return v == nil;
    }
    /// リスト（cons または NIL）か
    pub inline fn isList(v: Value) bool {
        return v.isCons() or v == nil;
    }

    // --- 文字
    pub inline fn fromChar(cp: u21) Value {
        return fromRaw((@as(u64, cp) << 8) | imm_char);
    }
    pub inline fn isChar(v: Value) bool {
        return v.raw() & 0xFF == imm_char;
    }
    pub inline fn asChar(v: Value) u21 {
        std.debug.assert(v.isChar());
        return @truncate(v.raw() >> 8);
    }

    // --- single-float
    pub inline fn fromSingle(f: f32) Value {
        return fromRaw((@as(u64, @as(u32, @bitCast(f))) << 32) | imm_single);
    }
    pub inline fn isSingleFloat(v: Value) bool {
        return v.raw() & 0xFF == imm_single;
    }
    pub inline fn asSingle(v: Value) f32 {
        std.debug.assert(v.isSingleFloat());
        return @bitCast(@as(u32, @truncate(v.raw() >> 32)));
    }
};

const testing = std.testing;

test "fixnum round trip and range" {
    for ([_]i64{ 0, 1, -1, 42, most_positive_fixnum, most_negative_fixnum }) |i| {
        const v = Value.fromFixnum(i);
        try testing.expect(v.isFixnum());
        try testing.expectEqual(i, v.asFixnum());
        try testing.expect(!v.isCons() and !v.isImmediate());
    }
    try testing.expect(!Value.fixnumFits(most_positive_fixnum + 1));
    try testing.expect(!Value.fixnumFits(most_negative_fixnum - 1));
}

test "tagged fixnum addition detects 62-bit overflow" {
    const a = Value.fromFixnum(most_positive_fixnum).raw();
    const one = Value.fromFixnum(1).raw();
    const r = @addWithOverflow(@as(i64, @bitCast(a)), @as(i64, @bitCast(one)));
    try testing.expectEqual(@as(u1, 1), r[1]);
    const b = Value.fromFixnum(40).raw();
    const s = @addWithOverflow(@as(i64, @bitCast(b)), @as(i64, @bitCast(Value.fromFixnum(2).raw())));
    try testing.expectEqual(@as(i64, 42), Value.fromRaw(@bitCast(s[0])).asFixnum());
}

test "immediates are distinct" {
    try testing.expect(Value.nil != Value.unbound and Value.nil != Value.unwind);
    try testing.expect(Value.nil.isImmediate() and !Value.nil.isFixnum());
    try testing.expect(Value.nil.isList() and !Value.nil.isCons());
    const c = Value.fromChar('λ');
    try testing.expect(c.isChar() and !c.isSingleFloat());
    try testing.expectEqual(@as(u21, 'λ'), c.asChar());
    try testing.expect(!Value.nil.isChar());
}

test "single float immediate" {
    for ([_]f32{ 0.0, -0.0, 1.5, std.math.floatMax(f32), std.math.inf(f32) }) |f| {
        const v = Value.fromSingle(f);
        try testing.expect(v.isSingleFloat() and v.isImmediate());
        try testing.expectEqual(@as(u32, @bitCast(f)), @as(u32, @bitCast(v.asSingle())));
    }
}

test "pointer tagging" {
    var cell: [2]u64 align(16) = .{ 0, 0 };
    const v = Value.fromPointer(&cell, .cons);
    try testing.expect(v.isCons() and !v.isOther());
    try testing.expectEqual(@intFromPtr(&cell), @intFromPtr(v.pointer()));
}
