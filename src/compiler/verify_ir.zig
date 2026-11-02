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
};

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
    try node(l, l.body);
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

fn node(l: *const Lambda, n: *const Node) IrError!void {
    switch (n.kind) {
        .constant, .global_ref, .global_fn, .global_setf_fn => {},
        .lex_ref => |v| try visible(l, v),
        .lex_set => |s| {
            try visible(l, s.v);
            if (!s.v.assigned) return error.BadAssignment;
            if (s.v.owner != l and !s.v.boxed()) return error.BadAssignment;
            try node(l, s.value);
        },
        .global_set => |s| try node(l, s.value),
        .call => |c| {
            if (c.args.len >= call_arguments_limit) return error.TooManyArgs;
            try node(l, c.callee);
            for (c.args) |a| try node(l, a);
        },
        .call_global => |c| {
            if (c.args.len >= call_arguments_limit) return error.TooManyArgs;
            for (c.args) |a| try node(l, a);
        },
        .prim => |p| {
            const want: usize = switch (p.op) {
                .car, .cdr, .not, .add1, .sub1 => 1,
                else => 2,
            };
            if (p.args.len != want) return error.PrimArity;
            for (p.args) |a| try node(l, a);
        },
        .if_ => |f| {
            try node(l, f.cond);
            try node(l, f.then);
            try node(l, f.else_);
        },
        .progn => |forms| for (forms) |f| try node(l, f),
        .let_ => |b| {
            if (b.vars.len != b.inits.len) return error.LetArity;
            for (b.inits) |i| try node(l, i);
            for (b.vars) |v| {
                if (v.owner != l) return error.BadOwner;
                if (!v.special and v.slot >= l.nlocals) return error.BadSlot;
            }
            if (ir.hasSpecial(b.vars) and b.depth_slot >= l.nlocals) return error.BadSlot;
            try node(l, b.body);
        },
        .values => |args| for (args) |a| try node(l, a),
        .mv_list => |f| try node(l, f),
        .mv_prog1 => |p| {
            try node(l, p.first);
            for (p.rest) |f| try node(l, f);
        },
        .mv_bind => |b| {
            try node(l, b.form);
            for (b.vars) |v| {
                if (v.owner != l) return error.BadOwner;
                if (!v.special and v.slot >= l.nlocals) return error.BadSlot;
            }
            if (ir.hasSpecial(b.vars) and b.depth_slot >= l.nlocals) return error.BadSlot;
            try node(l, b.body);
        },
        .progv => |p| {
            if (p.depth_slot >= l.nlocals) return error.BadSlot;
            try node(l, p.syms);
            try node(l, p.vals);
            try node(l, p.body);
        },
        .lambda => |child| {
            if (child.parent != l) return error.BadParent;
            for (child.captures.items) |c| try visible(l, c);
            try verify(child);
        },
    }
}
