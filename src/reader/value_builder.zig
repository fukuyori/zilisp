//! Reader が読んだものから Lisp の値（Value）を作る Builder（詳細設計 §5、§8）。
//!
//! 整数は fixnum の範囲を超えれば bignum に、比は約分して ratio（分母が 1 なら整数）にする（Phase 20）。

const std = @import("std");
const reader = @import("reader.zig");
const rt_mod = @import("../runtime/runtime.zig");
const Runtime = rt_mod.Runtime;
const Value = rt_mod.Value;
const Diagnostic = reader.Diagnostic;
const SourceLoc = reader.SourceLoc;
const Error = reader.Error;
const Thread = @import("../runtime/thread.zig").Thread;
const readtable = @import("readtable.zig");
const arrays = @import("../primitives/arrays.zig");

pub const ValueBuilder = struct {
    rt: *Runtime,
    /// 真なら、パッケージ修飾のパッケージがなければ空のパッケージを作る（ネイティブの定数を起動時に読むとき。Phase 22）。
    /// このときは、印字の変数・*readtable* によらず標準の構文で読む（定数は標準の構文で書いてある）
    create_packages: bool = false,
    /// reader macro・#. を呼ぶスレッド（なければ使えない。Phase 24）
    th: ?*Thread = null,
    /// ユーザーの reader macro を呼んでいる間の、外側の Reader の backquote の深さ（recursive な read が引き継ぐ）
    bq_depth: usize = 0,
    /// 今の *readtable*（標準の構文なら NIL：Reader は標準の表で読む）
    readtable: Value = Value.nil,
    /// Source が読んでいるストリーム（reader macro に渡す）と、Source の先頭のストリームの中の位置
    stream: Value = Value.nil,
    stream_base: usize = 0,
    /// ストリームが Latin-1（Source は UTF-8 にした写し）
    latin1: bool = false,
    /// #n= のラベル（((n . オブジェクト) …)。recursive の read は外側の表を使う）
    labels: Value = Value.nil,
    labels_ptr: ?*Value = null,
    /// ストリームの位置を、Reader が読んだところまで進める関数（ストリームから読むとき。readOp が設定する）。
    /// Builder の中からエラーを通知する前に呼ぶ（handler がその場でストリームを読むため。Codex のレビュー P25 2回目 #1）
    sync_position: ?SyncPosition = null,

    pub const SyncPosition = struct {
        ctx: *anyopaque,
        f: *const fn (*anyopaque) void,
    };

    fn syncPosition(b: *ValueBuilder) void {
        if (b.sync_position) |s| s.f(s.ctx);
    }

    pub const Datum = Value;
    /// 組み立て中のリスト（先頭と最後の cons）
    pub const List = struct { head: Value = Value.nil, last: Value = Value.nil, count: usize = 0 };

    fn fail(diag: *Diagnostic, loc: SourceLoc, message: []const u8) Error {
        diag.* = .{ .loc = loc, .message = message };
        return error.ReaderError;
    }

    /// read のたびに、Options を今の値にする（*read-base*・*read-default-float-format*・*read-suppress*・*readtable*。Phase 24）
    pub fn beginRead(b: *ValueBuilder, opts: *reader.Options) void {
        if (b.labels_ptr == null) b.labels = Value.nil;
        if (b.create_packages) {
            b.readtable = Value.nil;
            return;
        }
        const rt = b.rt;
        const tv = readtable.current(rt);
        opts.case = readtable.caseOf(tv);
        b.readtable = if (readtable.ptr(tv).header.flags & readtable.Table.standard_flag != 0) Value.nil else tv;
        const base = rt.symbolPtr(rt.syms.@"*read-base*").value;
        if (base.isFixnum() and base.asFixnum() >= 2 and base.asFixnum() <= 36) opts.read_base = @intCast(base.asFixnum());
        const ff = rt.symbolPtr(rt.syms.@"*read-default-float-format*").value;
        opts.default_float = if (ff == rt.syms.@"double-float" or ff == rt.syms.@"long-float") .double else .single;
        const sup = rt.symbolPtr(rt.syms.@"*read-suppress*").value;
        opts.suppress = sup != Value.nil and sup != Value.unbound;
    }

    /// 標準でない readtable で読むか（Reader が read の始めに聞く）
    pub fn customSyntax(b: *ValueBuilder) bool {
        return b.readtable != Value.nil;
    }

    pub fn charInfo(b: *ValueBuilder, cp: u21) ?reader.CharInfo {
        if (b.readtable == Value.nil) return null;
        return readtable.charInfo(b.rt, b.readtable, cp);
    }

    pub fn dispatchInfo(b: *ValueBuilder, disp: u21, sub: u21) ?reader.Macro {
        if (b.readtable == Value.nil) return null;
        return readtable.dispatchInfo(b.rt, b.readtable, disp, sub);
    }

    /// Source の位置 → ストリームの位置
    fn toStreamPos(b: *ValueBuilder, src: *reader.Source, pos: usize) usize {
        if (!b.latin1) return b.stream_base + pos;
        var n: usize = 0;
        for (src.text[0..pos]) |c| if (c & 0xC0 != 0x80) {
            n += 1;
        };
        return b.stream_base + n;
    }

    /// ストリームの位置 → Source の位置
    fn fromStreamPos(b: *ValueBuilder, src: *reader.Source, pos: usize) usize {
        const rel = pos -| b.stream_base;
        if (!b.latin1) return @min(rel, src.text.len);
        var chars: usize = 0;
        var i: usize = 0;
        while (i < src.text.len and chars < rel) : (i += 1) {
            if (src.text[i] & 0xC0 != 0x80) chars += 1;
        }
        while (i < src.text.len and src.text[i] & 0xC0 == 0x80) i += 1;
        return i;
    }

    /// ユーザー定義の reader macro を呼ぶ（Phase 24）。(関数 ストリーム 文字) か、dispatch なら (関数 ストリーム 文字 引数)。
    /// ストリームの位置を Source の位置に合わせてから呼び、呼んだ後の位置まで Source を進める。値がなければ null
    /// suppress（読み飛ばしの最中）なら、*read-suppress* を真に束縛して呼び（マクロの中の read も読み飛ばす）、値は NIL にする
    /// （SBCL と同じ。#+ で読み飛ばす中の #. を評価しない。Codex のレビュー 0.3 #1・#6）
    pub fn callMacro(b: *ValueBuilder, diag: *Diagnostic, loc: SourceLoc, src: *reader.Source, f_raw: u64, cp: u21, arg: ?usize, dispatch: bool, suppress: bool, bq_depth: usize) Error!?Value {
        const th = b.th orelse return fail(diag, loc, "ここではユーザー定義の reader macro を使えません");
        const streams = @import("../primitives/streams.zig");
        if (b.stream == Value.nil) {
            // テキストを読んでいる（load・read-from-string）：同じテキストの文字列の入力ストリームを作る
            b.stream = streams.makeStringInputBytes(th, src.text) orelse return error.LispError;
            b.stream_base = 0;
            b.latin1 = false;
        }
        const s = b.stream;
        streams.setReadPosition(s, b.toStreamPos(src, src.pos));
        var argv: [3]Value = .{ s, Value.fromChar(cp), if (arg) |n| Value.fromFixnum(@intCast(n)) else Value.nil };
        const saved = th.read_builder;
        th.read_builder = b;
        defer th.read_builder = saved;
        // マクロの中の recursive な read は、外側の backquote の深さで読む（Codex のレビュー 0.3 #4）
        const saved_bq = b.bq_depth;
        b.bq_depth = bq_depth;
        defer b.bq_depth = saved_bq;
        const depth = th.binding_depth;
        if (suppress and th.bind(b.rt.syms.@"*read-suppress*", b.rt.t) == Value.unwind) return error.LispError;
        th.mv_count = 1;
        const r = th.call(Value.fromRaw(f_raw), argv[0..if (dispatch) 3 else 2]);
        th.unbindTo(depth);
        if (r == Value.unwind) return error.LispError;
        const count = th.mv_count;
        // 標準入力は読み足すとバッファが動くので、Source のテキストを取り直す
        if (!b.latin1) if (streams.readBuffer(s)) |buf| {
            src.text = buf[@min(b.stream_base, buf.len)..];
        };
        src.seekTo(b.fromStreamPos(src, streams.readPosition(s)));
        if (count == 0) return null;
        if (suppress) return Value.nil;
        return r;
    }

    /// #.：*read-eval* が真ならフォームを評価する（偽なら reader-error。CLHS 2.4.8.6）
    /// ストリームから読んでいるなら、評価の前にストリームの位置を Source に合わせ、評価の後にバッファと位置を取り直す
    /// （評価の中の read-line などが標準入力を読み足すと、バッファが動く。Codex のレビュー 0.3 修正の修正の修正 #1）
    pub fn readEval(b: *ValueBuilder, diag: *Diagnostic, loc: SourceLoc, src: *reader.Source, form: Value) Error!Value {
        const rt = b.rt;
        if (rt.symbolPtr(rt.syms.@"*read-eval*").value == Value.nil) return fail(diag, loc, "*READ-EVAL* が偽なので #. は使えません");
        const th = b.th orelse return fail(diag, loc, "ここでは #. を使えません");
        const streams = @import("../primitives/streams.zig");
        const s = b.stream;
        if (s != Value.nil) streams.setReadPosition(s, b.toStreamPos(src, src.pos));
        const v = @import("../compiler/eval.zig").eval(th, form);
        if (s != Value.nil) {
            if (!b.latin1) if (streams.readBuffer(s)) |buf| {
                src.text = buf[@min(b.stream_base, buf.len)..];
            };
            src.seekTo(b.fromStreamPos(src, streams.readPosition(s)));
        }
        if (v == Value.unwind) return error.LispError;
        return v;
    }

    /// #S(名前 スロット 値 …)：構造体の標準の構築子（キーワードの引数のもの）を呼んで作る（CLHS 2.4.8.13。Phase 26）。
    /// 形の検査と構築子の呼び出しは Lisp の zl-sys::%read-structure（boot.lisp）。値が構造体でなく数なら誤りの種類
    pub fn structure(b: *ValueBuilder, diag: *Diagnostic, loc: SourceLoc, form: Value) Error!Value {
        const rt = b.rt;
        const th = b.th orelse return fail(diag, loc, "ここでは #S を使えません（構造体のリテラルは、実行時に読むときだけ使えます）");
        const f = if (rt.sys_read_structure == Value.nil) Value.nil else rt.symbolPtr(rt.sys_read_structure).function;
        if (!f.isFunctionPointer()) return fail(diag, loc, "ここでは #S を使えません");
        var argv: [1]Value = .{form};
        th.mv_count = 1;
        const r = th.call(f, &argv);
        if (r == Value.unwind) return error.LispError;
        th.mv_count = 1;
        if (!r.isFixnum()) return r;
        return fail(diag, loc, switch (r.asFixnum()) {
            1 => "#S の後には (構造体の名前 スロット 値 …) の形のリストが必要です",
            2 => "#S の構造体が定義されていません",
            3 => "#S の構造体には、標準の構築子（キーワードの引数の構築子）がありません",
            5 => "#S の構造体の構築子が、まだ定義されていません（構造体のリテラルは、定義を実行した後にだけ読めます）",
            else => "#S のスロットと値の並びが正しくありません",
        });
    }

    /// #nA と #A(次元 要素の型 . 中身)：配列を作る（SBCL 2.6.7 の sharp-A。Phase 24）。
    /// ネイティブの定数の読み込みはスレッドなしで読むので、make-array を呼ばずにここで作る。
    /// 中身の誤りは SBCL の make-array と同じ種類のエラー（スレッドがなければ reader-error）
    pub fn array(b: *ValueBuilder, diag: *Diagnostic, loc: SourceLoc, rank: ?usize, contents: Value) Error!Value {
        const gpa = b.rt.gpa;
        var dims: std.ArrayList(usize) = .empty;
        defer dims.deinit(gpa);
        if (rank) |r| {
            // 各軸の長さは、その軸の最初の要素の長さ（長さ 0 の軸より後ろの軸も 0。CLHS 2.4.8.12）
            var seq = contents;
            for (0..r) |axis| {
                const len = try b.readSeqLength(diag, loc, seq, true);
                try dims.append(gpa, len);
                if (axis + 1 != r and len != 0) seq = arrays.seqElt(seq, 0);
            }
            return b.makeReadArray(diag, loc, dims.items, contents, false);
        }
        // 次元の数がない #A は (次元 要素の型 . 中身) の形（SBCL が特殊化した配列を読み戻せる形で印字するときの形）
        if (!contents.isCons() or !Runtime.consPtr(contents).cdr.isCons())
            return fail(diag, loc, "#A の後には、#nA(中身) か (次元 要素の型 . 中身) が必要です");
        const dspec = Runtime.consPtr(contents).car;
        const rest = Runtime.consPtr(contents).cdr;
        const etype = Runtime.consPtr(rest).car;
        const body = Runtime.consPtr(rest).cdr;
        if (dspec.isFixnum() and dspec.asFixnum() >= 0) {
            try dims.append(gpa, @intCast(dspec.asFixnum()));
        } else {
            if (!dspec.isList()) return b.typeFail(diag, loc, dspec, "LIST");
            var x = dspec;
            while (x.isCons()) : (x = Runtime.consPtr(x).cdr) {
                const d = Runtime.consPtr(x).car;
                if (!d.isFixnum() or d.asFixnum() < 0) return b.typeFail(diag, loc, d, "INTEGER");
                try dims.append(gpa, @intCast(d.asFixnum()));
            }
            if (x != Value.nil) return b.typeFail(diag, loc, dspec, "LIST");
        }
        return b.makeReadArray(diag, loc, dims.items, body, isCharType(b.rt, etype));
    }

    /// 型の誤り（スレッドがあれば type-error。なければ reader-error）
    fn typeFail(b: *ValueBuilder, diag: *Diagnostic, loc: SourceLoc, datum: Value, type_name: []const u8) Error {
        const th = b.th orelse return fail(diag, loc, "#A の中身の型が正しくありません");
        const rt = b.rt;
        const expected = if (rt.findSymbol(rt.cl, type_name)) |f| f.symbol else Value.nil;
        b.syncPosition();
        _ = th.typeError(datum, expected);
        return error.LispError;
    }

    /// 中身の長さと次元が合わない（スレッドがあれば simple-error。SBCL の make-array と同じ）
    fn lengthFail(b: *ValueBuilder, diag: *Diagnostic, loc: SourceLoc, datum: Value) Error {
        const message = "#A の中身の長さが次元と合いません";
        const th = b.th orelse return fail(diag, loc, message);
        b.syncPosition();
        _ = th.signal(.simple_error, message, datum, Value.unbound);
        return error.LispError;
    }

    /// シーケンスの長さ。#nA の軸の中身がシーケンスでなければ reader-error（axis が真）、ドット対で終わるリストは type-error
    fn readSeqLength(b: *ValueBuilder, diag: *Diagnostic, loc: SourceLoc, v: Value, axis: bool) Error!usize {
        if (v.isList()) {
            var n: usize = 0;
            var x = v;
            while (x.isCons()) : (x = Runtime.consPtr(x).cdr) n += 1;
            if (x != Value.nil) return b.typeFail(diag, loc, x, "LIST");
            return n;
        }
        if (arrays.vectorView(v)) |view| return view.len;
        if (axis) return fail(diag, loc, "#nA の軸の中身がシーケンスではありません");
        return b.typeFail(diag, loc, v, "SEQUENCE");
    }

    /// 次元と、入れ子のシーケンスの中身から配列を作る（1次元なら単純ベクタか文字列。要素の型が T なら既定の要素は 0）
    fn makeReadArray(b: *ValueBuilder, diag: *Diagnostic, loc: SourceLoc, dims: []const usize, contents: Value, chars: bool) Error!Value {
        const rt = b.rt;
        var total: usize = 1;
        for (dims) |d| total = std.math.mul(usize, total, d) catch return fail(diag, loc, "#A の配列が大きすぎます");
        if (total > std.math.maxInt(u32)) return fail(diag, loc, "#A の配列が大きすぎます");
        const data = if (chars) try rt.makeStringFilled(total, 0) else try rt.makeVectorFilled(total, Value.fromFixnum(0));
        var base: usize = 0;
        try b.fillRead(diag, loc, data, dims, contents, &base, chars);
        if (dims.len == 1) return data;
        const a = try rt.makeArrayObject(dims, data, 0, 0);
        std.mem.doNotOptimizeAway(data);
        return a;
    }

    fn fillRead(b: *ValueBuilder, diag: *Diagnostic, loc: SourceLoc, data: Value, dims: []const usize, contents: Value, base: *usize, chars: bool) Error!void {
        if (dims.len == 0) {
            if (chars) {
                if (!contents.isChar()) return b.typeFail(diag, loc, contents, "CHARACTER");
                try b.rt.stringSetChar(data, base.*, contents.asChar());
            } else Runtime.vectorPtr(data).items()[base.*] = contents;
            base.* += 1;
            return;
        }
        const n = try b.readSeqLength(diag, loc, contents, false);
        if (n != dims[0]) return b.lengthFail(diag, loc, contents);
        // リストは先頭からたどる（要素ごとに先頭から数え直すと二乗の時間になる。Codex のレビュー 0.3 #7）
        if (contents.isList()) {
            var x = contents;
            while (x.isCons()) : (x = Runtime.consPtr(x).cdr) try b.fillRead(diag, loc, data, dims[1..], Runtime.consPtr(x).car, base, chars);
            return;
        }
        for (0..n) |i| try b.fillRead(diag, loc, data, dims[1..], arrays.seqElt(contents, i), base, chars);
    }

    fn labelsCell(b: *ValueBuilder) *Value {
        return b.labels_ptr orelse &b.labels;
    }

    fn labelEntry(b: *ValueBuilder, n: usize) ?Value {
        var x = b.labelsCell().*;
        while (x.isCons()) : (x = Runtime.consPtr(x).cdr) {
            const e = Runtime.consPtr(x).car;
            if (Runtime.consPtr(e).car == Value.fromFixnum(@intCast(n))) return e;
        }
        return null;
    }

    /// #n=：ラベルの仮の値（後で読んだオブジェクトに置き換える一意の cons）を登録する
    pub fn labelDefine(b: *ValueBuilder, diag: *Diagnostic, loc: SourceLoc, n: usize) Error!Value {
        if (n > std.math.maxInt(i32)) return fail(diag, loc, "#n= の数が大きすぎます");
        if (b.labelEntry(n) != null) return fail(diag, loc, "同じ #n= のラベルが2回あります");
        const rt = b.rt;
        // 仮の値は car が unbound の cons（利用者のデータには現れないので、ほかの cons と区別できる。構造体のスロットの型の
        // 検査 zl-sys::%check-slot-type は、仮の値を検査しない。Codex のレビュー P26 1回目 #1）
        const ph = try rt.cons(Value.unbound, Value.nil);
        const e = try rt.cons(Value.fromFixnum(@intCast(n)), ph);
        const cell = b.labelsCell();
        cell.* = try rt.cons(e, cell.*);
        return ph;
    }

    /// #n= の後のオブジェクトを読み終えた：仮の値への参照をオブジェクトに置き換える
    pub fn labelFinish(b: *ValueBuilder, diag: *Diagnostic, loc: SourceLoc, n: usize, ph: Value, obj: Value) Error!Value {
        if (obj == ph) return fail(diag, loc, "#n= の直後に同じ #n# は置けません");
        const e = b.labelEntry(n).?;
        Runtime.consPtr(e).cdr = obj;
        // 仮の値を置き換えた構造体は、置き換えた後でスロットの型を確かめる（構築子は仮の値を検査しなかった。
        // Codex のレビュー P26 1回目 #1）。構造体は obj からたどれるので、検査の間も GC に回収されない
        var patched: std.ArrayList(Value) = .empty;
        defer patched.deinit(b.rt.gpa);
        try patch(b.rt, obj, ph, obj, &patched);
        if (patched.items.len != 0) if (b.th) |th| {
            const f = if (b.rt.sys_check_structure == Value.nil) Value.nil else b.rt.symbolPtr(b.rt.sys_check_structure).function;
            if (f.isFunctionPointer()) for (patched.items) |s| {
                var argv: [1]Value = .{s};
                if (th.call(f, &argv) == Value.unwind) return error.LispError;
                th.mv_count = 1;
            };
        };
        return obj;
    }

    /// #n#
    pub fn labelRef(b: *ValueBuilder, diag: *Diagnostic, loc: SourceLoc, n: usize) Error!Value {
        const e = b.labelEntry(n) orelse return fail(diag, loc, "#n# のラベルが定義されていません");
        return Runtime.consPtr(e).cdr;
    }

    pub fn integer(b: *ValueBuilder, diag: *Diagnostic, loc: SourceLoc, negative: bool, digits: []const u8, radix: u8) Error!Value {
        _ = diag;
        _ = loc;
        var acc: i64 = 0;
        var small = true;
        for (digits) |c| {
            const m = @mulWithOverflow(acc, @as(i64, radix));
            const s = @addWithOverflow(m[0], digitValue(c));
            if (m[1] != 0 or s[1] != 0) {
                small = false;
                break;
            }
            acc = s[0];
        }
        if (small) {
            const v = if (negative) -acc else acc;
            if (Value.fixnumFits(v)) return Value.fromFixnum(v);
        }
        var m = try std.math.big.int.Managed.init(b.rt.gpa);
        defer m.deinit();
        m.setString(radix, digits) catch |e| switch (e) {
            error.OutOfMemory => return error.OutOfMemory,
            else => unreachable, // 数字は number.parse が確かめている
        };
        if (negative) m.negate();
        return b.rt.makeInteger(m.toConst());
    }

    fn digitValue(c: u8) i64 {
        return switch (c) {
            '0'...'9' => c - '0',
            'a'...'z' => c - 'a' + 10,
            'A'...'Z' => c - 'A' + 10,
            else => unreachable,
        };
    }

    /// 比：約分して、分母が 1 なら整数にする。分母が 0 なら division-by-zero（SBCL 2.6.7 は reader-error）
    pub fn ratio(b: *ValueBuilder, diag: *Diagnostic, loc: SourceLoc, negative: bool, num: []const u8, den: []const u8, radix: u8) Error!Value {
        const big = std.math.big.int;
        const gpa = b.rt.gpa;
        var n = try big.Managed.init(gpa);
        defer n.deinit();
        var d = try big.Managed.init(gpa);
        defer d.deinit();
        n.setString(radix, num) catch |e| switch (e) {
            error.OutOfMemory => return error.OutOfMemory,
            else => unreachable,
        };
        d.setString(radix, den) catch |e| switch (e) {
            error.OutOfMemory => return error.OutOfMemory,
            else => unreachable,
        };
        if (d.eqlZero()) return fail(diag, loc, "比の分母が 0 です");
        if (negative) n.negate();
        var g = try big.Managed.init(gpa);
        defer g.deinit();
        try g.gcd(&n, &d);
        var q = try big.Managed.init(gpa);
        defer q.deinit();
        var r = try big.Managed.init(gpa);
        defer r.deinit();
        try q.divTrunc(&r, &n, &g);
        try n.copy(q.toConst());
        try q.divTrunc(&r, &d, &g);
        try d.copy(q.toConst());
        const nv = try b.rt.makeInteger(n.toConst());
        if (d.toConst().orderAgainstScalar(1) == .eq) return nv;
        // 分子の値（bignum なら確保したもの）は、分母の確保の間、この関数のスタックにあるので GC から守られる
        const dv = try b.rt.makeInteger(d.toConst());
        const v = try b.rt.makeRatioRaw(nv, dv);
        std.mem.doNotOptimizeAway(nv);
        return v;
    }

    pub fn float(b: *ValueBuilder, loc: SourceLoc, value: reader.number.Float) Error!Value {
        _ = loc;
        return switch (value) {
            .single => |f| Value.fromSingle(f),
            .double => |f| try b.rt.makeDouble(f),
        };
    }

    pub fn symbol(b: *ValueBuilder, diag: *Diagnostic, loc: SourceLoc, pkg: reader.PackageRef, name: []const u8) Error!Value {
        const rt = b.rt;
        return switch (pkg) {
            .current => try rt.intern(rt.currentPackage() orelse return fail(diag, loc, "*PACKAGE* の値がパッケージではありません"), name),
            .keyword => try rt.internKeyword(name),
            .uninterned => try rt.makeSymbol(name),
            .named => |n| blk: {
                const p = rt.findPackage(n.name) orelse (if (b.create_packages)
                    // ネイティブのプログラムが起動時に定数を読むとき：まだ作られていないパッケージは、一覧に入れない仮のパッケージにする
                    // （後で make-package・defpackage が同じ名前で作るときに登録する。Codex のレビュー P22 #1）
                    try rt.pendingPackage(n.name)
                else
                    return fail(diag, loc, "そのパッケージはありません"));
                if (n.external) {
                    const f = rt.findSymbol(p, name) orelse return fail(diag, loc, "そのパッケージにシンボルがありません");
                    if (f.status != .external) return fail(diag, loc, "そのシンボルは外部シンボルではありません（:: で指定してください）");
                    break :blk f.symbol;
                }
                break :blk try rt.intern(p, name);
            },
        };
    }

    pub fn nil(b: *ValueBuilder, loc: SourceLoc) Error!Value {
        _ = .{ b, loc };
        return Value.nil;
    }

    /// #P"..."：文字列をパス名にする（Phase 23）
    pub fn pathname(b: *ValueBuilder, diag: *Diagnostic, loc: SourceLoc, obj: Value) Error!Value {
        const pathnames = @import("../primitives/pathnames.zig");
        if (!(obj.isOther() and Runtime.kindOf(obj) == .string)) return fail(diag, loc, "#P の後には文字列が必要です");
        const text = try pathnames.stringUtf8(b.rt.gpa, obj);
        defer b.rt.gpa.free(text);
        return pathnames.parse(b.rt, text);
    }

    pub fn string(b: *ValueBuilder, loc: SourceLoc, utf8: []const u8) Error!Value {
        _ = loc;
        return b.rt.makeString(utf8);
    }

    pub fn character(b: *ValueBuilder, loc: SourceLoc, cp: u21) Error!Value {
        _ = .{ b, loc };
        return Value.fromChar(cp);
    }

    pub fn listBegin(b: *ValueBuilder, loc: SourceLoc) Error!List {
        _ = .{ b, loc };
        return .{};
    }

    pub fn listPush(b: *ValueBuilder, list: *List, item: Value) Error!void {
        const c = try b.rt.cons(item, Value.nil);
        if (list.head == Value.nil) {
            list.head = c;
        } else {
            Runtime.consPtr(list.last).cdr = c;
        }
        list.last = c;
        list.count += 1;
    }

    pub fn listEnd(b: *ValueBuilder, list: *List, tail: ?Value) Error!Value {
        _ = b;
        if (tail) |t| {
            std.debug.assert(list.head != Value.nil);
            Runtime.consPtr(list.last).cdr = t;
        }
        return list.head;
    }

    pub fn vectorEnd(b: *ValueBuilder, list: *List) Error!Value {
        // 要素を Zig のヒープに写さず、ベクタを確保してからリストから直接埋める
        // （写した先は GC が走査しないため。§3.5）
        return b.rt.makeVectorFromList(list.head, list.count);
    }
};

/// 要素の型が文字か（character・base-char・standard-char。それ以外は T に格上げする。make-array と同じ）
fn isCharType(rt: *Runtime, t: Value) bool {
    for ([_][]const u8{ "CHARACTER", "BASE-CHAR", "STANDARD-CHAR" }) |n| {
        if (rt.findSymbol(rt.cl, n)) |f| if (f.symbol == t) return true;
    }
    return false;
}

/// obj の中（cons・単純ベクタ・配列の要素・構造体のスロット）の ph を val に置き換える。循環していてもよい
/// （一度通ったものは見ない）。スロットを置き換えた構造体は patched に足す
fn patch(rt: *Runtime, obj: Value, ph: Value, val: Value, patched: *std.ArrayList(Value)) Error!void {
    const gpa = rt.gpa;
    var seen: std.AutoHashMapUnmanaged(u64, void) = .empty;
    defer seen.deinit(gpa);
    var stack: std.ArrayList(Value) = .empty;
    defer stack.deinit(gpa);
    try stack.append(gpa, obj);
    while (stack.pop()) |x| {
        if (!(x.isCons() or (x.isOther() and (Runtime.kindOf(x) == .simple_vector or Runtime.kindOf(x) == .array or Runtime.kindOf(x) == .structure)))) continue;
        const g = try seen.getOrPut(gpa, x.raw());
        if (g.found_existing) continue;
        if (x.isCons()) {
            const c = Runtime.consPtr(x);
            if (c.car == ph) c.car = val else try stack.append(gpa, c.car);
            if (c.cdr == ph) c.cdr = val else try stack.append(gpa, c.cdr);
        } else if (Runtime.kindOf(x) == .simple_vector) {
            for (Runtime.vectorPtr(x).items()) |*it| {
                if (it.* == ph) it.* = val else try stack.append(gpa, it.*);
            }
        } else if (Runtime.kindOf(x) == .structure) {
            // 構造体（Phase 26）：#1=#S(node :next #1#) のように、スロットに仮の値が入っている
            const object = @import("../values/object.zig");
            const s: *object.Structure = @ptrCast(@alignCast(x.pointer()));
            var changed = false;
            for (s.slots()) |*it| {
                if (it.* == ph) {
                    it.* = val;
                    changed = true;
                } else try stack.append(gpa, it.*);
            }
            if (changed) try patched.append(gpa, x);
        } else {
            const object = @import("../values/object.zig");
            const a: *object.Array = @ptrCast(@alignCast(x.pointer()));
            if (Runtime.kindOf(a.data) == .simple_vector) try stack.append(gpa, a.data);
        }
    }
}

/// テキストから全てのデータを読み、読んだ順のリスト（Lisp の値）で返す（試験用）。
/// 読んでいる間は、それまでに読んだデータを明示的なルートに登録しておく（Zig のヒープには置かない：§3.5）。
/// 返したリストは、呼び出し側が生かしておくこと（ネイティブのスタックにある値は GC のルートになる）。
pub fn readAll(rt: *Runtime, gpa: std.mem.Allocator, text: []const u8, diag: *Diagnostic) Error!Value {
    var src = reader.Source.init(text, 0);
    var b: ValueBuilder = .{ .rt = rt };
    var r = reader.Reader(ValueBuilder).init(gpa, &src, &b, .{});
    defer r.deinit();
    const root = try rt.roots.register(Value.nil);
    defer _ = rt.roots.unregister(root);
    var last = Value.nil;
    while (true) {
        const v = r.read() catch |err| {
            diag.* = r.diagnostic;
            return err;
        } orelse break;
        const c = try rt.cons(v, Value.nil);
        if (last == Value.nil) {
            _ = rt.roots.set(root, c);
        } else {
            Runtime.consPtr(last).cdr = c;
        }
        last = c;
    }
    return rt.roots.get(root).?;
}

const testing = std.testing;

test "vectors and lists of heap objects survive collection during reading (gc stress)" {
    const rt = try Runtime.create(testing.allocator);
    defer rt.destroy();
    // 走査の上端はこの関数のフレーム。値を扱う本体は inline 展開しない別の関数で行う（gc.zig の withRuntime と同じ）
    rt.stack_top = @frameAddress();
    try @call(.never_inline, readVectorsUnderStress, .{rt});
}

fn readVectorsUnderStress(rt: *Runtime) !void {
    rt.heap.stress = true;
    defer rt.heap.stress = false;
    var diag: Diagnostic = .{};
    const text = "#(\"a\" #:b (c \"d\") 1.5d0 #(\"e\")) (\"f\" #:g) \"h\"";
    var x = try readAll(rt, testing.allocator, text, &diag);
    rt.heap.stress = false;
    rt.collect();
    rt.heap.finishSweep();
    var out: std.Io.Writer.Allocating = .init(testing.allocator);
    defer out.deinit();
    const printer = @import("../printer/printer.zig");
    while (x != Value.nil) : (x = Runtime.consPtr(x).cdr) {
        try printer.prin1(rt, &out.writer, Runtime.consPtr(x).car);
        try out.writer.writeByte(' ');
    }
    try testing.expectEqualStrings("#(\"a\" #:B (C \"d\") 1.5d0 #(\"e\")) (\"f\" #:G) \"h\" ", out.written());
}
