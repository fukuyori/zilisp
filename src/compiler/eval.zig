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

/// フォームを評価し、主値を返す。エラーなら Value.unwind（理由は th.fault と th.err）。
/// トップレベルの progn・マクロの展開結果・eval-when（:execute）の中のフォームは、1つずつコンパイルして実行する
/// （CLHS 3.2.3.1 のトップレベルのフォームの処理の順序。SBCL 2.6.7 の eval と同じ）。
/// これにより、(progn (defsetf f g) (setf (f x) 1)) の2つ目のフォームは、1つ目を実行した後で展開される
pub fn eval(th: *Thread, form: Value) Value {
    const rt = th.rt;
    const root = rt.roots.register(form) catch return th.outOfMemory();
    defer _ = rt.roots.unregister(root);
    var f = form;
    while (f.isCons()) {
        const head = Runtime.consPtr(f).car;
        if (head == rt.syms.progn) {
            var result = Value.nil;
            var x = Runtime.consPtr(f).cdr;
            while (x.isCons()) : (x = Runtime.consPtr(x).cdr) {
                result = eval(th, Runtime.consPtr(x).car);
                if (result == Value.unwind) return result;
            }
            return result;
        }
        if (head == rt.syms.@"eval-when") {
            const rest = Runtime.consPtr(f).cdr;
            if (!rest.isCons()) break; // 形の誤りは Resolver が報告する
            if (!hasExecute(th, Runtime.consPtr(rest).car)) return Value.nil;
            var result = Value.nil;
            var x = Runtime.consPtr(rest).cdr;
            while (x.isCons()) : (x = Runtime.consPtr(x).cdr) {
                result = eval(th, Runtime.consPtr(x).car);
                if (result == Value.unwind) return result;
            }
            return result;
        }
        // マクロなら展開して、その結果をトップレベルのフォームとして続ける
        if (!(head == Value.nil or (head.isOther() and Runtime.kindOf(head) == .symbol))) break;
        const s = rt.symbolPtr(head);
        const SF = @import("../values/object.zig").SymbolFlags;
        if (!s.hasFlag(SF.macro) or s.function == Value.unbound) break;
        const argv = [_]Value{ f, Value.nil };
        const expansion = th.call(s.function, &argv);
        if (expansion == Value.unwind) return expansion;
        _ = rt.roots.set(root, expansion);
        f = expansion;
    }
    const closure = compile(th, f);
    if (closure == Value.unwind) return closure;
    return vm.run(th, closure, &.{});
}

/// eval-when の状況の並びに :execute（execute・eval）があるか
fn hasExecute(th: *Thread, sits: Value) bool {
    const rt = th.rt;
    const kw = rt.internKeyword("EXECUTE") catch return false;
    var x = sits;
    while (x.isCons()) : (x = Runtime.consPtr(x).cdr) {
        const s = Runtime.consPtr(x).car;
        if (s == kw or s == rt.syms.eval) return true;
    }
    return false;
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

    var r = resolver_mod.Resolver.init(th, arena.allocator(), &pins);
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
