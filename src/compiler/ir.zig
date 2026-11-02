//! Core IR（詳細設計 §5.2）。Phase 08 の範囲のノードだけを定義する。
//! IR はトップレベルのフォーム1つごとに ArenaAllocator 上に作り、コンパイルが終わったら捨てる。
//! IR が持つ定数（Value）は、コンパイル中に GC のルートに登録したフォームから到達できる（§5.4）。

const std = @import("std");
const Value = @import("../values/value.zig").Value;
const SourceLoc = @import("../reader/source.zig").SourceLoc;

/// レキシカル変数
pub const Var = struct {
    name: Value,
    /// この変数を持つ lambda
    owner: *Lambda,
    /// owner の局所変数の番号
    slot: u32,
    /// 内側の lambda から参照される
    captured: bool = false,
    /// setq で代入される
    assigned: bool = false,
    /// 特殊変数の束縛・宣言（Phase 14）。この変数の参照・代入は、シンボルの値（動的な値）に対して行う。
    /// slot は使わない
    special: bool = false,

    /// 箱（value_cell）に入れるか（捕捉され、かつ代入される変数だけ：§5.2 の assignment conversion）
    pub fn boxed(v: *const Var) bool {
        return v.captured and v.assigned;
    }
};

pub const Lambda = struct {
    parent: ?*Lambda,
    params: []*Var = &.{},
    body: *Node = undefined,
    /// 局所変数の数（引数を含む）
    nlocals: u32 = 0,
    /// 次に使う局所変数の番号（let の範囲を抜けると戻す）
    next_slot: u32 = 0,
    /// 外側の lambda から捕捉する変数（closure の捕捉した値の並び順）
    captures: std.ArrayList(*Var) = .empty,
    /// ラムダリスト（印字用の名前 (LAMBDA ラムダリスト) に使う）
    name: Value = Value.nil,
    /// defun・flet・labels で付けた関数の名前（シンボル）。NIL なら無名の lambda
    fn_name: Value = Value.nil,
    /// 名前の付け方（印字用の名前：global は 名前、flet・labels は (FLET 名前)・(LABELS 名前)）
    fn_kind: FnKind = .none,

    pub const FnKind = enum { none, global, flet, labels, macro };

    pub fn newSlot(l: *Lambda) u32 {
        const s = l.next_slot;
        l.next_slot += 1;
        l.nlocals = @max(l.nlocals, l.next_slot);
        return s;
    }

    pub fn captureIndex(l: *const Lambda, v: *const Var) ?u32 {
        for (l.captures.items, 0..) |c, i| {
            if (c == v) return @intCast(i);
        }
        return null;
    }
};

pub const no_slot = std.math.maxInt(u32);

pub fn hasSpecial(vars: []const *Var) bool {
    for (vars) |v| if (v.special) return true;
    return false;
}

/// 高速経路にする CL の関数（§7.4。VM の命令に対応する）
pub const Prim = enum { cons, car, cdr, eq, not, add2, sub2, lt2, gt2, le2, ge2, numeq2, add1, sub1 };

pub const Node = struct {
    loc: SourceLoc = .{ .line = 0, .col = 0 },
    kind: Kind,

    pub const Kind = union(enum) {
        constant: Value,
        lex_ref: *Var,
        lex_set: struct { v: *Var, value: *Node },
        /// 大域変数（特殊変数）の参照・代入
        global_ref: Value,
        global_set: struct { sym: Value, value: *Node },
        /// (function シンボル)
        global_fn: Value,
        /// 関数の値を呼ぶ（funcall、((lambda ...) ...)）
        call: struct { callee: *Node, args: []*Node },
        /// シンボルの関数セルを呼ぶ
        call_global: struct { sym: Value, args: []*Node },
        prim: struct { op: Prim, args: []*Node },
        if_: struct { cond: *Node, then: *Node, else_: *Node },
        progn: []*Node,
        /// 並列の束縛（let）。inits は外側の範囲で評価する。
        /// vars に特殊変数（special）があれば、束縛の前の深さを局所変数 depth_slot に置き、本体の後で戻す
        let_: struct { vars: []*Var, inits: []*Node, body: *Node, depth_slot: u32 = no_slot },
        /// progv（Phase 14）：syms のシンボルを vals の値で動的に束縛して body を評価する
        progv: struct { syms: *Node, vals: *Node, body: *Node, depth_slot: u32 },
        lambda: *Lambda,
    };
};
