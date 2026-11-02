//! Zig で書いたプリミティブの登録表（詳細設計 §11.1 の 4）。
//! 起動時に、CL のシンボルの関数セルに native_function を置き、「未実装」の印を外す。

const std = @import("std");
const Value = @import("../values/value.zig").Value;
const runtime = @import("../runtime/runtime.zig");
const Runtime = runtime.Runtime;
const SymbolFlags = @import("../values/object.zig").SymbolFlags;
const function = @import("../runtime/function.zig");
const numbers = @import("numbers.zig");
const lists = @import("lists.zig");
const functions = @import("functions.zig");

const any = function.any_args;

pub const Entry = struct {
    name: []const u8,
    impl: function.Impl,
    min: u32,
    max: u32,
};

pub const table = [_]Entry{
    // 数（numbers.zig）
    .{ .name = "+", .impl = numbers.plus, .min = 0, .max = any },
    .{ .name = "-", .impl = numbers.minus, .min = 1, .max = any },
    .{ .name = "*", .impl = numbers.times, .min = 0, .max = any },
    .{ .name = "/", .impl = numbers.divide, .min = 1, .max = any },
    .{ .name = "1+", .impl = numbers.onePlus, .min = 1, .max = 1 },
    .{ .name = "1-", .impl = numbers.oneMinus, .min = 1, .max = 1 },
    .{ .name = "=", .impl = numbers.numEq, .min = 1, .max = any },
    .{ .name = "/=", .impl = numbers.numNe, .min = 1, .max = any },
    .{ .name = "<", .impl = numbers.lessThan, .min = 1, .max = any },
    .{ .name = ">", .impl = numbers.greaterThan, .min = 1, .max = any },
    .{ .name = "<=", .impl = numbers.lessEq, .min = 1, .max = any },
    .{ .name = ">=", .impl = numbers.greaterEq, .min = 1, .max = any },
    // リストと述語（lists.zig）
    .{ .name = "CONS", .impl = lists.cons, .min = 2, .max = 2 },
    .{ .name = "CAR", .impl = lists.car, .min = 1, .max = 1 },
    .{ .name = "CDR", .impl = lists.cdr, .min = 1, .max = 1 },
    .{ .name = "FIRST", .impl = lists.car, .min = 1, .max = 1 },
    .{ .name = "REST", .impl = lists.cdr, .min = 1, .max = 1 },
    .{ .name = "LIST", .impl = lists.list, .min = 0, .max = any },
    .{ .name = "LIST*", .impl = lists.listStar, .min = 1, .max = any },
    .{ .name = "NULL", .impl = lists.null_, .min = 1, .max = 1 },
    .{ .name = "NOT", .impl = lists.null_, .min = 1, .max = 1 },
    .{ .name = "ATOM", .impl = lists.atom, .min = 1, .max = 1 },
    .{ .name = "CONSP", .impl = lists.consp, .min = 1, .max = 1 },
    .{ .name = "LISTP", .impl = lists.listp, .min = 1, .max = 1 },
    .{ .name = "SYMBOLP", .impl = lists.symbolp, .min = 1, .max = 1 },
    .{ .name = "NUMBERP", .impl = lists.numberp, .min = 1, .max = 1 },
    .{ .name = "FUNCTIONP", .impl = lists.functionp, .min = 1, .max = 1 },
    .{ .name = "EQ", .impl = lists.eq, .min = 2, .max = 2 },
    .{ .name = "EQL", .impl = lists.eql, .min = 2, .max = 2 },
    // 関数の呼び出しと印字（functions.zig）
    .{ .name = "FUNCALL", .impl = functions.funcall, .min = 1, .max = any },
    .{ .name = "APPLY", .impl = functions.apply, .min = 2, .max = any },
    .{ .name = "PRIN1", .impl = functions.prin1, .min = 1, .max = 1 },
    .{ .name = "PRINT", .impl = functions.print, .min = 1, .max = 1 },
    .{ .name = "TERPRI", .impl = functions.terpri, .min = 0, .max = 0 },
    // 関数の参照（Phase 10）
    .{ .name = "FBOUNDP", .impl = functions.fboundp, .min = 1, .max = 1 },
    .{ .name = "SYMBOL-FUNCTION", .impl = functions.symbolFunction, .min = 1, .max = 1 },
    // 特殊変数の値（Phase 14）
    .{ .name = "BOUNDP", .impl = functions.boundp, .min = 1, .max = 1 },
    .{ .name = "SYMBOL-VALUE", .impl = functions.symbolValue, .min = 1, .max = 1 },
    .{ .name = "SET", .impl = functions.set, .min = 2, .max = 2 },
    .{ .name = "MAKUNBOUND", .impl = functions.makunbound, .min = 1, .max = 1 },
};

/// ZILISP-SYSTEM パッケージのプリミティブ（コンパイラが展開先として使う内部の関数）
pub const sys_table = [_]Entry{
    .{ .name = "%DEFUN", .impl = functions.sysDefun, .min = 2, .max = 2 },
    .{ .name = "%PROCLAIM-SPECIAL", .impl = functions.sysProclaimSpecial, .min = 1, .max = 1 },
};

pub fn install(rt: *Runtime) runtime.Error!void {
    for (table) |e| {
        const found = rt.findSymbol(rt.cl, e.name) orelse std.debug.panic("CL のシンボルがありません: {s}", .{e.name});
        const sym = found.symbol;
        const f = try function.makeNative(rt, sym, e.impl, e.min, e.max);
        const s = rt.symbolPtr(sym);
        s.function = f;
        s.header.flags &= ~SymbolFlags.unimplemented;
    }
    for (sys_table) |e| {
        const sym = try rt.intern(rt.sys, e.name);
        rt.symbolPtr(sym).function = try function.makeNative(rt, sym, e.impl, e.min, e.max);
    }
    rt.sys_defun = rt.findSymbol(rt.sys, "%DEFUN").?.symbol;
    rt.sys_proclaim_special = rt.findSymbol(rt.sys, "%PROCLAIM-SPECIAL").?.symbol;
    // Resolver が直接展開するマクロ（Zig で書いたブートストラップ用のマクロ：§11.1 の 6）。
    // マクロの印は残す（funcall できない）が、「未実装」の印は外す
    for ([_]Value{ rt.syms.defun, rt.syms.defvar, rt.syms.defparameter }) |m| rt.symbolPtr(m).header.flags &= ~SymbolFlags.unimplemented;
    // Resolver が直接解釈する特殊演算子
    rt.symbolPtr(rt.syms.progv).header.flags &= ~SymbolFlags.unimplemented;
}

test {
    _ = numbers;
}
