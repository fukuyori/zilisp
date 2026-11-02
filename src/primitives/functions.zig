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
    th.line_start = false;
    return args[0];
}

/// print：改行、prin1、空白（CLHS print）
pub fn print(th: *Thread, args: []const Value) Value {
    th.out.writeByte('\n') catch return writeFailed(th);
    printer.prin1(th.rt, th.out, args[0]) catch return writeFailed(th);
    th.out.writeByte(' ') catch return writeFailed(th);
    th.line_start = false;
    return args[0];
}

pub fn terpri(th: *Thread, args: []const Value) Value {
    _ = args;
    th.out.writeByte('\n') catch return writeFailed(th);
    th.line_start = true;
    return Value.nil;
}

/// (princ x)（Phase 19）
pub fn princ(th: *Thread, args: []const Value) Value {
    var buf: std.Io.Writer.Allocating = .init(th.rt.gpa);
    defer buf.deinit();
    printer.princ(th.rt, &buf.writer, args[0]) catch return writeFailed(th);
    const text = buf.written();
    th.out.writeAll(text) catch return writeFailed(th);
    if (text.len > 0) th.line_start = text[text.len - 1] == '\n';
    return args[0];
}

fn isString(v: Value) bool {
    return v.isOther() and Runtime.kindOf(v) == .string;
}

/// (format 出力先 制御文字列 引数...)（Phase 19 の最小版。全体は Phase 24）。
/// 出力先は T（標準出力）と NIL（文字列を返す）。指示子は ~A ~S ~D ~% ~& ~~ と、~ に続く改行（後ろの空白を読み飛ばす）。
/// それ以外の指示子・引数（~5D、~:A など）は明示的なエラーにする（基本設計 §3.1：黙って別の値を返さない）
pub fn format(th: *Thread, args: []const Value) Value {
    const dest = args[0];
    const control = args[1];
    if (!isString(control)) return th.typeError(control, (th.rt.findSymbol(th.rt.cl, "STRING") orelse unreachable).symbol);
    if (dest != Value.nil and dest != th.rt.t)
        return th.signal(.unimplemented, "FORMAT の出力先に T・NIL 以外を使うのは未実装です（ストリームは Phase 23 で実装予定）", dest, Value.unbound);
    var buf: std.Io.Writer.Allocating = .init(th.rt.gpa);
    defer buf.deinit();
    const w = &buf.writer;
    // 行の先頭にいるか（~& のため）。T なら標準出力の今の状態、NIL なら新しい文字列の先頭
    var at_line_start = if (dest == th.rt.t) th.line_start else true;
    const s = Runtime.stringPtr(control);
    const n = s.length();
    var next_arg: usize = 2;
    var i: usize = 0;
    while (i < n) : (i += 1) {
        const cp = s.charAt(i);
        if (cp != '~') {
            writeCp(w, cp) catch return writeFailed(th);
            at_line_start = cp == '\n';
            continue;
        }
        i += 1;
        if (i >= n) return th.signal(.simple_error, "FORMAT の制御文字列が ~ で終わっています", control, Value.unbound);
        const d = s.charAt(i);
        switch (d) {
            'a', 'A', 's', 'S', 'd', 'D' => {
                if (next_arg >= args.len) return th.signal(.simple_error, "FORMAT の引数が足りません", control, Value.unbound);
                const x = args[next_arg];
                next_arg += 1;
                const start = buf.written().len;
                // ~D は整数なら10進で書き、整数でなければ ~A と同じ（CLHS 22.3.2.2）
                const escape = (d == 's' or d == 'S') or ((d == 'd' or d == 'D') and x.isFixnum());
                printer.write(th.rt, w, x, escape) catch return writeFailed(th);
                const out = buf.written();
                if (out.len > start) at_line_start = out[out.len - 1] == '\n';
            },
            '%' => {
                w.writeByte('\n') catch return writeFailed(th);
                at_line_start = true;
            },
            '&' => {
                if (!at_line_start) w.writeByte('\n') catch return writeFailed(th);
                at_line_start = true;
            },
            '~' => {
                w.writeByte('~') catch return writeFailed(th);
                at_line_start = false;
            },
            '\n' => {
                // ~ と改行：改行と、続く空白を読み飛ばす（CLHS 22.3.9.3）
                while (i + 1 < n and (s.charAt(i + 1) == ' ' or s.charAt(i + 1) == '\t')) i += 1;
            },
            else => {
                var spec: [8]u8 = undefined;
                spec[0] = '~';
                const len = 1 + (std.unicode.utf8Encode(d, spec[1..]) catch 0);
                const name = th.rt.makeString(spec[0..len]) catch return th.outOfMemory();
                return th.signal(.unimplemented, "この FORMAT の指示子（または引数・修飾子の付いた指示子）は未実装です（Phase 24 で実装予定）", name, Value.unbound);
            },
        }
    }
    if (dest == Value.nil) return th.rt.makeString(buf.written()) catch th.outOfMemory();
    th.out.writeAll(buf.written()) catch return writeFailed(th);
    th.line_start = at_line_start;
    return Value.nil;
}

fn writeCp(w: *std.Io.Writer, cp: u21) std.Io.Writer.Error!void {
    var b: [4]u8 = undefined;
    const len = std.unicode.utf8Encode(cp, &b) catch return w.writeByte('?');
    try w.writeAll(b[0..len]);
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
    if (s.package == th.rt.cl.obj and !th.rt.booting)
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

/// ZILISP-SYSTEM::%PROCLAIM-SPECIAL 名前：名前を特殊変数と宣言する（defvar・defparameter を実行した時点）
pub fn sysProclaimSpecial(th: *Thread, args: []const Value) Value {
    if (checkAssignable(th, args[0])) |e| return e;
    th.rt.symbolPtr(args[0]).header.flags |= @import("../values/object.zig").SymbolFlags.special;
    return args[0];
}

// ---------------------------------------------------------------------------
// シンボルの属性リストと関数（Phase 16）

/// get シンボル 指示子 [既定値]
pub fn get(th: *Thread, args: []const Value) Value {
    if (!isSymbol(args[0])) return th.typeError(args[0], th.rt.syms.symbol);
    const lists = @import("lists.zig");
    var a = [_]Value{ th.rt.symbolPtr(args[0]).plist, args[1], if (args.len > 2) args[2] else Value.nil };
    return lists.getf(th, &a);
}

/// ZILISP-SYSTEM::%PUT シンボル 指示子 [既定値] 値：(setf (get ...) 値) の展開先。値を返す
pub fn sysPut(th: *Thread, args: []const Value) Value {
    if (!isSymbol(args[0])) return th.typeError(args[0], th.rt.syms.symbol);
    const lists = @import("lists.zig");
    const s = th.rt.symbolPtr(args[0]);
    const v = args[args.len - 1];
    var a = [_]Value{ s.plist, args[1], v };
    const p = lists.sysPutf(th, &a);
    if (p == Value.unwind) return p;
    th.rt.symbolPtr(args[0]).plist = p;
    return v;
}

pub fn symbolPlist(th: *Thread, args: []const Value) Value {
    if (!isSymbol(args[0])) return th.typeError(args[0], th.rt.syms.symbol);
    return th.rt.symbolPtr(args[0]).plist;
}

/// 関数の名前（シンボル、または (setf シンボル)）の、関数を置く欄
fn functionCell(th: *Thread, name: Value) ?*Value {
    if (isSymbol(name) and name != Value.nil) return &th.rt.symbolPtr(name).function;
    if (name.isCons()) {
        const c = @import("../runtime/runtime.zig").Runtime.consPtr(name);
        const setf_sym = (th.rt.findSymbol(th.rt.cl, "SETF") orelse unreachable).symbol;
        if (c.car == setf_sym and c.cdr.isCons()) {
            const sym = @import("../runtime/runtime.zig").Runtime.consPtr(c.cdr).car;
            if (isSymbol(sym) and sym != Value.nil) {
                if (th.rt.symbolPtr(sym).package == th.rt.cl.obj and !th.rt.booting) {
                    _ = th.signal(.package_error, "COMMON-LISP パッケージのシンボルの関数は定義できません", name, Value.unbound);
                    return null;
                }
                return &th.rt.symbolPtr(sym).setf_function;
            }
        }
    }
    _ = th.signal(.type_error, "関数の名前ではありません", name, Value.unbound);
    return null;
}

/// fdefinition 名前（シンボル、または (setf シンボル)）
pub fn fdefinition(th: *Thread, args: []const Value) Value {
    const cell = functionCell(th, args[0]) orelse return Value.unwind;
    if (cell.* == Value.unbound) return th.signal(.undefined_function, "", args[0], Value.unbound);
    return cell.*;
}

/// ZILISP-SYSTEM::%SET-FDEFINITION 名前 関数：(setf (fdefinition 名前) 関数)・(setf (symbol-function 名前) 関数) の展開先
pub fn sysSetFdefinition(th: *Thread, args: []const Value) Value {
    const name = args[0];
    if (isSymbol(name) and name != Value.nil) {
        const s = th.rt.symbolPtr(name);
        if (s.package == th.rt.cl.obj and !th.rt.booting)
            return th.signal(.package_error, "COMMON-LISP パッケージのシンボルの関数は定義できません", name, Value.unbound);
        // 関数を置くと、マクロではなくなる
        s.header.flags &= ~@import("../values/object.zig").SymbolFlags.macro;
    }
    const cell = functionCell(th, name) orelse return Value.unwind;
    if (!args[1].isFunctionPointer()) return th.typeError(args[1], th.rt.syms.function);
    cell.* = args[1];
    return args[1];
}

// ---------------------------------------------------------------------------
// 多値（Phase 17。§6.3）

/// values：引数を多値にする（関数として呼ばれた場合。(values ...) のフォームはコンパイラが直接の命令にする）
pub fn values(th: *Thread, args: []const Value) Value {
    return @import("../native/rt.zig").values(th, args);
}

/// values-list：リストの要素を多値にする
pub fn valuesList(th: *Thread, args: []const Value) Value {
    var x = args[0];
    while (x.isCons()) : (x = Runtime.consPtr(x).cdr) {}
    if (x != Value.nil) return th.typeError(args[0], th.rt.syms.list);
    return th.listToValues(args[0]);
}
