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

// ---------------------------------------------------------------------------
// 関数の定義と参照（Phase 10）

fn isSymbol(v: Value) bool {
    return v == Value.nil or (v.isOther() and Runtime.kindOf(v) == .symbol);
}

/// ZILISP-SYSTEM::%DEFUN 名前 関数：defun の展開先。関数をシンボルの関数セルに置き、名前を返す
pub fn sysDefun(th: *Thread, args: []const Value) Value {
    const name = args[0];
    const f = args[1];
    if (!isSymbol(name) or name == Value.nil) return th.typeError(name, th.rt.syms.symbol);
    const s = th.rt.symbolPtr(name);
    // CL パッケージのシンボルの関数は再定義できない（CLHS 11.1.2.1.2。SBCL 2.6.7 ではパッケージのロックのエラー）
    if (s.package == th.rt.cl.obj)
        return th.signal(.package_error, "COMMON-LISP パッケージのシンボルの関数は定義できません", name, Value.unbound);
    s.function = f;
    return name;
}

/// fboundp：関数・マクロ・特殊演算子の名前なら真（関数ならその関数を返す。SBCL 2.6.7 と同じ）
pub fn fboundp(th: *Thread, args: []const Value) Value {
    const name = args[0];
    if (!isSymbol(name)) return th.typeError(name, th.rt.syms.symbol);
    const s = th.rt.symbolPtr(name);
    if (s.function != Value.unbound) return s.function;
    const flags = @import("../values/object.zig").SymbolFlags;
    if (s.hasFlag(flags.special_operator) or s.hasFlag(flags.macro)) return th.rt.t;
    return Value.nil;
}

/// symbol-function：シンボルの関数セルの関数（なければ undefined-function）
pub fn symbolFunction(th: *Thread, args: []const Value) Value {
    const name = args[0];
    if (!isSymbol(name)) return th.typeError(name, th.rt.syms.symbol);
    const f = th.rt.symbolPtr(name).function;
    if (f == Value.unbound) return th.signal(.undefined_function, "", name, Value.unbound);
    return f;
}

// ---------------------------------------------------------------------------
// 特殊変数の値（Phase 14。値は今の動的な値：§6.5 の shallow binding）

pub fn boundp(th: *Thread, args: []const Value) Value {
    const name = args[0];
    if (!isSymbol(name)) return th.typeError(name, th.rt.syms.symbol);
    return th.rt.boolean(th.rt.symbolPtr(name).value != Value.unbound);
}

pub fn symbolValue(th: *Thread, args: []const Value) Value {
    const name = args[0];
    if (!isSymbol(name)) return th.typeError(name, th.rt.syms.symbol);
    const v = th.rt.symbolPtr(name).value;
    if (v == Value.unbound) return th.signal(.unbound_variable, "", name, Value.unbound);
    return v;
}

fn checkAssignable(th: *Thread, name: Value) ?Value {
    if (!isSymbol(name)) return th.typeError(name, th.rt.syms.symbol);
    const flags = @import("../values/object.zig").SymbolFlags;
    const s = th.rt.symbolPtr(name);
    if (name == Value.nil or s.hasFlag(flags.constant) or s.hasFlag(flags.keyword))
        return th.signal(.program_error, "定数には代入できません", name, Value.unbound);
    return null;
}

pub fn set(th: *Thread, args: []const Value) Value {
    if (checkAssignable(th, args[0])) |e| return e;
    th.rt.symbolPtr(args[0]).value = args[1];
    return args[1];
}

pub fn makunbound(th: *Thread, args: []const Value) Value {
    if (checkAssignable(th, args[0])) |e| return e;
    th.rt.symbolPtr(args[0]).value = Value.unbound;
    return args[0];
}
