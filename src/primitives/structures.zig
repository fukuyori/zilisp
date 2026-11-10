//! 構造体の Zig の側（詳細設計 §10.5。Phase 26）。
//! 構造体は、クラスの記述と、スロットの値を直接並べた 1 つのオブジェクト（object.Structure）。
//! クラスの記述は Lisp で作る simple-vector で、構造体の名前のシンボルの属性 zl-sys::%class に置く（condition と同じ場所。
//! 位置 0 が名前、位置 1 が自身を含む上位の構造体の名前のリスト）。defstruct の展開・構築子・印字は src/lisp/boot.lisp。
//! ここには、作る・スロットを読む・書く・複製する・型を確かめる基本の操作を置く。

const std = @import("std");
const Value = @import("../values/value.zig").Value;
const object = @import("../values/object.zig");
const Runtime = @import("../runtime/runtime.zig").Runtime;
const Thread = @import("../runtime/thread.zig").Thread;
const types = @import("types.zig");

pub fn isStructure(v: Value) bool {
    return v.isOther() and Runtime.kindOf(v) == .structure;
}

pub fn structPtr(v: Value) *object.Structure {
    return @ptrCast(@alignCast(v.pointer()));
}

/// 構造体のクラスの名前
pub fn className(v: Value) Value {
    return Runtime.vectorPtr(structPtr(v).class).items()[object.record_class_name];
}

/// v が名前 name の構造体か、それを :include した構造体か
fn isA(v: Value, name: Value) bool {
    if (!isStructure(v)) return false;
    const items = Runtime.vectorPtr(structPtr(v).class).items();
    if (items[object.record_class_name] == name) return true;
    var x = items[object.record_class_cpl];
    while (x.isCons()) : (x = Runtime.consPtr(x).cdr) if (Runtime.consPtr(x).car == name) return true;
    return false;
}

/// ZILISP-SYSTEM::%MAKE-STRUCTURE 名前 スロットの値…：構築子の展開先
pub fn sysMakeStructure(th: *Thread, args: []const Value) Value {
    const class = types.classOf(th.rt, args[0]) orelse
        return th.signal(.simple_error, "構造体が定義されていません", args[0], Value.unbound);
    const n = args.len - 1;
    const s = th.rt.heap.create(object.Structure, n * @sizeOf(Value)) catch return th.outOfMemory();
    s.* = .{ .header = .{ .kind = .structure, .len = @intCast(n) }, .class = class };
    @memcpy(s.slots(), args[1..]);
    th.mv_count = 1;
    return Value.fromPointer(s, .other);
}

fn slotIndex(th: *Thread, v: Value, name: Value, index: Value) ?usize {
    if (!isA(v, name)) {
        _ = th.typeError(v, name);
        return null;
    }
    // 同じ名前で定義し直した構造体の古いインスタンスは、スロットの数が違うことがある
    if (!index.isFixnum() or index.asFixnum() < 0 or @as(usize, @intCast(index.asFixnum())) >= structPtr(v).header.len) {
        _ = th.typeError(v, name);
        return null;
    }
    return @intCast(index.asFixnum());
}

/// ZILISP-SYSTEM::%STRUCTURE-REF 構造体 名前 位置：アクセサの展開先（名前の構造体でなければ type-error）
pub fn sysStructureRef(th: *Thread, args: []const Value) Value {
    const i = slotIndex(th, args[0], args[1], args[2]) orelse return Value.unwind;
    th.mv_count = 1;
    return structPtr(args[0]).slots()[i];
}

/// ZILISP-SYSTEM::%STRUCTURE-SET 構造体 名前 位置 値：(setf アクセサ) の展開先。値を返す
pub fn sysStructureSet(th: *Thread, args: []const Value) Value {
    const i = slotIndex(th, args[0], args[1], args[2]) orelse return Value.unwind;
    structPtr(args[0]).slots()[i] = args[3];
    th.mv_count = 1;
    return args[3];
}

/// ZILISP-SYSTEM::%STRUCTURE-P 値 [名前]：構造体か（名前があれば、その構造体か、それを :include した構造体か）
pub fn sysStructureP(th: *Thread, args: []const Value) Value {
    th.mv_count = 1;
    return th.rt.boolean(if (args.len > 1) isA(args[0], args[1]) else isStructure(args[0]));
}

/// ZILISP-SYSTEM::%STRUCTURE-CLASS-OF 構造体：クラスの記述（印字に使う）
pub fn sysStructureClass(th: *Thread, args: []const Value) Value {
    if (!isStructure(args[0])) return th.typeError(args[0], th.rt.syms.@"structure-object");
    th.mv_count = 1;
    return structPtr(args[0]).class;
}

/// ZILISP-SYSTEM::%CHECK-SLOT-TYPE 値 型：スロットの :type の検査。合わなければ type-error、合えば値を返す。
/// typep がまだ判定できない型（types.slotCheckable が偽）は検査しない
pub fn sysCheckSlotType(th: *Thread, args: []const Value) Value {
    th.mv_count = 1;
    if (args[1] == th.rt.t or !types.slotCheckable(th, args[1])) return args[0];
    // reader の #n= の仮の値（car が unbound の cons。value_builder.zig の labelDefine）は検査しない：#1=#S(node :next #1#)。
    // 仮の値を置き換えた後で、reader が zl-sys::%check-structure-slots で確かめる（Codex のレビュー P26 1回目 #1）
    if (args[0].isCons() and Runtime.consPtr(args[0]).car == Value.unbound) return args[0];
    const ok = types.typep(th, args[0], args[1]) catch return Value.unwind;
    th.mv_count = 1;
    return if (ok) args[0] else th.typeError(args[0], args[1]);
}

/// ZILISP-SYSTEM::%PRINT-DEPTH：今の印字の深さ（:print-function の 3 つ目の引数）
pub fn sysPrintDepth(th: *Thread, args: []const Value) Value {
    _ = args;
    th.mv_count = 1;
    return Value.fromFixnum(@intCast(th.pp_level));
}

/// ZILISP-SYSTEM::%PRINT-DESCEND 関数：印字の深さを 1 つ深くして、引数のない関数を呼ぶ（pretty でない印字の中身。
/// SBCL の descend-into）
pub fn sysPrintDescend(th: *Thread, args: []const Value) Value {
    th.pp_level += 1;
    defer th.pp_level -= 1;
    const r = th.call(args[0], &.{});
    if (r != Value.unwind) th.mv_count = 1;
    return r;
}

/// (copy-structure 構造体)：同じクラスで、スロットの値が同じ（eql）新しい構造体
pub fn copyStructure(th: *Thread, args: []const Value) Value {
    if (!isStructure(args[0])) return th.typeError(args[0], th.rt.syms.@"structure-object");
    const n = structPtr(args[0]).header.len;
    const s = th.rt.heap.create(object.Structure, @as(usize, n) * @sizeOf(Value)) catch return th.outOfMemory();
    // 確保で GC が起きても、元の構造体は引数（スタックの上）から届く
    const src = structPtr(args[0]);
    s.* = .{ .header = .{ .kind = .structure, .len = n }, .class = src.class };
    @memcpy(s.slots(), src.slots());
    th.mv_count = 1;
    return Value.fromPointer(s, .other);
}
