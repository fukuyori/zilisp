//! バイトコードの命令（詳細設計 §7.3・§7.4）。Phase 08 の範囲の命令だけを定義する。
//!
//! 符号化：オペコードは u8。オペランドはリトルエンディアンで、命令ごとに幅を固定する。
//!   k   = 定数表の添字 u16      i = 局所変数・捕捉した値の添字 u16
//!   n   = 個数 u8               rel = 相対ジャンプ i32（命令の末尾から数える）
//!   s16 = 小さい整数 i16
//! 接頭命令 WIDE の直後の命令では、k・i を u32、n を u32 にする（§7.3、レビュー #17）。

const std = @import("std");

pub const Op = enum(u8) {
    // 定数
    @"const",
    nil,
    t,
    smallint,
    // スタック
    pop,
    // 局所変数
    load_local,
    /// 値をスタックに残したまま局所変数に書く
    store_local,
    load_captured,
    /// スタックの先頭の値を箱（value_cell）に入れる
    make_cell,
    /// 箱の中身を取り出す
    cell_ref,
    /// [値 箱] → [値]：箱に書く
    cell_set,
    // 大域変数（特殊変数）
    load_special,
    /// 値をスタックに残したまま書く
    store_special,
    // 関数
    load_function,
    make_closure,
    /// [関数 引数...] → [値]
    call,
    /// [引数...] → [値]：シンボルの関数セルを呼ぶ
    call_global,
    @"return",
    // 制御
    jump,
    /// 先頭の値を取り除き、NIL ならジャンプする
    jump_if_nil,
    // 高速経路（fixnum・cons を直接扱い、それ以外は汎用の処理へ）
    cons,
    car,
    cdr,
    eq,
    not,
    add2,
    sub2,
    lt2,
    gt2,
    le2,
    ge2,
    numeq2,
    add1,
    sub1,
    /// 次の命令の k・i・n を 32 ビットにする
    wide,
};

pub const Operand = enum { k, i, n, rel, s16 };

pub fn operands(op: Op) []const Operand {
    return switch (op) {
        .@"const", .load_special, .store_special, .load_function => &.{.k},
        .load_local, .store_local, .load_captured => &.{.i},
        .smallint => &.{.s16},
        .make_closure, .call_global => &.{ .k, .n },
        .call => &.{.n},
        .jump, .jump_if_nil => &.{.rel},
        else => &.{},
    };
}

pub fn operandSize(o: Operand, wide: bool) usize {
    return switch (o) {
        .k, .i => if (wide) 4 else 2,
        .n => if (wide) 4 else 1,
        .rel => 4,
        .s16 => 2,
    };
}

/// 命令の長さ（オペコードを含む。WIDE 自身は 1）
pub fn length(op: Op, wide: bool) usize {
    var len: usize = 1;
    for (operands(op)) |o| len += operandSize(o, wide);
    return len;
}

/// スタックの深さの変化。n はその命令の個数のオペランド（なければ 0）
pub fn stackEffect(op: Op, n: u32) i64 {
    const ni: i64 = n;
    return switch (op) {
        .@"const", .nil, .t, .smallint, .load_local, .load_captured, .load_special, .load_function => 1,
        .pop, .cell_set, .jump_if_nil, .@"return" => -1,
        .store_local, .store_special, .make_cell, .cell_ref, .jump, .wide => 0,
        .car, .cdr, .not, .add1, .sub1 => 0,
        .cons, .eq, .add2, .sub2, .lt2, .gt2, .le2, .ge2, .numeq2 => -1,
        .make_closure => 1 - ni,
        .call => -ni,
        .call_global => 1 - ni,
    };
}

pub inline fn readU16(bc: [*]const u8, at: usize) u16 {
    return std.mem.readInt(u16, bc[at..][0..2], .little);
}
pub inline fn readU32(bc: [*]const u8, at: usize) u32 {
    return std.mem.readInt(u32, bc[at..][0..4], .little);
}
pub inline fn readI32(bc: [*]const u8, at: usize) i32 {
    return std.mem.readInt(i32, bc[at..][0..4], .little);
}
pub inline fn readI16(bc: [*]const u8, at: usize) i16 {
    return std.mem.readInt(i16, bc[at..][0..2], .little);
}
