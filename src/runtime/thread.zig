//! スレッドの状態（詳細設計 §6.1）。1.0 は単一スレッド。
//!
//! Phase 08 の範囲：多値の個数、`fault`、VM、Lisp のエラーの情報。
//! condition・handler・restart（Phase 25）ができるまでは、Lisp のエラーは
//! `fault = .lisp_error` と `err`（種類と値）で表し、トップレベル（REPL・スクリプト）まで戻って報告する。
//! Phase 25 で、`signal` は handler を探して呼ぶ処理に置き換え、最後は toplevel の restart へ脱出する（§6.6・§9）。

const std = @import("std");
const value_mod = @import("../values/value.zig");
const Value = value_mod.Value;
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
/// 動的束縛のスタックの1要素（§6.5：shallow binding。旧値は未束縛のこともある）
pub const Binding = struct { sym: Value, old: Value };

/// 制御スタックのエントリ（§6.4。Phase 18）
pub const ControlEntry = struct {
    kind: Kind,
    /// block・tagbody：実行時の識別子（fixnum）。catch：タグ。unwind-protect：NIL
    token: Value,
    /// エントリを積んだ時点の動的束縛の深さ（脱出先・cleanup で、ここまで戻す）
    binding_depth: u32,
    /// VM が積んだエントリの再開の位置：フレームの数・値スタックの深さ・命令の位置（ネイティブのエントリでは使わない）
    fp: u32 = 0,
    sp: u32 = 0,
    ip: u32 = 0,

    /// tagbody は、脱出先として着地した後もエントリを残す（tagbody の中で続けるため。Phase 19）
    pub const Kind = enum(u8) { block, catch_tag, unwind_protect, tagbody };
};

/// 処理途中の非局所脱出（§6.4 の Transfer）。th.unwinds にスタックとして積む
pub const Transfer = struct {
    /// 脱出先の制御スタックのエントリの番号。エラーで cleanup を実行している間は no_target
    target: u32,
    /// 運ぶ値：主値、個数、2つ目以降の値のリスト（個数が 2 以上のとき）
    primary: Value,
    rest: Value,
    count: u32,
    /// この脱出が cleanup の実行のために止まっている間、その cleanup を実行している深さ（制御スタックの深さ）。
    /// 止まっていなければ not_suspended
    cleanup_at: u32,
    /// target が no_target のとき、cleanup の後で続けるエラーの理由
    saved_fault: Fault,
    /// target が no_target のとき、エラーの内容を Thread.saved_errors に退避したか
    err_saved: bool = false,
};

/// cleanup の間に退避したエラーの内容（cleanup の中で別のエラーが起きて受け止められても、元のエラーを報告するため）
pub const SavedError = struct {
    err: LispError,
    backtrace: [backtrace_max]Value,
    backtrace_len: u32,
    backtrace_depth: u32,
};

pub const no_target = std.math.maxInt(u32);
pub const not_suspended = std.math.maxInt(u32);

/// エラーの報告に含める呼び出しの履歴の数
pub const backtrace_max = 16;

/// 戻り値が Value.unwind のときの理由（§6.6）
pub const Fault = enum(u8) {
    none,
    /// 非局所脱出の途中（Phase 18。th.unwinds の先頭が脱出の内容）
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
    package_error,
    division_by_zero,
    floating_point_overflow,
    floating_point_invalid_operation,
    storage_condition,
    parse_error,
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
            .package_error => "PACKAGE-ERROR",
            .division_by_zero => "DIVISION-BY-ZERO",
            .floating_point_overflow => "FLOATING-POINT-OVERFLOW",
            .floating_point_invalid_operation => "FLOATING-POINT-INVALID-OPERATION",
            .storage_condition => "STORAGE-CONDITION",
            .parse_error => "PARSE-ERROR",
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
    /// Lisp の文字列の説明（message の代わりに使う。Lisp で書いた標準ライブラリが報告するエラー）。なければ unbound
    detail: Value = Value.unbound,
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
    /// out に最後に書いたのが改行か（行の先頭にいるか。format の ~& が使う。Phase 19）
    line_start: bool = true,
    /// Zig の関数から関数を呼んでいる入れ子の深さ（Thread.call で数える）
    native_depth: u32 = 0,
    /// 動的束縛のスタック（§6.5）
    bindings: []Binding,
    binding_depth: usize = 0,
    /// 制御スタック（block・catch・unwind-protect。§6.4）
    control: []ControlEntry,
    control_depth: usize = 0,
    /// 処理途中の非局所脱出のスタック（§6.4）。大きさは制御スタック + 1。
    /// 制御スタックの深さとの和が制御スタックの大きさを超えないように、エントリを積むときに確かめる
    /// （cleanup に入るときはエントリを1つ取り除いてから記録を1つ積むので、和は増えない。増えるのは脱出を始めるときの1つだけ）
    unwinds: []Transfer,
    unwind_depth: usize = 0,
    /// cleanup の間に退避したエラーの内容（エラーの Transfer の err_saved に対応する。まれにしか使わないので必要なときに伸ばす）
    saved_errors: std.ArrayList(SavedError) = .empty,
    /// 次の block の識別子
    next_token: i64 = 0,
    /// 多値レジスタ（mv[0] は使わない。主値は戻り値）
    mv: [mv_limit]Value = @splat(Value.nil),
    /// エラーを記録した時点の呼び出しの履歴（VM のフレームの closure。新しい順）
    backtrace: [backtrace_max]Value = @splat(Value.nil),
    backtrace_len: u32 = 0,
    /// 履歴の全体の深さ（backtrace_max を超えた分は記録しない）
    backtrace_depth: u32 = 0,

    pub const Options = struct {
        /// VM の値スタックの要素数（§7.1。既定 1M 要素 = 8 MiB）
        stack_size: usize = 1 << 20,
        /// VM のフレームの数の上限（1 フレームは値スタックを 1 要素以上使うので、値スタックの 1/4 とする）
        frame_count: usize = 1 << 18,
        /// 動的束縛の深さの上限
        binding_count: usize = 1 << 16,
        /// 制御スタックの深さの上限（処理途中の脱出のスタックも同じ大きさ）
        control_count: usize = 1 << 16,
    };

    pub fn create(rt: *Runtime, out: *std.Io.Writer, options: Options) runtime.Error!*Thread {
        const th = try rt.gpa.create(Thread);
        errdefer rt.gpa.destroy(th);
        const bindings = try rt.gpa.alloc(Binding, options.binding_count);
        errdefer rt.gpa.free(bindings);
        const control = try rt.gpa.alloc(ControlEntry, options.control_count);
        errdefer rt.gpa.free(control);
        const unwinds = try rt.gpa.alloc(Transfer, options.control_count + 1);
        errdefer rt.gpa.free(unwinds);
        th.* = .{
            .rt = rt,
            .out = out,
            .vm = try vm_mod.Vm.init(rt.gpa, options.stack_size, options.frame_count),
            .bindings = bindings,
            .control = control,
            .unwinds = unwinds,
        };
        rt.thread = th;
        // 標準ライブラリ（Lisp で書いた標準マクロなど）を読み込む（§11.1 の 7）
        try @import("../compiler/boot.zig").load(th);
        return th;
    }

    pub fn destroy(th: *Thread) void {
        const rt = th.rt;
        if (rt.thread == th) rt.thread = null;
        th.vm.deinit(rt.gpa);
        rt.gpa.free(th.bindings);
        rt.gpa.free(th.control);
        rt.gpa.free(th.unwinds);
        th.saved_errors.deinit(rt.gpa);
        rt.gpa.destroy(th);
    }

    /// GC のルート（§3.3）：VM の値スタックとフレーム、多値レジスタ、エラーの値
    pub fn forEachRoot(th: *const Thread, ctx: anytype, comptime f: fn (@TypeOf(ctx), Value) void) void {
        th.vm.forEachRoot(ctx, f);
        if (th.mv_count > 1) for (th.mv[1..@min(th.mv_count, mv_limit)]) |v| f(ctx, v);
        f(ctx, th.err.datum);
        f(ctx, th.err.expected);
        f(ctx, th.err.detail);
        for (th.backtrace[0..th.backtrace_len]) |v| f(ctx, v);
        for (th.bindings[0..th.binding_depth]) |b| {
            f(ctx, b.sym);
            f(ctx, b.old);
        }
        for (th.control[0..th.control_depth]) |e| f(ctx, e.token);
        for (th.unwinds[0..th.unwind_depth]) |t| {
            f(ctx, t.primary);
            f(ctx, t.rest);
        }
        for (th.saved_errors.items) |*s| {
            f(ctx, s.err.datum);
            f(ctx, s.err.expected);
            f(ctx, s.err.detail);
            for (s.backtrace[0..s.backtrace_len]) |v| f(ctx, v);
        }
    }

    // ------------------------------------------------------------------
    // エラー（Phase 25 で condition の通知に置き換える）

    /// エラーを記録して Value.unwind を返す（呼び出し側はそのまま返す）
    /// エラーの経路はまれにしか通らないので、inline 展開しない（呼び出し側の高速経路のコードを小さく保つ）
    pub noinline fn signal(th: *Thread, kind: ErrorKind, message: []const u8, datum: Value, expected: Value) Value {
        th.fault = .lisp_error;
        th.err = .{ .kind = kind, .message = message, .datum = datum, .expected = expected };
        th.captureBacktrace();
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
                // COMMON-LISP パッケージの変数・定数で値がないのは、その機能が未実装のため
                if (e.datum.isOther() and Runtime.kindOf(e.datum) == .symbol and rt.symbolPtr(e.datum).package == rt.cl.obj) {
                    try w.writeAll(" は未実装です");
                } else {
                    try w.writeAll(" に値がありません");
                }
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
                if (e.detail != Value.unbound and e.detail.isOther() and Runtime.kindOf(e.detail) == .string) {
                    try Runtime.writeStringUtf8(e.detail, w);
                } else try w.writeAll(e.message);
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
        // トップレベルまで戻ったので、エラーで抜けた脱出の記録（cleanup の途中で止まっていたもの）も消す
        th.unwind_depth = 0;
        th.control_depth = 0;
        th.saved_errors.clearRetainingCapacity();
        th.err = .{};
        th.backtrace_len = 0;
        th.backtrace_depth = 0;
    }

    /// VM のフレームの関数を、新しい順に記録する（エラーの報告用。ネイティブのフレームは Phase 25 以降）
    fn captureBacktrace(th: *Thread) void {
        const n = th.vm.fp;
        th.backtrace_depth = @intCast(n);
        th.backtrace_len = @intCast(@min(n, backtrace_max));
        for (0..th.backtrace_len) |i| th.backtrace[i] = th.vm.frames[n - 1 - i].closure;
    }

    /// 呼び出しの履歴を書く（関数の中で起きたエラーのときだけ）。各行は 2 字下げで、改行で終わる
    pub fn writeBacktrace(th: *Thread, w: *std.Io.Writer) std.Io.Writer.Error!void {
        // トップレベルのフォームの中だけで起きたエラーには、履歴を書かない（情報がない）
        if (th.backtrace_depth <= 1) return;
        try w.writeAll("  呼び出しの履歴（新しい順）:\n");
        for (th.backtrace[0..th.backtrace_len], 0..) |c, i| {
            try w.print("    {d}: ", .{i});
            try printer.printCodeName(th.rt, w, function.closurePtr(c).codePtr().name);
            try w.writeByte('\n');
        }
        if (th.backtrace_depth > th.backtrace_len) try w.print("    …ほか {d} 件\n", .{th.backtrace_depth - th.backtrace_len});
    }

    // ------------------------------------------------------------------
    // 多値（§6.3）

    /// 今の多値（主値 primary と th.mv）をリストにする。確保の間、多値レジスタは GC のルート
    pub fn valuesToList(th: *Thread, primary: Value) error{OutOfMemory}!Value {
        const n = th.mv_count;
        if (n == 0) return Value.nil;
        var list = Value.nil;
        var i = n;
        while (i > 1) : (i -= 1) list = try th.rt.cons(th.mv[i - 1], list);
        return th.rt.cons(primary, list);
    }

    /// リストの要素を多値にする（主値を返す）。要素が multiple-values-limit を超える分は捨てる
    pub fn listToValues(th: *Thread, list: Value) Value {
        var x = list;
        var n: u32 = 0;
        var primary = Value.nil;
        while (x.isCons() and n < mv_limit) : (x = Runtime.consPtr(x).cdr) {
            const v = Runtime.consPtr(x).car;
            if (n == 0) primary = v else th.mv[n] = v;
            n += 1;
        }
        th.mv_count = n;
        return primary;
    }

    // ------------------------------------------------------------------
    // 動的束縛（§6.5）

    /// sym を v で動的に束縛する。束縛のスタックが溢れたら Value.unwind（それ以外は NIL）
    pub fn bind(th: *Thread, sym: Value, v: Value) Value {
        if (th.binding_depth >= th.bindings.len)
            return th.signal(.storage_condition, "動的束縛が深すぎます", Value.unbound, Value.unbound);
        const s = th.rt.symbolPtr(sym);
        th.bindings[th.binding_depth] = .{ .sym = sym, .old = s.value };
        th.binding_depth += 1;
        s.value = v;
        return Value.nil;
    }

    /// 束縛のスタックを depth まで戻す（新しい束縛から順に旧値を戻す）
    pub fn unbindTo(th: *Thread, depth: usize) void {
        while (th.binding_depth > depth) {
            th.binding_depth -= 1;
            const b = th.bindings[th.binding_depth];
            th.rt.symbolPtr(b.sym).value = b.old;
        }
    }

    /// progv：syms の各シンボルを vals の値で束縛する。値が足りなければ未束縛にする（CLHS progv）
    pub fn progvBind(th: *Thread, syms: Value, vals: Value) Value {
        const SF = @import("../values/object.zig").SymbolFlags;
        var x = syms;
        var y = vals;
        while (x.isCons()) : (x = Runtime.consPtr(x).cdr) {
            const sym = Runtime.consPtr(x).car;
            if (!(sym == Value.nil or (sym.isOther() and Runtime.kindOf(sym) == .symbol)))
                return th.typeError(sym, th.rt.syms.symbol);
            const s = th.rt.symbolPtr(sym);
            if (sym == Value.nil or s.hasFlag(SF.constant) or s.hasFlag(SF.keyword))
                return th.signal(.program_error, "定数は束縛できません", sym, Value.unbound);
            var v = Value.unbound;
            if (y.isCons()) {
                v = Runtime.consPtr(y).car;
                y = Runtime.consPtr(y).cdr;
            }
            if (th.bind(sym, v) == Value.unwind) return Value.unwind;
        }
        if (x != Value.nil) return th.typeError(syms, th.rt.syms.list);
        return Value.nil;
    }

    // ------------------------------------------------------------------
    // 非局所脱出（§6.4。Phase 18）
    //
    // 脱出の手順（VM とネイティブで共通）
    //   1. return-from・throw が脱出先のエントリを探し（なければ control-error）、運ぶ値を Transfer に写して積み、
    //      th.fault = .unwind として Value.unwind を返す
    //   2. Value.unwind を受け取った block・catch は、自分が脱出先なら、動的束縛を戻して値を受け取る（land）。
    //      そうでなければ自分のエントリを取り除いて Value.unwind を返し直す
    //   3. unwind-protect は、動的束縛を戻してから cleanup を実行する（uwpBegin）。cleanup の間、脱出は止まっている。
    //      cleanup の後で脱出を続ける（uwpResume）。エラーで抜けるときも cleanup を実行する
    //   4. cleanup の中から cleanup の外へ出る脱出は、止まっている脱出を取り消す（cleanup_at で判断する）

    /// 処理系の内部の誤り（検証済みのバイトコードでは起きない制御スタックの操作など）
    pub fn internalError(th: *Thread) Value {
        th.fault = .internal;
        return Value.unwind;
    }

    pub fn pushControl(th: *Thread, kind: ControlEntry.Kind, token: Value, fp: usize, sp: usize, ip: usize) Value {
        if (th.control_depth + th.unwind_depth >= th.control.len)
            return th.signal(.storage_condition, "block・catch・unwind-protect の入れ子が深すぎます", Value.unbound, Value.unbound);
        th.control[th.control_depth] = .{
            .kind = kind,
            .token = token,
            .binding_depth = @intCast(th.binding_depth),
            .fp = @intCast(fp),
            .sp = @intCast(sp),
            .ip = @intCast(ip),
        };
        th.control_depth += 1;
        return Value.nil;
    }

    /// block の識別子を作る（block に入るたびに別の値。脱出先の動的エクステントが終わったかを確かめるため）
    pub fn newBlockToken(th: *Thread) Value {
        const t = th.next_token;
        th.next_token = if (t == value_mod.most_positive_fixnum) 0 else t + 1;
        return Value.fromFixnum(t);
    }

    fn findEntry(th: *Thread, kind: ControlEntry.Kind, token: Value) ?u32 {
        var i = th.control_depth;
        while (i > 0) : (i -= 1) {
            const e = th.control[i - 1];
            if (e.kind == kind and e.token == token) return @intCast(i - 1);
        }
        return null;
    }

    /// (return-from 名前 値) の実行時の脱出。primary と th.mv_count・th.mv が運ぶ値
    pub fn returnFrom(th: *Thread, token: Value, primary: Value) Value {
        const target = th.findEntry(.block, token) orelse
            return th.signal(.control_error, "RETURN-FROM の脱出先の BLOCK は、既に抜けています", Value.unbound, Value.unbound);
        return th.startTransfer(target, primary);
    }

    /// (go タグ) の実行時の脱出（Phase 19）。運ぶ値はタグの番号（fixnum）
    pub fn goTo(th: *Thread, token: Value, index: u32) Value {
        const target = th.findEntry(.tagbody, token) orelse
            return th.signal(.control_error, "GO の脱出先の TAGBODY は、既に抜けています", Value.unbound, Value.unbound);
        th.mv_count = 1;
        return th.startTransfer(target, Value.fromFixnum(index));
    }

    /// (throw タグ 値)
    pub fn throwTo(th: *Thread, tag: Value, primary: Value) Value {
        const target = th.findEntry(.catch_tag, tag) orelse
            return th.signal(.control_error, "THROW のタグに対応する CATCH がありません", tag, Value.unbound);
        return th.startTransfer(target, primary);
    }

    /// 脱出を始める。cleanup の途中で止まっている脱出のうち、その cleanup の外へ出るものは取り消す
    fn startTransfer(th: *Thread, target: u32, primary: Value) Value {
        th.abandonSuspended(target);
        if (th.unwind_depth >= th.unwinds.len)
            return th.signal(.storage_condition, "非局所脱出の入れ子が深すぎます", Value.unbound, Value.unbound);
        const count = th.mv_count;
        var rest = Value.nil;
        if (count > 1) {
            // 確保の間、主値は呼び出し側（VM の値スタック、ネイティブのスタック）にあり、残りの値は多値レジスタにある
            var i = count;
            while (i > 1) : (i -= 1) rest = th.rt.cons(th.mv[i - 1], rest) catch return th.outOfMemory();
        }
        th.unwinds[th.unwind_depth] = .{
            .target = target,
            .primary = if (count == 0) Value.nil else primary,
            .rest = rest,
            .count = count,
            .cleanup_at = not_suspended,
            .saved_fault = .none,
        };
        th.unwind_depth += 1;
        th.fault = .unwind;
        return Value.unwind;
    }

    /// 制御スタックの深さ depth より内側で実行している cleanup の脱出（cleanup_at > depth）を取り消す
    fn abandonSuspended(th: *Thread, depth: u32) void {
        while (th.unwind_depth > 0) {
            const t = th.unwinds[th.unwind_depth - 1];
            if (t.cleanup_at == not_suspended or t.cleanup_at <= depth) break;
            if (t.err_saved) _ = th.saved_errors.pop();
            th.unwind_depth -= 1;
        }
    }

    /// Value.unwind を受け取ったときに、制御スタックの先頭のエントリ（block・catch）が脱出先か
    pub fn isTarget(th: *const Thread) bool {
        return th.fault == .unwind and th.unwind_depth > 0 and th.unwinds[th.unwind_depth - 1].target == th.control_depth - 1;
    }

    /// 先頭のエントリを脱出先として、脱出を終える：エントリと Transfer を取り除き、動的束縛を戻し、運んだ値を多値にして主値を返す。
    /// tagbody のエントリは残す（主値はタグの番号。tagbody の中で、そのタグから続ける）
    pub fn landTransfer(th: *Thread) Value {
        const e = th.control[th.control_depth - 1];
        if (e.kind != .tagbody) th.control_depth -= 1;
        th.unbindTo(e.binding_depth);
        th.unwind_depth -= 1;
        const t = th.unwinds[th.unwind_depth];
        th.fault = .none;
        th.mv_count = t.count;
        var x = t.rest;
        var i: u32 = 1;
        while (x.isCons()) : (x = Runtime.consPtr(x).cdr) {
            th.mv[i] = Runtime.consPtr(x).car;
            i += 1;
        }
        return t.primary;
    }

    /// ネイティブの block・catch が Value.unwind を受け取ったとき：脱出先なら値を受け取り、そうでなければ
    /// エントリを取り除いて Value.unwind を返す
    pub fn land(th: *Thread) Value {
        if (th.control_depth == 0) return th.internalError();
        if (th.isTarget()) return th.landTransfer();
        th.control_depth -= 1;
        return Value.unwind;
    }

    /// unwind-protect の cleanup を、脱出・エラーの途中で始める（エントリは取り除き、動的束縛は戻してあること）。
    /// 進行中の脱出を止める。エラーなら、エラーの理由を Transfer に退避する
    pub fn uwpBegin(th: *Thread) void {
        const depth: u32 = @intCast(th.control_depth);
        if (th.fault == .unwind) {
            th.unwinds[th.unwind_depth - 1].cleanup_at = depth;
        } else {
            th.abandonSuspended(depth);
            // 溢れない：エントリを1つ取り除いた後なので、制御スタックの深さとの和は増えない（unwinds の説明）。
            // 検証していないコードで溢れた場合は、cleanup を内部の誤りのまま実行する（uwpResume が誤りを返す）
            if (th.unwind_depth >= th.unwinds.len) {
                th.fault = .internal;
                return;
            }
            // エラーの内容を退避する（cleanup の中で起きて受け止められたエラーが th.err を上書きしても、元に戻すため）
            var saved = true;
            th.saved_errors.append(th.rt.gpa, .{
                .err = th.err,
                .backtrace = th.backtrace,
                .backtrace_len = th.backtrace_len,
                .backtrace_depth = th.backtrace_depth,
            }) catch {
                saved = false; // ※確保できなければ、内容は退避しない（理由の種類は残る）
            };
            th.unwinds[th.unwind_depth] = .{
                .target = no_target,
                .primary = Value.nil,
                .rest = Value.nil,
                .count = 0,
                .cleanup_at = depth,
                .saved_fault = th.fault,
                .err_saved = saved,
            };
            th.unwind_depth += 1;
        }
        th.fault = .none;
    }

    /// cleanup を終えて、止めていた脱出・エラーを続ける（Value.unwind を返す）
    pub fn uwpResume(th: *Thread) Value {
        // この cleanup のために止めた脱出は、先頭にあり、cleanup を実行している深さが今の深さと同じ
        if (th.unwind_depth == 0 or th.unwinds[th.unwind_depth - 1].cleanup_at != th.control_depth) return th.internalError();
        const t = &th.unwinds[th.unwind_depth - 1];
        if (t.target == no_target) {
            th.fault = t.saved_fault;
            if (t.err_saved) {
                const s = th.saved_errors.pop().?;
                th.err = s.err;
                th.backtrace = s.backtrace;
                th.backtrace_len = s.backtrace_len;
                th.backtrace_depth = s.backtrace_depth;
            }
            th.unwind_depth -= 1;
        } else {
            t.cleanup_at = not_suspended;
            th.fault = .unwind;
        }
        return Value.unwind;
    }

    /// unwind-protect の保護したフォームを抜けたとき：エントリを取り除き、cleanup の後で返す値を退避する印を返す。
    ///   fixnum 1：値は primary の1つ。fixnum -1：脱出・エラーの途中（primary が Value.unwind）。リスト：全部の値
    pub fn uwpSave(th: *Thread, primary: Value) Value {
        if (th.control_depth == 0 or th.control[th.control_depth - 1].kind != .unwind_protect) {
            _ = th.internalError();
            th.uwpBegin();
            return Value.fromFixnum(-1);
        }
        th.control_depth -= 1;
        if (primary == Value.unwind) {
            th.unbindTo(th.control[th.control_depth].binding_depth);
            th.uwpBegin();
            return Value.fromFixnum(-1);
        }
        if (th.mv_count == 1) return Value.fromFixnum(1);
        return th.valuesToList(primary) catch {
            _ = th.outOfMemory();
            th.uwpBegin();
            return Value.fromFixnum(-1);
        };
    }

    /// cleanup の後：退避した値を戻して主値を返す。脱出・エラーの途中なら、それを続ける（Value.unwind）
    pub fn uwpEnd(th: *Thread, primary: Value, marker: Value) Value {
        if (marker.isFixnum()) {
            if (marker.asFixnum() == 1) {
                th.mv_count = 1;
                return primary;
            }
            return th.uwpResume();
        }
        return th.listToValues(marker);
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

    /// シンボルの setf 関数。なければ undefined-function（名前は (setf シンボル)）
    pub fn resolveSetfFunction(th: *Thread, sym: Value) Value {
        const f = th.rt.symbolPtr(sym).setf_function;
        if (f != Value.unbound) return f;
        const tail = th.rt.cons(sym, Value.nil) catch return th.outOfMemory();
        const name = th.rt.cons(th.rt.syms.setf, tail) catch return th.outOfMemory();
        return th.signal(.undefined_function, "", name, Value.unbound);
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
