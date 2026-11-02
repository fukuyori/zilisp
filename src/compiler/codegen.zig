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
                var i = l.vars.len;
                while (i > 0) : (i -= 1) {
                    const v = l.vars[i - 1];
                    if (v.boxed()) try g.op0(.make_cell);
                    try g.opIndex(.store_local, v.slot);
                    try g.op0(.pop);
                }
                try g.gen(l.body);
            },
            .lambda => |child| try g.genLambda(child),
        }
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
    // 箱に入れる引数は、入口で箱に入れる
    for (l.params) |p| {
        if (p.boxed()) {
            try g.opIndex(.load_local, p.slot);
            try g.op0(.make_cell);
            try g.opIndex(.store_local, p.slot);
            try g.op0(.pop);
        }
    }
    try g.gen(l.body);
    try g.op0(.@"return");

    const consts = if (g.consts.items.len == 0) Value.nil else try rt.makeVector(g.consts.items);
    var name = l.fn_name;
    if (name == Value.nil and l.parent != null) {
        // 印字用の名前 (LAMBDA ラムダリスト)。consts と name は引数・局所変数として生きている（§3.4）
        name = try rt.cons(l.name, Value.nil);
        name = try rt.cons(rt.syms.lambda, name);
    }
    const spec: function.CodeSpec = .{
        .bytecode = g.buf.items,
        .consts = consts,
        .name = name,
        .nparams = @intCast(l.params.len),
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
