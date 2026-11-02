//! バイトコード VM（詳細設計 §7）。スタック型。
//!
//! 値スタックの使い方（1つのフレーム）
//!   [base .. base+nlocals)              局所変数（引数が先頭から並ぶ）
//!   [base+nlocals .. base+nlocals+max)  式の評価に使う領域
//! VM の closure から VM の closure を呼ぶときは、Zig の関数を挟まずに同じ実行ループの中でフレームを積む（§6.2）。
//! プリミティブなど VM 以外の関数は、汎用の入口（§6.2）で呼ぶ。
//!
//! GC との関係（§3.3）：値スタックは [0, Vm.sp) を正確に走査する（使い終わった枠に残った値は走査しない）。
//! 実行ループは sp を局所変数に持つので、**確保（GC が起きうる処理）と VM 以外の関数の呼び出しの前に、
//! 必ず Vm.sp へ書き戻す**。書き戻しを忘れると、まだ使っている値が回収される（--gc-stress の試験で検出する）。
//! 値スタックは起動時に NIL で埋めておく。

const std = @import("std");
const Value = @import("../values/value.zig").Value;
const ops = @import("opcodes.zig");
const Op = ops.Op;
const thread_mod = @import("../runtime/thread.zig");
const Thread = thread_mod.Thread;
const Runtime = @import("../runtime/runtime.zig").Runtime;
const function = @import("../runtime/function.zig");
const numbers = @import("../primitives/numbers.zig");
const SymbolFlags = @import("../values/object.zig").SymbolFlags;

pub const Frame = struct {
    closure: Value,
    /// 呼び出し中の命令の次の位置（このフレームが別の関数を呼んでいる間だけ意味がある）
    ip: u32,
    base: u32,
    /// 戻るときの sp（呼び出した側の、関数と引数を取り除いた位置）
    ret_sp: u32,
};

pub const Vm = struct {
    stack: []Value,
    sp: usize = 0,
    frames: []Frame,
    fp: usize = 0,

    pub fn init(gpa: std.mem.Allocator, stack_size: usize, frame_count: usize) error{OutOfMemory}!Vm {
        const stack = try gpa.alloc(Value, stack_size);
        errdefer gpa.free(stack);
        @memset(stack, Value.nil);
        const frames = try gpa.alloc(Frame, frame_count);
        return .{ .stack = stack, .frames = frames };
    }

    pub fn deinit(vm: *Vm, gpa: std.mem.Allocator) void {
        gpa.free(vm.stack);
        gpa.free(vm.frames);
    }

    pub fn forEachRoot(vm: *const Vm, ctx: anytype, comptime f: fn (@TypeOf(ctx), Value) void) void {
        for (vm.stack[0..vm.sp]) |v| f(ctx, v);
        for (vm.frames[0..vm.fp]) |fr| f(ctx, fr.closure);
    }

    /// 値スタックの上に n 個の枠を確保する（プリミティブが引数を並べるため。GC のルートになる）
    pub fn reserve(vm: *Vm, n: usize) ?[]Value {
        if (vm.sp + n > vm.stack.len) return null;
        const s = vm.stack[vm.sp..][0..n];
        vm.sp += n;
        return s;
    }

    pub fn release(vm: *Vm, n: usize) void {
        vm.sp -= n;
    }
};

/// VM の closure の汎用の入口（§6.2 のトランポリン）
pub fn closureEntry(th: *Thread, self: Value, args: [*]const Value, nargs: u32) callconv(.c) Value {
    return run(th, self, args[0..nargs]);
}

pub fn isVmClosure(f: Value) bool {
    return f.isFunctionPointer() and function.kindOfFunction(f) == .closure and
        function.closurePtr(f).entry == &closureEntry;
}

fn stackOverflow(th: *Thread) Value {
    return th.signal(.storage_condition, "VM のスタックが溢れました（呼び出しが深すぎます）", Value.unbound, Value.unbound);
}

/// フレームを積む。引数は stack[base .. base+nargs) にあること。失敗したら false（th にエラーを記録済み）
fn pushFrame(th: *Thread, closure: Value, base: usize, nargs: usize, ret_sp: usize) bool {
    const vm = &th.vm;
    const code = function.closurePtr(closure).codePtr();
    if (if (code.rest) nargs < code.nparams else nargs != code.nparams) {
        _ = th.argCountError(closure, @intCast(nargs));
        return false;
    }
    const extent = base + code.nlocals + code.max_stack;
    if (vm.fp >= vm.frames.len or extent > vm.stack.len) {
        _ = stackOverflow(th);
        return false;
    }
    var filled = nargs;
    if (code.rest) {
        // 必須の引数の後ろの引数を、リストにまとめて局所変数 nparams に置く（Phase 17）。
        // 確保の間、引数は値スタックの上（vm.sp より下）にあるので GC から守られる
        vm.sp = base + nargs;
        var list = Value.nil;
        var i = nargs;
        while (i > code.nparams) : (i -= 1) {
            list = th.rt.cons(vm.stack[base + i - 1], list) catch {
                _ = th.outOfMemory();
                return false;
            };
        }
        vm.stack[base + code.nparams] = list;
        filled = code.nparams + 1;
    }
    @memset(vm.stack[base + filled .. base + code.nlocals], Value.nil);
    vm.frames[vm.fp] = .{ .closure = closure, .ip = 0, .base = @intCast(base), .ret_sp = @intCast(ret_sp) };
    vm.fp += 1;
    vm.sp = base + code.nlocals;
    return true;
}

/// VM の closure を、Zig の関数から呼ぶ
pub fn run(th: *Thread, closure: Value, args: []const Value) Value {
    const vm = &th.vm;
    // Zig の関数から VM に入る入れ子の深さ（VM の closure 以外の呼び出しは Thread.call で数える）
    if (th.native_depth >= thread_mod.max_native_depth) return stackOverflow(th);
    th.native_depth += 1;
    defer th.native_depth -= 1;
    const entry_fp = vm.fp;
    const entry_sp = vm.sp;
    // エラーで抜けるときは、この実行の中で作った動的束縛を戻す（§6.5。handler・restart ができる Phase 25 までは
    // エラーはトップレベルまで戻るので、途中で受け止められることはない）
    const entry_binding = th.binding_depth;
    // この実行の中で積む制御スタックのエントリは、この深さより上（§6.4）
    const entry_control = th.control_depth;
    // 引数を値スタックの上に写す（args は呼び出し側の領域なので、後で上書きされても安全にする：§6.2 agy #9）
    if (vm.sp + args.len > vm.stack.len) return stackOverflow(th);
    const base = vm.sp;
    @memcpy(vm.stack[base..][0..args.len], args);
    vm.sp += args.len;
    if (!pushFrame(th, closure, base, args.len, entry_sp)) {
        vm.sp = entry_sp;
        return Value.unwind;
    }
    var r = execute(th, entry_fp);
    // 脱出・エラーで抜けてきたら、この実行が積んだエントリ（block・catch・unwind-protect）を内側から調べ、
    // 再開する場所（脱出先、cleanup）があれば、そこから実行を続ける
    while (r == Value.unwind and resumeAfterUnwind(th, entry_control)) r = execute(th, entry_fp);
    if (r == Value.unwind) {
        vm.fp = entry_fp;
        vm.sp = entry_sp;
        th.unbindTo(entry_binding);
    }
    return r;
}

/// Value.unwind で execute から抜けたとき、この run が積んだ制御スタックのエントリを内側から順に処理する。
/// unwind-protect なら cleanup の先頭、脱出先の block・catch ならその後ろで再開するよう VM の状態を合わせて true を返す。
/// どれもなければ（脱出先はこの run の外、またはエラー）、エントリを取り除いて false を返す
fn resumeAfterUnwind(th: *Thread, entry_control: usize) bool {
    const vm = &th.vm;
    while (th.control_depth > entry_control) {
        const e = th.control[th.control_depth - 1];
        if (e.kind == .unwind_protect) {
            th.control_depth -= 1;
            restoreTo(th, e);
            th.uwpBegin();
            // cleanup の先頭の深さは、保護したフォームの値と印の2つを積んだ深さ（印 -1 は脱出・エラーの途中）
            vm.stack[vm.sp] = Value.nil;
            vm.stack[vm.sp + 1] = Value.fromFixnum(-1);
            vm.sp += 2;
            return true;
        }
        if (th.isTarget()) {
            restoreTo(th, e);
            const primary = th.landTransfer();
            vm.stack[vm.sp] = primary;
            vm.sp += 1;
            return true;
        }
        th.control_depth -= 1;
    }
    return false;
}

/// エントリを積んだ時点の VM の状態（フレーム・値スタック・動的束縛）に戻し、再開する命令の位置を設定する
fn restoreTo(th: *Thread, e: thread_mod.ControlEntry) void {
    const vm = &th.vm;
    vm.fp = e.fp;
    vm.sp = e.sp;
    th.unbindTo(e.binding_depth);
    vm.frames[vm.fp - 1].ip = e.ip;
}

/// 添字・個数のオペランドを読む（WIDE の後なら 32 ビット）
inline fn readIndex(bc: [*]const u8, ip: *usize, wide: bool) u32 {
    if (wide) {
        const v = ops.readU32(bc, ip.*);
        ip.* += 4;
        return v;
    }
    const v = ops.readU16(bc, ip.*);
    ip.* += 2;
    return v;
}

inline fn readCount(bc: [*]const u8, ip: *usize, wide: bool) u32 {
    if (wide) {
        const v = ops.readU32(bc, ip.*);
        ip.* += 4;
        return v;
    }
    const v = bc[ip.*];
    ip.* += 1;
    return v;
}

inline fn tagged(v: Value) i64 {
    return @bitCast(v.raw());
}

/// 次の命令を読む
inline fn next(bc: [*]const u8, ip: *usize) Op {
    const op: Op = @fromBackingInt(bc[ip.*]);
    ip.* += 1;
    return op;
}

/// 実行ループ。フレーム entry_fp（run が積んだもの）から戻ったら、その値を返す。
/// 命令の分岐は、ラベル付き switch と continue で行う（§7.1）。各命令の最後で次の命令を読んで直接分岐するので、
/// 命令ごとに分岐の場所が分かれ、分岐予測が命令の並びを学習できる（スレッデッドコード相当）。
/// WIDE は、次の命令のオペランドを 32 ビットにする印を立てる。オペランドを読む命令は、最初に印を取り出して消す
fn execute(th: *Thread, entry_fp: usize) Value {
    const vm = &th.vm;
    const rt = th.rt;
    const stack = vm.stack.ptr;

    var frame = &vm.frames[vm.fp - 1];
    var closure = function.closurePtr(frame.closure);
    var code = closure.codePtr();
    var bc: [*]const u8 = code.bytecode;
    var consts = code.constants();
    var base: usize = frame.base;
    var sp: usize = vm.sp;
    // 新しいフレームでは 0。脱出の後で再開するときは、再開する位置（resumeAfterUnwind が設定する）
    var ip: usize = frame.ip;
    var wide = false;

    dispatch: switch (next(bc, &ip)) {
        .@"const" => {
            const w = wide;
            wide = false;
            stack[sp] = consts[readIndex(bc, &ip, w)];
            sp += 1;
            continue :dispatch next(bc, &ip);
        },
        .nil => {
            stack[sp] = Value.nil;
            sp += 1;
            continue :dispatch next(bc, &ip);
        },
        .t => {
            stack[sp] = rt.t;
            sp += 1;
            continue :dispatch next(bc, &ip);
        },
        .smallint => {
            stack[sp] = Value.fromFixnum(ops.readI16(bc, ip));
            ip += 2;
            sp += 1;
            continue :dispatch next(bc, &ip);
        },
        .pop => {
            sp -= 1;
            continue :dispatch next(bc, &ip);
        },
        .load_local => {
            const w = wide;
            wide = false;
            stack[sp] = stack[base + readIndex(bc, &ip, w)];
            sp += 1;
            continue :dispatch next(bc, &ip);
        },
        .store_local => {
            const w = wide;
            wide = false;
            stack[base + readIndex(bc, &ip, w)] = stack[sp - 1];
            continue :dispatch next(bc, &ip);
        },
        .load_captured => {
            const w = wide;
            wide = false;
            stack[sp] = closure.captured()[readIndex(bc, &ip, w)];
            sp += 1;
            continue :dispatch next(bc, &ip);
        },
        .make_cell => {
            vm.sp = sp;
            stack[sp - 1] = function.makeCell(rt, stack[sp - 1]) catch return th.outOfMemory();
            continue :dispatch next(bc, &ip);
        },
        .cell_ref => {
            stack[sp - 1] = function.cellPtr(stack[sp - 1]).value;
            continue :dispatch next(bc, &ip);
        },
        .cell_set => {
            function.cellPtr(stack[sp - 1]).value = stack[sp - 2];
            sp -= 1;
            continue :dispatch next(bc, &ip);
        },
        .load_special => {
            const w = wide;
            wide = false;
            const sym = consts[readIndex(bc, &ip, w)];
            const v = rt.symbolPtr(sym).value;
            if (v == Value.unbound) return th.signal(.unbound_variable, "", sym, Value.unbound);
            stack[sp] = v;
            sp += 1;
            continue :dispatch next(bc, &ip);
        },
        .store_special => {
            const w = wide;
            wide = false;
            rt.symbolPtr(consts[readIndex(bc, &ip, w)]).value = stack[sp - 1];
            continue :dispatch next(bc, &ip);
        },
        .binding_depth => {
            stack[sp] = Value.fromFixnum(@intCast(th.binding_depth));
            sp += 1;
            continue :dispatch next(bc, &ip);
        },
        .bind_special => {
            const w = wide;
            wide = false;
            const sym = consts[readIndex(bc, &ip, w)];
            if (th.bind(sym, stack[sp - 1]) == Value.unwind) return Value.unwind;
            sp -= 1;
            continue :dispatch next(bc, &ip);
        },
        .unbind_to => {
            th.unbindTo(@intCast(stack[sp - 1].asFixnum()));
            sp -= 1;
            continue :dispatch next(bc, &ip);
        },
        .progv_bind => {
            vm.sp = sp;
            if (th.progvBind(stack[sp - 2], stack[sp - 1]) == Value.unwind) return Value.unwind;
            sp -= 2;
            continue :dispatch next(bc, &ip);
        },
        .load_function => {
            const w = wide;
            wide = false;
            const sym = consts[readIndex(bc, &ip, w)];
            const f = th.resolveFunction(sym);
            if (f == Value.unwind) return f;
            stack[sp] = f;
            sp += 1;
            continue :dispatch next(bc, &ip);
        },
        .load_setf_function => {
            const w = wide;
            wide = false;
            const f = th.resolveSetfFunction(consts[readIndex(bc, &ip, w)]);
            if (f == Value.unwind) return f;
            stack[sp] = f;
            sp += 1;
            continue :dispatch next(bc, &ip);
        },
        .make_closure => {
            const w = wide;
            wide = false;
            const k = readIndex(bc, &ip, w);
            const n = readCount(bc, &ip, w);
            vm.sp = sp;
            const c = function.makeClosure(rt, consts[k], &closureEntry, stack[sp - n .. sp]) catch return th.outOfMemory();
            sp -= n;
            stack[sp] = c;
            sp += 1;
            continue :dispatch next(bc, &ip);
        },
        inline .call, .call_global => |op| {
            const w = wide;
            wide = false;
            var n: u32 = undefined;
            var f: Value = undefined;
            var ret_sp: usize = undefined;
            if (op == .call) {
                n = readCount(bc, &ip, w);
                ret_sp = sp - n - 1;
                f = stack[ret_sp];
                if (!f.isFunctionPointer()) {
                    f = th.resolveFunction(f);
                    if (f == Value.unwind) return f;
                }
            } else {
                const k = readIndex(bc, &ip, w);
                n = readCount(bc, &ip, w);
                ret_sp = sp - n;
                f = th.resolveFunction(consts[k]);
                if (f == Value.unwind) return f;
            }
            if (isVmClosure(f)) {
                // 同じ実行ループの中でフレームを積む
                frame.ip = @intCast(ip);
                if (!pushFrame(th, f, sp - n, n, ret_sp)) return Value.unwind;
                frame = &vm.frames[vm.fp - 1];
                closure = function.closurePtr(f);
                code = closure.codePtr();
                bc = code.bytecode;
                consts = code.constants();
                base = frame.base;
                sp = vm.sp;
                ip = 0;
            } else {
                vm.sp = sp;
                const r = function.functionHeader(f).entry(th, f, stack + sp - n, n);
                if (r == Value.unwind) return r;
                sp = ret_sp;
                stack[sp] = r;
                sp += 1;
            }
            continue :dispatch next(bc, &ip);
        },
        .@"return" => {
            const result = stack[sp - 1];
            const ret_sp = frame.ret_sp;
            vm.fp -= 1;
            sp = ret_sp;
            if (vm.fp == entry_fp) {
                // 値の個数は、関数の本体が書いてある（§6.2）
                vm.sp = sp;
                return result;
            }
            frame = &vm.frames[vm.fp - 1];
            closure = function.closurePtr(frame.closure);
            code = closure.codePtr();
            bc = code.bytecode;
            consts = code.constants();
            base = frame.base;
            ip = frame.ip;
            stack[sp] = result;
            sp += 1;
            continue :dispatch next(bc, &ip);
        },
        .jump => {
            const rel = ops.readI32(bc, ip);
            ip = @intCast(@as(i64, @intCast(ip + 4)) + rel);
            continue :dispatch next(bc, &ip);
        },
        .jump_if_nil => {
            const rel = ops.readI32(bc, ip);
            ip += 4;
            sp -= 1;
            if (stack[sp] == Value.nil) ip = @intCast(@as(i64, @intCast(ip)) + rel);
            continue :dispatch next(bc, &ip);
        },
        .cons => {
            vm.sp = sp;
            const c = rt.cons(stack[sp - 2], stack[sp - 1]) catch return th.outOfMemory();
            sp -= 1;
            stack[sp - 1] = c;
            continue :dispatch next(bc, &ip);
        },
        .car => {
            const x = stack[sp - 1];
            if (x.isCons()) {
                stack[sp - 1] = Runtime.consPtr(x).car;
            } else if (x != Value.nil) {
                return th.typeError(x, rt.syms.list);
            }
            continue :dispatch next(bc, &ip);
        },
        .cdr => {
            const x = stack[sp - 1];
            if (x.isCons()) {
                stack[sp - 1] = Runtime.consPtr(x).cdr;
            } else if (x != Value.nil) {
                return th.typeError(x, rt.syms.list);
            }
            continue :dispatch next(bc, &ip);
        },
        .eq => {
            sp -= 1;
            stack[sp - 1] = rt.boolean(stack[sp - 1] == stack[sp]);
            continue :dispatch next(bc, &ip);
        },
        .not => {
            stack[sp - 1] = rt.boolean(stack[sp - 1] == Value.nil);
            continue :dispatch next(bc, &ip);
        },
        inline .add2, .sub2 => |op| {
            const a = stack[sp - 2];
            const b = stack[sp - 1];
            var r: Value = Value.unwind;
            if (a.isFixnum() and b.isFixnum()) {
                // タグを付けたまま加減算する。溢れは 62 ビットの範囲を超えたことを表す（§2.2）
                const x = if (op == .add2) @addWithOverflow(tagged(a), tagged(b)) else @subWithOverflow(tagged(a), tagged(b));
                if (x[1] == 0) r = Value.fromRaw(@bitCast(x[0]));
            }
            if (r == Value.unwind) {
                vm.sp = sp;
                r = if (op == .add2) numbers.add2(th, a, b) else numbers.sub2(th, a, b);
                if (r == Value.unwind) return r;
            }
            sp -= 1;
            stack[sp - 1] = r;
            continue :dispatch next(bc, &ip);
        },
        inline .add1, .sub1 => |op| {
            const a = stack[sp - 1];
            var r: Value = Value.unwind;
            if (a.isFixnum()) {
                const one = tagged(Value.fromFixnum(1));
                const x = if (op == .add1) @addWithOverflow(tagged(a), one) else @subWithOverflow(tagged(a), one);
                if (x[1] == 0) r = Value.fromRaw(@bitCast(x[0]));
            }
            if (r == Value.unwind) {
                vm.sp = sp;
                r = if (op == .add1) numbers.add2(th, a, Value.fromFixnum(1)) else numbers.sub2(th, a, Value.fromFixnum(1));
                if (r == Value.unwind) return r;
            }
            stack[sp - 1] = r;
            continue :dispatch next(bc, &ip);
        },
        inline .lt2, .gt2, .le2, .ge2, .numeq2 => |o| {
            const a = stack[sp - 2];
            const b = stack[sp - 1];
            const c: numbers.Cmp = switch (o) {
                .lt2 => .lt,
                .gt2 => .gt,
                .le2 => .le,
                .ge2 => .ge,
                .numeq2 => .eq,
                else => unreachable,
            };
            var r: Value = undefined;
            if (a.isFixnum() and b.isFixnum()) {
                const x = tagged(a);
                const y = tagged(b);
                r = rt.boolean(switch (c) {
                    .lt => x < y,
                    .gt => x > y,
                    .le => x <= y,
                    .ge => x >= y,
                    .eq => x == y,
                });
            } else {
                vm.sp = sp;
                r = numbers.compare2(th, c, a, b);
                if (r == Value.unwind) return r;
            }
            sp -= 1;
            stack[sp - 1] = r;
            continue :dispatch next(bc, &ip);
        },
        .values => {
            const w = wide;
            wide = false;
            const n = readCount(bc, &ip, w);
            // [v1 ... vn] → [v1]、残りは多値レジスタへ
            if (n == 0) {
                stack[sp] = Value.nil;
                sp += 1;
            } else {
                const first = sp - n;
                for (1..n) |i| th.mv[i] = stack[first + i];
                sp = first + 1;
            }
            th.mv_count = n;
            continue :dispatch next(bc, &ip);
        },
        .single => {
            th.mv_count = 1;
            continue :dispatch next(bc, &ip);
        },
        .mv_list => {
            vm.sp = sp;
            stack[sp - 1] = th.valuesToList(stack[sp - 1]) catch return th.outOfMemory();
            continue :dispatch next(bc, &ip);
        },
        .mv_push_n => {
            const w = wide;
            wide = false;
            const n = readCount(bc, &ip, w);
            const count = th.mv_count;
            const primary = stack[sp - 1];
            sp -= 1;
            for (0..n) |i| {
                stack[sp] = if (i >= count) Value.nil else if (i == 0) primary else th.mv[i];
                sp += 1;
            }
            continue :dispatch next(bc, &ip);
        },
        .mv_restore => {
            stack[sp - 1] = th.listToValues(stack[sp - 1]);
            continue :dispatch next(bc, &ip);
        },
        .block_enter => {
            const w = wide;
            wide = false;
            const slot = readIndex(bc, &ip, w);
            const rel = ops.readI32(bc, ip);
            ip += 4;
            const token = th.newBlockToken();
            const resume_at: usize = @intCast(@as(i64, @intCast(ip)) + rel);
            if (th.pushControl(.block, token, vm.fp, sp, resume_at) == Value.unwind) return Value.unwind;
            stack[base + slot] = token;
            continue :dispatch next(bc, &ip);
        },
        .catch_enter => {
            const rel = ops.readI32(bc, ip);
            ip += 4;
            sp -= 1;
            const resume_at: usize = @intCast(@as(i64, @intCast(ip)) + rel);
            if (th.pushControl(.catch_tag, stack[sp], vm.fp, sp, resume_at) == Value.unwind) return Value.unwind;
            continue :dispatch next(bc, &ip);
        },
        .uwp_enter => {
            const rel = ops.readI32(bc, ip);
            ip += 4;
            const resume_at: usize = @intCast(@as(i64, @intCast(ip)) + rel);
            if (th.pushControl(.unwind_protect, Value.nil, vm.fp, sp, resume_at) == Value.unwind) return Value.unwind;
            continue :dispatch next(bc, &ip);
        },
        .control_pop => {
            const w = wide;
            wide = false;
            const n = readCount(bc, &ip, w);
            // 検証済みのバイトコードでは足りなくなることはない（検証器が制御スタックの並びを調べる）
            if (n > th.control_depth) return th.internalError();
            th.control_depth -= n;
            continue :dispatch next(bc, &ip);
        },
        .uwp_save => {
            vm.sp = sp;
            stack[sp] = th.uwpSave(stack[sp - 1]);
            sp += 1;
            continue :dispatch next(bc, &ip);
        },
        .uwp_end => {
            const r = th.uwpEnd(stack[sp - 2], stack[sp - 1]);
            if (r == Value.unwind) return r;
            sp -= 1;
            stack[sp - 1] = r;
            continue :dispatch next(bc, &ip);
        },
        .return_from_nl => {
            vm.sp = sp;
            return th.returnFrom(stack[sp - 2], stack[sp - 1]);
        },
        .throw => {
            vm.sp = sp;
            return th.throwTo(stack[sp - 2], stack[sp - 1]);
        },
        .slide => {
            const w = wide;
            wide = false;
            const n = readCount(bc, &ip, w);
            stack[sp - 1 - n] = stack[sp - 1];
            sp -= n;
            continue :dispatch next(bc, &ip);
        },
        .wide => {
            wide = true;
            continue :dispatch next(bc, &ip);
        },
    }
}
