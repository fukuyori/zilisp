//! Reader が読んだものから Lisp の値（Value）を作る Builder（詳細設計 §5、§8）。
//!
//! Phase 05 の制限（明示的なエラーにする。黙って別の値を返さない：基本設計 §3.1）
//!   - fixnum の範囲（±2^61）を超える整数：bignum は Phase 20 で実装
//!   - 比：有理数は Phase 20 で実装

const std = @import("std");
const reader = @import("reader.zig");
const rt_mod = @import("../runtime/runtime.zig");
const Runtime = rt_mod.Runtime;
const Value = rt_mod.Value;
const Diagnostic = reader.Diagnostic;
const SourceLoc = reader.SourceLoc;
const Error = reader.Error;

pub const ValueBuilder = struct {
    rt: *Runtime,

    pub const Datum = Value;
    /// 組み立て中のリスト（先頭と最後の cons）
    pub const List = struct { head: Value = Value.nil, last: Value = Value.nil, count: usize = 0 };

    fn fail(diag: *Diagnostic, loc: SourceLoc, message: []const u8) Error {
        diag.* = .{ .loc = loc, .message = message };
        return error.ReaderError;
    }

    pub fn integer(b: *ValueBuilder, diag: *Diagnostic, loc: SourceLoc, negative: bool, digits: []const u8, radix: u8) Error!Value {
        _ = b;
        var acc: i64 = 0;
        for (digits) |c| {
            const d: i64 = switch (c) {
                '0'...'9' => c - '0',
                'a'...'z' => c - 'a' + 10,
                'A'...'Z' => c - 'A' + 10,
                else => unreachable,
            };
            const m = @mulWithOverflow(acc, @as(i64, radix));
            if (m[1] != 0) return fail(diag, loc, "fixnum の範囲を超える整数は未実装です（bignum は Phase 20 で実装予定）");
            const s = @addWithOverflow(m[0], d);
            if (s[1] != 0) return fail(diag, loc, "fixnum の範囲を超える整数は未実装です（bignum は Phase 20 で実装予定）");
            acc = s[0];
        }
        const v = if (negative) -acc else acc;
        if (!Value.fixnumFits(v)) return fail(diag, loc, "fixnum の範囲を超える整数は未実装です（bignum は Phase 20 で実装予定）");
        return Value.fromFixnum(v);
    }

    pub fn ratio(b: *ValueBuilder, diag: *Diagnostic, loc: SourceLoc, negative: bool, num: []const u8, den: []const u8, radix: u8) Error!Value {
        _ = .{ b, negative, num, den, radix };
        return fail(diag, loc, "比は未実装です（有理数は Phase 20 で実装予定）");
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
            .current => try rt.intern(rt.current, name),
            .keyword => try rt.internKeyword(name),
            .uninterned => try rt.makeSymbol(name),
            .named => |n| blk: {
                const p = rt.findPackage(n.name) orelse return fail(diag, loc, "そのパッケージはありません");
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
        const items = try b.rt.gpa.alloc(Value, list.count);
        defer b.rt.gpa.free(items);
        var x = list.head;
        for (items) |*it| {
            const c = Runtime.consPtr(x);
            it.* = c.car;
            x = c.cdr;
        }
        return b.rt.makeVector(items);
    }
};

/// テキストから全てのデータを読む（試験・--read 用）
pub fn readAll(rt: *Runtime, gpa: std.mem.Allocator, text: []const u8, out: *std.ArrayList(Value), diag: *Diagnostic) Error!void {
    var src = reader.Source.init(text, 0);
    var b: ValueBuilder = .{ .rt = rt };
    var r = reader.Reader(ValueBuilder).init(gpa, &src, &b, .{});
    defer r.deinit();
    while (true) {
        const v = r.read() catch |err| {
            diag.* = r.diagnostic;
            return err;
        };
        try out.append(gpa, v orelse break);
    }
}
