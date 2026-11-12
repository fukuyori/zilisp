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
const equalp = @import("equalp.zig");
const strings = @import("strings.zig");
const seqfns = @import("seqfns.zig");
const packages = @import("packages.zig");
const load_mod = @import("load.zig");
const streams = @import("streams.zig");
const pathnames = @import("pathnames.zig");
const format_mod = @import("format.zig");
const readtable_mod = @import("../reader/readtable.zig");
const pprint_mod = @import("../printer/pprint.zig");
const types = @import("types.zig");
const conditions = @import("conditions.zig");
const time_mod = @import("time.zig");
const structures = @import("structures.zig");
const clos = @import("clos.zig");

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
    .{ .name = "PRINC", .impl = streams.princ, .min = 1, .max = 2 },
    .{ .name = "FORMAT", .impl = format_mod.format, .min = 2, .max = any },
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
    .{ .name = "PRIN1", .impl = streams.prin1, .min = 1, .max = 2 },
    .{ .name = "PRINT", .impl = streams.print, .min = 1, .max = 2 },
    .{ .name = "TERPRI", .impl = streams.terpri, .min = 0, .max = 1 },
    // 関数の参照（Phase 10）
    .{ .name = "FBOUNDP", .impl = functions.fboundp, .min = 1, .max = 1 },
    .{ .name = "SPECIAL-OPERATOR-P", .impl = functions.specialOperatorP, .min = 1, .max = 1 },
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
    .{ .name = "EQUALP", .impl = equalp.equalp, .min = 2, .max = 2 },
    .{ .name = "SXHASH", .impl = hashtables.sxhash, .min = 1, .max = 1 },
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
    .{ .name = "SCHAR", .impl = arrays.schar, .min = 2, .max = 2 },
    .{ .name = "LENGTH", .impl = arrays.length, .min = 1, .max = 1 },
    .{ .name = "COPY-SEQ", .impl = arrays.copySeq, .min = 1, .max = 1 },
    .{ .name = "VECTORP", .impl = arrays.vectorp, .min = 1, .max = 1 },
    .{ .name = "ARRAYP", .impl = arrays.arrayp, .min = 1, .max = 1 },
    .{ .name = "SIMPLE-VECTOR-P", .impl = arrays.simpleVectorP, .min = 1, .max = 1 },
    // 一般の配列（Phase 21）
    .{ .name = "ROW-MAJOR-AREF", .impl = arrays.rowMajorAref, .min = 2, .max = 2 },
    .{ .name = "ARRAY-DIMENSIONS", .impl = arrays.arrayDimensions, .min = 1, .max = 1 },
    .{ .name = "ARRAY-DIMENSION", .impl = arrays.arrayDimension, .min = 2, .max = 2 },
    .{ .name = "ARRAY-RANK", .impl = arrays.arrayRank, .min = 1, .max = 1 },
    .{ .name = "ARRAY-TOTAL-SIZE", .impl = arrays.arrayTotalSize, .min = 1, .max = 1 },
    .{ .name = "ARRAY-ROW-MAJOR-INDEX", .impl = arrays.arrayRowMajorIndex, .min = 1, .max = any },
    .{ .name = "ARRAY-ELEMENT-TYPE", .impl = arrays.arrayElementType, .min = 1, .max = 1 },
    .{ .name = "ARRAY-HAS-FILL-POINTER-P", .impl = arrays.arrayHasFillPointerP, .min = 1, .max = 1 },
    .{ .name = "ADJUSTABLE-ARRAY-P", .impl = arrays.adjustableArrayP, .min = 1, .max = 1 },
    .{ .name = "FILL-POINTER", .impl = arrays.fillPointer, .min = 1, .max = 1 },
    .{ .name = "VECTOR-PUSH", .impl = arrays.vectorPush, .min = 2, .max = 2 },
    .{ .name = "VECTOR-PUSH-EXTEND", .impl = arrays.vectorPushExtend, .min = 2, .max = 3 },
    .{ .name = "ADJUST-ARRAY", .impl = arrays.adjustArray, .min = 2, .max = any },
    .{ .name = "STRINGP", .impl = arrays.stringp, .min = 1, .max = 1 },
    .{ .name = "SIMPLE-STRING-P", .impl = arrays.simpleStringP, .min = 1, .max = 1 },
    // 文字・文字列・列の関数（Phase 21）
    .{ .name = "CHARACTERP", .impl = strings.characterp, .min = 1, .max = 1 },
    .{ .name = "CHAR-CODE", .impl = strings.charCode, .min = 1, .max = 1 },
    .{ .name = "CODE-CHAR", .impl = strings.codeChar, .min = 1, .max = 1 },
    .{ .name = "CHAR-INT", .impl = strings.charInt, .min = 1, .max = 1 },
    .{ .name = "CHAR-UPCASE", .impl = strings.charUpcase, .min = 1, .max = 1 },
    .{ .name = "CHAR-DOWNCASE", .impl = strings.charDowncase, .min = 1, .max = 1 },
    .{ .name = "UPPER-CASE-P", .impl = strings.upperCaseP, .min = 1, .max = 1 },
    .{ .name = "LOWER-CASE-P", .impl = strings.lowerCaseP, .min = 1, .max = 1 },
    .{ .name = "BOTH-CASE-P", .impl = strings.bothCaseP, .min = 1, .max = 1 },
    .{ .name = "ALPHA-CHAR-P", .impl = strings.alphaCharP, .min = 1, .max = 1 },
    .{ .name = "ALPHANUMERICP", .impl = strings.alphanumericp, .min = 1, .max = 1 },
    .{ .name = "GRAPHIC-CHAR-P", .impl = strings.graphicCharP, .min = 1, .max = 1 },
    .{ .name = "STANDARD-CHAR-P", .impl = strings.standardCharP, .min = 1, .max = 1 },
    .{ .name = "DIGIT-CHAR-P", .impl = strings.digitCharP, .min = 1, .max = 2 },
    .{ .name = "DIGIT-CHAR", .impl = strings.digitChar, .min = 1, .max = 2 },
    .{ .name = "CHAR=", .impl = strings.charEq, .min = 1, .max = any },
    .{ .name = "CHAR/=", .impl = strings.charNe, .min = 1, .max = any },
    .{ .name = "CHAR<", .impl = strings.charLt, .min = 1, .max = any },
    .{ .name = "CHAR>", .impl = strings.charGt, .min = 1, .max = any },
    .{ .name = "CHAR<=", .impl = strings.charLe, .min = 1, .max = any },
    .{ .name = "CHAR>=", .impl = strings.charGe, .min = 1, .max = any },
    .{ .name = "CHAR-EQUAL", .impl = strings.charEqual, .min = 1, .max = any },
    .{ .name = "CHAR-NOT-EQUAL", .impl = strings.charNotEqual, .min = 1, .max = any },
    .{ .name = "CHAR-LESSP", .impl = strings.charLessp, .min = 1, .max = any },
    .{ .name = "CHAR-GREATERP", .impl = strings.charGreaterp, .min = 1, .max = any },
    .{ .name = "CHAR-NOT-GREATERP", .impl = strings.charNotGreaterp, .min = 1, .max = any },
    .{ .name = "CHAR-NOT-LESSP", .impl = strings.charNotLessp, .min = 1, .max = any },
    .{ .name = "STRING", .impl = strings.string, .min = 1, .max = 1 },
    .{ .name = "STRING=", .impl = strings.stringEq, .min = 2, .max = any },
    .{ .name = "STRING/=", .impl = strings.stringNe, .min = 2, .max = any },
    .{ .name = "STRING<", .impl = strings.stringLt, .min = 2, .max = any },
    .{ .name = "STRING>", .impl = strings.stringGt, .min = 2, .max = any },
    .{ .name = "STRING<=", .impl = strings.stringLe, .min = 2, .max = any },
    .{ .name = "STRING>=", .impl = strings.stringGe, .min = 2, .max = any },
    .{ .name = "STRING-EQUAL", .impl = strings.stringEqual, .min = 2, .max = any },
    .{ .name = "STRING-NOT-EQUAL", .impl = strings.stringNotEqual, .min = 2, .max = any },
    .{ .name = "STRING-LESSP", .impl = strings.stringLessp, .min = 2, .max = any },
    .{ .name = "STRING-GREATERP", .impl = strings.stringGreaterp, .min = 2, .max = any },
    .{ .name = "STRING-NOT-GREATERP", .impl = strings.stringNotGreaterp, .min = 2, .max = any },
    .{ .name = "STRING-NOT-LESSP", .impl = strings.stringNotLessp, .min = 2, .max = any },
    .{ .name = "STRING-UPCASE", .impl = strings.stringUpcase, .min = 1, .max = any },
    .{ .name = "STRING-DOWNCASE", .impl = strings.stringDowncase, .min = 1, .max = any },
    .{ .name = "STRING-CAPITALIZE", .impl = strings.stringCapitalize, .min = 1, .max = any },
    .{ .name = "NSTRING-UPCASE", .impl = strings.nstringUpcase, .min = 1, .max = any },
    .{ .name = "NSTRING-DOWNCASE", .impl = strings.nstringDowncase, .min = 1, .max = any },
    .{ .name = "NSTRING-CAPITALIZE", .impl = strings.nstringCapitalize, .min = 1, .max = any },
    .{ .name = "STRING-TRIM", .impl = strings.stringTrim, .min = 2, .max = 2 },
    .{ .name = "STRING-LEFT-TRIM", .impl = strings.stringLeftTrim, .min = 2, .max = 2 },
    .{ .name = "STRING-RIGHT-TRIM", .impl = strings.stringRightTrim, .min = 2, .max = 2 },
    .{ .name = "MAKE-STRING", .impl = strings.makeString, .min = 1, .max = any },
    .{ .name = "PARSE-INTEGER", .impl = strings.parseInteger, .min = 1, .max = any },
    .{ .name = "MEMBER", .impl = seqfns.member, .min = 2, .max = any },
    .{ .name = "MEMBER-IF", .impl = seqfns.memberIf, .min = 2, .max = any },
    .{ .name = "MEMBER-IF-NOT", .impl = seqfns.memberIfNot, .min = 2, .max = any },
    .{ .name = "ASSOC", .impl = seqfns.assoc, .min = 2, .max = any },
    .{ .name = "ASSOC-IF", .impl = seqfns.assocIf, .min = 2, .max = any },
    .{ .name = "ASSOC-IF-NOT", .impl = seqfns.assocIfNot, .min = 2, .max = any },
    .{ .name = "RASSOC", .impl = seqfns.rassoc, .min = 2, .max = any },
    .{ .name = "RASSOC-IF", .impl = seqfns.rassocIf, .min = 2, .max = any },
    .{ .name = "RASSOC-IF-NOT", .impl = seqfns.rassocIfNot, .min = 2, .max = any },
    .{ .name = "FIND", .impl = seqfns.find, .min = 2, .max = any },
    .{ .name = "FIND-IF", .impl = seqfns.findIf, .min = 2, .max = any },
    .{ .name = "FIND-IF-NOT", .impl = seqfns.findIfNot, .min = 2, .max = any },
    .{ .name = "POSITION", .impl = seqfns.position, .min = 2, .max = any },
    .{ .name = "POSITION-IF", .impl = seqfns.positionIf, .min = 2, .max = any },
    .{ .name = "POSITION-IF-NOT", .impl = seqfns.positionIfNot, .min = 2, .max = any },
    .{ .name = "COUNT", .impl = seqfns.count, .min = 2, .max = any },
    .{ .name = "COUNT-IF", .impl = seqfns.countIf, .min = 2, .max = any },
    .{ .name = "COUNT-IF-NOT", .impl = seqfns.countIfNot, .min = 2, .max = any },
    .{ .name = "REMOVE", .impl = seqfns.remove, .min = 2, .max = any },
    .{ .name = "REMOVE-IF", .impl = seqfns.removeIf, .min = 2, .max = any },
    .{ .name = "REMOVE-IF-NOT", .impl = seqfns.removeIfNot, .min = 2, .max = any },
    .{ .name = "DELETE", .impl = seqfns.remove, .min = 2, .max = any },
    .{ .name = "DELETE-IF", .impl = seqfns.removeIf, .min = 2, .max = any },
    .{ .name = "DELETE-IF-NOT", .impl = seqfns.removeIfNot, .min = 2, .max = any },
    .{ .name = "SORT", .impl = seqfns.sort, .min = 2, .max = any },
    .{ .name = "STABLE-SORT", .impl = seqfns.sort, .min = 2, .max = any },
    .{ .name = "SEARCH", .impl = seqfns.search, .min = 2, .max = any },
    .{ .name = "MISMATCH", .impl = seqfns.mismatch, .min = 2, .max = any },
    .{ .name = "FILL", .impl = seqfns.fill, .min = 2, .max = any },
    .{ .name = "REPLACE", .impl = seqfns.replace, .min = 2, .max = any },
    .{ .name = "SUBSTITUTE", .impl = seqfns.substitute, .min = 3, .max = any },
    .{ .name = "SUBSTITUTE-IF", .impl = seqfns.substituteIf, .min = 3, .max = any },
    .{ .name = "SUBSTITUTE-IF-NOT", .impl = seqfns.substituteIfNot, .min = 3, .max = any },
    .{ .name = "NSUBSTITUTE", .impl = seqfns.nsubstitute, .min = 3, .max = any },
    .{ .name = "NSUBSTITUTE-IF", .impl = seqfns.nsubstituteIf, .min = 3, .max = any },
    .{ .name = "NSUBSTITUTE-IF-NOT", .impl = seqfns.nsubstituteIfNot, .min = 3, .max = any },
    .{ .name = "REMOVE-DUPLICATES", .impl = seqfns.removeDuplicates, .min = 1, .max = any },
    .{ .name = "DELETE-DUPLICATES", .impl = seqfns.removeDuplicates, .min = 1, .max = any },
    .{ .name = "ELT", .impl = seqfns.elt, .min = 2, .max = 2 },
    .{ .name = "SUBSEQ", .impl = seqfns.subseq, .min = 2, .max = 3 },
    .{ .name = "CONCATENATE", .impl = seqfns.concatenate, .min = 1, .max = any },
    .{ .name = "MAKE-SEQUENCE", .impl = seqfns.makeSequence, .min = 2, .max = any },
    .{ .name = "COERCE", .impl = seqfns.coerce, .min = 2, .max = 2 },
    .{ .name = "MAP", .impl = seqfns.map, .min = 3, .max = any },
    .{ .name = "MAP-INTO", .impl = seqfns.mapInto, .min = 2, .max = any },
    .{ .name = "SOME", .impl = seqfns.some, .min = 2, .max = any },
    .{ .name = "EVERY", .impl = seqfns.every, .min = 2, .max = any },
    .{ .name = "NOTANY", .impl = seqfns.notany, .min = 2, .max = any },
    .{ .name = "NOTEVERY", .impl = seqfns.notevery, .min = 2, .max = any },
    .{ .name = "MAKE-LIST", .impl = seqfns.makeList, .min = 1, .max = any },
    .{ .name = "LIST-LENGTH", .impl = seqfns.listLength_, .min = 1, .max = 1 },
    .{ .name = "VECTOR-POP", .impl = seqfns.vectorPop, .min = 1, .max = 1 },
    .{ .name = "ARRAY-IN-BOUNDS-P", .impl = arrays.arrayInBoundsP, .min = 1, .max = any },
    // パッケージ（Phase 22。packages.zig）
    .{ .name = "PACKAGEP", .impl = packages.packagep, .min = 1, .max = 1 },
    .{ .name = "FIND-PACKAGE", .impl = packages.findPackage, .min = 1, .max = 1 },
    .{ .name = "PACKAGE-NAME", .impl = packages.packageName, .min = 1, .max = 1 },
    .{ .name = "PACKAGE-NICKNAMES", .impl = packages.packageNicknames, .min = 1, .max = 1 },
    .{ .name = "PACKAGE-USE-LIST", .impl = packages.packageUseList, .min = 1, .max = 1 },
    .{ .name = "PACKAGE-USED-BY-LIST", .impl = packages.packageUsedByList, .min = 1, .max = 1 },
    .{ .name = "PACKAGE-SHADOWING-SYMBOLS", .impl = packages.packageShadowingSymbols, .min = 1, .max = 1 },
    .{ .name = "LIST-ALL-PACKAGES", .impl = packages.listAllPackages, .min = 0, .max = 0 },
    .{ .name = "MAKE-PACKAGE", .impl = packages.makePackage, .min = 1, .max = any },
    .{ .name = "RENAME-PACKAGE", .impl = packages.renamePackage, .min = 2, .max = 3 },
    .{ .name = "DELETE-PACKAGE", .impl = packages.deletePackage, .min = 1, .max = 1 },
    .{ .name = "FIND-SYMBOL", .impl = packages.findSymbol, .min = 1, .max = 2 },
    .{ .name = "INTERN", .impl = packages.intern, .min = 1, .max = 2 },
    .{ .name = "UNINTERN", .impl = packages.unintern, .min = 1, .max = 2 },
    .{ .name = "EXPORT", .impl = packages.exportSymbols, .min = 1, .max = 2 },
    .{ .name = "UNEXPORT", .impl = packages.unexportSymbols, .min = 1, .max = 2 },
    .{ .name = "IMPORT", .impl = packages.importSymbols, .min = 1, .max = 2 },
    .{ .name = "SHADOWING-IMPORT", .impl = packages.shadowingImport, .min = 1, .max = 2 },
    .{ .name = "SHADOW", .impl = packages.shadow, .min = 1, .max = 2 },
    .{ .name = "USE-PACKAGE", .impl = packages.usePackage, .min = 1, .max = 2 },
    .{ .name = "UNUSE-PACKAGE", .impl = packages.unusePackage, .min = 1, .max = 2 },
    .{ .name = "FIND-ALL-SYMBOLS", .impl = packages.findAllSymbols, .min = 1, .max = 1 },
    .{ .name = "SYMBOL-PACKAGE", .impl = packages.symbolPackage, .min = 1, .max = 1 },
    .{ .name = "KEYWORDP", .impl = packages.keywordp, .min = 1, .max = 1 },
    .{ .name = "MAKE-SYMBOL", .impl = packages.makeSymbol, .min = 1, .max = 1 },
    .{ .name = "LOAD", .impl = load_mod.load, .min = 1, .max = any },
    // ストリーム（Phase 23。streams.zig）
    .{ .name = "PPRINT", .impl = pprint_mod.pprint, .min = 1, .max = 2 },
    // pretty printer（Phase 24）
    .{ .name = "PPRINT-NEWLINE", .impl = pprint_mod.pprintNewline, .min = 1, .max = 2 },
    .{ .name = "PPRINT-INDENT", .impl = pprint_mod.pprintIndent, .min = 2, .max = 3 },
    .{ .name = "PPRINT-TAB", .impl = pprint_mod.pprintTab, .min = 3, .max = 4 },
    .{ .name = "PPRINT-FILL", .impl = pprint_mod.pprintFill, .min = 2, .max = 4 },
    .{ .name = "PPRINT-LINEAR", .impl = pprint_mod.pprintLinear, .min = 2, .max = 4 },
    .{ .name = "PPRINT-TABULAR", .impl = pprint_mod.pprintTabular, .min = 2, .max = 5 },
    .{ .name = "PPRINT-DISPATCH", .impl = pprint_mod.pprintDispatch, .min = 1, .max = 2 },
    .{ .name = "SET-PPRINT-DISPATCH", .impl = pprint_mod.setPprintDispatch, .min = 2, .max = 4 },
    .{ .name = "COPY-PPRINT-DISPATCH", .impl = pprint_mod.copyPprintDispatch, .min = 0, .max = 1 },
    .{ .name = "WRITE", .impl = streams.write, .min = 1, .max = any },
    .{ .name = "FRESH-LINE", .impl = streams.freshLine, .min = 0, .max = 1 },
    .{ .name = "WRITE-CHAR", .impl = streams.writeChar, .min = 1, .max = 2 },
    .{ .name = "WRITE-STRING", .impl = streams.writeString, .min = 1, .max = any },
    .{ .name = "WRITE-LINE", .impl = streams.writeLine, .min = 1, .max = any },
    .{ .name = "FINISH-OUTPUT", .impl = streams.finishOutput, .min = 0, .max = 1 },
    .{ .name = "FORCE-OUTPUT", .impl = streams.finishOutput, .min = 0, .max = 1 },
    .{ .name = "CLEAR-OUTPUT", .impl = streams.clearOutput, .min = 0, .max = 1 },
    .{ .name = "PRIN1-TO-STRING", .impl = streams.prin1ToString, .min = 1, .max = 1 },
    .{ .name = "PRINC-TO-STRING", .impl = streams.princToString, .min = 1, .max = 1 },
    .{ .name = "WRITE-TO-STRING", .impl = streams.writeToString, .min = 1, .max = any },
    .{ .name = "READ-CHAR", .impl = streams.readChar, .min = 0, .max = 4 },
    .{ .name = "READ-CHAR-NO-HANG", .impl = streams.readCharNoHang, .min = 0, .max = 4 },
    .{ .name = "UNREAD-CHAR", .impl = streams.unreadChar, .min = 1, .max = 2 },
    .{ .name = "PEEK-CHAR", .impl = streams.peekChar, .min = 0, .max = 5 },
    .{ .name = "READ-LINE", .impl = streams.readLine, .min = 0, .max = 4 },
    .{ .name = "LISTEN", .impl = streams.listen, .min = 0, .max = 1 },
    .{ .name = "CLEAR-INPUT", .impl = streams.clearInput, .min = 0, .max = 1 },
    .{ .name = "READ-BYTE", .impl = streams.readByte, .min = 1, .max = 3 },
    .{ .name = "WRITE-BYTE", .impl = streams.writeByte, .min = 2, .max = 2 },
    .{ .name = "READ-SEQUENCE", .impl = streams.readSequence, .min = 2, .max = any },
    .{ .name = "WRITE-SEQUENCE", .impl = streams.writeSequence, .min = 2, .max = any },
    .{ .name = "READ", .impl = streams.read, .min = 0, .max = 4 },
    .{ .name = "READ-PRESERVING-WHITESPACE", .impl = streams.readPreservingWhitespace, .min = 0, .max = 4 },
    .{ .name = "READ-DELIMITED-LIST", .impl = streams.readDelimitedList, .min = 1, .max = 3 },
    // readtable（Phase 24）
    .{ .name = "READTABLEP", .impl = readtable_mod.readtablep, .min = 1, .max = 1 },
    .{ .name = "COPY-READTABLE", .impl = readtable_mod.copyReadtable, .min = 0, .max = 2 },
    .{ .name = "SET-MACRO-CHARACTER", .impl = readtable_mod.setMacroCharacter, .min = 2, .max = 4 },
    .{ .name = "GET-MACRO-CHARACTER", .impl = readtable_mod.getMacroCharacter, .min = 1, .max = 2 },
    .{ .name = "MAKE-DISPATCH-MACRO-CHARACTER", .impl = readtable_mod.makeDispatchMacroCharacter, .min = 1, .max = 3 },
    .{ .name = "SET-DISPATCH-MACRO-CHARACTER", .impl = readtable_mod.setDispatchMacroCharacter, .min = 3, .max = 4 },
    .{ .name = "GET-DISPATCH-MACRO-CHARACTER", .impl = readtable_mod.getDispatchMacroCharacter, .min = 2, .max = 3 },
    .{ .name = "SET-SYNTAX-FROM-CHAR", .impl = readtable_mod.setSyntaxFromChar, .min = 2, .max = 4 },
    .{ .name = "READTABLE-CASE", .impl = readtable_mod.readtableCase, .min = 1, .max = 1 },
    .{ .name = "READ-FROM-STRING", .impl = streams.readFromString, .min = 1, .max = any },
    .{ .name = "MAKE-STRING-INPUT-STREAM", .impl = streams.makeStringInputStream, .min = 1, .max = 3 },
    .{ .name = "MAKE-STRING-OUTPUT-STREAM", .impl = streams.makeStringOutputStream, .min = 0, .max = any },
    .{ .name = "GET-OUTPUT-STREAM-STRING", .impl = streams.getOutputStreamString, .min = 1, .max = 1 },
    .{ .name = "MAKE-BROADCAST-STREAM", .impl = streams.makeBroadcastStream, .min = 0, .max = any },
    .{ .name = "MAKE-TWO-WAY-STREAM", .impl = streams.makeTwoWayStream, .min = 2, .max = 2 },
    .{ .name = "MAKE-SYNONYM-STREAM", .impl = streams.makeSynonymStream, .min = 1, .max = 1 },
    .{ .name = "TWO-WAY-STREAM-INPUT-STREAM", .impl = streams.twoWayStreamInputStream, .min = 1, .max = 1 },
    .{ .name = "TWO-WAY-STREAM-OUTPUT-STREAM", .impl = streams.twoWayStreamOutputStream, .min = 1, .max = 1 },
    .{ .name = "SYNONYM-STREAM-SYMBOL", .impl = streams.synonymStreamSymbol, .min = 1, .max = 1 },
    .{ .name = "BROADCAST-STREAM-STREAMS", .impl = streams.broadcastStreamStreams, .min = 1, .max = 1 },
    .{ .name = "STREAMP", .impl = streams.streamp, .min = 1, .max = 1 },
    .{ .name = "INPUT-STREAM-P", .impl = streams.inputStreamP, .min = 1, .max = 1 },
    .{ .name = "OUTPUT-STREAM-P", .impl = streams.outputStreamP, .min = 1, .max = 1 },
    .{ .name = "OPEN-STREAM-P", .impl = streams.openStreamP, .min = 1, .max = 1 },
    .{ .name = "INTERACTIVE-STREAM-P", .impl = streams.interactiveStreamP, .min = 1, .max = 1 },
    .{ .name = "STREAM-ELEMENT-TYPE", .impl = streams.streamElementType, .min = 1, .max = 1 },
    .{ .name = "OPEN", .impl = streams.open, .min = 1, .max = any },
    .{ .name = "CLOSE", .impl = streams.close, .min = 1, .max = any },
    .{ .name = "FILE-LENGTH", .impl = streams.fileLength, .min = 1, .max = 1 },
    .{ .name = "FILE-POSITION", .impl = streams.filePosition, .min = 1, .max = 2 },
    // パス名（Phase 23。pathnames.zig）
    .{ .name = "PATHNAME", .impl = pathnames.pathname, .min = 1, .max = 1 },
    .{ .name = "PATHNAMEP", .impl = pathnames.pathnamep, .min = 1, .max = 1 },
    .{ .name = "PATHNAME-HOST", .impl = pathnames.pathnameHost, .min = 1, .max = any },
    .{ .name = "PATHNAME-DEVICE", .impl = pathnames.pathnameDevice, .min = 1, .max = any },
    .{ .name = "PATHNAME-DIRECTORY", .impl = pathnames.pathnameDirectory, .min = 1, .max = any },
    .{ .name = "PATHNAME-NAME", .impl = pathnames.pathnameName, .min = 1, .max = any },
    .{ .name = "PATHNAME-TYPE", .impl = pathnames.pathnameType, .min = 1, .max = any },
    .{ .name = "PATHNAME-VERSION", .impl = pathnames.pathnameVersion, .min = 1, .max = 1 },
    .{ .name = "NAMESTRING", .impl = pathnames.namestring, .min = 1, .max = 1 },
    .{ .name = "FILE-NAMESTRING", .impl = pathnames.fileNamestring, .min = 1, .max = 1 },
    .{ .name = "DIRECTORY-NAMESTRING", .impl = pathnames.directoryNamestring, .min = 1, .max = 1 },
    .{ .name = "HOST-NAMESTRING", .impl = pathnames.hostNamestring, .min = 1, .max = 1 },
    .{ .name = "ENOUGH-NAMESTRING", .impl = pathnames.enoughNamestring, .min = 1, .max = 2 },
    .{ .name = "PARSE-NAMESTRING", .impl = pathnames.parseNamestring, .min = 1, .max = any },
    .{ .name = "MERGE-PATHNAMES", .impl = pathnames.mergePathnames, .min = 1, .max = 3 },
    .{ .name = "MAKE-PATHNAME", .impl = pathnames.makePathname, .min = 0, .max = any },
    .{ .name = "WILD-PATHNAME-P", .impl = pathnames.wildPathnameP, .min = 1, .max = 2 },
    .{ .name = "PATHNAME-MATCH-P", .impl = pathnames.pathnameMatchP, .min = 2, .max = 2 },
    .{ .name = "PROBE-FILE", .impl = pathnames.probeFile, .min = 1, .max = 1 },
    .{ .name = "TRUENAME", .impl = pathnames.truename, .min = 1, .max = 1 },
    .{ .name = "FILE-WRITE-DATE", .impl = pathnames.fileWriteDate, .min = 1, .max = 1 },
    .{ .name = "DELETE-FILE", .impl = pathnames.deleteFile, .min = 1, .max = 1 },
    .{ .name = "RENAME-FILE", .impl = pathnames.renameFile, .min = 2, .max = 2 },
    .{ .name = "ENSURE-DIRECTORIES-EXIST", .impl = pathnames.ensureDirectoriesExist, .min = 1, .max = any },
    .{ .name = "DIRECTORY", .impl = pathnames.directoryList, .min = 1, .max = any },
    // 多値（Phase 17）
    .{ .name = "VALUES", .impl = functions.values, .min = 0, .max = any },
    .{ .name = "VALUES-LIST", .impl = functions.valuesList, .min = 1, .max = 1 },
    // 型と condition（Phase 25。types.zig・conditions.zig）
    .{ .name = "TYPEP", .impl = types.typepFn, .min = 2, .max = 3 },
    .{ .name = "EVAL", .impl = load_mod.evalFn, .min = 1, .max = 1 },
    // 時刻（time.zig。decode-universal-time などは boot.lisp）
    // 構造体（Phase 26。structures.zig。defstruct は boot.lisp）
    .{ .name = "COPY-STRUCTURE", .impl = structures.copyStructure, .min = 1, .max = 1 },
    .{ .name = "GET-UNIVERSAL-TIME", .impl = time_mod.getUniversalTime, .min = 0, .max = 0 },
};

/// ZILISP-SYSTEM パッケージのプリミティブ（コンパイラが展開先として使う内部の関数）
pub const sys_table = [_]Entry{
    .{ .name = "%DEFUN", .impl = functions.sysDefun, .min = 2, .max = 2 },
    .{ .name = "%PROCLAIM-SPECIAL", .impl = functions.sysProclaimSpecial, .min = 1, .max = 1 },
    .{ .name = "%DEFMACRO", .impl = macros.sysDefmacro, .min = 2, .max = 3 },
    .{ .name = "%DBIND-ERROR", .impl = macros.sysDbindError, .min = 2, .max = 2 },
    .{ .name = "%GETF-KEY", .impl = macros.sysGetfKey, .min = 2, .max = 2 },
    .{ .name = "%CHECK-KEYS", .impl = macros.sysCheckKeys, .min = 4, .max = 4 },
    .{ .name = "%MACRO-FORM-ERROR", .impl = macros.sysMacroFormError, .min = 2, .max = 2 },
    .{ .name = "%MACRO-SIMPLE-ERROR", .impl = macros.sysMacroSimpleError, .min = 2, .max = 2 },
    .{ .name = "%UNIMPLEMENTED-ERROR", .impl = macros.sysUnimplementedError, .min = 2, .max = 2 },
    // setf の展開先（値を返す）
    .{ .name = "%SET-CAR", .impl = lists.sysSetCar, .min = 2, .max = 2 },
    .{ .name = "%SET-CDR", .impl = lists.sysSetCdr, .min = 2, .max = 2 },
    .{ .name = "%PUTF", .impl = lists.sysPutf, .min = 3, .max = 3 },
    .{ .name = "%PUT", .impl = functions.sysPut, .min = 3, .max = 4 },
    .{ .name = "%PUTHASH", .impl = hashtables.sysPuthash, .min = 3, .max = 4 },
    .{ .name = "%ASET", .impl = arrays.sysAset, .min = 2, .max = any },
    .{ .name = "%SVSET", .impl = arrays.sysSvset, .min = 3, .max = 3 },
    .{ .name = "%SET-CHAR", .impl = arrays.sysSetChar, .min = 3, .max = 3 },
    .{ .name = "%SET-ROW-MAJOR-AREF", .impl = arrays.sysSetRowMajorAref, .min = 3, .max = 3 },
    .{ .name = "%SET-FILL-POINTER", .impl = arrays.sysSetFillPointer, .min = 2, .max = 2 },
    .{ .name = "%SET-ELT", .impl = seqfns.sysSetElt, .min = 3, .max = 3 },
    .{ .name = "%SET-FDEFINITION", .impl = functions.sysSetFdefinition, .min = 2, .max = 2 },
    .{ .name = "%HASH-PAIRS", .impl = hashtables.sysHashPairs, .min = 1, .max = 1 },
    // パッケージ（Phase 22。boot.lisp の in-package・defpackage・do-symbols が使う）
    .{ .name = "%FIND-PACKAGE-OR-LOSE", .impl = packages.sysFindPackageOrLose, .min = 1, .max = 1 },
    .{ .name = "%TYPE-ERROR", .impl = packages.sysTypeError, .min = 2, .max = 2 },
    .{ .name = "%PACKAGE-SYMBOLS", .impl = packages.sysPackageSymbols, .min = 2, .max = 2 },
    .{ .name = "%ALL-PACKAGE-SYMBOLS", .impl = packages.sysAllPackageSymbols, .min = 0, .max = 0 },
    .{ .name = "%DEFPACKAGE", .impl = packages.sysDefpackage, .min = 10, .max = 10 },
    .{ .name = "%FORMAT-REST", .impl = format_mod.formatRest, .min = 3, .max = 3 },
    .{ .name = "%SET-READTABLE-CASE", .impl = readtable_mod.setReadtableCase, .min = 2, .max = 2 },
    .{ .name = "%PPRINT-LOGICAL-BLOCK", .impl = pprint_mod.sysLogicalBlock, .min = 7, .max = 7 },
    .{ .name = "%PPRINT-LENGTH-CHECK", .impl = pprint_mod.sysLengthCheck, .min = 2, .max = 2 },
    .{ .name = "%PPRINT-LENGTH-CHECK*", .impl = pprint_mod.sysLengthCheckStar, .min = 1, .max = 1 },
    .{ .name = "%OUTPUT-UGLY-OBJECT", .impl = pprint_mod.sysOutputUgly, .min = 2, .max = 2 },
    // condition と restart（Phase 25）
    .{ .name = "%MAKE-RECORD", .impl = conditions.sysMakeRecord, .min = 2, .max = 2 },
    .{ .name = "%MAKE-INSTANCE", .impl = clos.sysMakeInstance, .min = 2, .max = 2 },
    .{ .name = "%INSTANCE-P", .impl = clos.sysInstanceP, .min = 1, .max = 1 },
    .{ .name = "%INSTANCE-CLASS", .impl = clos.sysInstanceClass, .min = 1, .max = 1 },
    .{ .name = "%INSTANCE-REF", .impl = clos.sysInstanceRef, .min = 2, .max = 2 },
    .{ .name = "%INSTANCE-SET", .impl = clos.sysInstanceSet, .min = 3, .max = 3 },
    .{ .name = "%MAKE-CLASS", .impl = clos.sysMakeClass, .min = 2, .max = 2 },
    .{ .name = "%CLASS-P", .impl = clos.sysClassP, .min = 1, .max = 1 },
    .{ .name = "%CLASS-DESCRIPTOR", .impl = clos.sysClassDescriptor, .min = 1, .max = 1 },
    .{ .name = "%REFRESH-CLASS", .impl = clos.sysRefreshClass, .min = 2, .max = 2 },
    .{ .name = "%BUILTIN-CLASS-NAME", .impl = clos.sysBuiltinName, .min = 1, .max = 1 },
    .{ .name = "%RECORD-P", .impl = conditions.sysRecordP, .min = 1, .max = 1 },
    .{ .name = "%RECORD-CLASS", .impl = conditions.sysRecordClass, .min = 1, .max = 1 },
    .{ .name = "%RECORD-SLOTS", .impl = conditions.sysRecordSlots, .min = 1, .max = 1 },
    .{ .name = "%OBJECT-ADDRESS", .impl = conditions.sysObjectAddress, .min = 1, .max = 1 },
    .{ .name = "%UNHANDLED-CONDITION", .impl = conditions.sysUnhandledCondition, .min = 3, .max = 3 },
    // 構造体（Phase 26）
    .{ .name = "%MAKE-STRUCTURE", .impl = structures.sysMakeStructure, .min = 1, .max = any },
    .{ .name = "%STRUCTURE-REF", .impl = structures.sysStructureRef, .min = 3, .max = 3 },
    .{ .name = "%STRUCTURE-SET", .impl = structures.sysStructureSet, .min = 4, .max = 4 },
    .{ .name = "%STRUCTURE-P", .impl = structures.sysStructureP, .min = 1, .max = 2 },
    .{ .name = "%STRUCTURE-CLASS-OF", .impl = structures.sysStructureClass, .min = 1, .max = 1 },
    .{ .name = "%CHECK-SLOT-TYPE", .impl = structures.sysCheckSlotType, .min = 2, .max = 2 },
    .{ .name = "%PRINT-DEPTH", .impl = structures.sysPrintDepth, .min = 0, .max = 0 },
    .{ .name = "%PRINT-DESCEND", .impl = structures.sysPrintDescend, .min = 1, .max = 1 },
    .{ .name = "%TIMEZONE", .impl = time_mod.sysTimezone, .min = 1, .max = 1 },
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
    // condition（Phase 25）。関数と特殊変数は boot.lisp が定義する
    rt.sys_handler_clusters = try rt.intern(rt.sys, "*HANDLER-CLUSTERS*");
    rt.sys_restart_clusters = try rt.intern(rt.sys, "*RESTART-CLUSTERS*");
    rt.sys_signal_hook = try rt.intern(rt.sys, "%SIGNAL-ZIG-ERROR");
    rt.sys_print_record = try rt.intern(rt.sys, "%PRINT-RECORD");
    rt.sys_read_structure = try rt.intern(rt.sys, "%READ-STRUCTURE");
    rt.sys_check_structure = try rt.intern(rt.sys, "%CHECK-STRUCTURE-SLOTS");
    rt.sys_class_key = try rt.intern(rt.sys, "%CLASS");
    rt.debugger_hook = rt.findSymbol(rt.cl, "*DEBUGGER-HOOK*").?.symbol;
    _ = try rt.intern(rt.sys, "TOO-FEW");
    _ = try rt.intern(rt.sys, "TOO-MANY");
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
    _ = arrays;
    _ = strings;
    _ = seqfns;
    _ = equalp;
}
