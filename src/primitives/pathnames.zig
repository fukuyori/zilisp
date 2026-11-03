//! パス名（Phase 23。CLHS 19 章。SBCL 2.6.7 の Windows・Unix の解釈に合わせる）。
//!
//! - 欄：host（いつも NIL。SBCL は host のオブジェクト）、device（Windows のドライブ名の文字列か NIL）、
//!   directory（NIL か (:absolute|:relative 要素...)。要素は文字列、:wild（*）、:wild-inferiors（**）、:up（..））、
//!   name・type（文字列・:wild・NIL）、version（名前があれば :newest、なければ NIL）。
//! - 名前の途中の * や ? は、文字列のまま持つ（SBCL は pattern のオブジェクト）。wild-pathname-p・directory はそれを見る。
//! - namestring は / で区切る（Windows でも。SBCL と同じ）。読むときは Windows では \ も区切りとして扱う。
//! - ファイルを開くときなどは、*default-pathname-defaults* と併合してから namestring を OS に渡す。

const std = @import("std");
const builtin = @import("builtin");
const Io = std.Io;
const Value = @import("../values/value.zig").Value;
const object = @import("../values/object.zig");
const Thread = @import("../runtime/thread.zig").Thread;
const Runtime = @import("../runtime/runtime.zig").Runtime;
const RtError = @import("../runtime/runtime.zig").Error;
const arrays = @import("arrays.zig");
const keyargs = @import("keyargs.zig");

const windows = builtin.os.tag == .windows;

fn cl(th: *Thread, name: []const u8) Value {
    return (th.rt.findSymbol(th.rt.cl, name) orelse unreachable).symbol;
}

fn kw(th: *Thread, name: []const u8) ?Value {
    return th.rt.internKeyword(name) catch {
        _ = th.outOfMemory();
        return null;
    };
}

pub fn isPathname(v: Value) bool {
    return v.isOther() and Runtime.kindOf(v) == .pathname;
}

pub fn ptr(v: Value) *object.Pathname {
    return @ptrCast(@alignCast(v.pointer()));
}

fn isString(v: Value) bool {
    return v.isOther() and Runtime.kindOf(v) == .string;
}

/// 単純な文字列の UTF-8（呼び出し側が gpa で解放する）
pub fn stringUtf8(gpa: std.mem.Allocator, v: Value) error{OutOfMemory}![]u8 {
    const view = arrays.vectorView(v).?;
    var out: std.ArrayList(u8) = .empty;
    errdefer out.deinit(gpa);
    const s = Runtime.stringPtr(view.data);
    for (0..view.len) |i| {
        var b: [4]u8 = undefined;
        const n = std.unicode.utf8Encode(s.charAt(i), &b) catch unreachable;
        try out.appendSlice(gpa, b[0..n]);
    }
    return out.toOwnedSlice(gpa);
}

pub fn make(rt: *Runtime, host: Value, device: Value, directory: Value, name: Value, typ: Value, version: Value) RtError!Value {
    const p = try rt.heap.create(object.Pathname, 0);
    p.* = .{ .header = .{ .kind = .pathname }, .host = host, .device = device, .directory = directory, .name = name, .type = typ, .version = version };
    return Value.fromPointer(p, .other);
}

fn isSep(c: u8) bool {
    return c == '/' or (windows and c == '\\');
}

/// namestring を読んでパス名にする（SBCL 2.6.7 の解釈）
pub fn parse(rt: *Runtime, text: []const u8) RtError!Value {
    var s = text;
    var device = Value.nil;
    if (windows and s.len >= 2 and s[1] == ':' and std.ascii.isAlphabetic(s[0])) {
        device = try rt.makeString(s[0..1]);
        s = s[2..];
    }
    const absolute = s.len > 0 and isSep(s[0]);
    // 最後の区切りの後ろがファイルの部分
    var last: ?usize = null;
    for (s, 0..) |c, i| if (isSep(c)) {
        last = i;
    };
    const dir_part = if (last) |l| s[0..l] else "";
    const file_part = if (last) |l| s[l + 1 ..] else s;

    // 作った要素は、すぐに Lisp のリスト（逆順）につなぐ（Zig の配列に溜めると GC から見えない）
    var rev = Value.nil;
    var count: usize = 0;
    var it = std.mem.tokenizeAny(u8, dir_part, if (windows) "/\\" else "/");
    while (it.next()) |c| {
        const v = if (std.mem.eql(u8, c, "*"))
            try rt.internKeyword("WILD")
        else if (std.mem.eql(u8, c, "**"))
            try rt.internKeyword("WILD-INFERIORS")
        else if (std.mem.eql(u8, c, ".."))
            try rt.internKeyword("UP")
        else
            try rt.makeString(c);
        rev = try rt.cons(v, rev);
        count += 1;
    }
    var directory = Value.nil;
    if (absolute or count > 0) {
        // 逆順のリストを、cons を付け替えて正しい順にする（確保しない）
        while (rev.isCons()) {
            const next = Runtime.consPtr(rev).cdr;
            Runtime.consPtr(rev).cdr = directory;
            directory = rev;
            rev = next;
        }
        directory = try rt.cons(try rt.internKeyword(if (absolute) "ABSOLUTE" else "RELATIVE"), directory);
    }
    std.mem.doNotOptimizeAway(device);
    var name = Value.nil;
    var typ = Value.nil;
    if (file_part.len > 0) {
        // 最後の . で名前と型に分ける。先頭の . は名前の一部（.emacs）。".." は名前 "." と型 ""（SBCL と同じ）
        const dot = std.mem.lastIndexOfScalar(u8, file_part, '.');
        const n_part, const t_part: ?[]const u8 = if (dot) |d| (if (d == 0) .{ file_part, null } else .{ file_part[0..d], file_part[d + 1 ..] }) else .{ file_part, null };
        name = if (std.mem.eql(u8, n_part, "*")) try rt.internKeyword("WILD") else try rt.makeString(n_part);
        if (t_part) |t| typ = if (std.mem.eql(u8, t, "*")) try rt.internKeyword("WILD") else try rt.makeString(t);
    }
    const version = if (name != Value.nil) try rt.internKeyword("NEWEST") else Value.nil;
    return make(rt, Value.nil, device, directory, name, typ, version);
}

fn writeUtf8(w: *Io.Writer, v: Value) Io.Writer.Error!void {
    try Runtime.writeStringUtf8(v, w);
}

fn writeComponent(rt: *Runtime, w: *Io.Writer, v: Value) Io.Writer.Error!void {
    if (isString(v)) return writeUtf8(w, v);
    if (v == (rt.internKeyword("WILD") catch return error.WriteFailed)) return w.writeByte('*');
    if (v == (rt.internKeyword("WILD-INFERIORS") catch return error.WriteFailed)) return w.writeAll("**");
    if (v == (rt.internKeyword("UP") catch return error.WriteFailed) or v == (rt.internKeyword("BACK") catch return error.WriteFailed)) return w.writeAll("..");
}

/// device とディレクトリの部分
pub fn writeDirectory(rt: *Runtime, w: *Io.Writer, p: *const object.Pathname) Io.Writer.Error!void {
    if (isString(p.device)) {
        try writeUtf8(w, p.device);
        try w.writeByte(':');
    }
    if (p.directory.isCons()) {
        var x = p.directory;
        const head = Runtime.consPtr(x).car;
        if (head == (rt.internKeyword("ABSOLUTE") catch return error.WriteFailed)) try w.writeByte('/');
        x = Runtime.consPtr(x).cdr;
        while (x.isCons()) : (x = Runtime.consPtr(x).cdr) {
            try writeComponent(rt, w, Runtime.consPtr(x).car);
            try w.writeByte('/');
        }
    }
}

/// 名前と型の部分
pub fn writeFile(rt: *Runtime, w: *Io.Writer, p: *const object.Pathname) Io.Writer.Error!void {
    if (p.name != Value.nil) try writeComponent(rt, w, p.name);
    if (p.type != Value.nil) {
        try w.writeByte('.');
        try writeComponent(rt, w, p.type);
    }
}

pub fn writeNamestring(rt: *Runtime, w: *Io.Writer, v: Value) Io.Writer.Error!void {
    const p = ptr(v);
    try writeDirectory(rt, w, p);
    try writeFile(rt, w, p);
}

/// namestring の UTF-8（呼び出し側が gpa で解放する）
pub fn namestringUtf8(rt: *Runtime, v: Value) error{OutOfMemory}![]u8 {
    var out: Io.Writer.Allocating = .init(rt.gpa);
    errdefer out.deinit();
    writeNamestring(rt, &out.writer, v) catch return error.OutOfMemory;
    return out.toOwnedSlice() catch error.OutOfMemory;
}

// ---------------------------------------------------------------------------
// パス名指定子

/// パス名指定子（文字列・パス名・ファイルストリーム）をパス名にする。そうでなければ type-error（null）
pub fn designator(th: *Thread, v: Value) ?Value {
    if (isPathname(v)) return v;
    if (arrays.isStringLike(v)) {
        const text = stringUtf8(th.rt.gpa, v) catch {
            _ = th.outOfMemory();
            return null;
        };
        defer th.rt.gpa.free(text);
        return parse(th.rt, text) catch {
            _ = th.outOfMemory();
            return null;
        };
    }
    if (v.isOther() and Runtime.kindOf(v) == .stream) {
        const st: *object.Stream = @ptrCast(@alignCast(v.pointer()));
        if (@as(object.StreamKind, @fromBackingInt(@intCast(st.header.aux))) == .file and isPathname(st.ref)) return st.ref;
    }
    _ = th.typeError(v, cl(th, "PATHNAME"));
    return null;
}

fn defaultsValue(th: *Thread) Value {
    const v = th.rt.symbolPtr(th.rt.syms.@"*default-pathname-defaults*").value;
    return if (isPathname(v)) v else Value.nil;
}

/// merge-pathnames（CLHS 19.2.3）。defaults は パス名
pub fn merge(th: *Thread, pv: Value, dv: Value, default_version: Value) ?Value {
    const rt = th.rt;
    const p = ptr(pv);
    if (dv == Value.nil or !isPathname(dv)) return pv;
    const d = ptr(dv);
    const relative = kw(th, "RELATIVE") orelse return null;
    var directory = p.directory;
    if (directory == Value.nil) {
        directory = d.directory;
    } else if (Runtime.consPtr(directory).car == relative and d.directory.isCons()) {
        // 既定のディレクトリの後ろに、相対のディレクトリの要素を足す
        var items: std.ArrayList(Value) = .empty;
        defer items.deinit(rt.gpa);
        var x = d.directory;
        while (x.isCons()) : (x = Runtime.consPtr(x).cdr) items.append(rt.gpa, Runtime.consPtr(x).car) catch {
            _ = th.outOfMemory();
            return null;
        };
        x = Runtime.consPtr(directory).cdr;
        while (x.isCons()) : (x = Runtime.consPtr(x).cdr) items.append(rt.gpa, Runtime.consPtr(x).car) catch {
            _ = th.outOfMemory();
            return null;
        };
        var list = Value.nil;
        var i = items.items.len;
        while (i > 0) {
            i -= 1;
            list = rt.cons(items.items[i], list) catch {
                _ = th.outOfMemory();
                return null;
            };
        }
        directory = list;
    }
    const name = if (p.name != Value.nil) p.name else d.name;
    const typ = if (p.type != Value.nil) p.type else d.type;
    const version = if (p.version != Value.nil) p.version else if (p.name == Value.nil) d.version else default_version;
    const device = if (p.device != Value.nil) p.device else d.device;
    return make(rt, Value.nil, device, directory, name, typ, version) catch {
        _ = th.outOfMemory();
        return null;
    };
}

/// ファイルの操作に渡す OS の名前：*default-pathname-defaults* と併合した namestring（呼び出し側が gpa で解放する）
pub fn osName(th: *Thread, v: Value) ?[]u8 {
    const p = designator(th, v) orelse return null;
    const merged = merge(th, p, defaultsValue(th), Value.nil) orelse return null;
    return namestringUtf8(th.rt, merged) catch {
        _ = th.outOfMemory();
        return null;
    };
}

/// OS の絶対パス（UTF-8）をパス名にする。dir なら末尾を / にする（SBCL の probe-file と同じ）
fn fromOsPath(rt: *Runtime, path: []const u8, dir: bool) RtError!Value {
    var buf: std.ArrayList(u8) = .empty;
    defer buf.deinit(rt.gpa);
    for (path) |c| try buf.append(rt.gpa, if (windows and c == '\\') '/' else c);
    if (dir and (buf.items.len == 0 or buf.items[buf.items.len - 1] != '/')) try buf.append(rt.gpa, '/');
    return parse(rt, buf.items);
}

/// 起動時の *default-pathname-defaults*：今の作業ディレクトリ（末尾は /）
pub fn initialDefaults(rt: *Runtime) RtError!Value {
    const io = rt.io orelse return make(rt, Value.nil, Value.nil, Value.nil, Value.nil, Value.nil, Value.nil);
    const path = Io.Dir.cwd().realPathFileAlloc(io, ".", rt.gpa) catch return make(rt, Value.nil, Value.nil, Value.nil, Value.nil, Value.nil, Value.nil);
    defer rt.gpa.free(path);
    return fromOsPath(rt, path, true);
}

fn fileError(th: *Thread, message: []const u8, datum: Value) Value {
    return th.signal(.file_error, message, datum, Value.unbound);
}

fn ioOf(th: *Thread, datum: Value) ?Io {
    return th.rt.io orelse {
        _ = th.signal(.unimplemented, "この環境ではファイルを扱えません", datum, Value.unbound);
        return null;
    };
}

/// ファイルの絶対パスと種類（なければ null）
fn probe(th: *Thread, os_name: []const u8) ?struct { path: [:0]u8, dir: bool } {
    const io = th.rt.io orelse return null;
    const stat = Io.Dir.cwd().statFile(io, os_name, .{}) catch return null;
    const path = Io.Dir.cwd().realPathFileAlloc(io, os_name, th.rt.gpa) catch return null;
    return .{ .path = path, .dir = stat.kind == .directory };
}

// ---------------------------------------------------------------------------
// 関数

pub fn pathname(th: *Thread, args: []const Value) Value {
    return designator(th, args[0]) orelse Value.unwind;
}

pub fn pathnamep(th: *Thread, args: []const Value) Value {
    return th.rt.boolean(isPathname(args[0]));
}

fn accessor(comptime field: []const u8) fn (*Thread, []const Value) Value {
    return struct {
        fn f(th: *Thread, args: []const Value) Value {
            const p = designator(th, args[0]) orelse return Value.unwind;
            return @field(ptr(p), field);
        }
    }.f;
}

pub const pathnameHost = accessor("host");
pub const pathnameDevice = accessor("device");
pub const pathnameDirectory = accessor("directory");
pub const pathnameName = accessor("name");
pub const pathnameType = accessor("type");
pub const pathnameVersion = accessor("version");

fn stringResult(th: *Thread, comptime f: fn (*Runtime, *Io.Writer, *const object.Pathname) Io.Writer.Error!void, v: Value) Value {
    const p = designator(th, v) orelse return Value.unwind;
    var out: Io.Writer.Allocating = .init(th.rt.gpa);
    defer out.deinit();
    f(th.rt, &out.writer, ptr(p)) catch return th.outOfMemory();
    return th.rt.makeString(out.written()) catch th.outOfMemory();
}

fn writeAll(rt: *Runtime, w: *Io.Writer, p: *const object.Pathname) Io.Writer.Error!void {
    try writeDirectory(rt, w, p);
    try writeFile(rt, w, p);
}

pub fn namestring(th: *Thread, args: []const Value) Value {
    return stringResult(th, writeAll, args[0]);
}

pub fn fileNamestring(th: *Thread, args: []const Value) Value {
    return stringResult(th, writeFile, args[0]);
}

pub fn directoryNamestring(th: *Thread, args: []const Value) Value {
    return stringResult(th, writeDirectory, args[0]);
}

pub fn hostNamestring(th: *Thread, args: []const Value) Value {
    _ = designator(th, args[0]) orelse return Value.unwind;
    return th.rt.makeString("") catch th.outOfMemory();
}

/// (enough-namestring パス名 &optional 既定)：既定のディレクトリの下なら、相対の namestring
pub fn enoughNamestring(th: *Thread, args: []const Value) Value {
    const rt = th.rt;
    const p = designator(th, args[0]) orelse return Value.unwind;
    const d = if (args.len > 1) (designator(th, args[1]) orelse return Value.unwind) else defaultsValue(th);
    const pp = ptr(p);
    if (d != Value.nil and isPathname(d)) {
        const dp = ptr(d);
        const same_device = (pp.device == Value.nil and dp.device == Value.nil) or
            (isString(pp.device) and isString(dp.device) and @import("lists.zig").equal2(pp.device, dp.device));
        if (same_device and dp.directory.isCons() and pp.directory.isCons()) {
            var a = pp.directory;
            var b = dp.directory;
            var prefix = true;
            while (b.isCons()) : (b = Runtime.consPtr(b).cdr) {
                if (!a.isCons() or !@import("lists.zig").equal2(Runtime.consPtr(a).car, Runtime.consPtr(b).car)) {
                    prefix = false;
                    break;
                }
                a = Runtime.consPtr(a).cdr;
            }
            if (prefix) {
                var out: Io.Writer.Allocating = .init(rt.gpa);
                defer out.deinit();
                var x = a;
                while (x.isCons()) : (x = Runtime.consPtr(x).cdr) {
                    writeComponent(rt, &out.writer, Runtime.consPtr(x).car) catch return th.outOfMemory();
                    out.writer.writeByte('/') catch return th.outOfMemory();
                }
                writeFile(rt, &out.writer, pp) catch return th.outOfMemory();
                return rt.makeString(out.written()) catch th.outOfMemory();
            }
        }
    }
    return namestring(th, args[0..1]);
}

/// (parse-namestring 文字列 &optional host 既定 &key start end junk-allowed)：パス名と、読み終えた位置
pub fn parseNamestring(th: *Thread, args: []const Value) Value {
    const rt = th.rt;
    var kv: [3]?Value = .{ null, null, null };
    if (args.len > 3 and !keyargs.parse(th, args[3..], &.{ "START", "END", "JUNK-ALLOWED" }, &kv)) return Value.unwind;
    const thing = args[0];
    if (isPathname(thing)) {
        th.mv[1] = Value.fromFixnum(0);
        th.mv_count = 2;
        return thing;
    }
    if (!arrays.isStringLike(thing)) return th.typeError(thing, cl(th, "STRING"));
    const view = arrays.vectorView(thing).?;
    const start: usize = if (kv[0]) |s| (if (s.isFixnum() and s.asFixnum() >= 0) @intCast(s.asFixnum()) else return th.typeError(s, rt.syms.integer)) else 0;
    const end: usize = if (kv[1]) |e| (if (e == Value.nil) view.len else if (e.isFixnum() and e.asFixnum() >= 0) @intCast(e.asFixnum()) else return th.typeError(e, rt.syms.integer)) else view.len;
    if (start > end or end > view.len) return th.signal(.type_error, "PARSE-NAMESTRING の :start・:end が正しくありません", thing, Value.unbound);
    var text: std.ArrayList(u8) = .empty;
    defer text.deinit(rt.gpa);
    const s = Runtime.stringPtr(view.data);
    for (start..end) |i| {
        var b: [4]u8 = undefined;
        const n = std.unicode.utf8Encode(s.charAt(i), &b) catch unreachable;
        text.appendSlice(rt.gpa, b[0..n]) catch return th.outOfMemory();
    }
    const p = parse(rt, text.items) catch return th.outOfMemory();
    th.mv[1] = Value.fromFixnum(@intCast(end));
    th.mv_count = 2;
    return p;
}

/// (merge-pathnames パス名 &optional 既定 既定の版)
pub fn mergePathnames(th: *Thread, args: []const Value) Value {
    const p = designator(th, args[0]) orelse return Value.unwind;
    const d = if (args.len > 1) (designator(th, args[1]) orelse return Value.unwind) else defaultsValue(th);
    const ver = if (args.len > 2) args[2] else (kw(th, "NEWEST") orelse return Value.unwind);
    return merge(th, p, d, ver) orelse Value.unwind;
}

fn directoryArg(th: *Thread, v: Value) ?Value {
    const rt = th.rt;
    if (v == Value.nil or v.isCons()) return v;
    if (arrays.isStringLike(v)) {
        const abs = kw(th, "ABSOLUTE") orelse return null;
        const tail = rt.cons(v, Value.nil) catch {
            _ = th.outOfMemory();
            return null;
        };
        return rt.cons(abs, tail) catch {
            _ = th.outOfMemory();
            return null;
        };
    }
    if (v == (kw(th, "WILD") orelse return null)) {
        const abs = kw(th, "ABSOLUTE") orelse return null;
        const wi = kw(th, "WILD-INFERIORS") orelse return null;
        const tail = rt.cons(wi, Value.nil) catch {
            _ = th.outOfMemory();
            return null;
        };
        return rt.cons(abs, tail) catch {
            _ = th.outOfMemory();
            return null;
        };
    }
    _ = th.typeError(v, rt.syms.list);
    return null;
}

/// (make-pathname &key host device directory name type version defaults case)
pub fn makePathname(th: *Thread, args: []const Value) Value {
    var kv: [8]?Value = undefined;
    if (!keyargs.parse(th, args, &.{ "HOST", "DEVICE", "DIRECTORY", "NAME", "TYPE", "VERSION", "DEFAULTS", "CASE" }, &kv)) return Value.unwind;
    const d: ?*object.Pathname = if (kv[6]) |dv| ptr(designator(th, dv) orelse return Value.unwind) else null;
    const device = kv[1] orelse if (d) |dd| dd.device else Value.nil;
    const directory = if (kv[2]) |dir| (directoryArg(th, dir) orelse return Value.unwind) else if (d) |dd| dd.directory else Value.nil;
    const name = kv[3] orelse if (d) |dd| dd.name else Value.nil;
    const typ = kv[4] orelse if (d) |dd| dd.type else Value.nil;
    const version = kv[5] orelse if (d) |dd| (if (kv[3] == null) dd.version else (if (name != Value.nil) (kw(th, "NEWEST") orelse return Value.unwind) else Value.nil)) else if (name != Value.nil) (kw(th, "NEWEST") orelse return Value.unwind) else Value.nil;
    return make(th.rt, Value.nil, device, directory, name, typ, version) catch th.outOfMemory();
}

fn hasWildString(v: Value) bool {
    if (!isString(v)) return false;
    const s = Runtime.stringPtr(v);
    for (0..s.length()) |i| if (s.charAt(i) == '*' or s.charAt(i) == '?') return true;
    return false;
}

fn isWildComponent(th: *Thread, v: Value) bool {
    const rt = th.rt;
    return v == (rt.internKeyword("WILD") catch return false) or v == (rt.internKeyword("WILD-INFERIORS") catch return false) or hasWildString(v);
}

/// (wild-pathname-p パス名 &optional 欄)
pub fn wildPathnameP(th: *Thread, args: []const Value) Value {
    const p = designator(th, args[0]) orelse return Value.unwind;
    const pp = ptr(p);
    const field = if (args.len > 1) args[1] else Value.nil;
    const rt = th.rt;
    var dir_wild = false;
    var x = pp.directory;
    while (x.isCons()) : (x = Runtime.consPtr(x).cdr) if (isWildComponent(th, Runtime.consPtr(x).car)) {
        dir_wild = true;
    };
    const name_wild = isWildComponent(th, pp.name);
    const type_wild = isWildComponent(th, pp.type);
    const version_wild = pp.version == (kw(th, "WILD") orelse return Value.unwind);
    if (field == Value.nil) return rt.boolean(dir_wild or name_wild or type_wild or version_wild);
    if (field == (kw(th, "DIRECTORY") orelse return Value.unwind)) return rt.boolean(dir_wild);
    if (field == (kw(th, "NAME") orelse return Value.unwind)) return rt.boolean(name_wild);
    if (field == (kw(th, "TYPE") orelse return Value.unwind)) return rt.boolean(type_wild);
    if (field == (kw(th, "VERSION") orelse return Value.unwind)) return rt.boolean(version_wild);
    return Value.nil;
}

/// glob の照合（* は任意の文字列、? は任意の1文字）
fn globMatch(pat: []const u8, s: []const u8) bool {
    if (pat.len == 0) return s.len == 0;
    if (pat[0] == '*') {
        var i: usize = 0;
        while (i <= s.len) : (i += 1) if (globMatch(pat[1..], s[i..])) return true;
        return false;
    }
    if (s.len == 0) return false;
    if (pat[0] == '?' or pat[0] == s[0]) return globMatch(pat[1..], s[1..]);
    return false;
}

/// 名前・型の欄が文字列 s に合うか（NIL は空、:wild は何でも）
fn componentMatch(th: *Thread, pattern: Value, s: ?[]const u8) bool {
    const gpa = th.rt.gpa;
    if (pattern == (th.rt.internKeyword("WILD") catch return false)) return true;
    if (pattern == Value.nil) return s == null;
    const str = s orelse return false;
    const pat = stringUtf8(gpa, pattern) catch return false;
    defer gpa.free(pat);
    return globMatch(pat, str);
}

/// (pathname-match-p パス名 ワイルドカード)：名前と型だけを照合する（ディレクトリが両方とも同じか、ワイルドカード側が NIL）
pub fn pathnameMatchP(th: *Thread, args: []const Value) Value {
    const p = designator(th, args[0]) orelse return Value.unwind;
    const w = designator(th, args[1]) orelse return Value.unwind;
    const name = if (isString(ptr(p).name)) (stringUtf8(th.rt.gpa, ptr(p).name) catch return th.outOfMemory()) else null;
    defer if (name) |n| th.rt.gpa.free(n);
    const typ = if (isString(ptr(p).type)) (stringUtf8(th.rt.gpa, ptr(p).type) catch return th.outOfMemory()) else null;
    defer if (typ) |t| th.rt.gpa.free(t);
    return th.rt.boolean(componentMatch(th, ptr(w).name, name) and componentMatch(th, ptr(w).type, typ));
}

/// (probe-file パス名)：あれば絶対パスのパス名（ディレクトリは末尾が /）、なければ NIL
pub fn probeFile(th: *Thread, args: []const Value) Value {
    const name = osName(th, args[0]) orelse return Value.unwind;
    defer th.rt.gpa.free(name);
    const found = probe(th, name) orelse return Value.nil;
    defer th.rt.gpa.free(found.path);
    return fromOsPath(th.rt, found.path, found.dir) catch th.outOfMemory();
}

/// (truename パス名)：probe-file と同じだが、なければ file-error
pub fn truename(th: *Thread, args: []const Value) Value {
    const name = osName(th, args[0]) orelse return Value.unwind;
    defer th.rt.gpa.free(name);
    const found = probe(th, name) orelse return fileError(th, "ファイルがありません", args[0]);
    defer th.rt.gpa.free(found.path);
    return fromOsPath(th.rt, found.path, found.dir) catch th.outOfMemory();
}

/// (file-write-date パス名)：最後に書いた時刻（universal time）。分からなければ NIL
pub fn fileWriteDate(th: *Thread, args: []const Value) Value {
    const name = osName(th, args[0]) orelse return Value.unwind;
    defer th.rt.gpa.free(name);
    const io = ioOf(th, args[0]) orelse return Value.unwind;
    const stat = Io.Dir.cwd().statFile(io, name, .{}) catch return fileError(th, "ファイルの情報を読めません", args[0]);
    const secs = @divFloor(stat.mtime.nanoseconds, std.time.ns_per_s);
    // universal time は 1900-01-01 からの秒数
    return Value.fromFixnum(@intCast(secs + 2208988800));
}

/// (delete-file パス名)：消して T。なければ file-error
pub fn deleteFile(th: *Thread, args: []const Value) Value {
    const name = osName(th, args[0]) orelse return Value.unwind;
    defer th.rt.gpa.free(name);
    const io = ioOf(th, args[0]) orelse return Value.unwind;
    Io.Dir.cwd().deleteFile(io, name) catch return fileError(th, "ファイルを消せません", args[0]);
    return th.rt.t;
}

/// (rename-file 元 新しい名前)：新しい名前は元と併合する。値は 新しい名前・元の truename・新しい truename
pub fn renameFile(th: *Thread, args: []const Value) Value {
    const rt = th.rt;
    const old = designator(th, args[0]) orelse return Value.unwind;
    const new0 = designator(th, args[1]) orelse return Value.unwind;
    const merged = merge(th, new0, old, Value.nil) orelse return Value.unwind;
    const old_name = osName(th, old) orelse return Value.unwind;
    defer rt.gpa.free(old_name);
    const new_name = osName(th, merged) orelse return Value.unwind;
    defer rt.gpa.free(new_name);
    const io = ioOf(th, args[0]) orelse return Value.unwind;
    const old_true = probe(th, old_name) orelse return fileError(th, "ファイルがありません", args[0]);
    defer rt.gpa.free(old_true.path);
    const old_tv = fromOsPath(rt, old_true.path, old_true.dir) catch return th.outOfMemory();
    Io.Dir.cwd().rename(old_name, Io.Dir.cwd(), new_name, io) catch return fileError(th, "ファイルの名前を変えられません", args[0]);
    const new_true = probe(th, new_name) orelse return fileError(th, "ファイルがありません", merged);
    defer rt.gpa.free(new_true.path);
    const new_tv = fromOsPath(rt, new_true.path, new_true.dir) catch return th.outOfMemory();
    th.mv[1] = old_tv;
    th.mv[2] = new_tv;
    th.mv_count = 3;
    return merged;
}

/// (ensure-directories-exist パス名)：ディレクトリを作る。値は パス名指定子 と 作ったか
pub fn ensureDirectoriesExist(th: *Thread, args: []const Value) Value {
    const rt = th.rt;
    const p = designator(th, args[0]) orelse return Value.unwind;
    const merged = merge(th, p, defaultsValue(th), Value.nil) orelse return Value.unwind;
    var out: Io.Writer.Allocating = .init(rt.gpa);
    defer out.deinit();
    writeDirectory(rt, &out.writer, ptr(merged)) catch return th.outOfMemory();
    const io = ioOf(th, args[0]) orelse return Value.unwind;
    var created = false;
    if (out.written().len > 0) {
        const existed = probe(th, out.written());
        if (existed) |e| rt.gpa.free(e.path) else {
            Io.Dir.cwd().createDirPath(io, out.written()) catch return fileError(th, "ディレクトリを作れません", args[0]);
            created = true;
        }
    }
    th.mv[1] = rt.boolean(created);
    th.mv_count = 2;
    return args[0];
}

// ---------------------------------------------------------------------------
// directory

const Collector = struct {
    th: *Thread,
    results: std.ArrayList([]u8) = .empty,

    fn deinit(c: *Collector) void {
        for (c.results.items) |r| c.th.rt.gpa.free(r);
        c.results.deinit(c.th.rt.gpa);
    }
};

/// ディレクトリの要素の並び（文字列は glob、:wild は1つ、:wild-inferiors は0個以上）を、dir の下で照合する
fn walk(c: *Collector, io: Io, base: []const u8, comps: []const Value, pat: *const object.Pathname, want_dirs: bool) error{OutOfMemory}!void {
    const th = c.th;
    const gpa = th.rt.gpa;
    if (comps.len == 0) {
        // ディレクトリを探すとき（名前・型が NIL）：照合したディレクトリそのもの
        if (want_dirs) {
            if (base.len > 0) try c.results.append(gpa, try gpa.dupe(u8, base));
            return;
        }
        // ここで名前・型を照合する
        var dir = Io.Dir.cwd().openDir(io, if (base.len == 0) "." else base, .{ .iterate = true }) catch return;
        defer dir.close(io);
        var it = dir.iterate();
        while (it.next(io) catch null) |e| {
            if (e.kind == .directory) continue;
            const dot = std.mem.lastIndexOfScalar(u8, e.name, '.');
            const n, const t: ?[]const u8 = if (dot) |d| (if (d == 0) .{ e.name, null } else .{ e.name[0..d], e.name[d + 1 ..] }) else .{ e.name, null };
            if (!componentMatch(th, pat.name, n) or !componentMatch(th, pat.type, t)) continue;
            try c.results.append(gpa, try std.fmt.allocPrint(gpa, "{s}{s}", .{ base, e.name }));
        }
        return;
    }
    const first = comps[0];
    const rt = th.rt;
    if (first == (rt.internKeyword("WILD-INFERIORS") catch return error.OutOfMemory)) {
        // 0 個：このまま次へ。1 個以上：サブディレクトリに入って同じ要素を続ける
        try walk(c, io, base, comps[1..], pat, want_dirs);
        var dir = Io.Dir.cwd().openDir(io, if (base.len == 0) "." else base, .{ .iterate = true }) catch return;
        defer dir.close(io);
        var it = dir.iterate();
        while (it.next(io) catch null) |e| {
            if (e.kind != .directory) continue;
            const sub = try std.fmt.allocPrint(gpa, "{s}{s}/", .{ base, e.name });
            defer gpa.free(sub);
            try walk(c, io, sub, comps, pat, want_dirs);
        }
        return;
    }
    if (isWildComponent(th, first)) {
        var dir = Io.Dir.cwd().openDir(io, if (base.len == 0) "." else base, .{ .iterate = true }) catch return;
        defer dir.close(io);
        var it = dir.iterate();
        while (it.next(io) catch null) |e| {
            if (e.kind != .directory) continue;
            if (!componentMatch(th, first, e.name)) continue;
            const sub = try std.fmt.allocPrint(gpa, "{s}{s}/", .{ base, e.name });
            defer gpa.free(sub);
            try walk(c, io, sub, comps[1..], pat, want_dirs);
        }
        return;
    }
    var name: Io.Writer.Allocating = .init(gpa);
    defer name.deinit();
    writeComponent(rt, &name.writer, first) catch return error.OutOfMemory;
    const sub = try std.fmt.allocPrint(gpa, "{s}{s}/", .{ base, name.written() });
    defer gpa.free(sub);
    try walk(c, io, sub, comps[1..], pat, want_dirs);
}

fn lessThan(_: void, a: []u8, b: []u8) bool {
    return std.mem.lessThan(u8, a, b);
}

/// (directory パス名)：照合するファイル（名前と型が NIL ならディレクトリ）の truename のリスト（名前の順）
pub fn directoryList(th: *Thread, args: []const Value) Value {
    const rt = th.rt;
    const p0 = designator(th, args[0]) orelse return Value.unwind;
    const p = merge(th, p0, defaultsValue(th), Value.nil) orelse return Value.unwind;
    const pp = ptr(p);
    const io = ioOf(th, args[0]) orelse return Value.unwind;
    // 照合しない場合は probe-file と同じ
    if (wildPathnameP(th, &.{p}) == Value.nil) {
        const v = probeFile(th, &.{p});
        if (v == Value.unwind or v == Value.nil) return v;
        return rt.cons(v, Value.nil) catch th.outOfMemory();
    }
    var base: Io.Writer.Allocating = .init(rt.gpa);
    defer base.deinit();
    if (isString(pp.device)) {
        writeUtf8(&base.writer, pp.device) catch return th.outOfMemory();
        base.writer.writeByte(':') catch return th.outOfMemory();
    }
    var comps: std.ArrayList(Value) = .empty;
    defer comps.deinit(rt.gpa);
    if (pp.directory.isCons()) {
        if (Runtime.consPtr(pp.directory).car == (kw(th, "ABSOLUTE") orelse return Value.unwind)) base.writer.writeByte('/') catch return th.outOfMemory();
        var x = Runtime.consPtr(pp.directory).cdr;
        while (x.isCons()) : (x = Runtime.consPtr(x).cdr) comps.append(rt.gpa, Runtime.consPtr(x).car) catch return th.outOfMemory();
    }
    var c: Collector = .{ .th = th };
    defer c.deinit();
    const want_dirs = pp.name == Value.nil and pp.type == Value.nil;
    walk(&c, io, base.written(), comps.items, pp, want_dirs) catch return th.outOfMemory();
    std.mem.sort([]u8, c.results.items, {}, lessThan);
    var list = Value.nil;
    var i = c.results.items.len;
    while (i > 0) {
        i -= 1;
        const found = probe(th, c.results.items[i]) orelse continue;
        defer rt.gpa.free(found.path);
        const v = fromOsPath(rt, found.path, found.dir) catch return th.outOfMemory();
        list = rt.cons(v, list) catch return th.outOfMemory();
    }
    return list;
}

/// equal でのパス名の比較（欄ごとに equal）
pub fn equalPathnames(a: Value, b: Value) bool {
    const lists = @import("lists.zig");
    const x = ptr(a);
    const y = ptr(b);
    return lists.equal2(x.host, y.host) and lists.equal2(x.device, y.device) and lists.equal2(x.directory, y.directory) and
        lists.equal2(x.name, y.name) and lists.equal2(x.type, y.type) and lists.equal2(x.version, y.version);
}
