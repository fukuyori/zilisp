//! バイトコードの検証器（詳細設計 §7.4、レビュー #20）。
//! コンパイラが生成した直後（デバッグビルドと試験）に、次を確かめる。
//!   - 命令の境界：すべての命令とジャンプ先が命令の先頭にある。末尾で途切れていない
//!   - 添字の範囲：定数表・局所変数・捕捉した値
//!   - スタックの深さ：どの経路でも同じ位置では同じ深さ。負にならず、max_stack を超えない。return では 1
//! .zfasl から読み込んだバイトコードにも、ロードの時点で同じ検証を行う（Phase 35）。

const std = @import("std");
const ops = @import("opcodes.zig");
const Op = ops.Op;

pub const VerifyError = error{
    Truncated,
    BadOpcode,
    BadJumpTarget,
    BadConstIndex,
    BadLocalIndex,
    BadCapturedIndex,
    StackUnderflow,
    StackOverflow,
    StackMismatch,
    BadReturnDepth,
    /// WIDE の後の命令が、添字・個数のオペランドを持たない
    BadWide,
    FallsOffEnd,
    OutOfMemory,
};

const Insn = struct {
    op: Op,
    /// 命令の先頭（WIDE を含む）
    start: usize,
    /// 次の命令の先頭
    next: usize,
    index: u32 = 0,
    count: u32 = 0,
    target: ?usize = null,
};

fn decode(bc: []const u8, at: usize) VerifyError!Insn {
    var p = at;
    var wide = false;
    if (bc[p] == @backingInt(Op.wide)) {
        wide = true;
        p += 1;
        if (p >= bc.len) return error.Truncated;
    }
    const op = std.enums.fromInt(Op, bc[p]) orelse return error.BadOpcode;
    if (op == .wide) return error.BadOpcode;
    // WIDE は直後の命令の k・i・n にだけ効く。それを持たない命令の前の WIDE は拒否する
    // （VM は、オペランドを読む命令まで WIDE の印を残すため、検証器と VM で解釈が分かれないように）
    if (wide) {
        var has = false;
        for (ops.operands(op)) |o| {
            if (o == .k or o == .i or o == .n) has = true;
        }
        if (!has) return error.BadWide;
    }
    var insn: Insn = .{ .op = op, .start = at, .next = 0 };
    p += 1;
    for (ops.operands(op)) |o| {
        const size = ops.operandSize(o, wide);
        if (p + size > bc.len) return error.Truncated;
        switch (o) {
            .k, .i => insn.index = if (wide) ops.readU32(bc.ptr, p) else ops.readU16(bc.ptr, p),
            .n => insn.count = if (wide) ops.readU32(bc.ptr, p) else bc[p],
            .rel => {
                const end: i64 = @intCast(p + 4);
                const t = end + ops.readI32(bc.ptr, p);
                if (t < 0 or t >= bc.len) return error.BadJumpTarget;
                insn.target = @intCast(t);
            },
            .s16 => {},
        }
        p += size;
    }
    insn.next = p;
    return insn;
}

pub fn verify(gpa: std.mem.Allocator, bc: []const u8, nconsts: usize, nlocals: u32, ncaptured: u32, max_stack: u32) VerifyError!void {
    if (bc.len == 0) return error.FallsOffEnd;

    // 命令の先頭の印
    const is_start = try gpa.alloc(bool, bc.len);
    defer gpa.free(is_start);
    @memset(is_start, false);
    var at: usize = 0;
    while (at < bc.len) {
        const insn = try decode(bc, at);
        is_start[at] = true;
        switch (insn.op) {
            .@"const", .load_special, .store_special, .load_function, .load_setf_function, .make_closure, .call_global, .bind_special => if (insn.index >= nconsts) return error.BadConstIndex,
            .load_local, .store_local, .block_enter => if (insn.index >= nlocals) return error.BadLocalIndex,
            .load_captured => if (insn.index >= ncaptured) return error.BadCapturedIndex,
            else => {},
        }
        at = insn.next;
    }
    // ジャンプ先は、到達するかどうかに関係なく、すべて命令の先頭でなければならない
    at = 0;
    while (at < bc.len) {
        const insn = try decode(bc, at);
        if (insn.target) |t| {
            if (!is_start[t]) return error.BadJumpTarget;
        }
        at = insn.next;
    }

    // スタックの深さ（-1 は未到達）
    const depth = try gpa.alloc(i64, bc.len);
    defer gpa.free(depth);
    @memset(depth, -1);
    var work: std.ArrayList(usize) = .empty;
    defer work.deinit(gpa);
    depth[0] = 0;
    try work.append(gpa, 0);
    while (work.pop()) |start| {
        var pc = start;
        var d = depth[pc];
        while (true) {
            const insn = try decode(bc, pc);
            const effect = ops.stackEffect(insn.op, insn.count);
            // 命令が取り出す値の数（効果が負でない命令でも、取り出してから積むものがある）
            const pops: i64 = switch (insn.op) {
                .call => insn.count + 1,
                .call_global, .make_closure => insn.count,
                .store_local, .store_special, .make_cell, .cell_ref, .car, .cdr, .not, .add1, .sub1, .pop, .jump_if_nil, .@"return", .bind_special, .mv_list, .mv_push_n, .mv_restore, .catch_enter, .uwp_save => 1,
                .values => insn.count,
                .slide => insn.count + 1,
                .cell_set, .cons, .eq, .add2, .sub2, .lt2, .gt2, .le2, .ge2, .numeq2, .unbind_to, .progv_bind, .uwp_end, .return_from_nl, .throw => 2,
                else => 0,
            };
            if (d < pops) return error.StackUnderflow;
            if (insn.op == .@"return") {
                if (d != 1) return error.BadReturnDepth;
                break;
            }
            // 脱出（この後には進まない）
            if (insn.op == .return_from_nl or insn.op == .throw) break;
            d += effect;
            if (d > max_stack) return error.StackOverflow;
            if (insn.target) |t| {
                if (!is_start[t]) return error.BadJumpTarget;
                // 脱出先を作る命令の rel は、脱出したときに値を積んで再開する位置
                const td = d + (ops.landingExtra(insn.op) orelse 0);
                if (td > max_stack) return error.StackOverflow;
                if (depth[t] == -1) {
                    depth[t] = td;
                    try work.append(gpa, t);
                } else if (depth[t] != td) return error.StackMismatch;
            }
            if (insn.op == .jump) break;
            pc = insn.next;
            if (pc >= bc.len) return error.FallsOffEnd;
            if (depth[pc] == -1) {
                depth[pc] = d;
            } else {
                if (depth[pc] != d) return error.StackMismatch;
                break; // 既に調べた経路に合流した
            }
        }
    }
}

test "verifier accepts a simple function and rejects bad code" {
    // (lambda (x) (if x 1 2))
    const good = [_]u8{
        @backingInt(Op.load_local),  0,                         0,
        @backingInt(Op.jump_if_nil), 8,                         0,
        0,                           0,                         @backingInt(Op.smallint),
        1,                           0,                         @backingInt(Op.jump),
        3,                           0,                         0,
        0,                           @backingInt(Op.smallint),  2,
        0,                           @backingInt(Op.@"return"),
    };
    try verify(std.testing.allocator, &good, 0, 1, 0, 1);
    try std.testing.expectError(error.BadLocalIndex, verify(std.testing.allocator, &good, 0, 0, 0, 1));
    try std.testing.expectError(error.StackOverflow, verify(std.testing.allocator, &good, 0, 1, 0, 0));
    const underflow = [_]u8{ @backingInt(Op.pop), @backingInt(Op.@"return") };
    try std.testing.expectError(error.StackUnderflow, verify(std.testing.allocator, &underflow, 0, 0, 0, 1));
    const bad_return = [_]u8{ @backingInt(Op.nil), @backingInt(Op.nil), @backingInt(Op.@"return") };
    try std.testing.expectError(error.BadReturnDepth, verify(std.testing.allocator, &bad_return, 0, 0, 0, 2));
    // 到達しない命令のジャンプ先が命令の途中（NIL; RETURN; JUMP -4 はジャンプ自身のオペランドを指す）
    const unreachable_jump = [_]u8{ @backingInt(Op.nil), @backingInt(Op.@"return"), @backingInt(Op.jump), 0xFC, 0xFF, 0xFF, 0xFF };
    try std.testing.expectError(error.BadJumpTarget, verify(std.testing.allocator, &unreachable_jump, 0, 0, 0, 1));
    // WIDE の後に、添字・個数を持たない命令（Codex のレビュー P14 #5 の例：WIDE; NIL; POP; CONST 0; RETURN）
    const bad_wide = [_]u8{ @backingInt(Op.wide), @backingInt(Op.nil), @backingInt(Op.pop), @backingInt(Op.@"const"), 0, 0, @backingInt(Op.@"return") };
    try std.testing.expectError(error.BadWide, verify(std.testing.allocator, &bad_wide, 1, 0, 0, 1));
    const falls = [_]u8{@backingInt(Op.nil)};
    try std.testing.expectError(error.FallsOffEnd, verify(std.testing.allocator, &falls, 0, 0, 0, 1));
}
