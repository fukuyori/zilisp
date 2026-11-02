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
const macros = @import("macros.zig");
const hashtables = @import("hashtables.zig");
const arrays = @import("arrays.zig");
const sequences = @import("sequences.zig");

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
    // Phase 19：反復の教材で使う数の関数
    .{ .name = "EVENP", .impl = numbers.evenp, .min = 1, .max = 1 },
    .{ .name = "ODDP", .impl = numbers.oddp, .min = 1, .max = 1 },
    .{ .name = "ZEROP", .impl = numbers.zerop, .min = 1, .max = 1 },
    .{ .name = "PLUSP", .impl = numbers.plusp, .min = 1, .max = 1 },
    .{ .name = "MINUSP", .impl = numbers.minusp, .min = 1, .max = 1 },
    .{ .name = "MAX", .impl = numbers.max, .min = 1, .max = any },
    .{ .name = "MIN", .impl = numbers.min, .min = 1, .max = any },
    .{ .name = "ABS", .impl = numbers.abs, .min = 1, .max = 1 },
    .{ .name = "MOD", .impl = numbers.mod, .min = 2, .max = 2 },
    .{ .name = "REM", .impl = numbers.rem, .min = 2, .max = 2 },
    // Phase 20：数の階層（bignum・比）
    .{ .name = "FLOOR", .impl = numbers.floor, .min = 1, .max = 2 },
    .{ .name = "CEILING", .impl = numbers.ceiling, .min = 1, .max = 2 },
    .{ .name = "TRUNCATE", .impl = numbers.truncate, .min = 1, .max = 2 },
    .{ .name = "ROUND", .impl = numbers.round, .min = 1, .max = 2 },
    .{ .name = "GCD", .impl = numbers.gcd, .min = 0, .max = any },
    .{ .name = "LCM", .impl = numbers.lcm, .min = 0, .max = any },
    .{ .name = "NUMERATOR", .impl = numbers.numerator, .min = 1, .max = 1 },
    .{ .name = "DENOMINATOR", .impl = numbers.denominator, .min = 1, .max = 1 },
    .{ .name = "RATIONAL", .impl = numbers.rational, .min = 1, .max = 1 },
    .{ .name = "FLOAT", .impl = numbers.float, .min = 1, .max = 2 },
    .{ .name = "INTEGERP", .impl = numbers.integerp, .min = 1, .max = 1 },
    .{ .name = "RATIONALP", .impl = numbers.rationalp, .min = 1, .max = 1 },
    .{ .name = "FLOATP", .impl = numbers.floatp, .min = 1, .max = 1 },
    .{ .name = "REALP", .impl = numbers.realp, .min = 1, .max = 1 },
    .{ .name = "COMPLEXP", .impl = numbers.complexp, .min = 1, .max = 1 },
    .{ .name = "EXPT", .impl = numbers.expt, .min = 2, .max = 2 },
    .{ .name = "SQRT", .impl = numbers.sqrt, .min = 1, .max = 1 },
    .{ .name = "ISQRT", .impl = numbers.isqrt, .min = 1, .max = 1 },
    .{ .name = "EXP", .impl = numbers.exp, .min = 1, .max = 1 },
    .{ .name = "LOG", .impl = numbers.log, .min = 1, .max = 2 },
    .{ .name = "SIN", .impl = numbers.sin, .min = 1, .max = 1 },
    .{ .name = "COS", .impl = numbers.cos, .min = 1, .max = 1 },
    .{ .name = "TAN", .impl = numbers.tan, .min = 1, .max = 1 },
    .{ .name = "ASIN", .impl = numbers.asin, .min = 1, .max = 1 },
    .{ .name = "ACOS", .impl = numbers.acos, .min = 1, .max = 1 },
    .{ .name = "ATAN", .impl = numbers.atan, .min = 1, .max = 2 },
    .{ .name = "LOGAND", .impl = numbers.logand, .min = 0, .max = any },
    .{ .name = "LOGIOR", .impl = numbers.logior, .min = 0, .max = any },
    .{ .name = "LOGXOR", .impl = numbers.logxor, .min = 0, .max = any },
    .{ .name = "LOGNOT", .impl = numbers.lognot, .min = 1, .max = 1 },
    .{ .name = "ASH", .impl = numbers.ash, .min = 2, .max = 2 },
    .{ .name = "INTEGER-LENGTH", .impl = numbers.integerLength, .min = 1, .max = 1 },
    .{ .name = "LOGCOUNT", .impl = numbers.logcount, .min = 1, .max = 1 },
    // Phase 19：列・文字列の一部（sequences.zig）と出力
    .{ .name = "REVERSE", .impl = sequences.reverse, .min = 1, .max = 1 },
    .{ .name = "NREVERSE", .impl = sequences.nreverse, .min = 1, .max = 1 },
    .{ .name = "COPY-LIST", .impl = sequences.copyList, .min = 1, .max = 1 },
    .{ .name = "LAST", .impl = sequences.last, .min = 1, .max = 2 },
    .{ .name = "ENDP", .impl = sequences.endp, .min = 1, .max = 1 },
    .{ .name = "SYMBOL-NAME", .impl = sequences.symbolName, .min = 1, .max = 1 },
    .{ .name = "STRING=", .impl = sequences.stringEq, .min = 2, .max = any },
    .{ .name = "STRING-UPCASE", .impl = sequences.stringUpcase, .min = 1, .max = any },
    .{ .name = "STRING-DOWNCASE", .impl = sequences.stringDowncase, .min = 1, .max = any },
    .{ .name = "CHAR=", .impl = sequences.charEq, .min = 1, .max = any },
    .{ .name = "PRINC", .impl = functions.princ, .min = 1, .max = 1 },
    .{ .name = "FORMAT", .impl = functions.format, .min = 2, .max = any },
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
    // マクロ（Phase 15）
    .{ .name = "MACROEXPAND-1", .impl = macros.macroexpand1, .min = 1, .max = 2 },
    .{ .name = "MACROEXPAND", .impl = macros.macroexpand, .min = 1, .max = 2 },
    .{ .name = "MACRO-FUNCTION", .impl = macros.macroFunction, .min = 1, .max = 2 },
    .{ .name = "GENSYM", .impl = macros.gensym, .min = 0, .max = 1 },
    .{ .name = "APPEND", .impl = lists.append, .min = 0, .max = any },
    .{ .name = "VECTOR", .impl = lists.vector, .min = 0, .max = any },
    // setf と場所（Phase 16）
    .{ .name = "RPLACA", .impl = lists.rplaca, .min = 2, .max = 2 },
    .{ .name = "RPLACD", .impl = lists.rplacd, .min = 2, .max = 2 },
    .{ .name = "NTH", .impl = lists.nth, .min = 2, .max = 2 },
    .{ .name = "NTHCDR", .impl = lists.nthcdr, .min = 2, .max = 2 },
    .{ .name = "CAAR", .impl = lists.makeCxr("aa"), .min = 1, .max = 1 },
    .{ .name = "CADR", .impl = lists.makeCxr("ad"), .min = 1, .max = 1 },
    .{ .name = "CDAR", .impl = lists.makeCxr("da"), .min = 1, .max = 1 },
    .{ .name = "CDDR", .impl = lists.makeCxr("dd"), .min = 1, .max = 1 },
    .{ .name = "CAAAR", .impl = lists.makeCxr("aaa"), .min = 1, .max = 1 },
    .{ .name = "CAADR", .impl = lists.makeCxr("aad"), .min = 1, .max = 1 },
    .{ .name = "CADAR", .impl = lists.makeCxr("ada"), .min = 1, .max = 1 },
    .{ .name = "CADDR", .impl = lists.makeCxr("add"), .min = 1, .max = 1 },
    .{ .name = "CDAAR", .impl = lists.makeCxr("daa"), .min = 1, .max = 1 },
    .{ .name = "CDADR", .impl = lists.makeCxr("dad"), .min = 1, .max = 1 },
    .{ .name = "CDDAR", .impl = lists.makeCxr("dda"), .min = 1, .max = 1 },
    .{ .name = "CDDDR", .impl = lists.makeCxr("ddd"), .min = 1, .max = 1 },
    .{ .name = "CAAAAR", .impl = lists.makeCxr("aaaa"), .min = 1, .max = 1 },
    .{ .name = "CAAADR", .impl = lists.makeCxr("aaad"), .min = 1, .max = 1 },
    .{ .name = "CAADAR", .impl = lists.makeCxr("aada"), .min = 1, .max = 1 },
    .{ .name = "CAADDR", .impl = lists.makeCxr("aadd"), .min = 1, .max = 1 },
    .{ .name = "CADAAR", .impl = lists.makeCxr("adaa"), .min = 1, .max = 1 },
    .{ .name = "CADADR", .impl = lists.makeCxr("adad"), .min = 1, .max = 1 },
    .{ .name = "CADDAR", .impl = lists.makeCxr("adda"), .min = 1, .max = 1 },
    .{ .name = "CADDDR", .impl = lists.makeCxr("addd"), .min = 1, .max = 1 },
    .{ .name = "CDAAAR", .impl = lists.makeCxr("daaa"), .min = 1, .max = 1 },
    .{ .name = "CDAADR", .impl = lists.makeCxr("daad"), .min = 1, .max = 1 },
    .{ .name = "CDADAR", .impl = lists.makeCxr("dada"), .min = 1, .max = 1 },
    .{ .name = "CDADDR", .impl = lists.makeCxr("dadd"), .min = 1, .max = 1 },
    .{ .name = "CDDAAR", .impl = lists.makeCxr("ddaa"), .min = 1, .max = 1 },
    .{ .name = "CDDADR", .impl = lists.makeCxr("ddad"), .min = 1, .max = 1 },
    .{ .name = "CDDDAR", .impl = lists.makeCxr("ddda"), .min = 1, .max = 1 },
    .{ .name = "CDDDDR", .impl = lists.makeCxr("dddd"), .min = 1, .max = 1 },
    .{ .name = "SECOND", .impl = lists.makeNth(1), .min = 1, .max = 1 },
    .{ .name = "THIRD", .impl = lists.makeNth(2), .min = 1, .max = 1 },
    .{ .name = "FOURTH", .impl = lists.makeNth(3), .min = 1, .max = 1 },
    .{ .name = "FIFTH", .impl = lists.makeNth(4), .min = 1, .max = 1 },
    .{ .name = "SIXTH", .impl = lists.makeNth(5), .min = 1, .max = 1 },
    .{ .name = "SEVENTH", .impl = lists.makeNth(6), .min = 1, .max = 1 },
    .{ .name = "EIGHTH", .impl = lists.makeNth(7), .min = 1, .max = 1 },
    .{ .name = "NINTH", .impl = lists.makeNth(8), .min = 1, .max = 1 },
    .{ .name = "TENTH", .impl = lists.makeNth(9), .min = 1, .max = 1 },
    .{ .name = "GETF", .impl = lists.getf, .min = 2, .max = 3 },
    .{ .name = "EQUAL", .impl = lists.equal, .min = 2, .max = 2 },
    .{ .name = "GET", .impl = functions.get, .min = 2, .max = 3 },
    .{ .name = "SYMBOL-PLIST", .impl = functions.symbolPlist, .min = 1, .max = 1 },
    .{ .name = "FDEFINITION", .impl = functions.fdefinition, .min = 1, .max = 1 },
    .{ .name = "MAKE-HASH-TABLE", .impl = hashtables.makeHashTable, .min = 0, .max = any },
    .{ .name = "GETHASH", .impl = hashtables.gethash, .min = 2, .max = 3 },
    .{ .name = "REMHASH", .impl = hashtables.remhash, .min = 2, .max = 2 },
    .{ .name = "CLRHASH", .impl = hashtables.clrhash, .min = 1, .max = 1 },
    .{ .name = "MAPHASH", .impl = hashtables.maphash, .min = 2, .max = 2 },
    .{ .name = "HASH-TABLE-COUNT", .impl = hashtables.hashTableCount, .min = 1, .max = 1 },
    .{ .name = "HASH-TABLE-P", .impl = hashtables.hashTableP, .min = 1, .max = 1 },
    .{ .name = "MAKE-ARRAY", .impl = arrays.makeArray, .min = 1, .max = any },
    .{ .name = "AREF", .impl = arrays.aref, .min = 1, .max = any },
    .{ .name = "SVREF", .impl = arrays.svref, .min = 2, .max = 2 },
    .{ .name = "CHAR", .impl = arrays.char, .min = 2, .max = 2 },
    .{ .name = "SCHAR", .impl = arrays.char, .min = 2, .max = 2 },
    .{ .name = "LENGTH", .impl = arrays.length, .min = 1, .max = 1 },
    .{ .name = "COPY-SEQ", .impl = arrays.copySeq, .min = 1, .max = 1 },
    .{ .name = "VECTORP", .impl = arrays.vectorp, .min = 1, .max = 1 },
    .{ .name = "ARRAYP", .impl = arrays.arrayp, .min = 1, .max = 1 },
    .{ .name = "SIMPLE-VECTOR-P", .impl = arrays.simpleVectorP, .min = 1, .max = 1 },
    // 多値（Phase 17）
    .{ .name = "VALUES", .impl = functions.values, .min = 0, .max = any },
    .{ .name = "VALUES-LIST", .impl = functions.valuesList, .min = 1, .max = 1 },
};

/// ZILISP-SYSTEM パッケージのプリミティブ（コンパイラが展開先として使う内部の関数）
pub const sys_table = [_]Entry{
    .{ .name = "%DEFUN", .impl = functions.sysDefun, .min = 2, .max = 2 },
    .{ .name = "%PROCLAIM-SPECIAL", .impl = functions.sysProclaimSpecial, .min = 1, .max = 1 },
    .{ .name = "%DEFMACRO", .impl = macros.sysDefmacro, .min = 2, .max = 2 },
    .{ .name = "%DBIND-ERROR", .impl = macros.sysDbindError, .min = 2, .max = 2 },
    .{ .name = "%GETF-KEY", .impl = macros.sysGetfKey, .min = 2, .max = 2 },
    .{ .name = "%CHECK-KEYS", .impl = macros.sysCheckKeys, .min = 4, .max = 4 },
    .{ .name = "%MACRO-FORM-ERROR", .impl = macros.sysMacroFormError, .min = 2, .max = 2 },
    .{ .name = "%UNIMPLEMENTED-ERROR", .impl = macros.sysUnimplementedError, .min = 2, .max = 2 },
    // setf の展開先（値を返す）
    .{ .name = "%SET-CAR", .impl = lists.sysSetCar, .min = 2, .max = 2 },
    .{ .name = "%SET-CDR", .impl = lists.sysSetCdr, .min = 2, .max = 2 },
    .{ .name = "%PUTF", .impl = lists.sysPutf, .min = 3, .max = 3 },
    .{ .name = "%PUT", .impl = functions.sysPut, .min = 3, .max = 4 },
    .{ .name = "%PUTHASH", .impl = hashtables.sysPuthash, .min = 3, .max = 4 },
    .{ .name = "%ASET", .impl = arrays.sysAset, .min = 3, .max = any },
    .{ .name = "%SVSET", .impl = arrays.sysSvset, .min = 3, .max = 3 },
    .{ .name = "%SET-CHAR", .impl = arrays.sysSetChar, .min = 3, .max = 3 },
    .{ .name = "%SET-FDEFINITION", .impl = functions.sysSetFdefinition, .min = 2, .max = 2 },
    .{ .name = "%HASH-PAIRS", .impl = hashtables.sysHashPairs, .min = 1, .max = 1 },
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
    rt.sys_defmacro = rt.findSymbol(rt.sys, "%DEFMACRO").?.symbol;
    rt.sys_set_fdefinition = rt.findSymbol(rt.sys, "%SET-FDEFINITION").?.symbol;
    rt.sys_quasiquote = try rt.intern(rt.sys, "QUASIQUOTE");
    // 分解束縛の展開が引用するシンボル
    rt.sys_missing = try rt.intern(rt.sys, "%MISSING");
    _ = try rt.intern(rt.sys, "TOO-FEW");
    _ = try rt.intern(rt.sys, "TOO-MANY");
    rt.sys_tombstone = try rt.intern(rt.sys, "%TOMBSTONE");
    // Resolver が直接展開するマクロ（Zig で書いたブートストラップ用のマクロ：§11.1 の 6）。
    // マクロの印は残す（funcall できない）が、「未実装」の印は外す
    for ([_]Value{ rt.syms.defun, rt.syms.defvar, rt.syms.defparameter, rt.syms.defmacro, rt.syms.@"destructuring-bind", rt.syms.@"multiple-value-bind", rt.syms.@"multiple-value-list" }) |m| rt.symbolPtr(m).header.flags &= ~SymbolFlags.unimplemented;
    // Resolver が直接解釈する特殊演算子
    for ([_]Value{ rt.syms.progv, rt.syms.@"eval-when", rt.syms.@"multiple-value-prog1", rt.syms.@"multiple-value-call", rt.syms.block, rt.syms.@"return-from", rt.syms.@"catch", rt.syms.throw, rt.syms.@"unwind-protect", rt.syms.tagbody, rt.syms.go }) |op| rt.symbolPtr(op).header.flags &= ~SymbolFlags.unimplemented;
}

test {
    _ = numbers;
    _ = macros;
    _ = sequences;
}
