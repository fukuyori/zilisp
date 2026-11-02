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
    /// 束縛のスタックの深さ（fixnum）を積む（Phase 14）
    binding_depth,
    /// [値] → []：定数のシンボルを値で動的に束縛する
    bind_special,
    /// [値 深さ] → [値]：束縛のスタックを深さまで戻す
    unbind_to,
    /// [シンボルのリスト 値のリスト] → []：progv の束縛
    progv_bind,
    // 関数
    load_function,
    /// シンボルの setf 関数を積む（Phase 16）
    load_setf_function,
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
    // 多値（Phase 17。§6.3）
    /// [v1 ... vn] → [v1]：n 個の値を多値にする（th.mv_count = n）
    values,
    /// 単値にする（th.mv_count = 1）
    single,
    /// [主値] → [全部の値のリスト]
    mv_list,
    /// [主値] → [v1 ... vn]：値を n 個だけ積む（足りない分は NIL）
    mv_push_n,
    /// [リスト] → [主値]：リストの要素を多値にする（mv_list の逆）
    mv_restore,
    // 非局所脱出（Phase 18。§6.4）。*_enter の rel は、脱出したときに再開する位置（その位置の深さは、
    // block_enter・catch_enter では命令の後の深さ + 1、uwp_enter では + 2）
    /// []：block の識別子を作って局所変数 i に置き、制御スタックにエントリを積む
    block_enter,
    /// [タグ] → []：catch のエントリを積む
    catch_enter,
    /// []：unwind-protect のエントリを積む。rel は cleanup の先頭
    uwp_enter,
    /// 制御スタックから n 個のエントリを取り除く（block・catch を普通に抜けるとき、ジャンプで抜けるとき）
    control_pop,
    /// [主値] → [主値 印]：unwind-protect のエントリを取り除き、全部の値を退避する（Thread.uwpSave）
    uwp_save,
    /// [主値 印] → [主値]：退避した値を戻す。脱出・エラーの途中なら、それを続ける（Thread.uwpEnd）
    uwp_end,
    /// [識別子 値]：return-from の実行時の脱出（この後には進まない）
    return_from_nl,
    /// [タグ 値]：throw（この後には進まない）
    throw,
    /// [x1 ... xn v] → [v]：ジャンプで block を抜けるとき、途中の値を取り除く
    slide,
    /// 次の命令の k・i・n を 32 ビットにする
    wide,
};

pub const Operand = enum { k, i, n, rel, s16 };

pub fn operands(op: Op) []const Operand {
    return switch (op) {
        .@"const", .load_special, .store_special, .load_function, .load_setf_function, .bind_special => &.{.k},
        .load_local, .store_local, .load_captured => &.{.i},
        .smallint => &.{.s16},
        .make_closure, .call_global => &.{ .k, .n },
        .call, .values, .mv_push_n, .control_pop, .slide => &.{.n},
        .jump, .jump_if_nil, .catch_enter, .uwp_enter => &.{.rel},
        .block_enter => &.{ .i, .rel },
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
        .@"const", .nil, .t, .smallint, .load_local, .load_captured, .load_special, .load_function, .load_setf_function => 1,
        .pop, .cell_set, .jump_if_nil, .@"return", .bind_special, .unbind_to => -1,
        .binding_depth => 1,
        .progv_bind => -2,
        .store_local, .store_special, .make_cell, .cell_ref, .jump, .wide => 0,
        .car, .cdr, .not, .add1, .sub1 => 0,
        .cons, .eq, .add2, .sub2, .lt2, .gt2, .le2, .ge2, .numeq2 => -1,
        .make_closure => 1 - ni,
        .values => 1 - ni,
        .mv_push_n => ni - 1,
        .single, .mv_list, .mv_restore => 0,
        .call => -ni,
        .call_global => 1 - ni,
        .block_enter, .uwp_enter, .control_pop => 0,
        .catch_enter, .uwp_end => -1,
        .uwp_save => 1,
        .return_from_nl, .throw => -2,
        .slide => -ni,
    };
}

/// 脱出したときに rel の位置で再開する深さ（命令の後の深さに加える数）。脱出先を作る命令でなければ null
pub fn landingExtra(op: Op) ?i64 {
    return switch (op) {
        .block_enter, .catch_enter => 1,
        .uwp_enter => 2,
        else => null,
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
