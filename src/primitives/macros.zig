//! マクロまわりのプリミティブ（Phase 15）：%defmacro、分解束縛の補助、macroexpand-1・macroexpand・macro-function、gensym。

const std = @import("std");
const Value = @import("../values/value.zig").Value;
const object = @import("../values/object.zig");
const SymbolFlags = object.SymbolFlags;
const Thread = @import("../runtime/thread.zig").Thread;
const Runtime = @import("../runtime/runtime.zig").Runtime;

fn isSymbol(v: Value) bool {
    return v == Value.nil or (v.isOther() and Runtime.kindOf(v) == .symbol);
}

/// ZILISP-SYSTEM::%DEFMACRO 名前 展開関数 [ラムダリスト]：マクロを定義し、名前を返す。
/// ラムダリストは属性リストの ZILISP-SYSTEM::%MACRO-LAMBDA-LIST に置く（pretty printer が &body の位置を使う。Phase 24）
pub fn sysDefmacro(th: *Thread, args: []const Value) Value {
    const name = args[0];
    if (!isSymbol(name) or name == Value.nil) return th.typeError(name, th.rt.syms.symbol);
    const s = th.rt.symbolPtr(name);
    // CL パッケージのシンボルには定義できない（標準ライブラリの読み込み中を除く。CLHS 11.1.2.1.2）
    if (s.package == th.rt.cl.obj and !th.rt.booting)
        return th.signal(.package_error, "COMMON-LISP パッケージのシンボルにマクロは定義できません", name, Value.unbound);
    s.function = args[1];
    s.header.flags |= SymbolFlags.macro;
    s.header.flags &= ~SymbolFlags.unimplemented;
    if (args.len > 2) {
        const rt = th.rt;
        const key = rt.intern(rt.sys, "%MACRO-LAMBDA-LIST") catch return th.outOfMemory();
        // 属性リストの値を置き換える（なければ先頭に足す）
        var x = s.plist;
        while (x.isCons() and Runtime.consPtr(x).cdr.isCons()) : (x = Runtime.consPtr(Runtime.consPtr(x).cdr).cdr) {
            if (Runtime.consPtr(x).car == key) {
                Runtime.consPtr(Runtime.consPtr(x).cdr).car = args[2];
                return name;
            }
        }
        const tail = rt.cons(args[2], s.plist) catch return th.outOfMemory();
        rt.symbolPtr(name).plist = rt.cons(key, tail) catch return th.outOfMemory();
    }
    return name;
}

/// ZILISP-SYSTEM::%DBIND-ERROR 種類 ラムダリスト：分解束縛の引数の数の誤り（CLHS 3.5.1.2・3.5.1.3 の program-error）
pub fn sysDbindError(th: *Thread, args: []const Value) Value {
    const kind = args[0];
    const too_few = kind == (th.rt.findSymbol(th.rt.sys, "TOO-FEW") orelse unreachable).symbol;
    return th.signal(.program_error, if (too_few) "引数が足りません（ラムダリスト）" else "引数が多すぎます（ラムダリスト）", args[1], Value.unbound);
}

/// ZILISP-SYSTEM::%GETF-KEY 並び キーワード：キーワード引数の値（最も左のもの）。なければ %MISSING
pub fn sysGetfKey(th: *Thread, args: []const Value) Value {
    var x = args[0];
    while (x.isCons()) {
        const c = Runtime.consPtr(x);
        if (!c.cdr.isCons()) break;
        if (c.car == args[1]) return Runtime.consPtr(c.cdr).car;
        x = Runtime.consPtr(c.cdr).cdr;
    }
    return th.rt.sys_missing;
}

/// ZILISP-SYSTEM::%CHECK-KEYS 並び 知っているキーワード allow ラムダリスト：
/// 並びが偶数個で、知らないキーワードがないこと（:allow-other-keys が真なら許す。CLHS 3.4.1.4）
pub fn sysCheckKeys(th: *Thread, args: []const Value) Value {
    const plist = args[0];
    const known = args[1];
    var allow = args[2] != Value.nil;
    const allow_kw = th.rt.internKeyword("ALLOW-OTHER-KEYS") catch return th.outOfMemory();
    var x = plist;
    // :allow-other-keys の値（最も左のもの）
    while (x.isCons()) {
        const c = Runtime.consPtr(x);
        if (!c.cdr.isCons()) return th.signal(.program_error, "キーワード引数の数が奇数です", args[3], Value.unbound);
        if (c.car == allow_kw) {
            if (Runtime.consPtr(c.cdr).car != Value.nil) allow = true;
            break;
        }
        x = Runtime.consPtr(c.cdr).cdr;
    }
    x = plist;
    while (x.isCons()) {
        const c = Runtime.consPtr(x);
        if (!c.cdr.isCons()) return th.signal(.program_error, "キーワード引数の数が奇数です", args[3], Value.unbound);
        if (!allow and c.car != allow_kw) {
            var k = known;
            var found = false;
            while (k.isCons()) : (k = Runtime.consPtr(k).cdr) {
                if (Runtime.consPtr(k).car == c.car) found = true;
            }
            if (!found) return th.signal(.program_error, "知らないキーワード引数です", c.car, Value.unbound);
        }
        x = Runtime.consPtr(c.cdr).cdr;
    }
    if (x != Value.nil) return th.signal(.program_error, "キーワード引数の並びがドット対で終わっています", args[3], Value.unbound);
    return Value.nil;
}

/// form を1回だけ展開する。展開したら expanded に真を書く
fn expand1(th: *Thread, form: Value, expanded: *bool) Value {
    expanded.* = false;
    if (!form.isCons()) return form;
    const head = Runtime.consPtr(form).car;
    if (!isSymbol(head) or head == Value.nil) return form;
    const s = th.rt.symbolPtr(head);
    if (!s.hasFlag(SymbolFlags.macro) or s.function == Value.unbound) return form;
    const argv = [_]Value{ form, Value.nil };
    const r = th.call(s.function, &argv);
    if (r != Value.unwind) expanded.* = true;
    return r;
}

/// 2つ目の値を置く（多値の受け取りは Phase 17。今は主値だけが使われる）
fn twoValues(th: *Thread, primary: Value, second: Value) Value {
    th.mv[1] = second;
    th.mv_count = 2;
    return primary;
}

/// macroexpand-1 フォーム [環境]（環境は Phase 15 では大域の環境だけ）
pub fn macroexpand1(th: *Thread, args: []const Value) Value {
    var expanded = false;
    const r = expand1(th, args[0], &expanded);
    if (r == Value.unwind) return r;
    return twoValues(th, r, th.rt.boolean(expanded));
}

pub fn macroexpand(th: *Thread, args: []const Value) Value {
    var form = args[0];
    var any = false;
    while (true) {
        var expanded = false;
        const r = expand1(th, form, &expanded);
        if (r == Value.unwind) return r;
        if (!expanded) break;
        any = true;
        form = r;
    }
    return twoValues(th, form, th.rt.boolean(any));
}

/// macro-function シンボル：マクロなら展開関数、そうでなければ NIL
pub fn macroFunction(th: *Thread, args: []const Value) Value {
    const name = args[0];
    if (!isSymbol(name)) return th.typeError(name, th.rt.syms.symbol);
    const s = th.rt.symbolPtr(name);
    if (s.hasFlag(SymbolFlags.macro) and s.function != Value.unbound) return s.function;
    return Value.nil;
}

/// gensym [接頭辞]：#:G番号 の uninterned のシンボル。番号は *gensym-counter*（CLHS gensym）
pub fn gensym(th: *Thread, args: []const Value) Value {
    const rt = th.rt;
    const counter_sym = (rt.findSymbol(rt.cl, "*GENSYM-COUNTER*") orelse unreachable).symbol;
    const cs = rt.symbolPtr(counter_sym);
    if (!cs.value.isFixnum()) cs.value = Value.fromFixnum(1);
    var prefix_buf: [256]u8 = undefined;
    var prefix: []const u8 = "G";
    var n = cs.value.asFixnum();
    if (args.len == 1) {
        const a = args[0];
        if (a.isFixnum()) {
            n = a.asFixnum();
        } else if (a.isOther() and Runtime.kindOf(a) == .string) {
            var w: std.Io.Writer = .fixed(&prefix_buf);
            Runtime.writeStringUtf8(a, &w) catch return th.signal(.unimplemented, "gensym の接頭辞が長すぎます", a, Value.unbound);
            prefix = w.buffered();
        } else return th.typeError(a, rt.syms.integer);
    }
    if (args.len == 0 or !args[0].isFixnum()) cs.value = Value.fromFixnum(cs.value.asFixnum() + 1);
    var name_buf: [300]u8 = undefined;
    const name = std.fmt.bufPrint(&name_buf, "{s}{d}", .{ prefix, n }) catch unreachable;
    return rt.makeSymbol(name) catch th.outOfMemory();
}

/// 説明の文字列と値でエラーを記録する（Lisp で書いた標準ライブラリから使う）
fn signalWithDetail(th: *Thread, kind: @import("../runtime/thread.zig").ErrorKind, detail: Value, datum: Value) Value {
    return th.signalDetail(kind, "", datum, Value.unbound, detail);
}

/// ZILISP-SYSTEM::%MACRO-FORM-ERROR 説明 値：マクロのフォームの形の誤り（program-error）
pub fn sysMacroFormError(th: *Thread, args: []const Value) Value {
    return signalWithDetail(th, .program_error, args[0], args[1]);
}

/// ZILISP-SYSTEM::%MACRO-SIMPLE-ERROR 説明 値：マクロのフォームの形の誤り（simple-error。SBCL 2.6.7 の do・do*・psetq と同じ。
/// Phase 25）
pub fn sysMacroSimpleError(th: *Thread, args: []const Value) Value {
    return signalWithDetail(th, .simple_error, args[0], args[1]);
}

/// ZILISP-SYSTEM::%UNIMPLEMENTED-ERROR 説明 値：未実装の機能
pub fn sysUnimplementedError(th: *Thread, args: []const Value) Value {
    return signalWithDetail(th, .unimplemented, args[0], args[1]);
}
