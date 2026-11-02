//! スレッドの状態（詳細設計 §6.1）。1.0 は単一スレッド。
//!
//! Phase 08 の範囲：多値の個数、`fault`、VM、Lisp のエラーの情報。
//! condition・handler・restart（Phase 25）ができるまでは、Lisp のエラーは
//! `fault = .lisp_error` と `err`（種類と値）で表し、トップレベル（REPL・スクリプト）まで戻って報告する。
//! Phase 25 で、`signal` は handler を探して呼ぶ処理に置き換え、最後は toplevel の restart へ脱出する（§6.6・§9）。

const std = @import("std");
const Value = @import("../values/value.zig").Value;
const runtime = @import("runtime.zig");
const Runtime = runtime.Runtime;
const vm_mod = @import("../vm/vm.zig");
const function = @import("function.zig");
const printer = @import("../printer/printer.zig");

/// multiple-values-limit（§6.7）
pub const mv_limit = 1024;
/// call-arguments-limit（§6.7）。CLHS では「引数の個数の上限（この値を含まない）」なので、渡せるのは 65535 個まで
pub const call_arguments_limit = 65536;
/// Zig の関数（funcall・apply など）から関数を呼ぶ入れ子の深さの上限（ネイティブのスタックを溢れさせないため）
pub const max_native_depth = 1000;

/// 戻り値が Value.unwind のときの理由（§6.6）
pub const Fault = enum(u8) {
    none,
    /// 非局所脱出の途中（Phase 18 で使う）
    unwind,
    out_of_memory,
    /// 処理系の内部故障（バグ）
    internal,
    /// Lisp のエラー（Phase 25 で condition に置き換えるまでの暫定）。内容は Thread.err
    lisp_error,
};

/// エラーの種類。名前は CL の condition 型に対応させる（Phase 25 でその型の condition にする）
pub const ErrorKind = enum {
    simple_error,
    type_error,
    unbound_variable,
    undefined_function,
    program_error,
    control_error,
    division_by_zero,
    floating_point_overflow,
    floating_point_invalid_operation,
    storage_condition,
    /// 未実装の機能（CL の型ではない。Zilisp の拡張：基本設計 §3.1「黙って別の値を返さない」）
    unimplemented,

    pub fn typeName(k: ErrorKind) []const u8 {
        return switch (k) {
            .simple_error => "SIMPLE-ERROR",
            .type_error => "TYPE-ERROR",
            .unbound_variable => "UNBOUND-VARIABLE",
            .undefined_function => "UNDEFINED-FUNCTION",
            .program_error => "PROGRAM-ERROR",
            .control_error => "CONTROL-ERROR",
            .division_by_zero => "DIVISION-BY-ZERO",
            .floating_point_overflow => "FLOATING-POINT-OVERFLOW",
            .floating_point_invalid_operation => "FLOATING-POINT-INVALID-OPERATION",
            .storage_condition => "STORAGE-CONDITION",
            .unimplemented => "ZILISP:UNIMPLEMENTED",
        };
    }
};

pub const LispError = struct {
    kind: ErrorKind = .simple_error,
    /// 説明（静的な文字列）
    message: []const u8 = "",
    /// 問題の値（type-error の datum、未束縛の変数名など）。なければ unbound
    datum: Value = Value.unbound,
    /// type-error の期待する型（シンボル）。なければ unbound
    expected: Value = Value.unbound,
};

pub const Thread = struct {
    rt: *Runtime,
    /// 直前に返った値の個数（§6.2）
    mv_count: u32 = 1,
    fault: Fault = .none,
    err: LispError = .{},
    vm: vm_mod.Vm,
    /// *standard-output*（Phase 23 でストリームにする）
    out: *std.Io.Writer,
    /// Zig の関数から関数を呼んでいる入れ子の深さ（Thread.call で数える）
    native_depth: u32 = 0,
    /// 多値レジスタ（mv[0] は使わない。主値は戻り値）
    mv: [mv_limit]Value = @splat(Value.nil),

    pub const Options = struct {
        /// VM の値スタックの要素数（§7.1。既定 1M 要素 = 8 MiB）
        stack_size: usize = 1 << 20,
        /// VM のフレームの数の上限
        frame_count: usize = 1 << 16,
    };

    pub fn create(rt: *Runtime, out: *std.Io.Writer, options: Options) runtime.Error!*Thread {
        const th = try rt.gpa.create(Thread);
        errdefer rt.gpa.destroy(th);
        th.* = .{ .rt = rt, .out = out, .vm = try vm_mod.Vm.init(rt.gpa, options.stack_size, options.frame_count) };
        rt.thread = th;
        return th;
    }

    pub fn destroy(th: *Thread) void {
        const rt = th.rt;
        if (rt.thread == th) rt.thread = null;
        th.vm.deinit(rt.gpa);
        rt.gpa.destroy(th);
    }

    /// GC のルート（§3.3）：VM の値スタックとフレーム、多値レジスタ、エラーの値
    pub fn forEachRoot(th: *const Thread, ctx: anytype, comptime f: fn (@TypeOf(ctx), Value) void) void {
        th.vm.forEachRoot(ctx, f);
        for (th.mv[1..@min(th.mv_count, mv_limit)]) |v| f(ctx, v);
        f(ctx, th.err.datum);
        f(ctx, th.err.expected);
    }

    // ------------------------------------------------------------------
    // エラー（Phase 25 で condition の通知に置き換える）

    /// エラーを記録して Value.unwind を返す（呼び出し側はそのまま返す）
    pub fn signal(th: *Thread, kind: ErrorKind, message: []const u8, datum: Value, expected: Value) Value {
        th.fault = .lisp_error;
        th.err = .{ .kind = kind, .message = message, .datum = datum, .expected = expected };
        return Value.unwind;
    }

    pub fn typeError(th: *Thread, datum: Value, expected: Value) Value {
        return th.signal(.type_error, "", datum, expected);
    }

    pub fn outOfMemory(th: *Thread) Value {
        return th.signal(.storage_condition, "メモリが足りません", Value.unbound, Value.unbound);
    }

    pub fn argCountError(th: *Thread, f: Value, nargs: u32) Value {
        _ = f;
        return th.signal(.program_error, "引数の個数が正しくありません", Value.fromFixnum(nargs), Value.unbound);
    }

    /// エラーの内容を1行で書く（改行は含めない）
    pub fn writeError(th: *Thread, w: *std.Io.Writer) std.Io.Writer.Error!void {
        const e = th.err;
        const rt = th.rt;
        switch (th.fault) {
            .lisp_error => {},
            .out_of_memory => return w.writeAll("STORAGE-CONDITION: メモリが足りません"),
            .internal => return w.writeAll("処理系の内部エラー"),
            .unwind => return w.writeAll("CONTROL-ERROR: 脱出先がありません"),
            .none => return w.writeAll("（エラーはありません）"),
        }
        try w.print("{s}: ", .{e.kind.typeName()});
        switch (e.kind) {
            .type_error => {
                try w.writeAll("値 ");
                try printer.prin1(rt, w, e.datum);
                try w.writeAll(" は型 ");
                try printer.prin1(rt, w, e.expected);
                try w.writeAll(" ではありません");
            },
            .unbound_variable => {
                try w.writeAll("変数 ");
                try printer.prin1(rt, w, e.datum);
                try w.writeAll(" に値がありません");
            },
            .undefined_function => {
                try w.writeAll("関数 ");
                try printer.prin1(rt, w, e.datum);
                if (e.datum.isOther() and Runtime.kindOf(e.datum) == .symbol and
                    rt.symbolPtr(e.datum).hasFlag(@import("../values/object.zig").SymbolFlags.unimplemented))
                {
                    try w.writeAll(" は未実装です");
                } else {
                    try w.writeAll(" は定義されていません");
                }
            },
            else => {
                try w.writeAll(e.message);
                if (e.datum != Value.unbound) {
                    try w.writeAll(": ");
                    try printer.prin1(rt, w, e.datum);
                }
            },
        }
    }

    /// エラーの記録を消す（トップレベルで報告した後）
    pub fn clearError(th: *Thread) void {
        th.fault = .none;
        th.err = .{};
    }

    // ------------------------------------------------------------------
    // 関数の呼び出し（funcall の意味。§6.2）

    /// 関数指定子（関数、またはシンボル）を呼ぶ。args は GC のルートとして走査される領域にあること
    /// Zig の関数から関数を呼ぶ経路は、すべてここを通る。入れ子の深さ（native_depth）は、
    /// VM の closure なら vm.run が、それ以外（プリミティブ）ならここで数える（二重には数えない）。
    /// apply から apply を呼ぶ連鎖のように VM を挟まない場合も、深さの上限で止める
    pub fn call(th: *Thread, f: Value, args: []const Value) Value {
        const fv = th.resolveFunction(f);
        if (fv == Value.unwind) return fv;
        const entry = function.functionHeader(fv).entry;
        if (entry == &vm_mod.closureEntry) return entry(th, fv, args.ptr, @intCast(args.len));
        if (th.native_depth >= max_native_depth)
            return th.signal(.storage_condition, "呼び出しが深すぎます（Zig の関数を挟んだ呼び出しの入れ子が上限を超えました）", Value.unbound, Value.unbound);
        th.native_depth += 1;
        defer th.native_depth -= 1;
        return entry(th, fv, args.ptr, @intCast(args.len));
    }

    /// 関数指定子を関数オブジェクトにする（シンボルなら大域の関数）
    pub fn resolveFunction(th: *Thread, f: Value) Value {
        if (f.isFunctionPointer()) return f;
        if (f == Value.nil or (f.isOther() and Runtime.kindOf(f) == .symbol)) {
            const s = th.rt.symbolPtr(f);
            if (s.function == Value.unbound or s.hasFlag(@import("../values/object.zig").SymbolFlags.macro) or
                s.hasFlag(@import("../values/object.zig").SymbolFlags.special_operator))
                return th.signal(.undefined_function, "", f, Value.unbound);
            return s.function;
        }
        return th.typeError(f, th.rt.syms.function);
    }
};
