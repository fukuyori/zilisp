//! eval：フォームをコンパイルしてから VM で実行する（詳細設計 §5.1：評価器は作らない。D-1）。

const std = @import("std");
const Value = @import("../values/value.zig").Value;
const Runtime = @import("../runtime/runtime.zig").Runtime;
const Thread = @import("../runtime/thread.zig").Thread;
const function = @import("../runtime/function.zig");
const vm = @import("../vm/vm.zig");
const resolver_mod = @import("resolver.zig");
const codegen = @import("codegen.zig");
const verify_ir = @import("verify_ir.zig");
const builtin = @import("builtin");

/// フォームを評価し、主値を返す。エラーなら Value.unwind（理由は th.fault と th.err）
pub fn eval(th: *Thread, form: Value) Value {
    const closure = compile(th, form);
    if (closure == Value.unwind) return closure;
    return vm.run(th, closure, &.{});
}

/// フォームを、引数のない closure にコンパイルする。エラーなら Value.unwind
pub fn compile(th: *Thread, form: Value) Value {
    const rt = th.rt;
    // コンパイルの間、フォームを GC のルートにする（IR が持つ定数はフォームから届く：§5.4）
    const root = rt.roots.register(form) catch return th.outOfMemory();
    defer _ = rt.roots.unregister(root);
    var pins = codegen.Pins.init(rt) catch return th.outOfMemory();
    defer pins.deinit();
    var arena: std.heap.ArenaAllocator = .init(rt.gpa);
    defer arena.deinit();

    var r = resolver_mod.Resolver.init(th, arena.allocator());
    const lambda = r.toplevel(form) catch |err| return switch (err) {
        error.LispError => Value.unwind,
        error.OutOfMemory => th.outOfMemory(),
    };
    if (builtin.mode == .debug or builtin.is_test) {
        verify_ir.verify(lambda) catch |err| std.debug.panic("Resolver が作った IR が正しくありません: {t}", .{err});
    }
    const code = codegen.compileLambda(rt, arena.allocator(), &pins, lambda) catch return th.outOfMemory();
    return function.makeClosure(rt, code, &vm.closureEntry, &.{}) catch th.outOfMemory();
}
