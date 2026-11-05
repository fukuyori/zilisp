//! condition と restart の Zig の側（詳細設計 §9。Phase 25）。
//! condition・restart は record（クラスの記述とスロットのベクタ）として表す。クラスの階層、handler・restart の通知、
//! report などは src/lisp/boot.lisp に Lisp で書く。ここには、record を作る・調べる基本の操作と、handler が受け止めなかった
//! condition をトップレベルへ戻す操作を置く。

const std = @import("std");
const Value = @import("../values/value.zig").Value;
const object = @import("../values/object.zig");
const Runtime = @import("../runtime/runtime.zig").Runtime;
const Thread = @import("../runtime/thread.zig").Thread;

fn isRecord(v: Value) bool {
    return v.isOther() and Runtime.kindOf(v) == .record;
}

fn recordPtr(v: Value) *object.Record {
    return @ptrCast(@alignCast(v.pointer()));
}

fn isSimpleVector(v: Value) bool {
    return v.isOther() and Runtime.kindOf(v) == .simple_vector;
}

/// ZILISP-SYSTEM::%MAKE-RECORD クラスの記述 スロットのベクタ
pub fn sysMakeRecord(th: *Thread, args: []const Value) Value {
    if (!isSimpleVector(args[0]) or Runtime.vectorPtr(args[0]).items().len <= object.record_class_cpl)
        return th.typeError(args[0], th.rt.syms.@"simple-vector");
    if (!isSimpleVector(args[1])) return th.typeError(args[1], th.rt.syms.@"simple-vector");
    const r = th.rt.heap.create(object.Record, 0) catch return th.outOfMemory();
    r.* = .{ .header = .{ .kind = .record }, .class = args[0], .slots = args[1] };
    th.mv_count = 1;
    return Value.fromPointer(r, .other);
}

/// ZILISP-SYSTEM::%RECORD-P 値
pub fn sysRecordP(th: *Thread, args: []const Value) Value {
    th.mv_count = 1;
    return th.rt.boolean(isRecord(args[0]));
}

/// ZILISP-SYSTEM::%RECORD-CLASS record：クラスの記述
pub fn sysRecordClass(th: *Thread, args: []const Value) Value {
    if (!isRecord(args[0])) return th.typeError(args[0], sym(th, "CONDITION"));
    th.mv_count = 1;
    return recordPtr(args[0]).class;
}

/// ZILISP-SYSTEM::%RECORD-SLOTS record：スロットのベクタ
pub fn sysRecordSlots(th: *Thread, args: []const Value) Value {
    if (!isRecord(args[0])) return th.typeError(args[0], sym(th, "CONDITION"));
    th.mv_count = 1;
    return recordPtr(args[0]).slots;
}

/// ZILISP-SYSTEM::%OBJECT-ADDRESS 値：オブジェクトのアドレス（#<… {アドレス}> の印字に使う。即値は 0）
pub fn sysObjectAddress(th: *Thread, args: []const Value) Value {
    const v = args[0];
    th.mv_count = 1;
    if (!(v.isCons() or v.isOther() or v.isFunctionPointer())) return Value.fromFixnum(0);
    const addr: u64 = v.raw() & ~@as(u64, 7);
    return Value.fromFixnum(@intCast(addr));
}

/// ZILISP-SYSTEM::%UNHANDLED-CONDITION condition report restarts：handler が受け止めなかった condition を記録して、
/// トップレベルまで戻る（invoke-debugger の最後。Value.unwind を返す）
pub fn sysUnhandledCondition(th: *Thread, args: []const Value) Value {
    if (!isRecord(args[0])) return th.typeError(args[0], sym(th, "CONDITION"));
    return th.unhandledCondition(args[0], args[1], args[2]);
}

fn sym(th: *Thread, name: []const u8) Value {
    return (th.rt.findSymbol(th.rt.cl, name) orelse unreachable).symbol;
}
