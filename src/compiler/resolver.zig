//! Resolver：フォーム（Value）から Core IR を作る（詳細設計 §5.1）。
//! 名前解決、捕捉（captured）と代入（assigned）の計算、特殊演算子の解釈を行う。
//!
//! Phase 08 の範囲
//!   特殊演算子：quote if progn let let*（Phase 09）setq function、および lambda（CL ではマクロ）
//!   関数の呼び出し、((lambda ...) ...)、CL の一部の関数の高速経路（ir.Prim）
//! 範囲外のものは、明示的なエラーにする（基本設計 §3.1）。
//!   ほかの特殊演算子・マクロ（Phase 09〜）、&optional などのラムダリストキーワード（Phase 17）、
//!   special 宣言と特殊変数の束縛（Phase 14）
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

/// レキシカルな範囲（let・lambda ごとに1つ）
const Scope = struct {
    parent: ?*const Scope,
    lambda: *Lambda,
    vars: []const *Var,
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
        if (s.hasFlag(SymbolFlags.constant) or s.hasFlag(SymbolFlags.keyword))
            return r.fail(.program_error, "定数は束縛できません", name);
        if (s.hasFlag(SymbolFlags.special))
            return r.fail(.unimplemented, "特殊変数の束縛は未実装です（Phase 14 で実装予定）", name);
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
    fn parseBody(r: *Resolver, forms: []Value, allow_doc: bool, decls: *std.ArrayList(InlineDecl)) Error![]Value {
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

    fn checkDeclaration(r: *Resolver, spec: Value, decls: *std.ArrayList(InlineDecl)) Error!void {
        if (!spec.isCons()) return r.fail(.program_error, "宣言の形が正しくありません", spec);
        const y = r.rt.syms;
        const id = Runtime.consPtr(spec).car;
        if (id == y.special)
            return r.fail(.unimplemented, "special 宣言は未実装です（Phase 14 で実装予定）", spec);
        if (id == y.@"inline" or id == y.notinline) {
            const names = try r.listItems(Runtime.consPtr(spec).cdr, "宣言の形が正しくありません");
            for (names) |n| {
                // (setf 名前) の関数は Phase 16 で扱う。今は高速経路の対象にならないので記録しない
                if (isSymbol(n)) try decls.append(r.arena, .{ .sym = n, .notinline = id == y.notinline });
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
                try r.reference(v, scope.lambda);
                return r.node(.{ .lex_ref = v });
            }
        }
        // 特殊変数、または宣言のない自由変数（大域の値。SBCL と同じく特殊変数として参照する）
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
            return r.node(.{ .global_fn = name });
        }
        if (name.isCons() and Runtime.consPtr(name).car == r.rt.syms.lambda)
            return r.node(.{ .lambda = try r.resolveLambda(name, scope) });
        return r.fail(.unimplemented, "この関数の名前は未実装です（(setf 名前) は Phase 16 で実装予定）", name);
    }

    fn resolveLambda(r: *Resolver, form: Value, scope: *const Scope) Error!*Lambda {
        const parts = try r.listItems(Runtime.consPtr(form).cdr, "LAMBDA の形が正しくありません");
        if (parts.len < 1) return r.fail(.program_error, "LAMBDA にはラムダリストが必要です", form);
        return r.resolveLambdaParts(parts, Value.nil, scope);
    }

    /// parts = (ラムダリスト 本体...)。fn_name は defun などで付ける関数の名前（無名なら NIL）
    fn resolveLambdaParts(r: *Resolver, parts: []Value, fn_name: Value, scope: *const Scope) Error!*Lambda {
        const params = try r.listItems(parts[0], "ラムダリストがドット対で終わっています");
        const l = try r.arena.create(Lambda);
        l.* = .{ .parent = scope.lambda, .name = parts[0], .fn_name = fn_name };
        const vars = try r.arena.alloc(*Var, params.len);
        for (params, 0..) |p, i| {
            if (r.isLambdaListKeyword(p))
                return r.fail(.unimplemented, "ラムダリストのキーワードは未実装です（Phase 17 で実装予定）", p);
            try r.checkBindable(p);
            for (params[0..i]) |q| {
                if (q == p) return r.fail(.program_error, "ラムダリストに同じ変数が2回あります", p);
            }
            const v = try r.arena.create(Var);
            v.* = .{ .name = p, .owner = l, .slot = l.newSlot() };
            vars[i] = v;
        }
        l.params = vars;
        var decls: std.ArrayList(InlineDecl) = .empty;
        const body = try r.parseBody(parts[1..], true, &decls);
        const inner: Scope = .{ .parent = scope, .lambda = l, .vars = vars, .inline_decls = decls.items };
        l.body = if (body.len == 0) try r.node(.{ .constant = Value.nil }) else try r.resolveBody(body, &inner);
        return l;
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
        const l = try r.resolveLambdaParts(args[1..], name, scope);
        const call_args = try r.arena.alloc(*Node, 2);
        call_args[0] = try r.node(.{ .constant = name });
        call_args[1] = try r.node(.{ .lambda = l });
        return r.node(.{ .call_global = .{ .sym = r.rt.sys_defun, .args = call_args } });
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
        const vars = try r.arena.alloc(*Var, bindings.len);
        for (names, 0..) |name, i| {
            const v = try r.arena.create(Var);
            v.* = .{ .name = name, .owner = l, .slot = l.newSlot() };
            vars[i] = v;
        }
        var decls: std.ArrayList(InlineDecl) = .empty;
        const body = try r.parseBody(args[1..], false, &decls);
        const inner: Scope = .{ .parent = scope, .lambda = l, .vars = vars, .inline_decls = decls.items };
        const body_node = if (body.len == 0) try r.node(.{ .constant = Value.nil }) else try r.resolveBody(body, &inner);
        l.next_slot = saved;
        return r.node(.{ .let_ = .{ .vars = vars, .inits = inits, .body = body_node } });
    }

    /// let*：束縛を順に行う。各初期値は、それより前の変数が見える範囲で評価する。
    /// 同じ名前の変数を2回束縛してよい（後の束縛が前の束縛を隠す。SBCL 2.6.7 と同じ）。
    /// IR は、変数1つの let_ を入れ子にしたものにする
    fn resolveLetStar(r: *Resolver, form: Value, args: []Value, scope: *const Scope) Error!*Node {
        if (args.len < 1) return r.fail(.program_error, "LET* には束縛の並びが必要です", form);
        const bindings = try r.listItems(args[0], "LET* の束縛の並びがドット対で終わっています");
        const l = scope.lambda;
        const saved = l.next_slot;
        const vars = try r.arena.alloc(*Var, bindings.len);
        const inits = try r.arena.alloc(*Node, bindings.len);
        var cur: *const Scope = scope;
        for (bindings, 0..) |b, i| {
            const parsed = try r.parseBinding(b);
            // 初期値は、前の変数の局所変数の番号を確保した後で解決する（初期値の中の let が前の変数の番号を使わないように）
            inits[i] = try r.resolve(parsed.init_form, cur);
            const v = try r.arena.create(Var);
            v.* = .{ .name = parsed.name, .owner = l, .slot = l.newSlot() };
            vars[i] = v;
            const sc = try r.arena.create(Scope);
            sc.* = .{ .parent = cur, .lambda = l, .vars = vars[i .. i + 1] };
            cur = sc;
        }
        var decls: std.ArrayList(InlineDecl) = .empty;
        const body = try r.parseBody(args[1..], false, &decls);
        const inner: Scope = .{ .parent = cur, .lambda = l, .vars = &.{}, .inline_decls = decls.items };
        var result = if (body.len == 0) try r.node(.{ .constant = Value.nil }) else try r.resolveBody(body, &inner);
        l.next_slot = saved;
        var i = bindings.len;
        while (i > 0) : (i -= 1) {
            result = try r.node(.{ .let_ = .{ .vars = vars[i - 1 .. i], .inits = inits[i - 1 .. i], .body = result } });
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
                    try r.reference(v, scope.lambda);
                    v.assigned = true;
                    sets[i / 2] = try r.node(.{ .lex_set = .{ .v = v, .value = value } });
                    continue;
                }
            }
            sets[i / 2] = try r.node(.{ .global_set = .{ .sym = name, .value = value } });
        }
        if (sets.len == 1) return sets[0];
        return r.node(.{ .progn = sets });
    }
};
