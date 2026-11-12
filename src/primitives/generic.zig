//! P28 callable generic functions and method metadata. Dispatch lives in generic.lisp.
const Value = @import("../values/value.zig").Value;
const object = @import("../values/object.zig");
const function = @import("../runtime/function.zig");
const Thread = @import("../runtime/thread.zig").Thread;
const clos = @import("clos.zig");

pub fn isGeneric(v: Value) bool {
    return v.isFunctionPointer() and function.kindOfFunction(v) == .generic_function;
}
pub fn makeGeneric(th: *Thread, args: []const Value) Value {
    if (!clos.isKind(args[1], .simple_vector) or !args[2].isFunctionPointer()) return th.typeError(args[1], th.rt.t);
    const f = th.rt.heap.create(function.GenericFunction, 0) catch return th.outOfMemory();
    f.* = .{ .header = .{ .kind = .generic_function }, .entry = &function.genericEntry, .name = args[0], .descriptor = args[1], .dispatcher = args[2] };
    th.mv_count = 1;
    return Value.fromPointer(f, .function);
}
pub fn genericData(th: *Thread, args: []const Value) Value {
    if (!isGeneric(args[0])) return th.typeError(args[0], (th.rt.findSymbol(th.rt.cl, "GENERIC-FUNCTION") orelse unreachable).symbol);
    th.mv_count = 1;
    return function.genericPtr(args[0]).descriptor;
}
pub fn makeMethod(th: *Thread, args: []const Value) Value {
    if (!clos.isKind(args[0], .simple_vector)) return th.typeError(args[0], th.rt.syms.@"simple-vector");
    const m = th.rt.heap.create(object.Method, 0) catch return th.outOfMemory();
    m.* = .{ .header = .{ .kind = .method }, .descriptor = args[0] };
    th.mv_count = 1;
    return Value.fromPointer(m, .other);
}
pub fn methodData(th: *Thread, args: []const Value) Value {
    if (!clos.isKind(args[0], .method)) return th.typeError(args[0], (th.rt.findSymbol(th.rt.cl, "METHOD") orelse unreachable).symbol);
    th.mv_count = 1;
    return @as(*object.Method, @ptrCast(@alignCast(args[0].pointer()))).descriptor;
}
