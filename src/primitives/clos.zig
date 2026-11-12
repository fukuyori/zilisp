//! P27: managed class objects and instances with replaceable racks.
const Value = @import("../values/value.zig").Value;
const object = @import("../values/object.zig");
const Runtime = @import("../runtime/runtime.zig").Runtime;
const Thread = @import("../runtime/thread.zig").Thread;
const arrays = @import("arrays.zig");

pub fn isKind(v: Value, k: object.ObjKind) bool {
    return v.isOther() and Runtime.kindOf(v) == k;
}
pub fn instance(v: Value) *object.Instance {
    return @ptrCast(@alignCast(v.pointer()));
}
pub fn rack(v: Value) *object.Rack {
    return @ptrCast(@alignCast(v.pointer()));
}
pub fn class(v: Value) *object.Class {
    return @ptrCast(@alignCast(v.pointer()));
}

pub fn makeInstance(th: *Thread, descriptor: Value, slots: Value, record: bool) Value {
    const values = Runtime.vectorPtr(slots).items();
    const extra = if (!record and values.len > 0) (values.len - 1) * @sizeOf(Value) else 0;
    const r = th.rt.heap.create(object.Rack, extra) catch return th.outOfMemory();
    const desc = Runtime.vectorPtr(descriptor).items();
    const stamp: u64 = if (desc.len > 8 and desc[8].isFixnum()) @intCast(desc[8].asFixnum()) else 0;
    r.* = .{ .header = .{ .kind = .rack, .flags = if (record) 1 else 0, .len = @intCast(values.len) }, .stamp = stamp, .layout = descriptor, .slots = if (record) slots else Value.nil };
    if (!record) @memcpy(r.values(), values);
    const rv = Value.fromPointer(r, .other);
    const root = th.rt.roots.register(rv) catch return th.outOfMemory();
    defer _ = th.rt.roots.unregister(root);
    const i = th.rt.heap.create(object.Instance, 0) catch return th.outOfMemory();
    i.* = .{ .header = .{ .kind = .instance, .flags = if (record) 1 else 0 }, .class = descriptor, .rack = rv };
    th.mv_count = 1;
    return Value.fromPointer(i, .other);
}
pub fn sysMakeInstance(th: *Thread, args: []const Value) Value {
    if (!isKind(args[0], .simple_vector) or !isKind(args[1], .simple_vector)) return th.typeError(args[0], th.rt.syms.@"simple-vector");
    if (Runtime.vectorPtr(args[0]).items().len < 2) return th.typeError(args[0], th.rt.syms.@"simple-vector");
    return makeInstance(th, args[0], args[1], false);
}
pub fn sysInstanceP(th: *Thread, args: []const Value) Value {
    th.mv_count = 1;
    return th.rt.boolean(isKind(args[0], .instance));
}
pub fn sysInstanceClass(th: *Thread, args: []const Value) Value {
    if (!isKind(args[0], .instance)) return th.typeError(args[0], th.rt.t);
    th.mv_count = 1;
    return instance(args[0]).class;
}
fn slotValues(th: *Thread, value: Value, index: Value) ?[]Value {
    if (!isKind(value, .instance)) {
        _ = th.typeError(value, th.rt.t);
        return null;
    }
    const r = rack(instance(value).rack);
    const values = if (r.header.flags & 1 != 0) Runtime.vectorPtr(r.slots).items() else r.values();
    if (!index.isFixnum() or index.asFixnum() < 0 or @as(u64, @intCast(index.asFixnum())) >= values.len) {
        _ = th.typeError(index, (th.rt.findSymbol(th.rt.cl, "UNSIGNED-BYTE") orelse unreachable).symbol);
        return null;
    }
    return values;
}
pub fn sysInstanceRef(th: *Thread, args: []const Value) Value {
    const values = slotValues(th, args[0], args[1]) orelse return Value.unwind;
    th.mv_count = 1;
    return values[@intCast(args[1].asFixnum())];
}
pub fn sysInstanceSet(th: *Thread, args: []const Value) Value {
    const values = slotValues(th, args[0], args[1]) orelse return Value.unwind;
    values[@intCast(args[1].asFixnum())] = args[2];
    th.mv_count = 1;
    return args[2];
}
pub fn sysMakeClass(th: *Thread, args: []const Value) Value {
    if (!isKind(args[0], .simple_vector) or !args[1].isFixnum()) return th.typeError(args[0], th.rt.syms.@"simple-vector");
    if (Runtime.vectorPtr(args[0]).items().len < 2 or args[1].asFixnum() < 0 or args[1].asFixnum() > 3)
        return th.typeError(args[0], th.rt.syms.@"simple-vector");
    const c = th.rt.heap.create(object.Class, 0) catch return th.outOfMemory();
    c.* = .{ .header = .{ .kind = .class, .aux = @intCast(args[1].asFixnum()) }, .descriptor = args[0] };
    th.mv_count = 1;
    return Value.fromPointer(c, .other);
}
pub fn sysClassP(th: *Thread, args: []const Value) Value {
    th.mv_count = 1;
    return th.rt.boolean(isKind(args[0], .class));
}
pub fn sysClassDescriptor(th: *Thread, args: []const Value) Value {
    if (!isKind(args[0], .class)) return th.typeError(args[0], (th.rt.findSymbol(th.rt.cl, "CLASS") orelse unreachable).symbol);
    th.mv_count = 1;
    return class(args[0]).descriptor;
}
pub fn sysRefreshClass(th: *Thread, args: []const Value) Value {
    if (!isKind(args[0], .class) or !isKind(args[1], .simple_vector) or Runtime.vectorPtr(args[1]).items().len < 2)
        return th.typeError(args[0], (th.rt.findSymbol(th.rt.cl, "CLASS") orelse unreachable).symbol);
    class(args[0]).descriptor = args[1];
    th.mv_count = 1;
    return args[0];
}
pub fn sysBuiltinName(th: *Thread, args: []const Value) Value {
    const v = args[0];
    const name: []const u8 = if (v == Value.nil) "NULL" else if (v.isFixnum()) "FIXNUM" else if (v.isCons()) "CONS" else if (v.isChar()) "CHARACTER" else if (v.isSingleFloat()) "SINGLE-FLOAT" else if (v.isFunctionPointer()) "FUNCTION" else switch (Runtime.kindOf(v) orelse return th.typeError(v, th.rt.t)) {
        .symbol => "SYMBOL",
        .string => "SIMPLE-STRING",
        .simple_vector => "SIMPLE-VECTOR",
        .double_float => "DOUBLE-FLOAT",
        .bignum => "BIGNUM",
        .ratio => "RATIO",
        .array => if (arrays.isStringLike(v)) "STRING" else if (arrays.vectorView(v) != null) "VECTOR" else "ARRAY",
        .hash_table => "HASH-TABLE",
        .package => "PACKAGE",
        .stream => "STREAM",
        .pathname => "PATHNAME",
        .readtable => "READTABLE",
        .class => switch (class(v).header.aux) {
            1 => "BUILT-IN-CLASS",
            2 => "STRUCTURE-CLASS",
            3 => "CONDITION-CLASS",
            else => "STANDARD-CLASS",
        },
        else => "T",
    };
    th.mv_count = 1;
    return (th.rt.findSymbol(th.rt.cl, name) orelse (th.rt.findSymbol(th.rt.sys, name) orelse unreachable)).symbol;
}
