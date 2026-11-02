//! Core IR の検証器（Phase 12。詳細設計 §5.1）。
//! Resolver が作った IR が、バックエンド（VM・ネイティブ）の前提を満たすかを確かめる。
//! デバッグビルドと試験では、コンパイルのたびに実行する。
//!
//! 確かめること
//!   - 変数：持ち主の lambda、局所変数の番号の範囲、引数の番号の重複
//!   - 参照・代入：自分の lambda の変数か、捕捉の一覧にある変数か。外側の変数への代入は箱に入れた変数だけ
//!   - 捕捉：内側の lambda の捕捉の一覧の変数は、外側の lambda の変数か、外側の lambda も捕捉している変数
//!   - let：変数と初期値の数が同じ
//!   - 呼び出し：引数の個数が call-arguments-limit 未満。高速経路の命令の引数の個数
//!   - block・return-from（Phase 18）：ジャンプで抜ける return-from は、同じ lambda の、それを囲む block へ。
//!     実行時の脱出の脱出先の block は、識別子の局所変数を持つ

const std = @import("std");
const ir = @import("ir.zig");
const Node = ir.Node;
const Lambda = ir.Lambda;
const Var = ir.Var;
const call_arguments_limit = @import("../runtime/thread.zig").call_arguments_limit;

pub const IrError = error{
    BadOwner,
    BadSlot,
    DuplicateParam,
    NotVisible,
    BadAssignment,
    BadCapture,
    BadParent,
    LetArity,
    TooManyArgs,
    PrimArity,
    BadBlock,
};

/// 本体を調べている途中で、外側にある block（ジャンプで抜ける return-from の検査に使う）
const Enclosing = struct { blk: *const ir.Block, parent: ?*const Enclosing };

pub fn verify(l: *const Lambda) IrError!void {
    for (l.params, 0..) |p, i| {
        if (p.owner != l) return error.BadOwner;
        if (p.slot >= l.nlocals) return error.BadSlot;
        for (l.params[0..i]) |q| if (q.slot == p.slot) return error.DuplicateParam;
    }
    for (l.captures.items) |c| {
        if (!c.captured) return error.BadCapture;
        // 捕捉する変数は、外側の lambda のどれかが持つ
        var p = l.parent;
        var found = false;
        while (p) |pl| : (p = pl.parent) {
            if (c.owner == pl) {
                found = true;
                break;
            }
        }
        if (!found) return error.BadCapture;
    }
    for (l.blocks.items) |b| {
        if (b.lambda != l) return error.BadBlock;
        if (b.needs_entry) {
            if (b.token.owner != l or b.token.slot >= l.nlocals) return error.BadSlot;
        }
    }
    try node(l, l.body, null);
}

fn visible(l: *const Lambda, v: *const Var) IrError!void {
    // 特殊変数は IR の参照にならない（global_ref・global_set になる）
    if (v.special) return error.NotVisible;
    if (v.owner == l) {
        if (v.slot >= l.nlocals) return error.BadSlot;
        return;
    }
    if (!v.captured or l.captureIndex(v) == null) return error.NotVisible;
}

fn node(l: *const Lambda, n: *const Node, enc: ?*const Enclosing) IrError!void {
    switch (n.kind) {
        .constant, .global_ref, .global_fn, .global_setf_fn => {},
        .lex_ref => |v| try visible(l, v),
        .lex_set => |s| {
            try visible(l, s.v);
            if (!s.v.assigned) return error.BadAssignment;
            if (s.v.owner != l and !s.v.boxed()) return error.BadAssignment;
            try node(l, s.value, enc);
        },
        .global_set => |s| try node(l, s.value, enc),
        .call => |c| {
            if (c.args.len >= call_arguments_limit) return error.TooManyArgs;
            try node(l, c.callee, enc);
            for (c.args) |a| try node(l, a, enc);
        },
        .call_global => |c| {
            if (c.args.len >= call_arguments_limit) return error.TooManyArgs;
            for (c.args) |a| try node(l, a, enc);
        },
        .prim => |p| {
            const want: usize = switch (p.op) {
                .car, .cdr, .not, .add1, .sub1 => 1,
                else => 2,
            };
            if (p.args.len != want) return error.PrimArity;
            for (p.args) |a| try node(l, a, enc);
        },
        .if_ => |f| {
            try node(l, f.cond, enc);
            try node(l, f.then, enc);
            try node(l, f.else_, enc);
        },
        .progn => |forms| for (forms) |f| try node(l, f, enc),
        .let_ => |b| {
            if (b.vars.len != b.inits.len) return error.LetArity;
            for (b.inits) |i| try node(l, i, enc);
            for (b.vars) |v| {
                if (v.owner != l) return error.BadOwner;
                if (!v.special and v.slot >= l.nlocals) return error.BadSlot;
            }
            if (ir.hasSpecial(b.vars) and b.depth_slot >= l.nlocals) return error.BadSlot;
            try node(l, b.body, enc);
        },
        .values => |args| for (args) |a| try node(l, a, enc),
        .mv_list => |f| try node(l, f, enc),
        .mv_prog1 => |p| {
            try node(l, p.first, enc);
            for (p.rest) |f| try node(l, f, enc);
        },
        .mv_bind => |b| {
            try node(l, b.form, enc);
            for (b.vars) |v| {
                if (v.owner != l) return error.BadOwner;
                if (!v.special and v.slot >= l.nlocals) return error.BadSlot;
            }
            if (ir.hasSpecial(b.vars) and b.depth_slot >= l.nlocals) return error.BadSlot;
            try node(l, b.body, enc);
        },
        .progv => |p| {
            if (p.depth_slot >= l.nlocals) return error.BadSlot;
            try node(l, p.syms, enc);
            try node(l, p.vals, enc);
            try node(l, p.body, enc);
        },
        .block => |b| {
            if (b.blk.lambda != l) return error.BadBlock;
            const inner: Enclosing = .{ .blk = b.blk, .parent = enc };
            try node(l, b.body, &inner);
        },
        .return_from => |rf| {
            if (rf.nonlocal) {
                if (!rf.blk.needs_entry) return error.BadBlock;
                try visible(l, rf.blk.token);
            } else {
                // 同じ lambda の中で、この return-from を囲む block
                var e = enc;
                while (e) |x| : (e = x.parent) {
                    if (x.blk == rf.blk) break;
                } else return error.BadBlock;
            }
            try node(l, rf.value, enc);
        },
        .catch_ => |c| {
            try node(l, c.tag, enc);
            try node(l, c.body, enc);
        },
        .throw_ => |t| {
            try node(l, t.tag, enc);
            try node(l, t.value, enc);
        },
        .unwind_protect => |u| {
            try node(l, u.protected, enc);
            for (u.cleanup) |f| try node(l, f, enc);
        },
        .lambda => |child| {
            if (child.parent != l) return error.BadParent;
            for (child.captures.items) |c| try visible(l, c);
            try verify(child);
        },
    }
}
