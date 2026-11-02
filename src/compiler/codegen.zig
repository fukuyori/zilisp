//! バイトコードの生成（IR → バイトコード。詳細設計 §5.1・§7）。
//!
//! 生成した Code と、捕捉のない lambda から前もって作った closure は、外側の Code の定数表に入るまで
//! Pins（GC のルートに登録したリスト）で保持する（§5.4：Zig のヒープ上の配列は GC が走査しないため）。

const std = @import("std");
const builtin = @import("builtin");
const Value = @import("../values/value.zig").Value;
const Runtime = @import("../runtime/runtime.zig").Runtime;
const Thread = @import("../runtime/thread.zig").Thread;
const function = @import("../runtime/function.zig");
const roots = @import("../runtime/roots.zig");
const ops = @import("../vm/opcodes.zig");
const Op = ops.Op;
const vm = @import("../vm/vm.zig");
const verify = @import("../vm/verify.zig");
const ir = @import("ir.zig");
const Node = ir.Node;
const Lambda = ir.Lambda;
const Var = ir.Var;

pub const Error = error{OutOfMemory};

/// コンパイル中に作った Lisp の値を GC から守る（ルートに登録したリストに積む）
pub const Pins = struct {
    rt: *Runtime,
    handle: roots.Handle,

    pub fn init(rt: *Runtime) Error!Pins {
        return .{ .rt = rt, .handle = try rt.roots.register(Value.nil) };
    }
    pub fn deinit(p: *Pins) void {
        _ = p.rt.roots.unregister(p.handle);
    }
    pub fn pin(p: *Pins, v: Value) Error!void {
        // cons の確保で GC が起きても、v は引数として生きていて、これまでのリストはルートから届く
        const c = try p.rt.cons(v, p.rt.roots.get(p.handle).?);
        _ = p.rt.roots.set(p.handle, c);
    }
};

/// block の出口（Phase 18）
const BlockLabel = struct {
    blk: *ir.Block,
    /// block に入る前のスタックの深さ（出口では、これに値1つを加えた深さ）
    depth: i64,
    /// 多値の位置か（ジャンプで抜ける return-from の値も多値にする）
    multi: bool,
    /// 出口へのジャンプの、書き換える位置
    exits: std.ArrayList(usize) = .empty,
};

/// tagbody のタグの位置（Phase 19）
const TagbodyLabel = struct {
    tb: *ir.Tagbody,
    /// tagbody に入る前のスタックの深さ（タグの位置の深さ）
    depth: i64,
    /// タグの命令の位置（まだ出していなければ null）
    positions: []?usize,
    /// まだ位置の分からないタグへのジャンプの、書き換える位置
    forward: []std.ArrayList(usize),
};

/// ジャンプで抜けるときに戻す必要がある、動的な範囲（内側から順に積む）
const Dyn = union(enum) {
    block: *BlockLabel,
    tagbody: *TagbodyLabel,
    /// catch のエントリ
    catch_,
    /// 動的束縛。束縛の前の深さを置いた局所変数
    bind: u32,
};

const Gen = struct {
    rt: *Runtime,
    gpa: std.mem.Allocator,
    pins: *Pins,
    lambda: *Lambda,
    buf: std.ArrayList(u8) = .empty,
    consts: std.ArrayList(Value) = .empty,
    const_index: std.AutoHashMapUnmanaged(u64, u32) = .empty,
    depth: i64 = 0,
    max_depth: i64 = 0,
    dyn: std.ArrayList(Dyn) = .empty,

    fn adjust(g: *Gen, delta: i64) void {
        g.depth += delta;
        std.debug.assert(g.depth >= 0);
        g.max_depth = @max(g.max_depth, g.depth);
    }

    fn byte(g: *Gen, b: u8) Error!void {
        try g.buf.append(g.gpa, b);
    }
    fn int(g: *Gen, comptime T: type, v: T) Error!void {
        var b: [@sizeOf(T)]u8 = undefined;
        std.mem.writeInt(T, &b, v, .little);
        try g.buf.appendSlice(g.gpa, &b);
    }

    fn op0(g: *Gen, op: Op) Error!void {
        try g.byte(@backingInt(op));
        g.adjust(ops.stackEffect(op, 0));
    }

    /// 添字（k または i）を1つ取る命令
    fn opIndex(g: *Gen, op: Op, x: u32) Error!void {
        if (x > std.math.maxInt(u16)) {
            try g.byte(@backingInt(Op.wide));
            try g.byte(@backingInt(op));
            try g.int(u32, x);
        } else {
            try g.byte(@backingInt(op));
            try g.int(u16, @intCast(x));
        }
        g.adjust(ops.stackEffect(op, 0));
    }

    /// 個数（n）を1つ取る命令（call）
    fn opCount(g: *Gen, op: Op, n: u32) Error!void {
        if (n > std.math.maxInt(u8)) {
            try g.byte(@backingInt(Op.wide));
            try g.byte(@backingInt(op));
            try g.int(u32, n);
        } else {
            try g.byte(@backingInt(op));
            try g.byte(@intCast(n));
        }
        g.adjust(ops.stackEffect(op, n));
    }

    /// 添字と個数を取る命令（make_closure・call_global）
    fn opIndexCount(g: *Gen, op: Op, k: u32, n: u32) Error!void {
        if (k > std.math.maxInt(u16) or n > std.math.maxInt(u8)) {
            try g.byte(@backingInt(Op.wide));
            try g.byte(@backingInt(op));
            try g.int(u32, k);
            try g.int(u32, n);
        } else {
            try g.byte(@backingInt(op));
            try g.int(u16, @intCast(k));
            try g.byte(@intCast(n));
        }
        g.adjust(ops.stackEffect(op, n));
    }

    /// ジャンプを出し、後で書き換える位置を返す
    fn jump(g: *Gen, op: Op) Error!usize {
        try g.byte(@backingInt(op));
        const at = g.buf.items.len;
        try g.int(i32, 0);
        g.adjust(ops.stackEffect(op, 0));
        return at;
    }
    /// 局所変数の添字と rel を取る命令（block_enter）。後で書き換える rel の位置を返す
    fn jumpIndex(g: *Gen, op: Op, x: u32) Error!usize {
        if (x > std.math.maxInt(u16)) {
            try g.byte(@backingInt(Op.wide));
            try g.byte(@backingInt(op));
            try g.int(u32, x);
        } else {
            try g.byte(@backingInt(op));
            try g.int(u16, @intCast(x));
        }
        const at = g.buf.items.len;
        try g.int(i32, 0);
        g.adjust(ops.stackEffect(op, 0));
        return at;
    }

    /// 位置の分かっている命令（後ろへのジャンプ）へジャンプする
    fn jumpTo(g: *Gen, op: Op, target: usize) Error!void {
        try g.byte(@backingInt(op));
        const end: i64 = @intCast(g.buf.items.len + 4);
        try g.int(i32, @intCast(@as(i64, @intCast(target)) - end));
        g.adjust(ops.stackEffect(op, 0));
    }

    fn patch(g: *Gen, at: usize) void {
        const rel: i32 = @intCast(@as(i64, @intCast(g.buf.items.len)) - @as(i64, @intCast(at + 4)));
        std.mem.writeInt(i32, g.buf.items[at..][0..4], rel, .little);
    }

    fn constant(g: *Gen, v: Value) Error!u32 {
        const gop = try g.const_index.getOrPut(g.gpa, v.raw());
        if (!gop.found_existing) {
            gop.value_ptr.* = @intCast(g.consts.items.len);
            try g.consts.append(g.gpa, v);
        }
        return gop.value_ptr.*;
    }

    // ------------------------------------------------------------------

    fn genConstant(g: *Gen, v: Value) Error!void {
        if (v == Value.nil) return g.op0(.nil);
        if (v == g.rt.t) return g.op0(.t);
        if (v.isFixnum()) {
            const i = v.asFixnum();
            if (i >= std.math.minInt(i16) and i <= std.math.maxInt(i16)) {
                try g.byte(@backingInt(Op.smallint));
                try g.int(i16, @intCast(i));
                g.adjust(1);
                return;
            }
        }
        try g.opIndex(.@"const", try g.constant(v));
    }

    /// 変数の中身（箱に入れた変数なら箱そのもの）を積む
    fn loadVarRaw(g: *Gen, v: *Var) Error!void {
        if (v.owner == g.lambda) return g.opIndex(.load_local, v.slot);
        const idx = g.lambda.captureIndex(v) orelse unreachable;
        try g.opIndex(.load_captured, idx);
    }

    /// 値を捨てる位置の式
    fn genDiscard(g: *Gen, n: *Node) Error!void {
        switch (n.kind) {
            .constant, .lex_ref, .lambda => return,
            else => {
                try g.gen(n);
                try g.op0(.pop);
            },
        }
    }

    fn gen(g: *Gen, n: *Node) Error!void {
        switch (n.kind) {
            .constant => |v| try g.genConstant(v),
            .lex_ref => |v| {
                try g.loadVarRaw(v);
                if (v.boxed()) try g.op0(.cell_ref);
            },
            .lex_set => |s| {
                try g.gen(s.value);
                if (s.v.boxed()) {
                    try g.loadVarRaw(s.v);
                    try g.op0(.cell_set);
                } else {
                    std.debug.assert(s.v.owner == g.lambda);
                    try g.opIndex(.store_local, s.v.slot);
                }
            },
            .global_ref => |sym| try g.opIndex(.load_special, try g.constant(sym)),
            .global_set => |s| {
                try g.gen(s.value);
                try g.opIndex(.store_special, try g.constant(s.sym));
            },
            .global_fn => |sym| try g.opIndex(.load_function, try g.constant(sym)),
            .global_setf_fn => |sym| try g.opIndex(.load_setf_function, try g.constant(sym)),
            .call => |c| {
                try g.gen(c.callee);
                for (c.args) |a| try g.gen(a);
                try g.opCount(.call, @intCast(c.args.len));
            },
            .call_global => |c| {
                for (c.args) |a| try g.gen(a);
                try g.opIndexCount(.call_global, try g.constant(c.sym), @intCast(c.args.len));
            },
            .prim => |p| {
                for (p.args) |a| try g.gen(a);
                const op: Op = switch (p.op) {
                    inline else => |o| @field(Op, @tagName(o)),
                };
                try g.op0(op);
            },
            .if_ => |f| {
                try g.gen(f.cond);
                const to_else = try g.jump(.jump_if_nil);
                try g.gen(f.then);
                const to_end = try g.jump(.jump);
                g.adjust(-1); // else の側は、then の値がない深さから始まる
                g.patch(to_else);
                try g.gen(f.else_);
                g.patch(to_end);
            },
            .progn => |forms| {
                for (forms[0 .. forms.len - 1]) |f| try g.genDiscard(f);
                try g.gen(forms[forms.len - 1]);
            },
            .let_ => |l| {
                for (l.inits) |i| try g.gen(i);
                try g.bindVars(l.vars, l.depth_slot);
                try g.genBound(l.body, l.vars, l.depth_slot, false);
                try g.unbindVars(l.vars, l.depth_slot);
            },
            .progv => |p| {
                try g.progvEnter(p);
                try g.genIn(p.body, .{ .bind = p.depth_slot }, false);
                try g.opIndex(.load_local, p.depth_slot);
                try g.op0(.unbind_to);
            },
            .lambda => |child| try g.genLambda(child),
            .block => |b| try g.genBlock(b.blk, b.body, false),
            .return_from => |rf| try g.genReturnFrom(rf.blk, rf.value, rf.nonlocal),
            .catch_ => |c| try g.genCatch(c.tag, c.body, false),
            .throw_ => |t| try g.genThrow(t.tag, t.value),
            .unwind_protect => |u| try g.genUnwindProtect(u.protected, u.cleanup, false),
            .tagbody => |t| try g.genTagbody(t.tb, t.items),
            .go_ => |x| try g.genGo(x.tb, x.index, x.nonlocal),
            // 多値（Phase 17）。単値の位置では主値だけを使う
            .values => |args| {
                // 引数はすべて左から順に評価する。主値は最初の引数（なければ NIL）
                if (args.len == 0) return g.op0(.nil);
                try g.gen(args[0]);
                for (args[1..]) |a| try g.genDiscard(a);
            },
            .mv_list => |f| {
                try g.genMulti(f);
                try g.op0(.mv_list);
            },
            .mv_prog1 => |p| {
                try g.gen(p.first);
                for (p.rest) |f| try g.genDiscard(f);
            },
            .mv_bind => |b| {
                try g.mvBindEnter(b);
                try g.genBound(b.body, b.vars, b.depth_slot, false);
                try g.unbindVars(b.vars, b.depth_slot);
            },
        }
    }

    fn genMode(g: *Gen, n: *Node, multi: bool) Error!void {
        if (multi) try g.genMulti(n) else try g.gen(n);
    }

    /// 動的な範囲 d の中で n を生成する
    fn genIn(g: *Gen, n: *Node, d: Dyn, multi: bool) Error!void {
        try g.dyn.append(g.gpa, d);
        try g.genMode(n, multi);
        _ = g.dyn.pop();
    }

    /// let・multiple-value-bind の本体（特殊変数を束縛していれば、動的束縛の範囲）
    fn genBound(g: *Gen, body: *Node, vars: []*Var, depth_slot: u32, multi: bool) Error!void {
        if (ir.hasSpecial(vars)) return g.genIn(body, .{ .bind = depth_slot }, multi);
        try g.genMode(body, multi);
    }

    /// (block 名前 本体...)。実行時の脱出の脱出先なら、制御スタックにエントリを積む（§6.4）
    fn genBlock(g: *Gen, blk: *ir.Block, body: *Node, multi: bool) Error!void {
        var label: BlockLabel = .{ .blk = blk, .depth = g.depth, .multi = multi };
        defer label.exits.deinit(g.gpa);
        const enter_at: ?usize = if (blk.needs_entry) try g.jumpIndex(.block_enter, blk.token.slot) else null;
        try g.genIn(body, .{ .block = &label }, multi);
        // ジャンプで抜ける return-from は、ここ（エントリを取り除く前）に来る
        for (label.exits.items) |at| g.patch(at);
        if (enter_at) |at| {
            try g.opCount(.control_pop, 1);
            g.patch(at);
        }
    }

    fn genReturnFrom(g: *Gen, blk: *ir.Block, value: *Node, nonlocal: bool) Error!void {
        const before = g.depth;
        if (nonlocal) {
            // 実行時の脱出：block の識別子と全部の値を渡す
            try g.loadVarRaw(blk.token);
            try g.genMulti(value);
            try g.op0(.return_from_nl);
        } else {
            // ジャンプ：横切る動的束縛を戻し、横切るエントリ（catch・エントリのある block）を取り除き、途中の値を捨てる
            var label: ?*BlockLabel = null;
            var pops: u32 = 0;
            var unbind_slot: ?u32 = null;
            var i = g.dyn.items.len;
            while (i > 0) {
                i -= 1;
                switch (g.dyn.items[i]) {
                    .block => |l| {
                        if (l.blk == blk) {
                            label = l;
                            break;
                        }
                        if (l.blk.needs_entry) pops += 1;
                    },
                    .tagbody => |t| if (t.tb.needs_entry) {
                        pops += 1;
                    },
                    .catch_ => pops += 1,
                    .bind => |s| unbind_slot = s,
                }
            }
            const l = label orelse unreachable; // Resolver が見えることを確かめている
            try g.genMode(value, l.multi);
            if (unbind_slot) |s| {
                try g.opIndex(.load_local, s);
                try g.op0(.unbind_to);
            }
            const extra = g.depth - (l.depth + 1);
            if (extra > 0) try g.opCount(.slide, @intCast(extra));
            if (pops > 0) try g.opCount(.control_pop, pops);
            try l.exits.append(g.gpa, try g.jump(.jump));
        }
        // この後のコードには進まないが、生成は値が1つ積まれた深さで続ける
        g.depth = before + 1;
        g.max_depth = @max(g.max_depth, g.depth);
    }

    /// (tagbody ...)（Phase 19）。値は NIL。タグの位置の深さは tagbody に入る前の深さ。
    /// 実行時の go の脱出先なら、エントリを積み、着地したときはタグの番号でタグの位置へ分岐する
    fn genTagbody(g: *Gen, tb: *ir.Tagbody, items: []ir.TagItem) Error!void {
        const positions = try g.gpa.alloc(?usize, tb.ntags);
        defer g.gpa.free(positions);
        @memset(positions, null);
        const forward = try g.gpa.alloc(std.ArrayList(usize), tb.ntags);
        defer {
            for (forward) |*f| f.deinit(g.gpa);
            g.gpa.free(forward);
        }
        @memset(forward, .empty);
        var label: TagbodyLabel = .{ .tb = tb, .depth = g.depth, .positions = positions, .forward = forward };
        const d = g.depth;
        const enter_at: ?usize = if (tb.needs_entry) try g.jumpIndex(.tagbody_enter, tb.token.slot) else null;
        try g.dyn.append(g.gpa, .{ .tagbody = &label });
        for (items) |item| switch (item) {
            .tag => |i| {
                g.depth = d; // 前のフォームが go で終わっていても、タグの位置の深さは d
                positions[i] = g.buf.items.len;
                for (forward[i].items) |at| g.patch(at);
            },
            .form => |f| try g.genDiscard(f),
        };
        _ = g.dyn.pop();
        g.depth = d;
        if (enter_at) |at| {
            try g.opCount(.control_pop, 1);
            const skip = try g.jump(.jump);
            // 着地：タグの番号が積まれている。番号を局所変数に置き、タグの位置へ分岐する
            g.patch(at);
            g.depth = d + 1;
            g.max_depth = @max(g.max_depth, g.depth);
            try g.opIndex(.store_local, tb.index_slot);
            try g.op0(.pop);
            for (positions, 0..) |p, i| {
                try g.opIndex(.load_local, tb.index_slot);
                try g.genConstant(Value.fromFixnum(@intCast(i)));
                try g.op0(.numeq2);
                const next_tag = try g.jump(.jump_if_nil);
                try g.jumpTo(.jump, p.?);
                g.patch(next_tag);
            }
            try g.jumpTo(.jump, positions[0].?);
            g.patch(skip);
            g.depth = d;
        }
        try g.op0(.nil);
    }

    fn genGo(g: *Gen, tb: *ir.Tagbody, index: u32, nonlocal: bool) Error!void {
        const before = g.depth;
        if (nonlocal) {
            try g.loadVarRaw(tb.token);
            try g.genConstant(Value.fromFixnum(@intCast(index)));
            try g.op0(.go_nl);
        } else {
            // ジャンプ：途中の値を捨て、横切る動的束縛を戻し、横切るエントリを取り除く
            var label: ?*TagbodyLabel = null;
            var pops: u32 = 0;
            var unbind_slot: ?u32 = null;
            var i = g.dyn.items.len;
            while (i > 0) {
                i -= 1;
                switch (g.dyn.items[i]) {
                    .tagbody => |t| {
                        if (t.tb == tb) {
                            label = t;
                            break;
                        }
                        if (t.tb.needs_entry) pops += 1;
                    },
                    .block => |b| if (b.blk.needs_entry) {
                        pops += 1;
                    },
                    .catch_ => pops += 1,
                    .bind => |s| unbind_slot = s,
                }
            }
            const l = label orelse unreachable; // Resolver が見えることを確かめている
            while (g.depth > l.depth) try g.op0(.pop);
            if (unbind_slot) |s| {
                try g.op0(.nil);
                try g.opIndex(.load_local, s);
                try g.op0(.unbind_to);
                try g.op0(.pop);
            }
            if (pops > 0) try g.opCount(.control_pop, pops);
            if (l.positions[index]) |p| {
                try g.jumpTo(.jump, p);
            } else {
                try l.forward[index].append(g.gpa, try g.jump(.jump));
            }
        }
        // この後のコードには進まないが、生成は値が1つ積まれた深さで続ける
        g.depth = before + 1;
        g.max_depth = @max(g.max_depth, g.depth);
    }

    fn genCatch(g: *Gen, tag: *Node, body: *Node, multi: bool) Error!void {
        try g.gen(tag);
        const at = try g.jump(.catch_enter);
        try g.genIn(body, .catch_, multi);
        try g.opCount(.control_pop, 1);
        g.patch(at);
    }

    fn genThrow(g: *Gen, tag: *Node, value: *Node) Error!void {
        const before = g.depth;
        try g.gen(tag);
        try g.genMulti(value);
        try g.op0(.throw);
        g.depth = before + 1;
        g.max_depth = @max(g.max_depth, g.depth);
    }

    /// unwind-protect：保護したフォームの値を退避して cleanup を実行し、値を戻す。
    /// 脱出・エラーで抜けたときは、VM が cleanup の先頭から再開する（印 -1）
    fn genUnwindProtect(g: *Gen, protected: *Node, cleanup: []*Node, multi: bool) Error!void {
        const at = try g.jump(.uwp_enter);
        if (multi) {
            try g.genMulti(protected);
        } else {
            try g.gen(protected);
            try g.op0(.single);
        }
        try g.op0(.uwp_save);
        g.patch(at);
        for (cleanup) |f| try g.genDiscard(f);
        try g.op0(.uwp_end);
    }

    /// 多値の位置の式：評価した後、主値をスタックに、全部の値を th.mv_count・th.mv に置く（§5.5 の multiple。§6.2）。
    /// 関数の呼び出しは、呼んだ関数が個数を書くので、そのまま使う。単値の式なら個数を 1 にする
    fn genMulti(g: *Gen, n: *Node) Error!void {
        switch (n.kind) {
            .call, .call_global => try g.gen(n),
            .values => |args| {
                for (args) |a| try g.gen(a);
                try g.opCount(.values, @intCast(args.len));
            },
            .if_ => |f| {
                try g.gen(f.cond);
                const to_else = try g.jump(.jump_if_nil);
                try g.genMulti(f.then);
                const to_end = try g.jump(.jump);
                g.adjust(-1);
                g.patch(to_else);
                try g.genMulti(f.else_);
                g.patch(to_end);
            },
            .progn => |forms| {
                for (forms[0 .. forms.len - 1]) |f| try g.genDiscard(f);
                try g.genMulti(forms[forms.len - 1]);
            },
            .let_ => |l| {
                for (l.inits) |i| try g.gen(i);
                try g.bindVars(l.vars, l.depth_slot);
                try g.genBound(l.body, l.vars, l.depth_slot, true);
                try g.unbindVars(l.vars, l.depth_slot);
            },
            .progv => |p| {
                try g.progvEnter(p);
                try g.genIn(p.body, .{ .bind = p.depth_slot }, true);
                try g.opIndex(.load_local, p.depth_slot);
                try g.op0(.unbind_to);
            },
            .block => |b| try g.genBlock(b.blk, b.body, true),
            .catch_ => |c| try g.genCatch(c.tag, c.body, true),
            .unwind_protect => |u| try g.genUnwindProtect(u.protected, u.cleanup, true),
            // 脱出は、この後に進まないので個数を書く必要はない
            .return_from, .throw_, .go_ => try g.gen(n),
            .mv_prog1 => |p| {
                // 最初のフォームの全部の値をリストに退避し、残りを評価した後で戻す（§6.3）
                try g.genMulti(p.first);
                try g.op0(.mv_list);
                for (p.rest) |f| try g.genDiscard(f);
                try g.op0(.mv_restore);
            },
            .mv_bind => |b| {
                try g.mvBindEnter(b);
                try g.genBound(b.body, b.vars, b.depth_slot, true);
                try g.unbindVars(b.vars, b.depth_slot);
            },
            else => {
                try g.gen(n);
                try g.op0(.single);
            },
        }
    }

    /// スタックの上の値（vars と同じ数）を、vars に束縛する（let・multiple-value-bind）
    fn bindVars(g: *Gen, vars: []*Var, depth_slot: u32) Error!void {
        if (ir.hasSpecial(vars)) {
            // 束縛の前の深さを覚えておき、本体の後で戻す
            try g.op0(.binding_depth);
            try g.opIndex(.store_local, depth_slot);
            try g.op0(.pop);
        }
        var i = vars.len;
        while (i > 0) : (i -= 1) {
            const v = vars[i - 1];
            if (v.special) {
                try g.opIndex(.bind_special, try g.constant(v.name));
                continue;
            }
            if (v.boxed()) try g.op0(.make_cell);
            try g.opIndex(.store_local, v.slot);
            try g.op0(.pop);
        }
    }

    fn unbindVars(g: *Gen, vars: []*Var, depth_slot: u32) Error!void {
        if (ir.hasSpecial(vars)) {
            try g.opIndex(.load_local, depth_slot);
            try g.op0(.unbind_to);
        }
    }

    fn progvEnter(g: *Gen, p: anytype) Error!void {
        try g.op0(.binding_depth);
        try g.opIndex(.store_local, p.depth_slot);
        try g.op0(.pop);
        try g.gen(p.syms);
        try g.gen(p.vals);
        try g.op0(.progv_bind);
    }

    /// multiple-value-bind：フォームの値を変数の数だけスタックに積み（足りない分は NIL）、束縛する
    fn mvBindEnter(g: *Gen, b: anytype) Error!void {
        try g.genMulti(b.form);
        try g.opCount(.mv_push_n, @intCast(b.vars.len));
        try g.bindVars(b.vars, b.depth_slot);
    }

    fn genLambda(g: *Gen, child: *Lambda) Error!void {
        const code = try compileLambda(g.rt, g.gpa, g.pins, child);
        if (child.captures.items.len == 0) {
            // 捕捉のない lambda の closure は、コンパイル時に1つ作って定数にする
            const c = try function.makeClosure(g.rt, code, &vm.closureEntry, &.{});
            try g.pins.pin(c);
            return g.genConstant(c);
        }
        for (child.captures.items) |v| try g.loadVarRaw(v);
        try g.opIndexCount(.make_closure, try g.constant(code), @intCast(child.captures.items.len));
    }
};

/// lambda を Code にする。作った Code は pins に積む
pub fn compileLambda(rt: *Runtime, gpa: std.mem.Allocator, pins: *Pins, l: *Lambda) Error!Value {
    var g: Gen = .{ .rt = rt, .gpa = gpa, .pins = pins, .lambda = l };
    defer g.dyn.deinit(gpa);
    // 箱に入れる引数は、入口で箱に入れる
    for (l.params) |p| {
        if (p.boxed()) {
            try g.opIndex(.load_local, p.slot);
            try g.op0(.make_cell);
            try g.opIndex(.store_local, p.slot);
            try g.op0(.pop);
        }
    }
    // 関数の本体の最後の式は多値の位置（値の個数を呼び出し側へ伝える：§6.2）
    try g.genMulti(l.body);
    try g.op0(.@"return");

    const consts = if (g.consts.items.len == 0) Value.nil else try rt.makeVector(g.consts.items);
    // 印字用の名前。consts と name は引数・局所変数として生きている（§3.4）
    var name = Value.nil;
    switch (l.fn_kind) {
        .global => name = l.fn_name,
        .flet, .labels, .macro => {
            name = try rt.cons(l.fn_name, Value.nil);
            name = try rt.cons(switch (l.fn_kind) {
                .flet => rt.syms.flet,
                .labels => rt.syms.labels,
                else => try rt.internKeyword("MACRO"),
            }, name);
        },
        .none => if (l.parent != null) {
            name = try rt.cons(l.name, Value.nil);
            name = try rt.cons(rt.syms.lambda, name);
        },
    }
    const spec: function.CodeSpec = .{
        .bytecode = g.buf.items,
        .consts = consts,
        .name = name,
        .nparams = @intCast(l.params.len - @intFromBool(l.rest_param)),
        .rest = l.rest_param,
        .nlocals = l.nlocals,
        .ncaptured = @intCast(l.captures.items.len),
        .max_stack = @intCast(g.max_depth),
    };
    if (builtin.mode == .debug or builtin.is_test) {
        verify.verify(gpa, spec.bytecode, g.consts.items.len, spec.nlocals, spec.ncaptured, spec.max_stack) catch |err|
            std.debug.panic("生成したバイトコードが正しくありません: {t}", .{err});
    }
    const code = try function.makeCode(rt, spec);
    try pins.pin(code);
    std.mem.doNotOptimizeAway(consts);
    std.mem.doNotOptimizeAway(name);
    return code;
}
