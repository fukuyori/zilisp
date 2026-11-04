//! 印字（CLHS 22.1「The Lisp Printer」）。規則は SBCL 2.6.7 の出力に合わせる（CLHS 22.1.3「Default Print-Object Methods」）。
//! 印字の変数（Phase 24）：*print-escape*・*print-readably*・*print-base*・*print-radix*・*print-case*・*print-circle*・
//! *print-level*・*print-length*・*print-array*・*print-gensym*、と *read-default-float-format*（浮動小数の指数の印）。
//! 印字の前に変数の値を Settings に読み取る（Settings.current）。エラーの報告など処理系の内部の印字は、変数によらない
//! Settings.standard を使う（prin1・princ・write）。
//! *print-readably* が真のとき、読み戻せないもの（関数・ストリーム・パッケージ・ハッシュ表など）は error.NotReadable
//! （呼び出し側が print-not-readable のエラーにする）。
//! *print-circle*：先に同じ範囲（*print-level*・*print-length* の内側）を走査し、2回以上現れるもの（数・文字・intern された
//! シンボル以外）に #n= と #n# を付ける（SBCL 2.6.7 と同じ。関数・ハッシュ表・パス名も対象）。

const std = @import("std");
const rt_mod = @import("../runtime/runtime.zig");
const syntax = @import("../reader/syntax.zig");
const number = @import("../reader/number.zig");
const unicode = @import("../unicode/unicode.zig");
const reader = @import("../reader/reader.zig");
const readtable_mod = @import("../reader/readtable.zig");
const Runtime = rt_mod.Runtime;
const Value = rt_mod.Value;
const Writer = std.Io.Writer;

pub const Error = error{ WriteFailed, NotReadable };

pub const Case = enum { upcase, downcase, capitalize };

/// 印字の設定（印字の変数の値）
pub const Settings = struct {
    escape: bool = true,
    readably: bool = false,
    base: u8 = 10,
    radix: bool = false,
    case: Case = .upcase,
    circle: bool = false,
    level: ?usize = null,
    length: ?usize = null,
    array: bool = true,
    gensym: bool = true,
    /// *read-default-float-format* が double-float（または long-float）
    double_default: bool = false,
    /// *readtable* の readtable-case と、標準でない readtable（マクロ文字のエスケープの判定に使う。標準なら NIL。Phase 24）
    rt_case: reader.Case = .upcase,
    readtable: Value = Value.nil,

    /// 印字の変数によらない設定（処理系の内部の印字）
    pub fn standard(escape: bool) Settings {
        return .{ .escape = escape };
    }

    /// 今の印字の変数の値から作る。escape が null なら *print-escape* を使う。
    /// *print-readably* が真なら、escape・array・gensym を真に、level・length を NIL とみなす（CLHS *print-readably*）
    pub fn current(rt: *Runtime, escape: ?bool) Settings {
        const y = &rt.syms;
        var s: Settings = .{};
        s.escape = escape orelse truthy(rt, y.@"*print-escape*", true);
        s.readably = truthy(rt, y.@"*print-readably*", false);
        const b = rt.symbolPtr(y.@"*print-base*").value;
        if (b.isFixnum() and b.asFixnum() >= 2 and b.asFixnum() <= 36) s.base = @intCast(b.asFixnum());
        s.radix = truthy(rt, y.@"*print-radix*", false);
        const c = rt.symbolPtr(y.@"*print-case*").value;
        if (c.isOther() and Runtime.kindOf(c) == .symbol) {
            const name = rt.symbolPtr(c).name;
            if (stringIs(name, "DOWNCASE")) s.case = .downcase else if (stringIs(name, "CAPITALIZE")) s.case = .capitalize;
        }
        s.circle = truthy(rt, y.@"*print-circle*", false);
        s.level = limit(rt, y.@"*print-level*");
        s.length = limit(rt, y.@"*print-length*");
        s.array = truthy(rt, y.@"*print-array*", true);
        s.gensym = truthy(rt, y.@"*print-gensym*", true);
        const f = rt.symbolPtr(y.@"*read-default-float-format*").value;
        s.double_default = f == y.@"double-float" or f == y.@"long-float";
        // princ（escape を偽と指定）は *print-readably* も偽で印字する（CLHS princ）
        if (escape) |e| if (!e) {
            s.readably = false;
        };
        if (s.readably) {
            s.escape = true;
            s.array = true;
            s.gensym = true;
            s.level = null;
            s.length = null;
        }
        // シンボルは *readtable* に従って書く。*print-readably* なら標準の readtable（SBCL 2.6.7 の output-symbol と同じ）
        if (!s.readably) {
            const rtv = readtable_mod.current(rt);
            s.rt_case = readtable_mod.caseOf(rtv);
            if (readtable_mod.ptr(rtv).header.flags & readtable_mod.Table.standard_flag == 0) s.readtable = rtv;
        }
        return s;
    }
};

fn truthy(rt: *Runtime, sym: Value, default: bool) bool {
    const v = rt.symbolPtr(sym).value;
    if (v == Value.unbound) return default;
    return v != Value.nil;
}

fn limit(rt: *Runtime, sym: Value) ?usize {
    const v = rt.symbolPtr(sym).value;
    if (v.isFixnum() and v.asFixnum() >= 0) return @intCast(v.asFixnum());
    return null;
}

fn stringIs(str: Value, text: []const u8) bool {
    const s = Runtime.stringPtr(str);
    if (s.length() != text.len) return false;
    for (text, 0..) |ch, i| if (s.charAt(i) != ch) return false;
    return true;
}

/// エスケープ付きの印字（処理系の内部用。印字の変数によらない）
pub fn prin1(rt: *Runtime, w: *Writer, v: Value) Writer.Error!void {
    return write(rt, w, v, true);
}

/// princ（処理系の内部用。印字の変数によらない）
pub fn princ(rt: *Runtime, w: *Writer, v: Value) Writer.Error!void {
    return write(rt, w, v, false);
}

/// 処理系の内部の印字（印字の変数によらない）
pub fn write(rt: *Runtime, w: *Writer, v: Value, escape: bool) Writer.Error!void {
    var bad: Value = Value.nil;
    writeObject(rt, w, v, Settings.standard(escape), &bad) catch return error.WriteFailed;
}

/// #nA の形で読み戻せる多次元の配列か（要素の型が T で、長さ 0 の軸より前に長さが 0 でない軸がない。
/// #nA は長さ 0 の軸より後ろの軸の長さを 0 とみなすため。SBCL 2.6.7 の array-readably-printable-p）
pub fn readablyPrintable(dims: []const usize, is_string: bool) bool {
    if (is_string) return false;
    const zero = std.mem.indexOfScalar(usize, dims, 0) orelse return true;
    var last_nonzero: ?usize = null;
    for (dims, 0..) |d, i| if (d != 0) {
        last_nonzero = i;
    };
    const nonzero = last_nonzero orelse return true;
    return zero > nonzero;
}

/// 設定に従って印字する。*print-readably* で読み戻せないものがあれば error.NotReadable（bad にそのオブジェクト）
pub fn writeObject(rt: *Runtime, w: *Writer, v: Value, s: Settings, bad: *Value) Error!void {
    var p: P = .{ .rt = rt, .w = w, .s = s, .bad = bad };
    defer p.labels.deinit(rt.gpa);
    if (s.circle) try p.scan(v, 0);
    return p.obj(v, 0);
}

/// 複数のオブジェクトを順に書く（それぞれの後ろに改行）。*print-circle* の #n= の番号は全体で共有する
/// （ネイティブの定数表。別の定数の中の同じオブジェクトも、読み戻すと同じになる。Codex のレビュー 0.3 #5）。
/// 書けなかったオブジェクトの番号を index に入れる
pub fn writeObjects(rt: *Runtime, w: *Writer, vs: []const Value, s: Settings, bad: *Value, index: *usize) Error!void {
    var p: P = .{ .rt = rt, .w = w, .s = s, .bad = bad };
    defer p.labels.deinit(rt.gpa);
    if (s.circle) for (vs) |v| try p.scan(v, 0);
    for (vs, 0..) |v, i| {
        index.* = i;
        try p.obj(v, 0);
        try w.writeByte('\n');
    }
}

/// 印字の状態
const P = struct {
    rt: *Runtime,
    w: *Writer,
    s: Settings,
    bad: *Value,
    /// *print-circle*：オブジェクトのアドレス → 0（1回だけ）・-1（2回以上で、まだ番号なし）・n（番号）
    labels: std.AutoHashMapUnmanaged(u64, i32) = .empty,
    next_label: i32 = 1,

    fn notReadable(p: *P, v: Value) Error {
        p.bad.* = v;
        return error.NotReadable;
    }

    /// #n= を付ける対象（数・文字・intern されたシンボル以外の、ヒープのオブジェクト）
    fn trackable(p: *P, v: Value) bool {
        if (v.isCons() or v.isFunctionPointer()) return true;
        if (!v.isOther() or v == Value.nil) return false;
        return switch (Runtime.kindOf(v) orelse return false) {
            .bignum, .ratio, .double_float => false,
            .symbol => p.rt.symbolPtr(v).package == Value.nil,
            else => true,
        };
    }

    fn levelExceeded(p: *P, depth: usize) bool {
        return if (p.s.level) |l| depth >= l else false;
    }

    /// *print-circle* の下調べ：印字と同じ範囲を走査して、2回以上現れるものに印を付ける
    fn scan(p: *P, v: Value, depth: usize) Error!void {
        if (!p.trackable(v)) return;
        const container = v.isCons() or (v.isOther() and switch (Runtime.kindOf(v) orelse .symbol) {
            .simple_vector, .array => true,
            else => false,
        });
        if (container and p.levelExceeded(depth)) return;
        const gop = p.labels.getOrPut(p.rt.gpa, v.raw()) catch return error.WriteFailed;
        if (gop.found_existing) {
            gop.value_ptr.* = -1;
            return;
        }
        gop.value_ptr.* = 0;
        if (v.isCons()) {
            var x = v;
            var count: usize = 0;
            while (true) {
                if (p.s.length) |l| if (count >= l) return;
                const c = Runtime.consPtr(x);
                try p.scan(c.car, depth + 1);
                count += 1;
                x = c.cdr;
                if (!x.isCons()) return p.scan(x, depth + 1);
                const g = p.labels.getOrPut(p.rt.gpa, x.raw()) catch return error.WriteFailed;
                if (g.found_existing) {
                    g.value_ptr.* = -1;
                    return;
                }
                g.value_ptr.* = 0;
            }
        }
        if (!v.isOther()) return;
        switch (Runtime.kindOf(v) orelse return) {
            .simple_vector => for (Runtime.vectorPtr(v).items(), 0..) |x, i| {
                if (p.s.length) |l| if (i >= l) break;
                try p.scan(x, depth + 1);
            },
            .array => {
                const object = @import("../values/object.zig");
                const a: *object.Array = @ptrCast(@alignCast(v.pointer()));
                if (Runtime.kindOf(a.data) == .string) return;
                const dims = a.dims();
                const items = Runtime.vectorPtr(a.data).items();
                const n = if (dims.len == 1) (if (a.header.flags & object.Array.has_fill_pointer != 0) a.fill_pointer else dims[0]) else items.len;
                for (items[0..n], 0..) |x, i| {
                    if (dims.len == 1) if (p.s.length) |l| if (i >= l) break;
                    try p.scan(x, depth + dims.len);
                }
            },
            else => {},
        }
    }

    /// オブジェクトを書く（*print-circle* の #n= と #n# を含む）
    fn obj(p: *P, v: Value, depth: usize) Error!void {
        if (p.s.circle and p.trackable(v)) {
            if (p.labels.getPtr(v.raw())) |l| {
                if (l.* > 0) return p.w.print("#{d}#", .{l.*});
                if (l.* < 0) {
                    l.* = p.next_label;
                    p.next_label += 1;
                    try p.w.print("#{d}=", .{l.*});
                }
            }
        }
        return p.body(v, depth);
    }

    fn body(p: *P, v: Value, depth: usize) Error!void {
        const rt = p.rt;
        const w = p.w;
        const escape = p.s.escape;
        if (v.isFixnum()) return p.integer(v);
        if (v == Value.nil) return p.symbol(v);
        if (v.isChar()) return if (escape) printChar(w, v.asChar()) else writeCp(w, v.asChar());
        if (v.isSingleFloat()) return p.float(f32, v.asSingle(), v);
        if (v == Value.unbound) return w.writeAll("#<unbound>");
        if (v == Value.unwind) return w.writeAll("#<unwind>");
        if (v.isCons()) return p.list(v, depth);
        if (v.isFunctionPointer()) {
            if (p.s.readably) return p.notReadable(v);
            return printFunction(rt, w, v);
        }
        switch (Runtime.kindOf(v) orelse return w.print("#<object {x}>", .{v.raw()})) {
            .symbol => return p.symbol(v),
            .string => return if (escape) printString(w, v) else Runtime.writeStringUtf8(v, w),
            .double_float => return p.float(f64, Runtime.doubleValue(v), v),
            .bignum => return p.integer(v),
            .ratio => return p.integer(v),
            .simple_vector => {
                if (!p.s.array) return w.print("#<(SIMPLE-VECTOR {d}) {{{X}}}>", .{ Runtime.vectorPtr(v).items().len, v.raw() & ~@as(u64, 7) });
                if (p.levelExceeded(depth)) return w.writeByte('#');
                return p.vectorItems(Runtime.vectorPtr(v).items(), depth);
            },
            .array => return p.array(v, depth),
            .package => {
                if (p.s.readably) return p.notReadable(v);
                return w.print("#<PACKAGE \"{s}\">", .{Runtime.packageData(v).name});
            },
            .closure, .native_function => {
                if (p.s.readably) return p.notReadable(v);
                return w.print("#<object {x}>", .{v.raw()});
            },
            .code => {
                if (p.s.readably) return p.notReadable(v);
                return w.print("#<CODE {{{X}}}>", .{v.raw() & ~@as(u64, 7)});
            },
            .value_cell => {
                if (p.s.readably) return p.notReadable(v);
                return w.print("#<VALUE-CELL {{{X}}}>", .{v.raw() & ~@as(u64, 7)});
            },
            .hash_table => {
                // SBCL 2.6.7 は #.(MAKE-HASH-TABLE …) で書くが、Zilisp は読み戻せないものとする（impl-dependent.toml）
                if (p.s.readably) return p.notReadable(v);
                const object = @import("../values/object.zig");
                const t: *object.HashTable = @ptrCast(@alignCast(v.pointer()));
                const name = switch (@as(object.HashTest, @fromBackingInt(t.header.aux))) {
                    .eq => "EQ",
                    .eql => "EQL",
                    .equal => "EQUAL",
                    .equalp => "EQUALP",
                };
                // SBCL 2.6.7 と同じ形：#<HASH-TABLE :TEST EQL :COUNT 2 {…}>
                return w.print("#<HASH-TABLE :TEST {s} :COUNT {d} {{{X}}}>", .{ name, t.count, v.raw() & ~@as(u64, 7) });
            },
            .stream => {
                if (p.s.readably) return p.notReadable(v);
                return @import("../primitives/streams.zig").printStream(rt, w, v);
            },
            .pathname => {
                const pathnames = @import("../primitives/pathnames.zig");
                if (!escape) return pathnames.writeNamestring(rt, w, v);
                // #P"..."（" と \ はエスケープする）
                var buf: Writer.Allocating = .init(rt.gpa);
                defer buf.deinit();
                pathnames.writeNamestring(rt, &buf.writer, v) catch return error.WriteFailed;
                try w.writeAll("#P\"");
                for (buf.written()) |c| {
                    if (c == '"' or c == '\\') try w.writeByte('\\');
                    try w.writeByte(c);
                }
                return w.writeByte('"');
            },
            .readtable => {
                if (p.s.readably) return p.notReadable(v);
                return w.print("#<READTABLE {{{X}}}>", .{v.raw() & ~@as(u64, 7)});
            },
            .pprint_dispatch => {
                if (p.s.readably) return p.notReadable(v);
                return w.print("#<PPRINT-DISPATCH-TABLE {{{X}}}>", .{v.raw() & ~@as(u64, 7)});
            },
            // raw_vector はハッシュ表の中だけで使い、Lisp からは見えない
            .raw_vector, _ => return w.print("#<object {x}>", .{v.raw()}),
        }
    }

    /// リスト（*print-level* を超えれば #、*print-length* を超えた残りは ...。CLHS 22.1.3.5）
    fn list(p: *P, v: Value, depth: usize) Error!void {
        if (p.levelExceeded(depth)) return p.w.writeByte('#');
        const w = p.w;
        try w.writeByte('(');
        var x = v;
        var count: usize = 0;
        while (true) {
            if (count > 0) try w.writeByte(' ');
            if (p.s.length) |l| if (count >= l) {
                try w.writeAll("...");
                x = Value.nil;
                break;
            };
            const c = Runtime.consPtr(x);
            try p.obj(c.car, depth + 1);
            count += 1;
            x = c.cdr;
            if (!x.isCons()) break;
            // 尾が共有されていれば . #n# か . #n=(…) の形にする（*print-circle*）
            if (p.s.circle) if (p.labels.get(x.raw())) |l| if (l != 0) {
                try w.writeAll(" . ");
                try p.obj(x, depth + 1);
                x = Value.nil;
                break;
            };
        }
        if (x != Value.nil) {
            try w.writeAll(" . ");
            try p.obj(x, depth + 1);
        }
        try w.writeByte(')');
    }

    fn vectorItems(p: *P, items: []const Value, depth: usize) Error!void {
        try p.w.writeAll("#(");
        for (items, 0..) |x, i| {
            if (i > 0) try p.w.writeByte(' ');
            if (p.s.length) |l| if (i >= l) {
                try p.w.writeAll("...");
                break;
            };
            try p.obj(x, depth + 1);
        }
        try p.w.writeByte(')');
    }

    /// 単純でない配列（Phase 21）。1次元はベクタ・文字列と同じ形で、有効な部分（fill-pointer まで）だけを書く。
    /// 多次元は #nA((…) …)、0次元は #0A要素（SBCL 2.6.7 と同じ。CLHS 22.1.3.8）
    fn array(p: *P, v: Value, depth: usize) Error!void {
        const object = @import("../values/object.zig");
        const w = p.w;
        const a: *object.Array = @ptrCast(@alignCast(v.pointer()));
        const dims = a.dims();
        const is_string = Runtime.kindOf(a.data) == .string;
        if (dims.len == 1) {
            const n = if (a.header.flags & object.Array.has_fill_pointer != 0) a.fill_pointer else dims[0];
            if (is_string) {
                const s = Runtime.stringPtr(a.data);
                if (p.s.escape) try w.writeByte('"');
                for (0..n) |i| {
                    const cp = s.charAt(i);
                    if (p.s.escape and (cp == '"' or cp == '\\')) try w.writeByte('\\');
                    try writeCp(w, cp);
                }
                if (p.s.escape) try w.writeByte('"');
                return;
            }
            if (!p.s.array) return w.print("#<(VECTOR T {d}) {{{X}}}>", .{ dims[0], v.raw() & ~@as(u64, 7) });
            if (p.levelExceeded(depth)) return w.writeByte('#');
            return p.vectorItems(Runtime.vectorPtr(a.data).items()[0..n], depth);
        }
        if (!p.s.array) {
            const simple = a.header.flags & (object.Array.has_fill_pointer | object.Array.adjustable) == 0;
            try w.print("#<({s} {s} ", .{ if (simple) "SIMPLE-ARRAY" else "ARRAY", if (is_string) "CHARACTER" else "T" });
            if (dims.len == 0) try w.writeAll("NIL") else {
                try w.writeByte('(');
                for (dims, 0..) |d, i| {
                    if (i > 0) try w.writeByte(' ');
                    try w.print("{d}", .{d});
                }
                try w.writeByte(')');
            }
            return w.print(") {{{X}}}>", .{v.raw() & ~@as(u64, 7)});
        }
        if (p.s.readably and !readablyPrintable(dims, is_string)) return p.arrayWithType(a.data, is_string, dims, depth);
        try w.print("#{d}A", .{dims.len});
        var index: usize = 0;
        return p.arrayAxis(a.data, is_string, dims, &index, depth);
    }

    /// #A(次元 要素の型 . 中身)：#nA では読み戻せない配列を *print-readably* で書く形
    /// （SBCL 2.6.7 の output-unreadable-array-readably。中身は各行のリスト）
    fn arrayWithType(p: *P, data: Value, is_string: bool, dims: []const usize, depth: usize) Error!void {
        const w = p.w;
        // 次元・NIL・要素の型も、ふつうのオブジェクトとして書く（*package* によってはパッケージ名が付く）
        try w.writeAll("#A(");
        if (dims.len == 0) try p.obj(Value.nil, depth + 1) else {
            try w.writeByte('(');
            for (dims, 0..) |d, i| {
                if (i > 0) try w.writeByte(' ');
                try p.obj(Value.fromFixnum(@intCast(d)), depth + 2);
            }
            try w.writeByte(')');
        }
        try w.writeByte(' ');
        const etype = (p.rt.findSymbol(p.rt.cl, if (is_string) "CHARACTER" else "T") orelse unreachable).symbol;
        try p.obj(etype, depth + 1);
        var index: usize = 0;
        if (dims.len == 0) {
            try w.writeAll(" . ");
            try p.listAxis(data, is_string, dims, &index, depth + 1);
        } else for (0..dims[0]) |_| {
            try w.writeByte(' ');
            try p.listAxis(data, is_string, dims[1..], &index, depth + 1);
        }
        try w.writeByte(')');
    }

    /// arrayWithType の中身の1つの軸（リストとして書く。空なら NIL）
    fn listAxis(p: *P, data: Value, is_string: bool, dims: []const usize, index: *usize, depth: usize) Error!void {
        if (dims.len == 0) {
            const x = if (is_string) Value.fromChar(Runtime.stringPtr(data).charAt(index.*)) else Runtime.vectorPtr(data).items()[index.*];
            index.* += 1;
            return p.obj(x, depth);
        }
        if (dims[0] == 0) return p.obj(Value.nil, depth);
        try p.w.writeByte('(');
        for (0..dims[0]) |i| {
            if (i > 0) try p.w.writeByte(' ');
            try p.listAxis(data, is_string, dims[1..], index, depth + 1);
        }
        try p.w.writeByte(')');
    }

    fn arrayAxis(p: *P, data: Value, is_string: bool, dims: []const usize, index: *usize, depth: usize) Error!void {
        const w = p.w;
        if (dims.len == 0) {
            const x = if (is_string) Value.fromChar(Runtime.stringPtr(data).charAt(index.*)) else Runtime.vectorPtr(data).items()[index.*];
            index.* += 1;
            return p.obj(x, depth);
        }
        if (p.levelExceeded(depth)) {
            index.* += product(dims);
            return w.writeByte('#');
        }
        try w.writeByte('(');
        for (0..dims[0]) |i| {
            if (i > 0) try w.writeByte(' ');
            if (p.s.length) |l| if (i >= l) {
                try w.writeAll("...");
                index.* += (dims[0] - i) * product(dims[1..]);
                break;
            };
            try p.arrayAxis(data, is_string, dims[1..], index, depth + 1);
        }
        try w.writeByte(')');
    }

    /// 整数と比（*print-base*・*print-radix*。CLHS 22.1.3.1.1・22.1.3.1.2）
    fn integer(p: *P, v: Value) Error!void {
        const w = p.w;
        const base = p.s.base;
        const is_ratio = v.isOther() and Runtime.kindOf(v) == .ratio;
        if (p.s.radix) {
            switch (base) {
                2 => try w.writeAll("#b"),
                8 => try w.writeAll("#o"),
                16 => try w.writeAll("#x"),
                10 => if (is_ratio) try w.writeAll("#10r"),
                else => try w.print("#{d}r", .{base}),
            }
        }
        if (is_ratio) {
            const r = Runtime.ratioPtr(v);
            try p.digits(r.numerator);
            try w.writeByte('/');
            try p.digits(r.denominator);
        } else try p.digits(v);
        if (p.s.radix and base == 10 and !is_ratio) try w.writeByte('.');
    }

    fn digits(p: *P, v: Value) Error!void {
        if (v.isFixnum()) {
            const n = v.asFixnum();
            if (p.s.base == 10) return p.w.print("{d}", .{n});
            var buf: [72]u8 = undefined;
            if (n < 0) try p.w.writeByte('-');
            return p.w.writeAll(fmtBase(@abs(n), p.s.base, &buf));
        }
        const base = p.s.base;
        // 2 の累乗の基数（4・8・32）は、2 進の文字列から作る（Zig 0.17.0 の toStringAlloc は、(expt 2 70) を基数 8 で
        // 2^72 の、基数 32 で 2^71 の桁にした。基数 2・4・16 は正しい。docs/zig-std-usage.md）
        const bits: u8 = switch (base) {
            4 => 2,
            8 => 3,
            32 => 5,
            else => 0,
        };
        const text = Runtime.bignumConst(v).toStringAlloc(p.rt.gpa, if (bits != 0) 2 else base, .upper) catch return error.WriteFailed;
        defer p.rt.gpa.free(text);
        if (bits == 0) return p.w.writeAll(text);
        const neg = text.len > 0 and text[0] == '-';
        const bin = if (neg) text[1..] else text;
        if (neg) try p.w.writeByte('-');
        // 先頭の桁の幅（2 進の桁数を bits で割った余り。0 なら bits）
        var i: usize = 0;
        var width: usize = bin.len % bits;
        if (width == 0) width = bits;
        while (i < bin.len) {
            var d: u8 = 0;
            for (bin[i .. i + width]) |c| d = d * 2 + (c - '0');
            try p.w.writeByte(if (d < 10) '0' + d else 'A' + d - 10);
            i += width;
            width = bits;
        }
    }

    fn float(p: *P, comptime T: type, x: T, v: Value) Error!void {
        if (p.s.readably and (std.math.isNan(x) or std.math.isInf(x))) return p.notReadable(v);
        return printFloat(p.w, T, x, p.s.double_default);
    }

    /// シンボル（パッケージの修飾、|…|、*print-case*、*print-gensym*）
    fn symbol(p: *P, v: Value) Error!void {
        const rt = p.rt;
        const w = p.w;
        if (v == Value.nil) {
            if (!p.s.escape) return writeCased(w, "NIL", p.s.case, p.s.rt_case);
            return p.nilSymbol();
        }
        const sym = rt.symbolPtr(v);
        var name_buf: Writer.Allocating = .init(rt.gpa);
        defer name_buf.deinit();
        Runtime.writeStringUtf8(sym.name, &name_buf.writer) catch return error.WriteFailed;
        const name = name_buf.written();
        if (!p.s.escape) return writeCased(w, name, p.s.case, p.s.rt_case);

        if (sym.package == Value.nil) {
            if (p.s.gensym) try w.writeAll("#:");
        } else {
            const home = Runtime.packageData(sym.package);
            if (home == rt.keyword) {
                try w.writeByte(':');
            } else if (qualify_all) {
                try writeSymbolName(rt, w, home.name, &standard_token);
                try w.writeAll("::");
            } else {
                // 今のパッケージから同じシンボルが見えれば修飾しない
                const cur = rt.currentPackage();
                const visible = if (cur) |c| (if (rt.findSymbol(c, name)) |f| f.symbol == v else false) else false;
                if (!visible) {
                    // 今のパッケージにホームパッケージのローカルの別名があれば、それで修飾する（SBCL 2.6.7 と同じ。Phase 22）
                    var prefix = home.name;
                    if (cur) |c| for (c.local_nicknames.items) |n| if (n.pkg == home) {
                        prefix = n.name;
                        break;
                    };
                    try writeSymbolName(rt, w, prefix, &p.s);
                    const external = if (home.external.get(name)) |s| s == v else false;
                    try w.writeAll(if (external) ":" else "::");
                }
            }
        }
        try writeSymbolName(rt, w, name, if (qualify_all) &standard_token else &p.s);
    }

    /// NIL（即値）。エスケープ付きの印字では、ほかのシンボルと同じく、今のパッケージから見えなければ修飾する
    /// （CL を use しないパッケージでは COMMON-LISP:NIL。SBCL 2.6.7 と同じ。Codex のレビュー P22 #5）
    fn nilSymbol(p: *P) Error!void {
        const rt = p.rt;
        const w = p.w;
        if (qualify_all) return w.writeAll("COMMON-LISP::NIL");
        const cur = rt.currentPackage();
        const visible = if (cur) |c| (if (rt.findSymbol(c, "NIL")) |f| f.symbol == Value.nil else false) else false;
        // 名前は、ほかのシンボルと同じく readtable に従って囲む（:downcase なら |NIL|。Codex のレビュー 0.3 #3）
        if (visible) return writeSymbolName(rt, w, "NIL", &p.s);
        var prefix: []const u8 = rt.cl.name;
        if (cur) |c| for (c.local_nicknames.items) |n| if (n.pkg == rt.cl) {
            prefix = n.name;
            break;
        };
        try writeSymbolName(rt, w, prefix, &p.s);
        try w.writeByte(':');
        return writeSymbolName(rt, w, "NIL", &p.s);
    }
};

fn product(dims: []const usize) usize {
    var n: usize = 1;
    for (dims) |d| n *= d;
    return n;
}

/// 符号なしの整数を base 進で書く（英字の数字は大文字。SBCL 2.6.7 と同じ）
fn fmtBase(n: u64, base: u8, buf: []u8) []const u8 {
    var i = buf.len;
    var x = n;
    while (true) {
        const d: u8 = @intCast(x % base);
        i -= 1;
        buf[i] = if (d < 10) '0' + d else 'A' + d - 10;
        x /= base;
        if (x == 0) break;
    }
    return buf[i..];
}

/// シンボル名を、*print-case* と readtable-case に従って書く（SBCL 2.6.7 の output-symbol-case-dispatch と同じ）：
///   :upcase の readtable   *print-case* :upcase はそのまま、:downcase はすべて小文字、:capitalize は単語の先頭以外の大文字を小文字に
///   :downcase の readtable :upcase はすべて大文字、:downcase はそのまま、:capitalize は単語の先頭を大文字に
///   :preserve はそのまま、:invert は大文字だけなら小文字に、小文字だけなら大文字に（*print-case* によらない）
/// 単語は英数字の並び
fn writeCased(w: *Writer, name: []const u8, case: Case, rt_case: reader.Case) Writer.Error!void {
    const Mode = enum { preserve, lower, upper, cap_up, cap_down };
    var mode: Mode = switch (rt_case) {
        .upcase => switch (case) {
            .upcase => .preserve,
            .downcase => .lower,
            .capitalize => .cap_up,
        },
        .downcase => switch (case) {
            .upcase => .upper,
            .downcase => .preserve,
            .capitalize => .cap_down,
        },
        .preserve => .preserve,
        .invert => blk: {
            var all_upper = true;
            var all_lower = true;
            var view = std.unicode.Utf8View.init(name) catch return w.writeAll(name);
            var it0 = view.iterator();
            while (it0.nextCodepoint()) |cp| {
                if (unicode.isUpper(cp)) all_lower = false;
                if (unicode.isLower(cp)) all_upper = false;
            }
            break :blk if (all_upper) .lower else if (all_lower) .upper else .preserve;
        },
    };
    if (mode == .preserve) return w.writeAll(name);
    var it = (std.unicode.Utf8View.init(name) catch return w.writeAll(name)).iterator();
    var prev_not_alnum = true;
    while (it.nextCodepoint()) |cp| {
        const out = switch (mode) {
            .preserve => cp,
            .lower => unicode.downcase(cp),
            .upper => unicode.upcase(cp),
            .cap_up => if (prev_not_alnum or unicode.isLower(cp)) cp else unicode.downcase(cp),
            .cap_down => if (prev_not_alnum) unicode.upcase(cp) else cp,
        };
        prev_not_alnum = !unicode.isAlnum(cp);
        try writeCp(w, out);
    }
    mode = .preserve;
}

/// 関数（SBCL 2.6.7 と同じ形：#<FUNCTION CAR>、#<FUNCTION (LAMBDA (X)) {アドレス}>）
fn printFunction(rt: *Runtime, w: *Writer, v: Value) Writer.Error!void {
    const function = @import("../runtime/function.zig");
    switch (function.kindOfFunction(v)) {
        .native_function => {
            try w.writeAll("#<FUNCTION ");
            try prin1(rt, w, function.nativePtr(v).name);
            try w.writeByte('>');
        },
        .closure => {
            const name = function.closurePtr(v).codePtr().name;
            try w.writeAll("#<FUNCTION ");
            try printCodeName(rt, w, name);
            // 名前の付いた大域の関数（defun）はアドレスを書かない（SBCL 2.6.7：#<FUNCTION FACT>、#<FUNCTION (SETF F)>）
            if (!name.isCons() or Runtime.consPtr(name).car == rt.syms.setf) return w.writeByte('>');
            try w.print(" {{{X}}}>", .{v.raw() & ~@as(u64, 7)});
        },
        else => try w.print("#<FUNCTION {{{X}}}>", .{v.raw() & ~@as(u64, 7)}),
    }
}

/// 関数の名前（Code の name）を書く：FACT、(LAMBDA (X))、(FLET F)。トップレベルのフォーム（NIL）は「トップレベル」
pub fn printCodeName(rt: *Runtime, w: *Writer, name: Value) Writer.Error!void {
    if (name == Value.nil) return w.writeAll("（トップレベル）");
    if (name.isCons() and Runtime.consPtr(name).car == rt.syms.lambda) {
        // 空のラムダリストは () と書く（SBCL 2.6.7：#<FUNCTION (LAMBDA ()) {…}>）
        const ll = Runtime.consPtr(Runtime.consPtr(name).cdr).car;
        try w.writeAll("(LAMBDA ");
        if (ll == Value.nil) try w.writeAll("()") else try prin1(rt, w, ll);
        return w.writeByte(')');
    }
    try prin1(rt, w, name);
}

fn printString(w: *Writer, v: Value) Writer.Error!void {
    const s = Runtime.stringPtr(v);
    try w.writeByte('"');
    var i: usize = 0;
    while (i < s.length()) : (i += 1) {
        const cp = s.charAt(i);
        if (cp == '"' or cp == '\\') try w.writeByte('\\');
        try writeCp(w, cp);
    }
    try w.writeByte('"');
}

fn writeCp(w: *Writer, cp: u21) Writer.Error!void {
    var b: [4]u8 = undefined;
    const n = std.unicode.utf8Encode(cp, &b) catch return w.print("\\u{x}", .{cp});
    try w.writeAll(b[0..n]);
}

fn printChar(w: *Writer, cp: u21) Writer.Error!void {
    try w.writeAll("#\\");
    const name: ?[]const u8 = switch (cp) {
        '\n' => "Newline",
        '\t' => "Tab",
        0x0C => "Page",
        '\r' => "Return",
        0x7F => "Rubout",
        0x08 => "Backspace",
        0 => "Nul",
        else => null,
    };
    if (name) |n| return w.writeAll(n);
    // 名前のない制御文字は U+XXXX で書く（Zilisp の Reader で読み戻せる形。SBCL は #\Soh のような名前を使う）
    if (cp < 0x20 or (cp >= 0x80 and cp < 0xA0)) return w.print("U+{X}", .{cp});
    return writeCp(w, cp);
}

/// 浮動小数（SBCL 2.6.7 と同じ形）：
///   0.001 ≦ |x| < 1e7 は小数点の形（1.5、100000.0）、それ以外は指数の形（1.0e7、1.0e-4）。
///   桁数は読み戻せる最短の桁数。*read-default-float-format* と違う型には指数の印を付ける
///   （既定の single-float なら double-float に d：1.5d0、1.0d7。double-float が既定なら single-float に f：1.5f0。CLHS 22.1.3.1.3）
pub fn printFloat(w: *Writer, comptime T: type, x: T, double_default: bool) Writer.Error!void {
    if (std.math.isNan(x)) return w.writeAll(if (T == f32) "#<single-float quiet NaN>" else "#<double-float quiet NaN>");
    if (std.math.isInf(x)) return w.print("#<{s}-float {s}infinity>", .{ if (T == f32) "single" else "double", if (x < 0) "-" else "+" });
    const is_default = (T == f64) == double_default;
    const suffix_fixed: []const u8 = if (is_default) "" else if (T == f32) "f0" else "d0";
    const marker: u8 = if (is_default) 'e' else if (T == f32) 'f' else 'd';
    if (std.math.signbit(x)) try w.writeByte('-');
    const a = @abs(x);
    if (a == 0) return w.print("0.0{s}", .{suffix_fixed});

    // 最短の桁と10進の指数を得る（Zig の {e} は最短の桁で "d.ddde±x" を出す）
    var buf: [64]u8 = undefined;
    const s = std.fmt.bufPrint(&buf, "{e}", .{a}) catch unreachable;
    const e_pos = std.mem.indexOfScalar(u8, s, 'e').?;
    const exp10 = std.fmt.parseInt(i32, s[e_pos + 1 ..], 10) catch unreachable;
    var digits_buf: [40]u8 = undefined;
    var nd: usize = 0;
    for (s[0..e_pos]) |c| {
        if (c != '.') {
            digits_buf[nd] = c;
            nd += 1;
        }
    }
    const digits = digits_buf[0..nd]; // 値 = 0.d1d2... × 10^(exp10+1)

    if (a >= 1e-3 and a < 1e7) {
        const point: i32 = exp10 + 1; // 小数点の前の桁数
        if (point <= 0) {
            try w.writeAll("0.");
            var z: i32 = 0;
            while (z < -point) : (z += 1) try w.writeByte('0');
            try w.writeAll(digits);
        } else {
            const p: usize = @intCast(point);
            if (p >= digits.len) {
                try w.writeAll(digits);
                var z: usize = digits.len;
                while (z < p) : (z += 1) try w.writeByte('0');
                try w.writeAll(".0");
            } else {
                try w.writeAll(digits[0..p]);
                try w.writeByte('.');
                try w.writeAll(digits[p..]);
            }
        }
        return w.writeAll(suffix_fixed);
    }
    try w.writeByte(digits[0]);
    try w.writeByte('.');
    if (digits.len > 1) try w.writeAll(digits[1..]) else try w.writeByte('0');
    return w.print("{c}{d}", .{ marker, exp10 });
}

/// 真なら、キーワードと uninterned 以外のシンボルをすべて「パッケージ::名前」の形で書く（ネイティブバックエンドが定数を
/// 埋め込むとき。起動時に読み直すときの *package* や、export の済んでいない順序によらず同じシンボルになる。Phase 22）
pub var qualify_all: bool = false;

/// パッケージ名・qualify_all の印字の設定（標準の構文）
const standard_token: Settings = .{};

/// シンボル名を、必要なら |…| で囲んで書く（CLHS 22.1.3.3.1）。囲まないときは *print-case* と readtable-case に従う。
/// *print-base* の数として読める名前も囲む（*print-base* が 16 なら ABC は |ABC|。SBCL 2.6.7 と同じ）
fn writeSymbolName(rt: *Runtime, w: *Writer, name: []const u8, s: *const Settings) Writer.Error!void {
    if (!needsEscape(rt, name, s)) return writeCased(w, name, s.case, s.rt_case);
    try w.writeByte('|');
    for (name) |c| {
        if (c == '|' or c == '\\') try w.writeByte('\\');
        try w.writeByte(c);
    }
    try w.writeByte('|');
}

fn needsEscape(rt: *Runtime, name: []const u8, s: *const Settings) bool {
    const base = s.base;
    if (name.len == 0) return true;
    var all_dots = true;
    var all_ascii = true;
    var it = (std.unicode.Utf8View.init(name) catch return true).iterator();
    var index: usize = 0;
    while (it.nextCodepoint()) |cp| : (index += 1) {
        if (cp != '.') all_dots = false;
        if (cp > 0x7F) all_ascii = false;
        // 読み取りで大文字・小文字が変わる文字（:upcase なら小文字、:downcase なら大文字。:preserve・:invert は囲まない）
        switch (s.rt_case) {
            .upcase => if (syntax.upcase(cp) != cp) return true,
            .downcase => if (syntax.downcase(cp) != cp) return true,
            .preserve, .invert => {},
        }
        // 標準でない readtable：先頭のマクロ文字、途中の終端マクロ文字（SBCL 2.6.7 の symbol-quotep と同じ）
        if (s.readtable != Value.nil) {
            const st = readtable_mod.charEntry(s.readtable, cp).syntax;
            if (st == .terminating_macro) return true;
            if (index == 0 and st == .non_terminating_macro) return true;
        }
        _ = rt;
        switch (syntax.syntaxType(cp)) {
            .constituent => {},
            // # は先頭以外なら囲まなくても読み戻せるが、SBCL 2.6.7 は位置にかかわらず囲む（A#B → |A#B|）ので合わせる
            .non_terminating_macro => return true,
            else => return true,
        }
        if (cp == ':') return true;
    }
    if (all_dots) return true;
    if (all_ascii) {
        var buf: [256]u8 = undefined;
        if (name.len + 8 <= buf.len) {
            if (number.parse(name, base, .single, &buf) catch return true) |_| return true;
        }
        if (number.isPotentialNumber(name, base)) return true;
    }
    return false;
}

// ---------------------------------------------------------------------------

const testing = std.testing;
const vb = @import("../reader/value_builder.zig");

fn readPrint(rt: *Runtime, text: []const u8) ![]u8 {
    var diag: @import("../reader/reader.zig").Diagnostic = .{};
    var x = try vb.readAll(rt, testing.allocator, text, &diag);
    var out: Writer.Allocating = .init(testing.allocator);
    defer out.deinit();
    var first = true;
    while (x != Value.nil) : (x = Runtime.consPtr(x).cdr) {
        if (!first) try out.writer.writeByte('\n');
        first = false;
        try prin1(rt, &out.writer, Runtime.consPtr(x).car);
    }
    return out.toOwnedSlice();
}

fn expectPrint(rt: *Runtime, input: []const u8, expected: []const u8) !void {
    const got = try readPrint(rt, input);
    defer testing.allocator.free(got);
    testing.expectEqualStrings(expected, got) catch |e| {
        std.debug.print("input: {s}\n", .{input});
        return e;
    };
}

test "floats print like SBCL 2.6.7" {
    const rt = try Runtime.create(testing.allocator);
    defer rt.destroy();
    const cases = [_][2][]const u8{
        .{ "1.5", "1.5" },                                       .{ "100000.0", "100000.0" },         .{ "1234567.0", "1234567.0" },
        .{ "9999999.0", "9999999.0" },                           .{ "10000000.0", "1.0e7" },          .{ "1.5e10", "1.5e10" },
        .{ "0.001", "0.001" },                                   .{ "0.0001", "1.0e-4" },             .{ "123.456", "123.456" },
        .{ "0.1", "0.1" },                                       .{ "-0.0", "-0.0" },                 .{ "0.0", "0.0" },
        .{ "1.0", "1.0" },                                       .{ "1.5d0", "1.5d0" },               .{ "1.0d7", "1.0d7" },
        .{ "1.0d-4", "1.0d-4" },                                 .{ "0.1d0", "0.1d0" },               .{ "100000.0d0", "100000.0d0" },
        .{ "1d100", "1.0d100" },                                 .{ "3.4028235e38", "3.4028235e38" }, .{ "0.33333334", "0.33333334" },
        .{ "1.7976931348623157d308", "1.7976931348623157d308" },
    };
    for (cases) |c| try expectPrint(rt, c[0], c[1]);
}

test "symbols print like SBCL 2.6.7" {
    const rt = try Runtime.create(testing.allocator);
    defer rt.destroy();
    const cases = [_][2][]const u8{
        .{ "foo", "FOO" },                 .{ "|foo|", "|foo|" },     .{ "|Foo|", "|Foo|" },
        .{ "|a b|", "|a b|" },             .{ "|1|", "|1|" },         .{ "|1.5|", "|1.5|" },
        .{ "1+", "1+" },                   .{ "+", "+" },             .{ "|.|", "|.|" },
        .{ "|..|", "|..|" },               .{ "|a.b|", "|a.b|" },     .{ "-", "-" },
        .{ "|a:b|", "|a:b|" },             .{ "|(|", "|(|" },         .{ "|a\\|b|", "|a\\|b|" },
        .{ "|a\\\\b|", "|a\\\\b|" },       .{ "|#a|", "|#a|" },       .{ "|a#|", "|a#|" },
        .{ "||", "||" },                   .{ ":kw", ":KW" },         .{ ":|kw|", ":|kw|" },
        .{ "#:u", "#:U" },                 .{ "#:|u|", "#:|u|" },     .{ "cl:car", "CAR" },
        .{ "日本語", "日本語" },
        .{ "|1E|", "|1E|" },               .{ "|1E5|", "|1E5|" },     .{ "+.", "+." },
        .{ "|1/2|", "|1/2|" },             .{ "|1/2/3|", "|1/2/3|" }, .{ "^", "^" },
        .{ "|A;B|", "|A;B|" },             .{ "nil", "NIL" },         .{ "t", "T" },
        .{ "1ab", "1AB" },                 .{ "|1A|", "|1A|" },       .{ "zl-sys::quasiquote", "ZILISP-SYSTEM:QUASIQUOTE" },
        .{ "zilisp::foo", "ZILISP::FOO" },
        // 空のエスケープ（||）もエスケープとして扱う（SBCL 2.6.7 と同じ）
        .{ "1||", "|1|" },         .{ ":||", ":||" },
        .{ "(a .|| b)", "(A |.| B)" },     .{ "..||", "|..|" },       .{ "||1", "|1|" },
        .{ "cl-user::||", "||" },
    };
    for (cases) |c| try expectPrint(rt, c[0], c[1]);
}

test "other objects print like SBCL 2.6.7" {
    const rt = try Runtime.create(testing.allocator);
    defer rt.destroy();
    const cases = [_][2][]const u8{
        .{ "\"abc\"", "\"abc\"" },                                                 .{ "\"a\\\"b\"", "\"a\\\"b\"" },                     .{ "\"a\\\\b\"", "\"a\\\\b\"" },
        .{ "\"日本\"", "\"日本\"" },
        .{ "\"\"", "\"\"" },                                                       .{ "#\\a", "#\\a" },                                 .{ "#\\A", "#\\A" },
        .{ "#\\Space", "#\\ " },                                                   .{ "#\\Newline", "#\\Newline" },                     .{ "#\\Tab", "#\\Tab" },
        .{ "#\\Return", "#\\Return" },                                             .{ "#\\Page", "#\\Page" },                           .{ "#\\Rubout", "#\\Rubout" },
        .{ "#\\Backspace", "#\\Backspace" },                                       .{ "#\\Nul", "#\\Nul" },                             .{ "#\\(", "#\\(" },
        .{ "#\\\"", "#\\\"" },                                                     .{ "(1 2 3)", "(1 2 3)" },                           .{ "(1 . 2)", "(1 . 2)" },
        .{ "(1 2 . 3)", "(1 2 . 3)" },                                             .{ "'a", "(QUOTE A)" },                              .{ "#'f", "(FUNCTION F)" },
        .{ "((a) (b))", "((A) (B))" },                                             .{ "#(1 2)", "#(1 2)" },                             .{ "#()", "#()" },
        .{ "(nil)", "(NIL)" },                                                     .{ "0", "0" },                                       .{ "-5", "-5" },
        .{ "2305843009213693951", "2305843009213693951" },                         .{ "-2305843009213693952", "-2305843009213693952" },
        // bignum・比（Phase 20）
        .{ "2305843009213693952", "2305843009213693952" },
        .{ "-123456789012345678901234567890", "-123456789012345678901234567890" }, .{ "1/2", "1/2" },                                   .{ "-6/4", "-3/2" },
        .{ "4/2", "2" },
        // 読み飛ばしの最中の #n= は値を返さず、続くオブジェクトが読み飛ばされる（SBCL 2.6.7）
                                                                  .{ "#+nosuch #1=(a b) c", "C" },                     .{ "(#+nosuch #1=(a b) c)", "(C)" },
        .{ "#+nosuch #1=#2=(a) c", "C" },                                          .{ "#+nosuch ## c", "C" },
    };
    for (cases) |c| try expectPrint(rt, c[0], c[1]);
}

test "read errors from the value builder" {
    const rt = try Runtime.create(testing.allocator);
    defer rt.destroy();
    var diag: @import("../reader/reader.zig").Diagnostic = .{};
    for ([_][]const u8{ "nosuchpkg:x", "cl:nosuchsym123", "1/0", "||:x", "cl-user:" }) |t| {
        testing.expectError(error.ReaderError, vb.readAll(rt, testing.allocator, t, &diag)) catch |e| {
            std.debug.print("input: {s}\n", .{t});
            return e;
        };
    }
}

test "round trip: read, print, read gives an equal structure" {
    const rt = try Runtime.create(testing.allocator);
    defer rt.destroy();
    const inputs = [_][]const u8{
        "(defun fact (n) (if (<= n 1) 1 (* n (fact (- n 1)))))",
        "(a |b c| \"s\\\"t\" #\\x #\\Space 1.5 2.5d0 -3 :k #(1 (2)) (x . y))",
        "(cl-user::foo zl-sys:quasiquote |1E5| |.| \\1)",
    };
    for (inputs) |text| {
        const once = try readPrint(rt, text);
        defer testing.allocator.free(once);
        const twice = try readPrint(rt, once);
        defer testing.allocator.free(twice);
        try testing.expectEqualStrings(once, twice);
    }
}

test "interned symbols are eq after reading" {
    const rt = try Runtime.create(testing.allocator);
    defer rt.destroy();
    var diag: @import("../reader/reader.zig").Diagnostic = .{};
    var x = try vb.readAll(rt, testing.allocator, "foo FOO |FOO| cl-user::foo #:foo car cl:car", &diag);
    var v: [7]Value = undefined;
    for (&v) |*it| {
        it.* = Runtime.consPtr(x).car;
        x = Runtime.consPtr(x).cdr;
    }
    try testing.expect(v[0] == v[1] and v[1] == v[2] and v[2] == v[3]);
    try testing.expect(v[4] != v[0]);
    try testing.expect(v[5] == v[6]);
}
