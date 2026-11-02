//! マクロまわりの展開（Phase 15。詳細設計 §5.1・§11.1 の 6）。
//! どれも Lisp のフォームを作り、Resolver がそれを解決する。
//!   - backquote（zl-sys:quasiquote・unquote・unquote-splicing・unquote-nsplicing）を list・list*・append などの呼び出しにする
//!   - 分解束縛（defmacro と destructuring-bind のラムダリスト：CLHS 3.4.4・3.4.5）を let* にする
//!   - defmacro を (zl-sys::%defmacro '名前 (lambda (whole env) (let* ...)))にする
//! 作ったフォームと uninterned のシンボルは、作るたびに Pins（GC のルート）に積む（§5.4：Zig のヒープ上の配列は走査されない）。

const std = @import("std");
const Value = @import("../values/value.zig").Value;
const Runtime = @import("../runtime/runtime.zig").Runtime;
const resolver_mod = @import("resolver.zig");
const Resolver = resolver_mod.Resolver;
const Error = resolver_mod.Error;

fn isSymbol(v: Value) bool {
    return v == Value.nil or (v.isOther() and Runtime.kindOf(v) == .symbol);
}

/// フォームを作る道具
pub const Builder = struct {
    r: *Resolver,

    fn pin(b: Builder, v: Value) Error!Value {
        try b.r.pins.pin(v);
        return v;
    }

    pub fn cons(b: Builder, a: Value, d: Value) Error!Value {
        return b.pin(try b.r.rt.cons(a, d));
    }

    /// (items... . tail)
    pub fn listStar(b: Builder, elems: []const Value, tail: Value) Error!Value {
        var acc = tail;
        var i = elems.len;
        while (i > 0) : (i -= 1) acc = try b.r.rt.cons(elems[i - 1], acc);
        return b.pin(acc);
    }

    pub fn list(b: Builder, elems: []const Value) Error!Value {
        return b.listStar(elems, Value.nil);
    }

    pub fn gensym(b: Builder, name: []const u8) Error!Value {
        return b.pin(try b.r.rt.makeSymbol(name));
    }

    pub fn quote(b: Builder, v: Value) Error!Value {
        return b.list(&.{ b.r.rt.syms.quote, v });
    }

    fn sys(b: Builder, name: []const u8) Value {
        return (b.r.rt.findSymbol(b.r.rt.sys, name) orelse std.debug.panic("ZILISP-SYSTEM のシンボルがありません: {s}", .{name})).symbol;
    }
    fn cl(b: Builder, name: []const u8) Value {
        return (b.r.rt.findSymbol(b.r.rt.cl, name) orelse std.debug.panic("CL のシンボルがありません: {s}", .{name})).symbol;
    }
};

fn items(r: *Resolver, list: Value) Error![]Value {
    var out: std.ArrayList(Value) = .empty;
    var x = list;
    while (x.isCons()) : (x = Runtime.consPtr(x).cdr) try out.append(r.arena, Runtime.consPtr(x).car);
    return out.items;
}

/// (name x) の形か
fn isForm(v: Value, name: Value) bool {
    if (!v.isCons() or Runtime.consPtr(v).car != name) return false;
    const rest = Runtime.consPtr(v).cdr;
    return rest.isCons() and Runtime.consPtr(rest).cdr == Value.nil;
}

fn second(v: Value) Value {
    return Runtime.consPtr(Runtime.consPtr(v).cdr).car;
}

// ---------------------------------------------------------------------------
// backquote（CLHS 2.4.6）

const Qq = struct {
    b: Builder,
    quasiquote: Value,
    unquote: Value,
    splicing: Value,
    nsplicing: Value,

    /// x に、深さ depth で効く unquote があるか
    fn hasUnquote(q: *const Qq, x: Value, depth: u32) bool {
        if (x.isOther() and Runtime.kindOf(x) == .simple_vector) {
            for (Runtime.vectorPtr(x).items()) |e| if (q.hasUnquote(e, depth)) return true;
            return false;
        }
        if (!x.isCons()) return false;
        const head = Runtime.consPtr(x).car;
        if (head == q.unquote or head == q.splicing or head == q.nsplicing) {
            if (depth == 1) return true;
            return q.hasUnquote(Runtime.consPtr(x).cdr, depth - 1);
        }
        if (head == q.quasiquote) return q.hasUnquote(Runtime.consPtr(x).cdr, depth + 1);
        return q.hasUnquote(head, depth) or q.hasUnquote(Runtime.consPtr(x).cdr, depth);
    }

    /// x を作るフォームを返す（depth は backquote の入れ子の深さ。1 が一番外側）
    fn expand(q: *const Qq, x: Value, depth: u32) Error!Value {
        const b = q.b;
        if (!q.hasUnquote(x, depth)) return b.quote(x);
        if (x.isOther() and Runtime.kindOf(x) == .simple_vector) {
            // `#(a ,b) → (apply #'vector `(a ,b))
            const elems = try b.list(Runtime.vectorPtr(x).items());
            const lst = try q.expand(elems, depth);
            const fv = try b.list(&.{ b.r.rt.syms.function, b.cl("VECTOR") });
            return b.list(&.{ b.cl("APPLY"), fv, lst });
        }
        const head = Runtime.consPtr(x).car;
        if (isForm(x, q.unquote)) {
            if (depth == 1) return second(x);
            return b.list(&.{ b.cl("LIST"), try b.quote(q.unquote), try q.expand(second(x), depth - 1) });
        }
        if (isForm(x, q.quasiquote)) {
            return b.list(&.{ b.cl("LIST"), try b.quote(q.quasiquote), try q.expand(second(x), depth + 1) });
        }
        if ((head == q.splicing or head == q.nsplicing) and depth == 1)
            return b.r.failForm(",@ と ,. はリストの中でしか使えません", x);

        // リスト：要素を順に、(list ...) の区切りと ,@ の区切りに分け、append でつなぐ
        var segments: std.ArrayList(Value) = .empty;
        var pending: std.ArrayList(Value) = .empty;
        var p = x;
        var tail = Value.nil;
        while (true) {
            if (!p.isCons()) {
                if (p != Value.nil) tail = try q.expand(p, depth);
                break;
            }
            // (a . ,b) は (a unquote b) と読まれる：残りが (unquote b) なら、それが末尾
            if (isForm(p, q.unquote) or isForm(p, q.quasiquote)) {
                tail = try q.expand(p, depth);
                break;
            }
            const e = Runtime.consPtr(p).car;
            if (depth == 1 and (isForm(e, q.splicing) or isForm(e, q.nsplicing))) {
                // ,. は、壊してよい場合の ,@。壊さない append でつないでも意味は変わらない（CLHS 2.4.6）
                if (pending.items.len > 0) {
                    try segments.append(b.r.arena, try b.listStar(&.{b.cl("LIST")}, try b.list(pending.items)));
                    pending.clearRetainingCapacity();
                }
                try segments.append(b.r.arena, second(e));
            } else {
                try pending.append(b.r.arena, try q.expand(e, depth));
            }
            p = Runtime.consPtr(p).cdr;
        }
        if (segments.items.len == 0) {
            if (tail == Value.nil) return b.listStar(&.{b.cl("LIST")}, try b.list(pending.items));
            if (pending.items.len == 0) return tail;
            try pending.append(b.r.arena, tail);
            return b.listStar(&.{b.cl("LIST*")}, try b.list(pending.items));
        }
        if (pending.items.len > 0) try segments.append(b.r.arena, try b.listStar(&.{b.cl("LIST")}, try b.list(pending.items)));
        if (tail != Value.nil) try segments.append(b.r.arena, tail);
        return b.listStar(&.{b.cl("APPEND")}, try b.list(segments.items));
    }
};

/// (zl-sys:quasiquote x) を展開したフォーム
pub fn expandQuasiquote(r: *Resolver, x: Value) Error!Value {
    const rt = r.rt;
    const b: Builder = .{ .r = r };
    const q: Qq = .{
        .b = b,
        .quasiquote = b.sys("QUASIQUOTE"),
        .unquote = b.sys("UNQUOTE"),
        .splicing = b.sys("UNQUOTE-SPLICING"),
        .nsplicing = b.sys("UNQUOTE-NSPLICING"),
    };
    _ = rt;
    return q.expand(x, 1);
}

// ---------------------------------------------------------------------------
// 分解束縛（CLHS 3.4.4 マクロのラムダリスト、3.4.5 destructuring-bind のラムダリスト）

const Destructure = struct {
    b: Builder,
    /// let* の束縛の並び（(変数 初期値) の形）
    bindings: std.ArrayList(Value) = .empty,
    /// エラーの報告に使う、ラムダリスト全体
    whole_ll: Value,

    fn bind(d: *Destructure, v: Value, init: Value) Error!void {
        try d.bindings.append(d.b.r.arena, try d.b.list(&.{ v, init }));
    }

    fn err(d: *Destructure, what: []const u8) Error!Value {
        return d.b.list(&.{ d.b.sys("%DBIND-ERROR"), try d.b.quote(d.b.sys(what)), try d.b.quote(d.whole_ll) });
    }

    fn kw(d: *Destructure, name: []const u8) Value {
        return d.b.cl(name);
    }

    /// ll を、リスト src（シンボル）に対して分解する。macro_env があれば &environment に束縛する
    fn walk(d: *Destructure, ll: Value, src: Value, whole: Value, macro_env: ?Value) Error!void {
        const b = d.b;
        const r = b.r;
        const y = r.rt.syms;
        const consp = b.cl("CONSP");
        var rest = try b.gensym("REST");
        try d.bind(rest, src);
        var state: enum { required, optional, rest, key, aux } = .required;
        var rest_seen = false;
        var keys: std.ArrayList(Value) = .empty;
        var allow_other = false;
        var p = ll;
        var first = true;
        while (p.isCons()) : (p = Runtime.consPtr(p).cdr) {
            const e = Runtime.consPtr(p).car;
            defer first = false;
            if (e == y.@"&whole") {
                if (!first) return r.failForm("&whole はラムダリストの先頭にしか書けません", ll);
                p = Runtime.consPtr(p).cdr;
                if (!p.isCons()) return r.failForm("&whole の後に変数が必要です", ll);
                try d.bindPattern(Runtime.consPtr(p).car, whole);
                continue;
            }
            if (e == y.@"&environment") {
                p = Runtime.consPtr(p).cdr;
                if (!p.isCons() or macro_env == null) return r.failForm("&environment はマクロのラムダリストにだけ書けます", ll);
                try d.bind(Runtime.consPtr(p).car, macro_env.?);
                continue;
            }
            if (e == y.@"&optional") {
                state = .optional;
                continue;
            }
            if (e == y.@"&rest" or e == y.@"&body") {
                p = Runtime.consPtr(p).cdr;
                if (!p.isCons()) return r.failForm("&rest の後に変数が必要です", ll);
                try d.bindPattern(Runtime.consPtr(p).car, rest);
                rest_seen = true;
                state = .rest;
                continue;
            }
            if (e == y.@"&key") {
                state = .key;
                rest_seen = true;
                continue;
            }
            if (e == y.@"&allow-other-keys") {
                allow_other = true;
                continue;
            }
            if (e == y.@"&aux") {
                state = .aux;
                continue;
            }
            switch (state) {
                .required => {
                    // (var (if (consp rest) (car rest) (%dbind-error 'too-few ll))) (rest (cdr rest))
                    const take = try b.list(&.{ y.@"if", try b.list(&.{ consp, rest }), try b.list(&.{ y.car, rest }), try d.err("TOO-FEW") });
                    try d.bindPattern(e, take);
                    const next = try b.gensym("REST");
                    try d.bind(next, try b.list(&.{ y.cdr, rest }));
                    rest = next;
                },
                .optional => {
                    var v = e;
                    var init = Value.nil;
                    var svar = Value.nil;
                    if (e.isCons()) {
                        const parts = try items(r, e);
                        v = parts[0];
                        if (parts.len > 1) init = parts[1];
                        if (parts.len > 2) svar = parts[2];
                    }
                    const has = try b.gensym("HAS");
                    try d.bind(has, try b.list(&.{ consp, rest }));
                    try d.bindPattern(v, try b.list(&.{ y.@"if", has, try b.list(&.{ y.car, rest }), init }));
                    if (svar != Value.nil) try d.bind(svar, has);
                    const next = try b.gensym("REST");
                    try d.bind(next, try b.list(&.{ y.@"if", has, try b.list(&.{ y.cdr, rest }), rest }));
                    rest = next;
                },
                .key => {
                    var v = e;
                    var init = Value.nil;
                    var svar = Value.nil;
                    var key = Value.nil;
                    if (e.isCons()) {
                        const parts = try items(r, e);
                        v = parts[0];
                        if (parts.len > 1) init = parts[1];
                        if (parts.len > 2) svar = parts[2];
                    }
                    if (v.isCons()) {
                        // ((:key var) init svar)
                        const kv = try items(r, v);
                        if (kv.len != 2) return r.failForm("&key の指定の形が正しくありません", e);
                        key = kv[0];
                        v = kv[1];
                    } else {
                        if (!isSymbol(v)) return r.failForm("&key の変数はシンボルでなければなりません", e);
                        key = try r.rt.internKeyword(try symbolNameAlloc(r, v));
                        try r.pins.pin(key);
                    }
                    try keys.append(r.arena, key);
                    const missing = b.sys("%MISSING");
                    const kv = try b.gensym("KEY");
                    try d.bind(kv, try b.list(&.{ b.sys("%GETF-KEY"), src_for_keys(rest), try b.quote(key) }));
                    const absent = try b.list(&.{ y.eq, kv, try b.quote(missing) });
                    try d.bindPattern(v, try b.list(&.{ y.@"if", absent, init, kv }));
                    if (svar != Value.nil) try d.bind(svar, try b.list(&.{ y.not, absent }));
                },
                .aux => {
                    var v = e;
                    var init = Value.nil;
                    if (e.isCons()) {
                        const parts = try items(r, e);
                        v = parts[0];
                        if (parts.len > 1) init = parts[1];
                    }
                    try d.bind(v, init);
                },
                .rest => return r.failForm("&rest の変数の後には &key・&aux しか書けません", ll),
            }
        }
        if (p != Value.nil) {
            // (a . b)：残りを b に束縛する（&rest と同じ）
            try d.bindPattern(p, rest);
            rest_seen = true;
        }
        if (state == .key or keys.items.len > 0 or allow_other) {
            // キーワード引数の並びを検査する（偶数個、知らないキーワード）
            const check = try b.list(&.{ b.sys("%CHECK-KEYS"), rest, try b.quote(try b.list(keys.items)), if (allow_other) r.rt.t else Value.nil, try b.quote(d.whole_ll) });
            try d.bind(try b.gensym("CHECKED"), check);
        }
        if (!rest_seen) {
            // 余った引数があればエラー
            try d.bind(try b.gensym("END"), try b.list(&.{ y.@"if", rest, try d.err("TOO-MANY"), Value.nil }));
        }
    }

    fn src_for_keys(rest: Value) Value {
        return rest;
    }

    /// 変数、または入れ子のラムダリストに束縛する
    fn bindPattern(d: *Destructure, pat: Value, init: Value) Error!void {
        if (pat.isCons()) {
            const sub = try d.b.gensym("SUB");
            try d.bind(sub, init);
            return d.walk(pat, sub, sub, null);
        }
        try d.bind(pat, init);
    }
};

fn symbolNameAlloc(r: *Resolver, sym: Value) Error![]const u8 {
    var buf: std.Io.Writer.Allocating = .init(r.arena);
    Runtime.writeStringUtf8(r.rt.symbolPtr(sym).name, &buf.writer) catch return error.OutOfMemory;
    return buf.written();
}

/// (let* (分解の束縛...) 本体...) を作る。whole はラムダリスト全体に対応する値のフォーム（変数）
fn destructuringLet(r: *Resolver, ll: Value, list_var: Value, whole: Value, env: ?Value, body: []const Value) Error!Value {
    const b: Builder = .{ .r = r };
    var d: Destructure = .{ .b = b, .whole_ll = ll };
    try d.walk(ll, list_var, whole, env);
    const let_form = try b.listStar(&.{ r.rt.syms.@"let*", try b.list(d.bindings.items) }, try b.list(body));
    return let_form;
}

/// (destructuring-bind ラムダリスト 式 本体...) → (let* ((#:src 式) ...) 本体...)
pub fn expandDestructuringBind(r: *Resolver, form: Value, args: []Value) Error!Value {
    if (args.len < 2) return r.failForm("DESTRUCTURING-BIND にはラムダリストと式が必要です", form);
    const b: Builder = .{ .r = r };
    const src = try b.gensym("SRC");
    const inner = try destructuringLet(r, args[0], src, src, null, args[2..]);
    // 式を先に評価して変数に入れ、その変数を分解する
    return b.list(&.{ r.rt.syms.let, try b.list(&.{try b.list(&.{ src, args[1] })}), inner });
}

/// (defmacro 名前 ラムダリスト 本体...) の展開関数のフォーム (lambda (#:whole #:env) (let* ...))
pub fn macroLambda(r: *Resolver, ll: Value, body_forms: []Value) Error!Value {
    const b: Builder = .{ .r = r };
    const whole = try b.gensym("WHOLE");
    const env = try b.gensym("ENV");
    const args = try b.gensym("ARGS");
    // 説明文字列は本体から除く（let* の本体には書けない）
    var body = body_forms;
    if (body.len > 1 and body[0].isOther() and Runtime.kindOf(body[0]) == .string) body = body[1..];
    const inner = try destructuringLet(r, ll, args, whole, env, body);
    const outer = try b.list(&.{ r.rt.syms.let, try b.list(&.{try b.list(&.{ args, try b.list(&.{ r.rt.syms.cdr, whole }) })}), inner });
    return b.list(&.{ r.rt.syms.lambda, try b.list(&.{ whole, env }), outer });
}
