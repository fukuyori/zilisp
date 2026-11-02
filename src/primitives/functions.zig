//! funcall・apply、印字（print・prin1・terpri）。
//! 印字の出力先は th.out（*standard-output* の代わり。ストリームは Phase 23 で実装する）。

const std = @import("std");
const Value = @import("../values/value.zig").Value;
const thread_mod = @import("../runtime/thread.zig");
const Thread = thread_mod.Thread;
const Runtime = @import("../runtime/runtime.zig").Runtime;
const printer = @import("../printer/printer.zig");

pub fn funcall(th: *Thread, args: []const Value) Value {
    return th.call(args[0], args[1..]);
}

/// (apply f a1 ... an list)：引数を VM の値スタックの上に並べて呼ぶ（並べた値は GC のルートになる）
pub fn apply(th: *Thread, args: []const Value) Value {
    const f = args[0];
    const fixed = args[1 .. args.len - 1];
    const spread = args[args.len - 1];
    var n: usize = fixed.len;
    var x = spread;
    while (x.isCons()) : (x = Runtime.consPtr(x).cdr) n += 1;
    if (x != Value.nil) return th.typeError(spread, th.rt.syms.list);
    if (n >= thread_mod.call_arguments_limit)
        return th.signal(.program_error, "引数が多すぎます（call-arguments-limit を超えています）", Value.fromFixnum(@intCast(n)), Value.unbound);
    const slots = th.vm.reserve(n) orelse return th.signal(.storage_condition, "VM の値スタックが溢れました", Value.unbound, Value.unbound);
    defer th.vm.release(n);
    @memcpy(slots[0..fixed.len], fixed);
    var i = fixed.len;
    x = spread;
    while (x.isCons()) : (x = Runtime.consPtr(x).cdr) {
        slots[i] = Runtime.consPtr(x).car;
        i += 1;
    }
    return th.call(f, slots);
}

fn writeFailed(th: *Thread) Value {
    return th.signal(.simple_error, "出力に失敗しました", Value.unbound, Value.unbound);
}

pub fn prin1(th: *Thread, args: []const Value) Value {
    printer.prin1(th.rt, th.out, args[0]) catch return writeFailed(th);
    return args[0];
}

/// print：改行、prin1、空白（CLHS print）
pub fn print(th: *Thread, args: []const Value) Value {
    th.out.writeByte('\n') catch return writeFailed(th);
    printer.prin1(th.rt, th.out, args[0]) catch return writeFailed(th);
    th.out.writeByte(' ') catch return writeFailed(th);
    return args[0];
}

pub fn terpri(th: *Thread, args: []const Value) Value {
    _ = args;
    th.out.writeByte('\n') catch return writeFailed(th);
    return Value.nil;
}
