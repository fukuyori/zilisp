//! パッケージ（Phase 22。CLHS 11 章。詳細設計 §8.2）。
//!
//! packagep・find-package・make-package・rename-package・delete-package・list-all-packages・package-name・
//! package-nicknames・package-use-list・package-used-by-list・package-shadowing-symbols、
//! intern・find-symbol・unintern・export・unexport・import・shadow・shadowing-import・use-package・unuse-package・
//! find-all-symbols・symbol-package・keywordp。
//! マクロ in-package・defpackage・do-symbols などは src/lisp/boot.lisp（下の ZILISP-SYSTEM の関数を使う）。
//!
//! 名前の衝突（CLHS 11.1.1.2.5）は、表を変える前にすべて調べ、あれば package-error にする（SBCL 2.6.7 は
//! package-error の一種の name-conflict。restart は condition の Phase 25 で加える）。

const std = @import("std");
const Value = @import("../values/value.zig").Value;
const Thread = @import("../runtime/thread.zig").Thread;
const runtime_mod = @import("../runtime/runtime.zig");
const Runtime = runtime_mod.Runtime;
const PackageData = runtime_mod.PackageData;
const Found = runtime_mod.Found;
const arrays = @import("arrays.zig");
const keyargs = @import("keyargs.zig");

fn cl(th: *Thread, name: []const u8) Value {
    return (th.rt.findSymbol(th.rt.cl, name) orelse unreachable).symbol;
}

fn isSymbol(v: Value) bool {
    return v == Value.nil or (v.isOther() and Runtime.kindOf(v) == .symbol);
}

fn symbolName(rt: *Runtime, v: Value) Value {
    return if (v == Value.nil) rt.nil_symbol.name else rt.symbolPtr(v).name;
}

fn symbolHome(rt: *Runtime, v: Value) Value {
    return rt.symbolPtr(v).package;
}

fn setSymbolHome(rt: *Runtime, v: Value, pkg: Value) void {
    rt.symbolPtr(v).package = pkg;
}

/// 文字列の内容を UTF-8 にする（呼び出し側が gpa で解放する）
fn stringUtf8(gpa: std.mem.Allocator, data: Value, len: usize) error{OutOfMemory}![]u8 {
    var out: std.ArrayList(u8) = .empty;
    errdefer out.deinit(gpa);
    const s = Runtime.stringPtr(data);
    for (0..len) |i| {
        var b: [4]u8 = undefined;
        const n = std.unicode.utf8Encode(s.charAt(i), &b) catch unreachable;
        try out.appendSlice(gpa, b[0..n]);
    }
    return out.toOwnedSlice(gpa);
}

/// 文字列指定子（文字列・シンボル・文字）の UTF-8 の名前。呼び出し側が th.rt.gpa で解放する。
/// 指定子でなければ type-error（null）
fn designatorName(th: *Thread, v: Value) ?[]u8 {
    const rt = th.rt;
    const r = if (arrays.isStringLike(v)) blk: {
        const view = arrays.vectorView(v).?;
        break :blk stringUtf8(rt.gpa, view.data, view.len);
    } else if (isSymbol(v)) blk: {
        const name = symbolName(rt, v);
        break :blk stringUtf8(rt.gpa, name, Runtime.stringPtr(name).length());
    } else if (v.isChar()) blk: {
        var b: [4]u8 = undefined;
        const n = std.unicode.utf8Encode(v.asChar(), &b) catch unreachable;
        break :blk rt.gpa.dupe(u8, b[0..n]);
    } else {
        _ = th.typeError(v, cl(th, "STRING"));
        return null;
    };
    return r catch {
        _ = th.outOfMemory();
        return null;
    };
}

/// 文字列（指定子ではない）の UTF-8。intern・find-symbol の引数
fn stringArgName(th: *Thread, v: Value) ?[]u8 {
    if (!arrays.isStringLike(v)) {
        _ = th.typeError(v, cl(th, "STRING"));
        return null;
    }
    return designatorName(th, v);
}

fn symbolUtf8(th: *Thread, sym: Value) ?[]u8 {
    const name = symbolName(th.rt, sym);
    return stringUtf8(th.rt.gpa, name, Runtime.stringPtr(name).length()) catch {
        _ = th.outOfMemory();
        return null;
    };
}

fn packageError(th: *Thread, message: []const u8, datum: Value) ?*PackageData {
    _ = th.signal(.package_error, message, datum, Value.unbound);
    return null;
}

/// パッケージ指定子（パッケージ・文字列指定子）をパッケージにする。なければ package-error
fn packageArg(th: *Thread, v: Value) ?*PackageData {
    if (Runtime.isPackage(v)) {
        const p = Runtime.packageData(v);
        if (p.deleted) return packageError(th, "削除したパッケージです", v);
        return p;
    }
    const name = designatorName(th, v) orelse return null;
    defer th.rt.gpa.free(name);
    return th.rt.findPackage(name) orelse packageError(th, "そのパッケージはありません", v);
}

/// 省略できるパッケージの引数（省略すれば *package*）
fn optPackage(th: *Thread, args: []const Value, i: usize) ?*PackageData {
    if (args.len > i) return packageArg(th, args[i]);
    return th.rt.currentPackage() orelse {
        _ = th.typeError(th.rt.symbolPtr(th.rt.package_sym).value, cl(th, "PACKAGE"));
        return null;
    };
}

/// シンボル、またはシンボルの真リスト（NIL は空のリスト）。呼び出し側が gpa で解放する
fn symbolList(th: *Thread, v: Value) ?[]Value {
    const rt = th.rt;
    var out: std.ArrayList(Value) = .empty;
    if (v != Value.nil and isSymbol(v)) {
        out.append(rt.gpa, v) catch {
            _ = th.outOfMemory();
            return null;
        };
        return out.toOwnedSlice(rt.gpa) catch {
            _ = th.outOfMemory();
            return null;
        };
    }
    var x = v;
    while (x.isCons()) : (x = Runtime.consPtr(x).cdr) {
        const s = Runtime.consPtr(x).car;
        if (!isSymbol(s)) {
            out.deinit(rt.gpa);
            _ = th.typeError(s, rt.syms.symbol);
            return null;
        }
        out.append(rt.gpa, s) catch {
            out.deinit(rt.gpa);
            _ = th.outOfMemory();
            return null;
        };
    }
    if (x != Value.nil) {
        out.deinit(rt.gpa);
        _ = th.typeError(v, rt.syms.list);
        return null;
    }
    return out.toOwnedSlice(rt.gpa) catch {
        _ = th.outOfMemory();
        return null;
    };
}

/// 指定子、または指定子の真リスト（NIL は空のリスト）
fn designatorItems(th: *Thread, v: Value) ?[]Value {
    const rt = th.rt;
    var out: std.ArrayList(Value) = .empty;
    if (!v.isCons() and v != Value.nil) {
        out.append(rt.gpa, v) catch {
            _ = th.outOfMemory();
            return null;
        };
    } else {
        var x = v;
        while (x.isCons()) : (x = Runtime.consPtr(x).cdr) {
            out.append(rt.gpa, Runtime.consPtr(x).car) catch {
                out.deinit(rt.gpa);
                _ = th.outOfMemory();
                return null;
            };
        }
        if (x != Value.nil) {
            out.deinit(rt.gpa);
            _ = th.typeError(v, rt.syms.list);
            return null;
        }
    }
    return out.toOwnedSlice(rt.gpa) catch {
        _ = th.outOfMemory();
        return null;
    };
}

fn statusKeyword(th: *Thread, f: Found) ?Value {
    return th.rt.internKeyword(switch (f.status) {
        .internal => "INTERNAL",
        .external => "EXTERNAL",
        .inherited => "INHERITED",
    }) catch {
        _ = th.outOfMemory();
        return null;
    };
}

fn oom(th: *Thread) Value {
    return th.outOfMemory();
}

/// 名前の表からシンボルを取り除く（キーを解放する）
fn removeFromTables(rt: *Runtime, p: *PackageData, name: []const u8) void {
    if (p.internal.fetchRemove(name)) |kv| rt.gpa.free(kv.key);
    if (p.external.fetchRemove(name)) |kv| rt.gpa.free(kv.key);
}

fn removeShadowing(p: *PackageData, sym: Value) void {
    if (std.mem.indexOfScalar(Value, p.shadowing.items, sym)) |i| _ = p.shadowing.orderedRemove(i);
}

/// p からシンボルを取り除く（present であること）。ホームパッケージが p なら、ホームを NIL にする
fn removePresent(rt: *Runtime, p: *PackageData, sym: Value, name: []const u8) void {
    removeFromTables(rt, p, name);
    removeShadowing(p, sym);
    if (symbolHome(rt, sym) == p.obj) setSymbolHome(rt, sym, Value.nil);
}

// ---------------------------------------------------------------------------
// パッケージの問い合わせ

pub fn packagep(th: *Thread, args: []const Value) Value {
    return th.rt.boolean(Runtime.isPackage(args[0]));
}

/// (find-package 名前)：パッケージはそのまま。名前・別名・ローカルの別名で探し、なければ NIL
pub fn findPackage(th: *Thread, args: []const Value) Value {
    if (Runtime.isPackage(args[0])) return args[0];
    const name = designatorName(th, args[0]) orelse return Value.unwind;
    defer th.rt.gpa.free(name);
    return if (th.rt.findPackage(name)) |p| p.obj else Value.nil;
}

/// パッケージの引数（削除したパッケージも受け取る：package-name などは NIL を返す）
fn queryPackage(th: *Thread, v: Value) ?*PackageData {
    if (Runtime.isPackage(v)) return Runtime.packageData(v);
    return packageArg(th, v);
}

pub fn packageName(th: *Thread, args: []const Value) Value {
    const p = queryPackage(th, args[0]) orelse return Value.unwind;
    if (p.deleted) return Value.nil;
    return th.rt.makeString(p.name) catch oom(th);
}

pub fn packageNicknames(th: *Thread, args: []const Value) Value {
    const p = queryPackage(th, args[0]) orelse return Value.unwind;
    if (p.deleted) return Value.nil;
    var list = Value.nil;
    var i = p.nicknames.len;
    while (i > 0) {
        i -= 1;
        const s = th.rt.makeString(p.nicknames[i]) catch return oom(th);
        list = th.rt.cons(s, list) catch return oom(th);
    }
    return list;
}

fn packageListValue(th: *Thread, items: []const *PackageData) Value {
    var list = Value.nil;
    var i = items.len;
    while (i > 0) {
        i -= 1;
        list = th.rt.cons(items[i].obj, list) catch return oom(th);
    }
    return list;
}

pub fn packageUseList(th: *Thread, args: []const Value) Value {
    const p = queryPackage(th, args[0]) orelse return Value.unwind;
    return packageListValue(th, p.use_list.items);
}

pub fn packageUsedByList(th: *Thread, args: []const Value) Value {
    const p = queryPackage(th, args[0]) orelse return Value.unwind;
    return packageListValue(th, p.used_by.items);
}

pub fn packageShadowingSymbols(th: *Thread, args: []const Value) Value {
    const p = queryPackage(th, args[0]) orelse return Value.unwind;
    var list = Value.nil;
    var i = p.shadowing.items.len;
    while (i > 0) {
        i -= 1;
        list = th.rt.cons(p.shadowing.items[i], list) catch return oom(th);
    }
    return list;
}

pub fn listAllPackages(th: *Thread, args: []const Value) Value {
    _ = args;
    return packageListValue(th, th.rt.packages.items);
}

pub fn symbolPackage(th: *Thread, args: []const Value) Value {
    if (!isSymbol(args[0])) return th.typeError(args[0], th.rt.syms.symbol);
    if (args[0] == Value.nil) return th.rt.nil_symbol.package;
    return symbolHome(th.rt, args[0]);
}

/// (make-symbol 名前)：ホームパッケージのない新しいシンボル（名前は写す）
pub fn makeSymbol(th: *Thread, args: []const Value) Value {
    const name = stringArgName(th, args[0]) orelse return Value.unwind;
    defer th.rt.gpa.free(name);
    return th.rt.makeSymbol(name) catch oom(th);
}

pub fn keywordp(th: *Thread, args: []const Value) Value {
    const v = args[0];
    if (v == Value.nil or !isSymbol(v)) return Value.nil;
    return th.rt.boolean(symbolHome(th.rt, v) == th.rt.keyword.obj);
}

// ---------------------------------------------------------------------------
// シンボルを探す・作る

/// (find-symbol 文字列 &optional パッケージ)：シンボルと状態（:internal・:external・:inherited）、なければ NIL NIL
pub fn findSymbol(th: *Thread, args: []const Value) Value {
    const name = stringArgName(th, args[0]) orelse return Value.unwind;
    defer th.rt.gpa.free(name);
    const p = optPackage(th, args, 1) orelse return Value.unwind;
    th.mv_count = 2;
    if (th.rt.findSymbol(p, name)) |f| {
        th.mv[1] = statusKeyword(th, f) orelse return Value.unwind;
        th.mv_count = 2;
        return f.symbol;
    }
    th.mv[1] = Value.nil;
    return Value.nil;
}

/// (intern 文字列 &optional パッケージ)：あればそのシンボルと状態、なければ作って NIL
pub fn intern(th: *Thread, args: []const Value) Value {
    const name = stringArgName(th, args[0]) orelse return Value.unwind;
    defer th.rt.gpa.free(name);
    const p = optPackage(th, args, 1) orelse return Value.unwind;
    if (th.rt.findSymbol(p, name)) |f| {
        th.mv[1] = statusKeyword(th, f) orelse return Value.unwind;
        th.mv_count = 2;
        return f.symbol;
    }
    const s = th.rt.intern(p, name) catch return oom(th);
    th.mv[1] = Value.nil;
    th.mv_count = 2;
    return s;
}

/// (unintern シンボル &optional パッケージ)：p にあれば取り除いて T、なければ NIL。
/// シャドウイングシンボルを取り除くと、use している複数のパッケージの同名の外部シンボルが衝突するなら package-error
pub fn unintern(th: *Thread, args: []const Value) Value {
    const sym = args[0];
    if (!isSymbol(sym)) return th.typeError(sym, th.rt.syms.symbol);
    const p = optPackage(th, args, 1) orelse return Value.unwind;
    const name = symbolUtf8(th, sym) orelse return Value.unwind;
    defer th.rt.gpa.free(name);
    const f = p.present(name) orelse return Value.nil;
    if (f.symbol != sym) return Value.nil;
    if (p.isShadowing(sym)) {
        var seen: ?Value = null;
        for (p.use_list.items) |u| {
            const e = u.external.get(name) orelse continue;
            if (seen) |s0| {
                if (s0 != e) return th.signal(.package_error, "取り除くと、use しているパッケージの同名のシンボルが衝突します", sym, Value.unbound);
            } else seen = e;
        }
    }
    removePresent(th.rt, p, sym, name);
    return th.rt.t;
}

// ---------------------------------------------------------------------------
// export・import・shadow

/// (export シンボル &optional パッケージ)
pub fn exportSymbols(th: *Thread, args: []const Value) Value {
    const rt = th.rt;
    const syms = symbolList(th, args[0]) orelse return Value.unwind;
    defer rt.gpa.free(syms);
    const p = optPackage(th, args, 1) orelse return Value.unwind;
    // 先にすべて調べる
    for (syms) |sym| {
        const name = symbolUtf8(th, sym) orelse return Value.unwind;
        defer rt.gpa.free(name);
        const f = rt.findSymbol(p, name);
        if (f == null or f.?.symbol != sym)
            return th.signal(.package_error, "そのパッケージからアクセスできないシンボルは export できません", sym, Value.unbound);
        if (f.?.status == .external) continue;
        for (p.used_by.items) |q| {
            const g = rt.findSymbol(q, name) orelse continue;
            if (g.symbol == sym) continue;
            if (g.status != .inherited and q.isShadowing(g.symbol)) continue;
            return th.signal(.package_error, "export すると、use しているパッケージの同名のシンボルと衝突します", sym, Value.unbound);
        }
    }
    for (syms) |sym| {
        const name = symbolUtf8(th, sym) orelse return Value.unwind;
        defer rt.gpa.free(name);
        const f = rt.findSymbol(p, name).?;
        if (f.status == .external) continue;
        // 外部の表に入れてから内部の表から除く（継承したシンボルは、取り込んでから外部にする）
        rt.putSymbol(&p.external, name, sym) catch return oom(th);
        if (p.internal.fetchRemove(name)) |kv| rt.gpa.free(kv.key);
    }
    return rt.t;
}

/// (unexport シンボル &optional パッケージ)
pub fn unexportSymbols(th: *Thread, args: []const Value) Value {
    const rt = th.rt;
    const syms = symbolList(th, args[0]) orelse return Value.unwind;
    defer rt.gpa.free(syms);
    const p = optPackage(th, args, 1) orelse return Value.unwind;
    for (syms) |sym| {
        const name = symbolUtf8(th, sym) orelse return Value.unwind;
        defer rt.gpa.free(name);
        const f = rt.findSymbol(p, name);
        if (f == null or f.?.symbol != sym)
            return th.signal(.package_error, "そのパッケージからアクセスできないシンボルは unexport できません", sym, Value.unbound);
        if (p == rt.keyword) return th.signal(.package_error, "KEYWORD のシンボルは unexport できません", sym, Value.unbound);
    }
    for (syms) |sym| {
        const name = symbolUtf8(th, sym) orelse return Value.unwind;
        defer rt.gpa.free(name);
        const f = rt.findSymbol(p, name).?;
        if (f.status != .external) continue;
        rt.putSymbol(&p.internal, name, sym) catch return oom(th);
        if (p.external.fetchRemove(name)) |kv| rt.gpa.free(kv.key);
    }
    return rt.t;
}

/// (import シンボル &optional パッケージ)：同名の別のシンボルがアクセスできれば package-error
pub fn importSymbols(th: *Thread, args: []const Value) Value {
    const rt = th.rt;
    const syms = symbolList(th, args[0]) orelse return Value.unwind;
    defer rt.gpa.free(syms);
    const p = optPackage(th, args, 1) orelse return Value.unwind;
    for (syms, 0..) |sym, i| {
        const name = symbolUtf8(th, sym) orelse return Value.unwind;
        defer rt.gpa.free(name);
        if (rt.findSymbol(p, name)) |f| if (f.symbol != sym)
            return th.signal(.package_error, "同じ名前の別のシンボルがアクセスできるので import できません", sym, Value.unbound);
        // 同じ呼び出しの中で、同名の別のシンボルを import しようとしている
        for (syms[0..i]) |other| {
            if (other == sym) continue;
            const on = symbolUtf8(th, other) orelse return Value.unwind;
            defer rt.gpa.free(on);
            if (std.mem.eql(u8, on, name)) return th.signal(.package_error, "同じ名前の別のシンボルを同時に import できません", sym, Value.unbound);
        }
    }
    for (syms) |sym| {
        const name = symbolUtf8(th, sym) orelse return Value.unwind;
        defer rt.gpa.free(name);
        if (p.present(name) == null) rt.putSymbol(if (p == rt.keyword) &p.external else &p.internal, name, sym) catch return oom(th);
        // ホームパッケージのないシンボルは、p をホームにする（既に p にある場合も。CLHS import。Codex のレビュー P22 #2）
        if (sym != Value.nil and symbolHome(rt, sym) == Value.nil) setSymbolHome(rt, sym, p.obj);
    }
    return rt.t;
}

/// (shadowing-import シンボル &optional パッケージ)：同名の別のシンボルがあれば取り除き、シャドウイングシンボルにする
pub fn shadowingImport(th: *Thread, args: []const Value) Value {
    const rt = th.rt;
    const syms = symbolList(th, args[0]) orelse return Value.unwind;
    defer rt.gpa.free(syms);
    const p = optPackage(th, args, 1) orelse return Value.unwind;
    for (syms) |sym| {
        const name = symbolUtf8(th, sym) orelse return Value.unwind;
        defer rt.gpa.free(name);
        if (p.present(name)) |f| {
            if (f.symbol != sym) removePresent(rt, p, f.symbol, name);
        }
        // ホームパッケージは変えない（SBCL 2.6.7 と同じ。Codex のレビュー P22 #3）
        if (p.present(name) == null) rt.putSymbol(&p.internal, name, sym) catch return oom(th);
        if (!p.isShadowing(sym)) p.shadowing.append(rt.gpa, sym) catch return oom(th);
    }
    return rt.t;
}

/// (shadow 名前 &optional パッケージ)：p になければ内部シンボルを作り、シャドウイングシンボルにする
pub fn shadow(th: *Thread, args: []const Value) Value {
    const rt = th.rt;
    const items = designatorItems(th, args[0]) orelse return Value.unwind;
    defer rt.gpa.free(items);
    const p = optPackage(th, args, 1) orelse return Value.unwind;
    for (items) |it| {
        const name = designatorName(th, it) orelse return Value.unwind;
        defer rt.gpa.free(name);
        const sym = if (p.present(name)) |f| f.symbol else blk: {
            const s = rt.makeSymbolWithPackage(name, p.obj) catch return oom(th);
            rt.putSymbol(&p.internal, name, s) catch return oom(th);
            break :blk s;
        };
        if (!p.isShadowing(sym)) p.shadowing.append(rt.gpa, sym) catch return oom(th);
    }
    return rt.t;
}

// ---------------------------------------------------------------------------
// use-package・unuse-package

/// adds を p が use すると名前が衝突するか（衝突すれば package-error を記録して真）
fn useConflict(th: *Thread, p: *PackageData, adds: []const *PackageData) bool {
    const rt = th.rt;
    for (adds, 0..) |u, i| {
        var it = u.external.iterator();
        while (it.next()) |e| {
            const name = e.key_ptr.*;
            const sym = e.value_ptr.*;
            if (rt.findSymbol(p, name)) |f| {
                if (f.symbol != sym and !(f.status != .inherited and p.isShadowing(f.symbol))) {
                    _ = th.signal(.package_error, "use すると、同じ名前の別のシンボルと衝突します", sym, Value.unbound);
                    return true;
                }
            }
            // 同時に use するパッケージどうしの衝突（p にシャドウイングシンボルがあれば衝突しない）
            for (adds[0..i]) |prev| {
                const e2 = prev.external.get(name) orelse continue;
                if (e2 == sym) continue;
                if (p.present(name)) |f| if (p.isShadowing(f.symbol)) continue;
                _ = th.signal(.package_error, "同時に use するパッケージの同じ名前の別のシンボルが衝突します", sym, Value.unbound);
                return true;
            }
        }
    }
    return false;
}

/// p に adds を use させる（重複は除く）。衝突があれば何もせず偽（エラーを記録済み）
pub fn usePackages(th: *Thread, p: *PackageData, adds_in: []const *PackageData) bool {
    const rt = th.rt;
    // KEYWORD はほかのパッケージを use できない（SBCL 2.6.7 は simple-error。Codex のレビュー P22 #4）
    if (p == rt.keyword and adds_in.len != 0) {
        _ = th.signal(.simple_error, "KEYWORD パッケージは、ほかのパッケージを use できません", p.obj, Value.unbound);
        return false;
    }
    var adds: std.ArrayList(*PackageData) = .empty;
    defer adds.deinit(rt.gpa);
    for (adds_in) |u| {
        if (u == rt.keyword) {
            _ = th.signal(.package_error, "KEYWORD パッケージは use できません", u.obj, Value.unbound);
            return false;
        }
        if (u == p) continue;
        if (std.mem.indexOfScalar(*PackageData, p.use_list.items, u) != null) continue;
        if (std.mem.indexOfScalar(*PackageData, adds.items, u) != null) continue;
        adds.append(rt.gpa, u) catch {
            _ = th.outOfMemory();
            return false;
        };
    }
    if (useConflict(th, p, adds.items)) return false;
    p.use_list.ensureUnusedCapacity(rt.gpa, adds.items.len) catch {
        _ = th.outOfMemory();
        return false;
    };
    for (adds.items) |u| {
        u.used_by.append(rt.gpa, p) catch {
            _ = th.outOfMemory();
            return false;
        };
        p.use_list.appendAssumeCapacity(u);
    }
    return true;
}

fn packageItems(th: *Thread, v: Value) ?[]*PackageData {
    const rt = th.rt;
    const items = designatorItems(th, v) orelse return null;
    defer rt.gpa.free(items);
    const out = rt.gpa.alloc(*PackageData, items.len) catch {
        _ = th.outOfMemory();
        return null;
    };
    for (items, 0..) |it, i| {
        out[i] = packageArg(th, it) orelse {
            rt.gpa.free(out);
            return null;
        };
    }
    return out;
}

/// (use-package パッケージ &optional パッケージ)
pub fn usePackage(th: *Thread, args: []const Value) Value {
    const adds = packageItems(th, args[0]) orelse return Value.unwind;
    defer th.rt.gpa.free(adds);
    const p = optPackage(th, args, 1) orelse return Value.unwind;
    if (!usePackages(th, p, adds)) return Value.unwind;
    return th.rt.t;
}

/// (unuse-package パッケージ &optional パッケージ)
pub fn unusePackage(th: *Thread, args: []const Value) Value {
    const dels = packageItems(th, args[0]) orelse return Value.unwind;
    defer th.rt.gpa.free(dels);
    const p = optPackage(th, args, 1) orelse return Value.unwind;
    for (dels) |u| {
        if (std.mem.indexOfScalar(*PackageData, p.use_list.items, u)) |i| _ = p.use_list.orderedRemove(i);
        if (std.mem.indexOfScalar(*PackageData, u.used_by.items, p)) |i| _ = u.used_by.orderedRemove(i);
    }
    return th.rt.t;
}

// ---------------------------------------------------------------------------
// パッケージを作る・名前を変える・削除する

/// 名前の一覧（文字列指定子のリスト）を UTF-8 の配列にする。呼び出し側が freeNames で解放する
fn namesArg(th: *Thread, v: Value) ?[][]u8 {
    const rt = th.rt;
    const items = designatorItems(th, v) orelse return null;
    defer rt.gpa.free(items);
    const out = rt.gpa.alloc([]u8, items.len) catch {
        _ = th.outOfMemory();
        return null;
    };
    for (items, 0..) |it, i| {
        out[i] = designatorName(th, it) orelse {
            freeNames(rt.gpa, out[0..i]);
            rt.gpa.free(out);
            return null;
        };
    }
    return out;
}

fn freeNames(gpa: std.mem.Allocator, names: [][]u8) void {
    for (names) |n| gpa.free(n);
}

/// 名前・別名が、ほかのパッケージ（except 以外）の名前・別名と重なれば package-error を記録して真
fn nameTaken(th: *Thread, name: []const u8, except: ?*PackageData, datum: Value) bool {
    if (th.rt.findPackageGlobal(name)) |q| if (q != except) {
        _ = th.signal(.package_error, "その名前のパッケージは既にあります", datum, Value.unbound);
        return true;
    };
    return false;
}

/// (make-package 名前 &key nicknames use)：use の既定は空（SBCL 2.6.7 と同じ）
pub fn makePackage(th: *Thread, args: []const Value) Value {
    const rt = th.rt;
    var kv: [2]?Value = undefined;
    if (!keyargs.parse(th, args[1..], &.{ "NICKNAMES", "USE" }, &kv)) return Value.unwind;
    const name = designatorName(th, args[0]) orelse return Value.unwind;
    defer rt.gpa.free(name);
    const nicks = namesArg(th, kv[0] orelse Value.nil) orelse return Value.unwind;
    defer {
        freeNames(rt.gpa, nicks);
        rt.gpa.free(nicks);
    }
    const uses = packageItems(th, kv[1] orelse Value.nil) orelse return Value.unwind;
    defer rt.gpa.free(uses);
    if (nameTaken(th, name, null, args[0])) return Value.unwind;
    for (nicks) |n| if (nameTaken(th, n, null, args[0])) return Value.unwind;
    const p = rt.makePackage(name, @ptrCast(nicks)) catch return oom(th);
    if (!usePackages(th, p, uses)) return Value.unwind;
    return p.obj;
}

/// (rename-package パッケージ 新しい名前 &optional 新しい別名)
pub fn renamePackage(th: *Thread, args: []const Value) Value {
    const rt = th.rt;
    const p = packageArg(th, args[0]) orelse return Value.unwind;
    const name = designatorName(th, args[1]) orelse return Value.unwind;
    const nicks = namesArg(th, if (args.len > 2) args[2] else Value.nil) orelse {
        rt.gpa.free(name);
        return Value.unwind;
    };
    var ok = !nameTaken(th, name, p, args[1]);
    if (ok) for (nicks) |n| if (nameTaken(th, n, p, args[1])) {
        ok = false;
        break;
    };
    if (!ok) {
        rt.gpa.free(name);
        freeNames(rt.gpa, nicks);
        rt.gpa.free(nicks);
        return Value.unwind;
    }
    rt.gpa.free(p.name);
    for (p.nicknames) |n| rt.gpa.free(n);
    rt.gpa.free(p.nicknames);
    p.name = name;
    p.nicknames = @ptrCast(nicks);
    return p.obj;
}

/// (delete-package パッケージ)：削除して T。既に削除したパッケージなら NIL。
/// 標準のパッケージと、ほかのパッケージが use しているパッケージは削除できない（package-error。
/// SBCL 2.6.7 は continue の restart で unuse してから削除する。restart は Phase 25）
pub fn deletePackage(th: *Thread, args: []const Value) Value {
    const rt = th.rt;
    if (Runtime.isPackage(args[0]) and Runtime.packageData(args[0]).deleted) return Value.nil;
    const p = packageArg(th, args[0]) orelse return Value.unwind;
    for ([_]*PackageData{ rt.cl, rt.cl_user, rt.keyword, rt.zilisp, rt.sys }) |std_p| {
        if (p == std_p) return th.signal(.package_error, "標準のパッケージは削除できません", p.obj, Value.unbound);
    }
    if (p.used_by.items.len != 0) return th.signal(.package_error, "ほかのパッケージが use しているパッケージは削除できません", p.obj, Value.unbound);
    rt.deleted_packages.ensureUnusedCapacity(rt.gpa, 1) catch return oom(th);
    for (p.use_list.items) |u| {
        if (std.mem.indexOfScalar(*PackageData, u.used_by.items, p)) |i| _ = u.used_by.orderedRemove(i);
    }
    // ホームパッケージが p のシンボルは、ホームを NIL にする
    for ([_]*std.StringHashMapUnmanaged(Value){ &p.internal, &p.external }) |t| {
        var it = t.valueIterator();
        while (it.next()) |s| if (s.* != Value.nil and symbolHome(rt, s.*) == p.obj) setSymbolHome(rt, s.*, Value.nil);
    }
    // ほかのパッケージのローカルの別名から外す
    for (rt.packages.items) |q| {
        var i: usize = 0;
        while (i < q.local_nicknames.items.len) {
            if (q.local_nicknames.items[i].pkg == p) {
                rt.gpa.free(q.local_nicknames.items[i].name);
                _ = q.local_nicknames.orderedRemove(i);
            } else i += 1;
        }
    }
    if (std.mem.indexOfScalar(*PackageData, rt.packages.items, p)) |i| _ = rt.packages.orderedRemove(i);
    var it1 = p.internal.keyIterator();
    while (it1.next()) |k| rt.gpa.free(k.*);
    p.internal.clearAndFree(rt.gpa);
    var it2 = p.external.keyIterator();
    while (it2.next()) |k| rt.gpa.free(k.*);
    p.external.clearAndFree(rt.gpa);
    p.use_list.clearAndFree(rt.gpa);
    p.shadowing.clearAndFree(rt.gpa);
    p.deleted = true;
    rt.deleted_packages.appendAssumeCapacity(p);
    return rt.t;
}

/// (find-all-symbols 名前)：その名前のシンボルがある（present）パッケージのシンボルすべて（同じものは1つ）
pub fn findAllSymbols(th: *Thread, args: []const Value) Value {
    const rt = th.rt;
    const name = designatorName(th, args[0]) orelse return Value.unwind;
    defer rt.gpa.free(name);
    var list = Value.nil;
    for (rt.packages.items) |p| {
        const f = p.present(name) orelse continue;
        var x = list;
        var dup = false;
        while (x.isCons()) : (x = Runtime.consPtr(x).cdr) {
            if (Runtime.consPtr(x).car == f.symbol) dup = true;
        }
        if (!dup) list = rt.cons(f.symbol, list) catch return oom(th);
    }
    return list;
}

// ---------------------------------------------------------------------------
// ZILISP-SYSTEM の関数（boot.lisp のマクロが使う）

/// ZILISP-SYSTEM::%TYPE-ERROR 値 型：type-error（boot.lisp のマクロが引数を検査するとき）
pub fn sysTypeError(th: *Thread, args: []const Value) Value {
    return th.typeError(args[0], args[1]);
}

/// ZILISP-SYSTEM::%FIND-PACKAGE-OR-LOSE 指定子：in-package が使う（なければ package-error）
pub fn sysFindPackageOrLose(th: *Thread, args: []const Value) Value {
    const p = packageArg(th, args[0]) orelse return Value.unwind;
    return p.obj;
}

/// ZILISP-SYSTEM::%PACKAGE-SYMBOLS パッケージ 種類：シンボルのリスト（do-symbols などが使う）。
/// 種類は :external（外部）、:present（あるもの）、:accessible（アクセスできるもの。継承したものは、同名のものが
/// p にないときだけ）
pub fn sysPackageSymbols(th: *Thread, args: []const Value) Value {
    const rt = th.rt;
    const p = packageArg(th, args[0]) orelse return Value.unwind;
    const kind = args[1];
    const external_only = kind == (rt.internKeyword("EXTERNAL") catch return oom(th));
    const accessible = kind == (rt.internKeyword("ACCESSIBLE") catch return oom(th));
    var list = Value.nil;
    var et = p.external.valueIterator();
    while (et.next()) |s| list = rt.cons(s.*, list) catch return oom(th);
    if (external_only) return list;
    var it = p.internal.valueIterator();
    while (it.next()) |s| list = rt.cons(s.*, list) catch return oom(th);
    if (!accessible) return list;
    for (p.use_list.items) |u| {
        var ut = u.external.iterator();
        while (ut.next()) |e| {
            // 見えるのは、findSymbol がそのシンボルを返すときだけ（同名のものが p にあるか、先に use したパッケージにあれば隠れる）
            const f = rt.findSymbol(p, e.key_ptr.*) orelse continue;
            if (f.symbol != e.value_ptr.* or f.status != .inherited) continue;
            list = rt.cons(e.value_ptr.*, list) catch return oom(th);
        }
    }
    return list;
}

/// ZILISP-SYSTEM::%ALL-PACKAGE-SYMBOLS：すべてのパッケージにあるシンボル（do-all-symbols。同じシンボルが何度も現れてよい）
pub fn sysAllPackageSymbols(th: *Thread, args: []const Value) Value {
    _ = args;
    const rt = th.rt;
    var list = Value.nil;
    for (rt.packages.items) |p| {
        for ([_]*std.StringHashMapUnmanaged(Value){ &p.external, &p.internal }) |t| {
            var it = t.valueIterator();
            while (it.next()) |s| list = rt.cons(s.*, list) catch return oom(th);
        }
    }
    return list;
}

/// ZILISP-SYSTEM::%DEFPACKAGE 名前 別名 use 'use を指定したか shadow shadowing-import-from import-from intern export
///   local-nicknames：defpackage の本体（CLHS defpackage の順序：shadow・shadowing-import-from、use、import-from・
///   intern、export）。既にあるパッケージは、その設定に足す（SBCL 2.6.7 は前の設定との違いを警告し、export・shadow は残す）
pub fn sysDefpackage(th: *Thread, args: []const Value) Value {
    const rt = th.rt;
    const name = designatorName(th, args[0]) orelse return Value.unwind;
    defer rt.gpa.free(name);
    const nicks = namesArg(th, args[1]) orelse return Value.unwind;
    defer {
        freeNames(rt.gpa, nicks);
        rt.gpa.free(nicks);
    }
    const uses = packageItems(th, args[2]) orelse return Value.unwind;
    defer rt.gpa.free(uses);
    // :import-from・:shadowing-import-from のパッケージも、先にあるか確かめる
    for ([_]Value{ args[5], args[6] }) |spec_list| {
        var x = spec_list;
        while (x.isCons()) : (x = Runtime.consPtr(x).cdr) {
            _ = packageArg(th, Runtime.consPtr(Runtime.consPtr(x).car).car) orelse return Value.unwind;
        }
    }
    var x_ln = args[9];
    while (x_ln.isCons()) : (x_ln = Runtime.consPtr(x_ln).cdr) {
        _ = packageArg(th, Runtime.consPtr(Runtime.consPtr(x_ln).car).cdr) orelse return Value.unwind;
    }

    const p = rt.findPackageGlobal(name) orelse blk: {
        if (nameTaken(th, name, null, args[0])) return Value.unwind;
        for (nicks) |n| if (nameTaken(th, n, null, args[0])) return Value.unwind;
        break :blk rt.makePackage(name, &.{}) catch return oom(th);
    };
    // 別名（既にあるものに足す）
    for (nicks) |n| {
        if (nameTaken(th, n, p, args[0])) return Value.unwind;
        var found = false;
        for (p.nicknames) |m| if (std.mem.eql(u8, m, n)) {
            found = true;
        };
        if (found) continue;
        const new = rt.gpa.alloc([]const u8, p.nicknames.len + 1) catch return oom(th);
        @memcpy(new[0..p.nicknames.len], p.nicknames);
        new[p.nicknames.len] = rt.gpa.dupe(u8, n) catch {
            rt.gpa.free(new);
            return oom(th);
        };
        rt.gpa.free(p.nicknames);
        p.nicknames = new;
    }
    // :shadow
    if (shadow(th, &.{ args[4], p.obj }) == Value.unwind) return Value.unwind;
    // :shadowing-import-from (パッケージ 名前...)
    var x = args[5];
    while (x.isCons()) : (x = Runtime.consPtr(x).cdr) {
        if (importFrom(th, p, Runtime.consPtr(x).car, true) == Value.unwind) return Value.unwind;
    }
    // :use
    if (!usePackages(th, p, uses)) return Value.unwind;
    // :import-from
    x = args[6];
    while (x.isCons()) : (x = Runtime.consPtr(x).cdr) {
        if (importFrom(th, p, Runtime.consPtr(x).car, false) == Value.unwind) return Value.unwind;
    }
    // :intern
    const interns = namesArg(th, args[7]) orelse return Value.unwind;
    defer {
        freeNames(rt.gpa, interns);
        rt.gpa.free(interns);
    }
    for (interns) |n| _ = rt.intern(p, n) catch return oom(th);
    // :export（なければ intern する）
    const exports = namesArg(th, args[8]) orelse return Value.unwind;
    defer {
        freeNames(rt.gpa, exports);
        rt.gpa.free(exports);
    }
    var list = Value.nil;
    for (exports) |n| {
        const s = rt.intern(p, n) catch return oom(th);
        list = rt.cons(s, list) catch return oom(th);
    }
    if (list != Value.nil and exportSymbols(th, &.{ list, p.obj }) == Value.unwind) return Value.unwind;
    // :local-nicknames ((別名 パッケージ) ...)
    var ln = args[9];
    while (ln.isCons()) : (ln = Runtime.consPtr(ln).cdr) {
        const pair = Runtime.consPtr(ln).car;
        const nick = designatorName(th, Runtime.consPtr(pair).car) orelse return Value.unwind;
        const target = packageArg(th, Runtime.consPtr(pair).cdr) orelse {
            rt.gpa.free(nick);
            return Value.unwind;
        };
        var replaced = false;
        for (p.local_nicknames.items) |*e| if (std.mem.eql(u8, e.name, nick)) {
            e.pkg = target;
            replaced = true;
        };
        if (replaced) {
            rt.gpa.free(nick);
            continue;
        }
        p.local_nicknames.append(rt.gpa, .{ .name = nick, .pkg = target }) catch {
            rt.gpa.free(nick);
            return oom(th);
        };
    }
    return p.obj;
}

/// (パッケージ 名前...) のシンボルを p に import する（shadowing なら shadowing-import）。名前のシンボルがなければ package-error
fn importFrom(th: *Thread, p: *PackageData, spec: Value, shadowing: bool) Value {
    const rt = th.rt;
    const from = packageArg(th, Runtime.consPtr(spec).car) orelse return Value.unwind;
    var list = Value.nil;
    var x = Runtime.consPtr(spec).cdr;
    while (x.isCons()) : (x = Runtime.consPtr(x).cdr) {
        const n = designatorName(th, Runtime.consPtr(x).car) orelse return Value.unwind;
        defer rt.gpa.free(n);
        const f = rt.findSymbol(from, n) orelse return th.signal(.package_error, "そのパッケージにその名前のシンボルがありません", Runtime.consPtr(x).car, Value.unbound);
        list = rt.cons(f.symbol, list) catch return oom(th);
    }
    if (list == Value.nil) return rt.t;
    return if (shadowing) shadowingImport(th, &.{ list, p.obj }) else importSymbols(th, &.{ list, p.obj });
}
