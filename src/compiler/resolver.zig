//! Resolver：フォーム（Value）から Core IR を作る（詳細設計 §5.1）。
//! 名前解決、捕捉（captured）と代入（assigned）の計算、特殊演算子の解釈を行う。
//!
//! Phase 08 の範囲
//!   特殊演算子：quote if progn let let*（Phase 09）setq function、および lambda（CL ではマクロ）
//!   関数の呼び出し、((lambda ...) ...)、CL の一部の関数の高速経路（ir.Prim）
//! 範囲外のものは、明示的なエラーにする（基本設計 §3.1）。
//!   ほかの特殊演算子・マクロ（Phase 15〜）、&optional などのラムダリストキーワード（Phase 17）
//! 特殊変数（Phase 14）：defvar・defparameter で宣言したシンボル、special 宣言した変数の束縛は動的束縛にする。
//!   範囲の中の特殊変数は、special の印の付いた Var で表し、参照・代入は global_ref・global_set にする
//! 宣言は ignore・ignorable・type・ftype・optimize・inline・notinline・dynamic-extent と型名による宣言を
//! 受け付けて無視する（CLHS 3.3.1：これらを無視しても意味は変わらない）。

const std = @import("std");
const Value = @import("../values/value.zig").Value;
const object = @import("../values/object.zig");
const SymbolFlags = object.SymbolFlags;
const runtime = @import("../runtime/runtime.zig");
const Runtime = runtime.Runtime;
const thread_mod = @import("../runtime/thread.zig");
const Thread = thread_mod.Thread;
const ErrorKind = thread_mod.ErrorKind;
const ir = @import("ir.zig");
const Node = ir.Node;
const Var = ir.Var;
const Lambda = ir.Lambda;

pub const Error = error{ LispError, OutOfMemory };

/// inline・notinline の宣言（§5.3：尊重する）
const InlineDecl = struct { sym: Value, notinline: bool };

/// 本体の先頭の宣言のうち、意味に影響するもの
const Decls = struct {
    inlines: std.ArrayList(InlineDecl) = .empty,
    /// special 宣言した名前
    specials: std.ArrayList(Value) = .empty,

    fn isSpecial(d: *const Decls, name: Value) bool {
        for (d.specials.items) |n| if (n == name) return true;
        return false;
    }
};

/// 局所関数（flet・labels）の束縛。関数の値は、名前の見えない局所変数 v に入れる
const FnBinding = struct { name: Value, v: *Var };

/// レキシカルな範囲（let・lambda・flet・labels ごとに1つ）
const Scope = struct {
    parent: ?*const Scope,
    lambda: *Lambda,
    vars: []const *Var,
    /// 関数の名前空間の束縛（flet・labels）
    fns: []const FnBinding = &.{},
    /// この範囲の本体の先頭で宣言された inline・notinline（後のものが優先）
    inline_decls: []const InlineDecl = &.{},

    /// 関数 sym が notinline と宣言されているか（内側の範囲の宣言が優先）
    fn isNotinline(scope: *const Scope, sym: Value) bool {
        var s: ?*const Scope = scope;
        while (s) |sc| : (s = sc.parent) {
            var i = sc.inline_decls.len;
            while (i > 0) : (i -= 1) {
                if (sc.inline_decls[i - 1].sym == sym) return sc.inline_decls[i - 1].notinline;
            }
        }
        return false;
    }
};

pub const Resolver = struct {
    th: *Thread,
    rt: *Runtime,
    arena: std.mem.Allocator,

    pub fn init(th: *Thread, arena: std.mem.Allocator) Resolver {
        return .{ .th = th, .rt = th.rt, .arena = arena };
    }

    fn fail(r: *Resolver, kind: ErrorKind, message: []const u8, datum: Value) Error {
        _ = r.th.signal(kind, message, datum, Value.unbound);
        return error.LispError;
    }

    fn node(r: *Resolver, kind: Node.Kind) Error!*Node {
        const n = try r.arena.create(Node);
        n.* = .{ .kind = kind };
        return n;
    }

    /// トップレベルのフォームを、引数のない lambda の本体として解決する
    pub fn toplevel(r: *Resolver, form: Value) Error!*Lambda {
        const l = try r.arena.create(Lambda);
        l.* = .{ .parent = null };
        const scope: Scope = .{ .parent = null, .lambda = l, .vars = &.{} };
        l.body = try r.resolve(form, &scope);
        return l;
    }

    // ------------------------------------------------------------------
    // 補助

    fn isSymbol(v: Value) bool {
        return v == Value.nil or (v.isOther() and Runtime.kindOf(v) == .symbol);
    }

    /// 真リストを配列にする。ドット対で終わるリストはエラー
    fn listItems(r: *Resolver, list: Value, what: []const u8) Error![]Value {
        var items: std.ArrayList(Value) = .empty;
        var x = list;
        while (x.isCons()) : (x = Runtime.consPtr(x).cdr) {
            try items.append(r.arena, Runtime.consPtr(x).car);
        }
        if (x != Value.nil) return r.fail(.program_error, what, list);
        return items.items;
    }

    /// 局所関数を探す（内側の束縛が優先。同じ flet に同じ名前が2つあれば後のもの）
    fn lookupFn(scope: *const Scope, name: Value) ?*Var {
        var s: ?*const Scope = scope;
        while (s) |sc| : (s = sc.parent) {
            var i = sc.fns.len;
            while (i > 0) : (i -= 1) {
                if (sc.fns[i - 1].name == name) return sc.fns[i - 1].v;
            }
        }
        return null;
    }

    fn lookup(scope: *const Scope, name: Value) ?*Var {
        var s: ?*const Scope = scope;
        while (s) |sc| : (s = sc.parent) {
            var i = sc.vars.len;
            while (i > 0) : (i -= 1) {
                if (sc.vars[i - 1].name == name) return sc.vars[i - 1];
            }
        }
        return null;
    }

    /// 変数 v を、lambda `from` の中から参照する。外側の lambda の変数なら、途中の lambda すべてに捕捉を登録する
    fn reference(r: *Resolver, v: *Var, from: *Lambda) Error!void {
        if (v.owner == from) return;
        v.captured = true;
        var l: ?*Lambda = from;
        while (l) |lam| : (l = lam.parent) {
            if (lam == v.owner) break;
            if (lam.captureIndex(v) == null) try lam.captures.append(r.arena, v);
        }
    }

    /// 束縛する変数の名前を検査する（引数・let の変数）
    fn checkBindable(r: *Resolver, name: Value) Error!void {
        if (!isSymbol(name)) return r.fail(.program_error, "変数の名前はシンボルでなければなりません", name);
        const s = r.rt.symbolPtr(name);
        if (name == Value.nil or s.hasFlag(SymbolFlags.constant) or s.hasFlag(SymbolFlags.keyword))
            return r.fail(.program_error, "定数は束縛できません", name);
    }

    /// 束縛を動的束縛にするか（defvar などで特殊変数と宣言したシンボル、または束縛の special 宣言がある）
    fn bindsSpecially(r: *Resolver, name: Value, decls: *const Decls) bool {
        return r.rt.symbolPtr(name).hasFlag(SymbolFlags.special) or decls.isSpecial(name);
    }

    fn specialVar(r: *Resolver, name: Value, l: *Lambda) Error!*Var {
        const v = try r.arena.create(Var);
        v.* = .{ .name = name, .owner = l, .slot = 0, .special = true };
        return v;
    }

    /// 範囲の変数の一覧：束縛した変数と、束縛しない名前の special 宣言（自由な宣言：その範囲で参照を特殊変数にする）
    fn scopeVars(r: *Resolver, bound: []*Var, decls: *const Decls, l: *Lambda) Error![]*Var {
        var list: std.ArrayList(*Var) = .empty;
        try list.appendSlice(r.arena, bound);
        outer: for (decls.specials.items) |name| {
            for (bound) |v| if (v.name == name) continue :outer;
            try list.append(r.arena, try r.specialVar(name, l));
        }
        return list.items;
    }

    fn isLambdaListKeyword(r: *Resolver, v: Value) bool {
        const y = r.rt.syms;
        inline for (.{ "&optional", "&rest", "&key", "&aux", "&body", "&whole", "&environment", "&allow-other-keys" }) |f| {
            if (v == @field(y, f)) return true;
        }
        return false;
    }

    /// 本体の先頭の宣言（と、許す場合は説明文字列1つ）を読み飛ばし、残りのフォームを返す（CLHS 3.4.11）。
    /// 説明文字列は、後ろにフォームがある場合だけ説明文字列とみなす（最後のフォームなら値）。2つ目の文字列は本体のフォーム。
    /// inline・notinline の宣言は decls に加える
    fn parseBody(r: *Resolver, forms: []Value, allow_doc: bool, decls: *Decls) Error![]Value {
        var i: usize = 0;
        var doc_seen = false;
        while (i < forms.len) : (i += 1) {
            const f = forms[i];
            if (allow_doc and !doc_seen and f.isOther() and Runtime.kindOf(f) == .string and i + 1 < forms.len) {
                doc_seen = true;
                continue;
            }
            if (!(f.isCons() and Runtime.consPtr(f).car == r.rt.syms.declare)) break;
            const specs = try r.listItems(Runtime.consPtr(f).cdr, "宣言の形が正しくありません");
            for (specs) |spec| try r.checkDeclaration(spec, decls);
        }
        return forms[i..];
    }

    fn checkDeclaration(r: *Resolver, spec: Value, decls: *Decls) Error!void {
        if (!spec.isCons()) return r.fail(.program_error, "宣言の形が正しくありません", spec);
        const y = r.rt.syms;
        const id = Runtime.consPtr(spec).car;
        if (id == y.special) {
            const names = try r.listItems(Runtime.consPtr(spec).cdr, "宣言の形が正しくありません");
            for (names) |n| {
                try r.checkBindable(n);
                try decls.specials.append(r.arena, n);
            }
            return;
        }
        if (id == y.@"inline" or id == y.notinline) {
            const names = try r.listItems(Runtime.consPtr(spec).cdr, "宣言の形が正しくありません");
            for (names) |n| {
                // (setf 名前) の関数は Phase 16 で扱う。今は高速経路の対象にならないので記録しない
                if (isSymbol(n)) try decls.inlines.append(r.arena, .{ .sym = n, .notinline = id == y.notinline });
            }
        }
        // ignore・ignorable・type・ftype・optimize・dynamic-extent、型名による宣言は無視する
        // （CLHS 3.3.1：無視しても意味は変わらない）
    }

    // ------------------------------------------------------------------
    // 解決

    fn resolve(r: *Resolver, form: Value, scope: *const Scope) Error!*Node {
        if (form.isCons()) return r.resolveCompound(form, scope);
        if (isSymbol(form)) return r.resolveSymbol(form, scope);
        // 自己評価するオブジェクト（数、文字、文字列、ベクタなど）
        return r.node(.{ .constant = form });
    }

    fn resolveSymbol(r: *Resolver, sym: Value, scope: *const Scope) Error!*Node {
        if (sym == Value.nil) return r.node(.{ .constant = Value.nil });
        const s = r.rt.symbolPtr(sym);
        if (s.hasFlag(SymbolFlags.keyword)) return r.node(.{ .constant = sym });
        if (s.hasFlag(SymbolFlags.constant) and s.value != Value.unbound) return r.node(.{ .constant = s.value });
        if (!s.hasFlag(SymbolFlags.special)) {
            if (lookup(scope, sym)) |v| {
                if (!v.special) {
                    try r.reference(v, scope.lambda);
                    return r.node(.{ .lex_ref = v });
                }
            }
        }
        // 特殊変数（範囲の中の special 宣言を含む）、または宣言のない自由変数（大域の値。SBCL と同じく特殊変数として参照する）
        return r.node(.{ .global_ref = sym });
    }

    fn resolveBody(r: *Resolver, forms: []const Value, scope: *const Scope) Error!*Node {
        if (forms.len == 1) return r.resolve(forms[0], scope);
        const nodes = try r.arena.alloc(*Node, forms.len);
        for (forms, 0..) |f, i| nodes[i] = try r.resolve(f, scope);
        return r.node(.{ .progn = nodes });
    }

    fn resolveCompound(r: *Resolver, form: Value, scope: *const Scope) Error!*Node {
        const head = Runtime.consPtr(form).car;
        const args = try r.listItems(Runtime.consPtr(form).cdr, "フォームがドット対で終わっています");
        const y = r.rt.syms;

        if (isSymbol(head)) {
            if (head == y.quote) {
                if (args.len != 1) return r.fail(.program_error, "QUOTE の引数は1つです", form);
                return r.node(.{ .constant = args[0] });
            }
            if (head == y.@"if") {
                if (args.len < 2 or args.len > 3) return r.fail(.program_error, "IF の引数は2つか3つです", form);
                return r.node(.{ .if_ = .{
                    .cond = try r.resolve(args[0], scope),
                    .then = try r.resolve(args[1], scope),
                    .else_ = if (args.len == 3) try r.resolve(args[2], scope) else try r.node(.{ .constant = Value.nil }),
                } });
            }
            if (head == y.progn) {
                if (args.len == 0) return r.node(.{ .constant = Value.nil });
                return r.resolveBody(args, scope);
            }
            if (head == y.let) return r.resolveLet(form, args, scope);
            if (head == y.@"let*") return r.resolveLetStar(form, args, scope);
            if (head == y.setq) return r.resolveSetq(form, args, scope);
            if (head == y.function) return r.resolveFunction(form, args, scope);
            if (head == y.lambda) return r.node(.{ .lambda = try r.resolveLambda(form, scope) });
            if (head == y.declare) return r.fail(.program_error, "DECLARE はこの位置には書けません", form);
            if (head == y.defun) return r.resolveDefun(form, args, scope);
            if (head == y.defvar) return r.resolveDefvar(form, args, scope, false);
            if (head == y.defparameter) return r.resolveDefvar(form, args, scope, true);
            if (head == y.progv) return r.resolveProgv(form, args, scope);
            if (head == y.flet) return r.resolveLocalFunctions(form, args, scope, false);
            if (head == y.labels) return r.resolveLocalFunctions(form, args, scope, true);
            // 局所関数の呼び出し（大域の関数・マクロより優先：CLHS 3.1.2.1.2.3）
            if (lookupFn(scope, head)) |v| {
                try r.reference(v, scope.lambda);
                return r.node(.{ .call = .{
                    .callee = try r.node(.{ .lex_ref = v }),
                    .args = try r.resolveArgs(args, scope),
                } });
            }

            const s = r.rt.symbolPtr(head);
            if (s.hasFlag(SymbolFlags.special_operator))
                return r.fail(.unimplemented, "この特殊演算子は未実装です", head);
            if (s.hasFlag(SymbolFlags.macro))
                return r.fail(.unimplemented, "このマクロは未実装です（defmacro とマクロ展開は Phase 15 で実装予定）", head);
            return r.resolveCall(head, args, scope);
        }
        if (head.isCons() and Runtime.consPtr(head).car == y.lambda) {
            const l = try r.resolveLambda(head, scope);
            return r.node(.{ .call = .{
                .callee = try r.node(.{ .lambda = l }),
                .args = try r.resolveArgs(args, scope),
            } });
        }
        return r.fail(.program_error, "関数の位置に書けないものです", head);
    }

    fn resolveArgs(r: *Resolver, args: []const Value, scope: *const Scope) Error![]*Node {
        if (args.len >= thread_mod.call_arguments_limit)
            return r.fail(.program_error, "引数が多すぎます（call-arguments-limit を超えています）", Value.fromFixnum(@intCast(args.len)));
        const nodes = try r.arena.alloc(*Node, args.len);
        for (args, 0..) |a, i| nodes[i] = try r.resolve(a, scope);
        return nodes;
    }

    /// CL の関数を高速経路にできるか（CL パッケージの関数の再定義は未定義の動作：CLHS 11.1.2.1.2）
    fn primFor(r: *Resolver, sym: Value, nargs: usize, scope: *const Scope) ?ir.Prim {
        const y = r.rt.syms;
        if (scope.isNotinline(sym)) return null;
        if (nargs == 1) {
            if (sym == y.car) return .car;
            if (sym == y.cdr) return .cdr;
            if (sym == y.not or sym == y.null) return .not;
            if (sym == y.@"1+") return .add1;
            if (sym == y.@"1-") return .sub1;
        } else if (nargs == 2) {
            if (sym == y.cons) return .cons;
            if (sym == y.eq) return .eq;
            if (sym == y.@"+") return .add2;
            if (sym == y.@"-") return .sub2;
            if (sym == y.@"<") return .lt2;
            if (sym == y.@">") return .gt2;
            if (sym == y.@"<=") return .le2;
            if (sym == y.@">=") return .ge2;
            if (sym == y.@"=") return .numeq2;
        }
        return null;
    }

    fn resolveCall(r: *Resolver, sym: Value, args: []const Value, scope: *const Scope) Error!*Node {
        const nodes = try r.resolveArgs(args, scope);
        if (r.primFor(sym, args.len, scope)) |op| return r.node(.{ .prim = .{ .op = op, .args = nodes } });
        // (funcall f a ...) は、関数の値を直接呼ぶ命令にする
        if (sym == r.rt.syms.funcall and nodes.len >= 1 and !scope.isNotinline(sym)) {
            return r.node(.{ .call = .{ .callee = nodes[0], .args = nodes[1..] } });
        }
        return r.node(.{ .call_global = .{ .sym = sym, .args = nodes } });
    }

    fn resolveFunction(r: *Resolver, form: Value, args: []Value, scope: *const Scope) Error!*Node {
        if (args.len != 1) return r.fail(.program_error, "FUNCTION の引数は1つです", form);
        const name = args[0];
        if (isSymbol(name)) {
            if (name == Value.nil) return r.fail(.program_error, "NIL は関数の名前にできません", form);
            if (lookupFn(scope, name)) |v| {
                try r.reference(v, scope.lambda);
                return r.node(.{ .lex_ref = v });
            }
            return r.node(.{ .global_fn = name });
        }
        if (name.isCons() and Runtime.consPtr(name).car == r.rt.syms.lambda)
            return r.node(.{ .lambda = try r.resolveLambda(name, scope) });
        return r.fail(.unimplemented, "この関数の名前は未実装です（(setf 名前) は Phase 16 で実装予定）", name);
    }

    fn resolveLambda(r: *Resolver, form: Value, scope: *const Scope) Error!*Lambda {
        const parts = try r.listItems(Runtime.consPtr(form).cdr, "LAMBDA の形が正しくありません");
        if (parts.len < 1) return r.fail(.program_error, "LAMBDA にはラムダリストが必要です", form);
        return r.resolveLambdaParts(parts, Value.nil, .none, scope);
    }

    /// parts = (ラムダリスト 本体...)。fn_name は defun などで付ける関数の名前（無名なら NIL）
    fn resolveLambdaParts(r: *Resolver, parts: []Value, fn_name: Value, fn_kind: Lambda.FnKind, scope: *const Scope) Error!*Lambda {
        const params = try r.listItems(parts[0], "ラムダリストがドット対で終わっています");
        const l = try r.arena.create(Lambda);
        l.* = .{ .parent = scope.lambda, .name = parts[0], .fn_name = fn_name, .fn_kind = fn_kind };
        var decls: Decls = .{};
        const body = try r.parseBody(parts[1..], true, &decls);
        // 引数の変数。特殊変数の引数は、名前の見えない局所変数で受け取り、本体を (let ((*x* 引数)) ...) で囲む
        const params_vars = try r.arena.alloc(*Var, params.len);
        const scope_vars = try r.arena.alloc(*Var, params.len);
        var specials: std.ArrayList(*Var) = .empty;
        var special_inits: std.ArrayList(*Node) = .empty;
        for (params, 0..) |p, i| {
            if (r.isLambdaListKeyword(p))
                return r.fail(.unimplemented, "ラムダリストのキーワードは未実装です（Phase 17 で実装予定）", p);
            try r.checkBindable(p);
            for (params[0..i]) |q| {
                if (q == p) return r.fail(.program_error, "ラムダリストに同じ変数が2回あります", p);
            }
            const v = try r.arena.create(Var);
            if (r.bindsSpecially(p, &decls)) {
                v.* = .{ .name = Value.unbound, .owner = l, .slot = l.newSlot() };
                const sv = try r.specialVar(p, l);
                scope_vars[i] = sv;
                try specials.append(r.arena, sv);
                try special_inits.append(r.arena, try r.node(.{ .lex_ref = v }));
            } else {
                v.* = .{ .name = p, .owner = l, .slot = l.newSlot() };
                scope_vars[i] = v;
            }
            params_vars[i] = v;
        }
        l.params = params_vars;
        const depth_slot = if (specials.items.len > 0) l.newSlot() else ir.no_slot;
        const inner: Scope = .{ .parent = scope, .lambda = l, .vars = try r.scopeVars(scope_vars, &decls, l), .inline_decls = decls.inlines.items };
        var body_node = if (body.len == 0) try r.node(.{ .constant = Value.nil }) else try r.resolveBody(body, &inner);
        if (specials.items.len > 0) {
            body_node = try r.node(.{ .let_ = .{ .vars = specials.items, .inits = special_inits.items, .body = body_node, .depth_slot = depth_slot } });
        }
        l.body = body_node;
        return l;
    }

    /// defvar・defparameter（Zig で書いたブートストラップ用のマクロ：§11.1 の 6。Phase 14）。
    /// 名前を特殊変数と宣言する。この宣言はコンパイルの時点で行う（同じフォームの後ろの部分や、後のフォームの
    /// コンパイルで、束縛が動的束縛になるように：CLHS defvar「the compiler must recognize that the name has been proclaimed special」）。
    ///   (defparameter 名前 初期値 [説明])  → (progn (setq 名前 初期値) '名前)
    ///   (defvar 名前 [初期値 [説明]])      → (progn (if (boundp '名前) nil (setq 名前 初期値)) '名前)
    fn resolveDefvar(r: *Resolver, form: Value, args: []Value, scope: *const Scope, parameter: bool) Error!*Node {
        const min: usize = if (parameter) 2 else 1;
        if (args.len < min or args.len > 3) return r.fail(.program_error, "DEFVAR・DEFPARAMETER の引数の数が正しくありません", form);
        const name = args[0];
        try r.checkBindable(name);
        const s = r.rt.symbolPtr(name);
        s.header.flags |= SymbolFlags.special;
        const name_node = try r.node(.{ .constant = name });
        if (args.len == 1) return name_node;
        const set = try r.node(.{ .global_set = .{ .sym = name, .value = try r.resolve(args[1], scope) } });
        const forms = try r.arena.alloc(*Node, 2);
        forms[1] = name_node;
        if (parameter) {
            forms[0] = set;
        } else {
            const call_args = try r.arena.alloc(*Node, 1);
            call_args[0] = name_node;
            forms[0] = try r.node(.{ .if_ = .{
                .cond = try r.node(.{ .call_global = .{ .sym = r.rt.syms.boundp, .args = call_args } }),
                .then = try r.node(.{ .constant = Value.nil }),
                .else_ = set,
            } });
        }
        return r.node(.{ .progn = forms });
    }

    /// progv（特殊演算子。Phase 14）：(progv シンボルのリスト 値のリスト 本体...)
    fn resolveProgv(r: *Resolver, form: Value, args: []Value, scope: *const Scope) Error!*Node {
        if (args.len < 2) return r.fail(.program_error, "PROGV にはシンボルのリストと値のリストが必要です", form);
        const l = scope.lambda;
        const saved = l.next_slot;
        const syms = try r.resolve(args[0], scope);
        const vals = try r.resolve(args[1], scope);
        const depth_slot = l.newSlot();
        const body = if (args.len == 2) try r.node(.{ .constant = Value.nil }) else try r.resolveBody(args[2..], scope);
        l.next_slot = saved;
        return r.node(.{ .progv = .{ .syms = syms, .vals = vals, .body = body, .depth_slot = depth_slot } });
    }

    /// defun（Zig で書いたブートストラップ用のマクロ：§11.1 の 6）。
    /// (defun 名前 ラムダリスト 本体...) を (zl-sys::%defun '名前 (lambda ラムダリスト 本体...)) にする。
    /// 関数の名前を付けた lambda にする（印字は #<FUNCTION 名前>）。
    /// 本体を (block 名前 ...) で囲む処理は、block を実装する Phase 18 で加える
    fn resolveDefun(r: *Resolver, form: Value, args: []Value, scope: *const Scope) Error!*Node {
        if (args.len < 2) return r.fail(.program_error, "DEFUN には名前とラムダリストが必要です", form);
        const name = args[0];
        if (name.isCons()) return r.fail(.unimplemented, "(setf 名前) の関数の定義は未実装です（Phase 16 で実装予定）", name);
        if (!isSymbol(name) or name == Value.nil) return r.fail(.program_error, "関数の名前はシンボルでなければなりません", name);
        const l = try r.resolveLambdaParts(args[1..], name, .global, scope);
        const call_args = try r.arena.alloc(*Node, 2);
        call_args[0] = try r.node(.{ .constant = name });
        call_args[1] = try r.node(.{ .lambda = l });
        return r.node(.{ .call_global = .{ .sym = r.rt.sys_defun, .args = call_args } });
    }

    /// flet・labels（局所関数）。
    /// flet：関数の本体は外側の範囲で解決する（自分自身も、同じ flet の他の関数も見えない）。
    ///       IR は (let ((f1 (lambda ...)) ...) 本体) と同じ形。
    /// labels：関数の本体から、同じ labels のすべての関数が見える（再帰・相互再帰）。
    ///       IR は (let ((f1 nil) ...) (setq f1 (lambda ...)) ... 本体) と同じ形。互いに参照する関数の変数は、
    ///       捕捉され代入されるので value_cell に入る（closure を作った後で書き込むため）。
    /// 関数の本体を (block 名前 ...) で囲む処理は、block を実装する Phase 18 で加える
    fn resolveLocalFunctions(r: *Resolver, form: Value, args: []Value, scope: *const Scope, labels: bool) Error!*Node {
        if (args.len < 1) return r.fail(.program_error, "FLET・LABELS には関数の定義の並びが必要です", form);
        const defs = try r.listItems(args[0], "FLET・LABELS の定義の並びがドット対で終わっています");
        const l = scope.lambda;
        const saved = l.next_slot;
        const names = try r.arena.alloc(Value, defs.len);
        const bodies = try r.arena.alloc([]Value, defs.len);
        for (defs, 0..) |d, i| {
            if (!d.isCons()) return r.fail(.program_error, "局所関数の定義の形が正しくありません", d);
            const parts = try r.listItems(d, "局所関数の定義の形が正しくありません");
            if (parts.len < 2) return r.fail(.program_error, "局所関数の定義には名前とラムダリストが必要です", d);
            const name = parts[0];
            if (name.isCons()) return r.fail(.unimplemented, "(setf 名前) の局所関数は未実装です（Phase 16 で実装予定）", name);
            if (!isSymbol(name) or name == Value.nil) return r.fail(.program_error, "関数の名前はシンボルでなければなりません", name);
            const s = r.rt.symbolPtr(name);
            if (s.hasFlag(SymbolFlags.special_operator))
                return r.fail(.program_error, "特殊演算子の名前は局所関数の名前にできません", name);
            // CL パッケージのシンボルは局所関数の名前にできない（CLHS 11.1.2.1.2。SBCL 2.6.7 ではパッケージのロックのエラー）
            if (s.package == r.rt.cl.obj)
                return r.fail(.program_error, "COMMON-LISP パッケージのシンボルは局所関数の名前にできません", name);
            names[i] = name;
            bodies[i] = parts[1..];
        }
        const kind: Lambda.FnKind = if (labels) .labels else .flet;
        const vars = try r.arena.alloc(*Var, defs.len);
        const fns = try r.arena.alloc(FnBinding, defs.len);
        const lambdas = try r.arena.alloc(*Lambda, defs.len);
        if (!labels) {
            // flet：関数を先に外側の範囲で解決する
            for (bodies, 0..) |b, i| lambdas[i] = try r.resolveLambdaParts(b, names[i], kind, scope);
        }
        for (names, 0..) |name, i| {
            const v = try r.arena.create(Var);
            v.* = .{ .name = name, .owner = l, .slot = l.newSlot() };
            vars[i] = v;
            fns[i] = .{ .name = name, .v = v };
        }
        const fn_scope = try r.arena.create(Scope);
        fn_scope.* = .{ .parent = scope, .lambda = l, .vars = &.{}, .fns = fns };
        if (labels) {
            for (bodies, 0..) |b, i| lambdas[i] = try r.resolveLambdaParts(b, names[i], kind, fn_scope);
        }
        var decls: Decls = .{};
        const body = try r.parseBody(args[1..], false, &decls);
        const inner: Scope = .{ .parent = fn_scope, .lambda = l, .vars = try r.scopeVars(&.{}, &decls, l), .inline_decls = decls.inlines.items };
        const body_node = if (body.len == 0) try r.node(.{ .constant = Value.nil }) else try r.resolveBody(body, &inner);
        l.next_slot = saved;

        const inits = try r.arena.alloc(*Node, defs.len);
        if (!labels) {
            for (lambdas, 0..) |lam, i| inits[i] = try r.node(.{ .lambda = lam });
            return r.node(.{ .let_ = .{ .vars = vars, .inits = inits, .body = body_node } });
        }
        const forms = try r.arena.alloc(*Node, defs.len + 1);
        for (lambdas, 0..) |lam, i| {
            inits[i] = try r.node(.{ .constant = Value.nil });
            vars[i].assigned = true;
            forms[i] = try r.node(.{ .lex_set = .{ .v = vars[i], .value = try r.node(.{ .lambda = lam }) } });
        }
        forms[defs.len] = body_node;
        return r.node(.{ .let_ = .{ .vars = vars, .inits = inits, .body = try r.node(.{ .progn = forms }) } });
    }

    const Binding = struct { name: Value, init_form: Value };

    /// 束縛の1つ（var、(var)、(var init)）を読む
    fn parseBinding(r: *Resolver, b: Value) Error!Binding {
        var name = b;
        var init_form = Value.nil;
        if (b.isCons()) {
            const parts = try r.listItems(b, "LET の束縛の形が正しくありません");
            if (parts.len > 2) return r.fail(.program_error, "LET の束縛の形が正しくありません", b);
            name = parts[0];
            if (parts.len == 2) init_form = parts[1];
        }
        try r.checkBindable(name);
        return .{ .name = name, .init_form = init_form };
    }

    fn resolveLet(r: *Resolver, form: Value, args: []Value, scope: *const Scope) Error!*Node {
        if (args.len < 1) return r.fail(.program_error, "LET には束縛の並びが必要です", form);
        const bindings = try r.listItems(args[0], "LET の束縛の並びがドット対で終わっています");
        const names = try r.arena.alloc(Value, bindings.len);
        const inits = try r.arena.alloc(*Node, bindings.len);
        for (bindings, 0..) |b, i| {
            const parsed = try r.parseBinding(b);
            const name = parsed.name;
            const init_form = parsed.init_form;
            for (names[0..i]) |q| {
                if (q == name) return r.fail(.program_error, "LET に同じ変数が2回あります", name);
            }
            names[i] = name;
            // 初期値は外側の範囲で評価する（並列の束縛）
            inits[i] = try r.resolve(init_form, scope);
        }
        const l = scope.lambda;
        const saved = l.next_slot;
        var decls: Decls = .{};
        const body = try r.parseBody(args[1..], false, &decls);
        const vars = try r.arena.alloc(*Var, bindings.len);
        for (names, 0..) |name, i| {
            if (r.bindsSpecially(name, &decls)) {
                vars[i] = try r.specialVar(name, l);
            } else {
                const v = try r.arena.create(Var);
                v.* = .{ .name = name, .owner = l, .slot = l.newSlot() };
                vars[i] = v;
            }
        }
        const depth_slot = if (ir.hasSpecial(vars)) l.newSlot() else ir.no_slot;
        const inner: Scope = .{ .parent = scope, .lambda = l, .vars = try r.scopeVars(vars, &decls, l), .inline_decls = decls.inlines.items };
        const body_node = if (body.len == 0) try r.node(.{ .constant = Value.nil }) else try r.resolveBody(body, &inner);
        l.next_slot = saved;
        return r.node(.{ .let_ = .{ .vars = vars, .inits = inits, .body = body_node, .depth_slot = depth_slot } });
    }

    /// let*：束縛を順に行う。各初期値は、それより前の変数が見える範囲で評価する。
    /// 同じ名前の変数を2回束縛してよい（後の束縛が前の束縛を隠す。SBCL 2.6.7 と同じ）。
    /// IR は、変数1つの let_ を入れ子にしたものにする
    fn resolveLetStar(r: *Resolver, form: Value, args: []Value, scope: *const Scope) Error!*Node {
        if (args.len < 1) return r.fail(.program_error, "LET* には束縛の並びが必要です", form);
        const bindings = try r.listItems(args[0], "LET* の束縛の並びがドット対で終わっています");
        const l = scope.lambda;
        const saved = l.next_slot;
        var decls: Decls = .{};
        const body = try r.parseBody(args[1..], false, &decls);
        const vars = try r.arena.alloc(*Var, bindings.len);
        const inits = try r.arena.alloc(*Node, bindings.len);
        const depth_slots = try r.arena.alloc(u32, bindings.len);
        var cur: *const Scope = scope;
        for (bindings, 0..) |b, i| {
            const parsed = try r.parseBinding(b);
            // 初期値は、前の変数の局所変数の番号を確保した後で解決する（初期値の中の let が前の変数の番号を使わないように）
            inits[i] = try r.resolve(parsed.init_form, cur);
            depth_slots[i] = ir.no_slot;
            if (r.bindsSpecially(parsed.name, &decls)) {
                vars[i] = try r.specialVar(parsed.name, l);
                depth_slots[i] = l.newSlot();
            } else {
                const v = try r.arena.create(Var);
                v.* = .{ .name = parsed.name, .owner = l, .slot = l.newSlot() };
                vars[i] = v;
            }
            const sc = try r.arena.create(Scope);
            sc.* = .{ .parent = cur, .lambda = l, .vars = vars[i .. i + 1] };
            cur = sc;
        }
        const inner: Scope = .{ .parent = cur, .lambda = l, .vars = try r.scopeVars(&.{}, &decls, l), .inline_decls = decls.inlines.items };
        var result = if (body.len == 0) try r.node(.{ .constant = Value.nil }) else try r.resolveBody(body, &inner);
        l.next_slot = saved;
        var i = bindings.len;
        while (i > 0) : (i -= 1) {
            result = try r.node(.{ .let_ = .{ .vars = vars[i - 1 .. i], .inits = inits[i - 1 .. i], .body = result, .depth_slot = depth_slots[i - 1] } });
        }
        return result;
    }

    fn resolveSetq(r: *Resolver, form: Value, args: []Value, scope: *const Scope) Error!*Node {
        if (args.len % 2 != 0) return r.fail(.program_error, "SETQ の引数は変数と値の組です", form);
        if (args.len == 0) return r.node(.{ .constant = Value.nil });
        const sets = try r.arena.alloc(*Node, args.len / 2);
        var i: usize = 0;
        while (i < args.len) : (i += 2) {
            const name = args[i];
            if (!isSymbol(name)) return r.fail(.program_error, "SETQ の変数はシンボルでなければなりません", name);
            const s = r.rt.symbolPtr(name);
            if (name == Value.nil or s.hasFlag(SymbolFlags.constant) or s.hasFlag(SymbolFlags.keyword))
                return r.fail(.program_error, "定数には代入できません", name);
            const value = try r.resolve(args[i + 1], scope);
            if (!s.hasFlag(SymbolFlags.special)) {
                if (lookup(scope, name)) |v| {
                    if (!v.special) {
                        try r.reference(v, scope.lambda);
                        v.assigned = true;
                        sets[i / 2] = try r.node(.{ .lex_set = .{ .v = v, .value = value } });
                        continue;
                    }
                }
            }
            sets[i / 2] = try r.node(.{ .global_set = .{ .sym = name, .value = value } });
        }
        if (sets.len == 1) return sets[0];
        return r.node(.{ .progn = sets });
    }
};
