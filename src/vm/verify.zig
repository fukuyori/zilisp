//! バイトコードの検証器（詳細設計 §7.4、レビュー #20）。
//! コンパイラが生成した直後（デバッグビルドと試験）に、次を確かめる。
//!   - 命令の境界：すべての命令とジャンプ先が命令の先頭にある。末尾で途切れていない
//!   - 添字の範囲：定数表・局所変数・捕捉した値
//!   - スタックの深さ：どの経路でも同じ位置では同じ深さ。負にならず、max_stack を超えない。return では 1
//!   - 制御スタック（Phase 18）：この関数が積んだエントリの並び（block・catch・unwind-protect）と、実行中の cleanup を
//!     位置ごとに求め、どの経路でも同じ位置では同じ並び。CONTROL_POP は block・catch だけを、UWP_SAVE は unwind-protect の
//!     エントリを取り除き、UWP_END は cleanup の中でだけ使える。return ではエントリも cleanup も残っていない
//!     （Codex・agy のレビュー P18）
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
    /// 制御スタックの操作が、積んだエントリの並びと合わない
    BadControl,
    OutOfMemory,
};

/// 制御スタックの並びの要素
const Ctl = struct {
    const block: u8 = 'b';
    const catch_tag: u8 = 'c';
    const uwp: u8 = 'u';
    /// unwind-protect の cleanup の実行中（エントリは取り除いてある）
    const cleanup: u8 = 'C';
};

/// 制御スタックの並びを番号にする（同じ並びは同じ番号）
const CtlTable = struct {
    items: std.ArrayList([]u8) = .empty,

    fn intern(t: *CtlTable, gpa: std.mem.Allocator, seq: []const u8) VerifyError!u32 {
        for (t.items.items, 0..) |s, i| if (std.mem.eql(u8, s, seq)) return @intCast(i);
        try t.items.append(gpa, try gpa.dupe(u8, seq));
        return @intCast(t.items.items.len - 1);
    }

    fn deinit(t: *CtlTable, gpa: std.mem.Allocator) void {
        for (t.items.items) |s| gpa.free(s);
        t.items.deinit(gpa);
    }
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

    // スタックの深さ（-1 は未到達）と、制御スタックの並びの番号
    const depth = try gpa.alloc(i64, bc.len);
    defer gpa.free(depth);
    @memset(depth, -1);
    const ctl = try gpa.alloc(u32, bc.len);
    defer gpa.free(ctl);
    var table: CtlTable = .{};
    defer table.deinit(gpa);
    var cur: std.ArrayList(u8) = .empty;
    defer cur.deinit(gpa);
    var land: std.ArrayList(u8) = .empty;
    defer land.deinit(gpa);
    var work: std.ArrayList(usize) = .empty;
    defer work.deinit(gpa);
    depth[0] = 0;
    ctl[0] = try table.intern(gpa, "");
    try work.append(gpa, 0);
    while (work.pop()) |start| {
        var pc = start;
        var d = depth[pc];
        cur.clearRetainingCapacity();
        try cur.appendSlice(gpa, table.items.items[ctl[pc]]);
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
                if (cur.items.len != 0) return error.BadControl;
                break;
            }
            // 脱出（この後には進まない）
            if (insn.op == .return_from_nl or insn.op == .throw) break;
            // 制御スタックの並び。脱出したときに再開する位置の並びは land（エントリを取り除いた並び。cleanup なら印を加える）
            land.clearRetainingCapacity();
            try land.appendSlice(gpa, cur.items);
            switch (insn.op) {
                .block_enter => try cur.append(gpa, Ctl.block),
                .catch_enter => try cur.append(gpa, Ctl.catch_tag),
                .uwp_enter => {
                    try land.append(gpa, Ctl.cleanup);
                    try cur.append(gpa, Ctl.uwp);
                },
                .control_pop => {
                    if (insn.count > cur.items.len) return error.BadControl;
                    for (cur.items[cur.items.len - insn.count ..]) |k| {
                        if (k != Ctl.block and k != Ctl.catch_tag) return error.BadControl;
                    }
                    cur.shrinkRetainingCapacity(cur.items.len - insn.count);
                },
                .uwp_save => {
                    if (cur.items.len == 0 or cur.items[cur.items.len - 1] != Ctl.uwp) return error.BadControl;
                    cur.items[cur.items.len - 1] = Ctl.cleanup;
                },
                .uwp_end => {
                    if (cur.items.len == 0 or cur.items[cur.items.len - 1] != Ctl.cleanup) return error.BadControl;
                    _ = cur.pop();
                },
                else => {},
            }
            d += effect;
            if (d > max_stack) return error.StackOverflow;
            if (insn.target) |t| {
                if (!is_start[t]) return error.BadJumpTarget;
                // 脱出先を作る命令の rel は、脱出したときに値を積んで再開する位置
                const extra = ops.landingExtra(insn.op);
                const td = d + (extra orelse 0);
                if (td > max_stack) return error.StackOverflow;
                const tc = try table.intern(gpa, if (extra != null) land.items else cur.items);
                if (depth[t] == -1) {
                    depth[t] = td;
                    ctl[t] = tc;
                    try work.append(gpa, t);
                } else if (depth[t] != td or ctl[t] != tc) return error.StackMismatch;
            }
            if (insn.op == .jump) break;
            pc = insn.next;
            if (pc >= bc.len) return error.FallsOffEnd;
            const nc = try table.intern(gpa, cur.items);
            if (depth[pc] == -1) {
                depth[pc] = d;
                ctl[pc] = nc;
            } else {
                if (depth[pc] != d or ctl[pc] != nc) return error.StackMismatch;
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

test "verifier checks the control stack (Phase 18, Codex and agy review)" {
    const a = std.testing.allocator;
    const P = @backingInt(Op.control_pop);
    // 積んでいないエントリを取り除く：CONTROL_POP 1; NIL; RETURN
    try std.testing.expectError(error.BadControl, verify(a, &.{ P, 1, @backingInt(Op.nil), @backingInt(Op.@"return") }, 0, 0, 0, 1));
    // cleanup の外の UWP_END（偽の印 -1）：NIL; SMALLINT -1; UWP_END; RETURN
    try std.testing.expectError(error.BadControl, verify(a, &.{ @backingInt(Op.nil), @backingInt(Op.smallint), 0xFF, 0xFF, @backingInt(Op.uwp_end), @backingInt(Op.@"return") }, 0, 0, 0, 2));
    // エントリを残したまま戻る：BLOCK_ENTER 0 →L; NIL; RETURN; L: RETURN
    try std.testing.expectError(error.BadControl, verify(a, &.{ @backingInt(Op.block_enter), 0, 0, 2, 0, 0, 0, @backingInt(Op.nil), @backingInt(Op.@"return"), @backingInt(Op.@"return") }, 0, 1, 0, 1));
    // 正しい形：BLOCK_ENTER 0 →L; NIL; CONTROL_POP 1; L: RETURN
    try verify(a, &.{ @backingInt(Op.block_enter), 0, 0, 3, 0, 0, 0, @backingInt(Op.nil), P, 1, @backingInt(Op.@"return") }, 0, 1, 0, 1);
    // unwind-protect の正しい形：UWP_ENTER →L; NIL; UWP_SAVE; L: UWP_END; RETURN
    try verify(a, &.{ @backingInt(Op.uwp_enter), 2, 0, 0, 0, @backingInt(Op.nil), @backingInt(Op.uwp_save), @backingInt(Op.uwp_end), @backingInt(Op.@"return") }, 0, 0, 0, 2);
    // UWP_SAVE で block のエントリを取り除こうとする：BLOCK_ENTER 0 →L; NIL; UWP_SAVE; POP; RETURN; L: RETURN
    try std.testing.expectError(error.BadControl, verify(a, &.{ @backingInt(Op.block_enter), 0, 0, 4, 0, 0, 0, @backingInt(Op.nil), @backingInt(Op.uwp_save), @backingInt(Op.pop), @backingInt(Op.@"return"), @backingInt(Op.@"return") }, 0, 1, 0, 2));
}
