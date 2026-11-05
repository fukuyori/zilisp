//! ストリーム（Phase 23。CLHS 21 章。詳細設計 §2.4・§3.2）。
//!
//! - ストリームのオブジェクト（object.Stream）は GC のヒープに置き、Lisp の値は ref に持つ。入出力のバッファ・ファイルの
//!   ハンドルなどは Zig の側の状態（StreamState。gpa で確保）に置き、Runtime.streams が一覧で持つ。オブジェクトが回収
//!   されたら、GC が状態を閉じて解放する（finalizeDead。出力は書き出してから閉じる）。Runtime を破棄するときも同じ。
//! - 入力は、どのストリームも UTF-8 のバイト列と位置で扱う（read-line・read-char・read が同じ位置を共有する）。
//!   ファイルと文字列の入力ストリームは、開いたときに全体を読む。標準入力は、必要になった分だけ読み足す。
//!   改行は変換しない（CR LF の CR も文字として読む。SBCL 2.6.7 と同じ。出力は LF だけを書く）。
//! - 出力は、いったんバイト列にしてから、ストリームの種類に応じて書く（emit）。ファイルはバッファに溜めて、
//!   64 KiB を超えたとき・finish-output・close で書き出す。
//! - 標準のストリーム：*standard-output*（th.out に書く）、*standard-input*、*error-output*、*terminal-io*（two-way）、
//!   *query-io*・*debug-io*（*terminal-io* の synonym）、*trace-output*（*standard-output* の synonym）。

const std = @import("std");
const builtin = @import("builtin");
const Io = std.Io;
const Value = @import("../values/value.zig").Value;
const object = @import("../values/object.zig");
const StreamKind = object.StreamKind;
const SF = object.StreamFlags;
const Thread = @import("../runtime/thread.zig").Thread;
const Runtime = @import("../runtime/runtime.zig").Runtime;
const printer = @import("../printer/printer.zig");
const pretty_mod = @import("../printer/pretty.zig");
const pprint_mod = @import("../printer/pprint.zig");
const reader = @import("../reader/reader.zig");
const vb = @import("../reader/value_builder.zig");
const arrays = @import("arrays.zig");
const keyargs = @import("keyargs.zig");
const pathnames = @import("pathnames.zig");

const windows = builtin.os.tag == .windows;
/// ファイルの出力をまとめて書き出す大きさ
const flush_threshold = 64 * 1024;

pub const StreamState = struct {
    /// ストリームのオブジェクトのアドレス（GC で生きているかを調べる）
    owner: usize,
    kind: StreamKind,
    /// 入力のバイト列（ファイル・文字列の入力。gpa で確保）と、読む位置
    in_buf: []u8 = &.{},
    /// 標準入力が読み足すバイト列（in_buf の代わりに使う）
    in_list: std.ArrayList(u8) = .empty,
    pos: usize = 0,
    /// 最後に read-char で読んだ文字のバイト数（unread-char が戻る）
    last_len: usize = 0,
    stdin_eof: bool = false,
    /// 標準入力を読み足すときにメモリが足りなかった（エラーは記録済み。終わりの扱いの代わりに巻き戻す。
    /// agy のレビュー 0.3 #14）
    stdin_oom: bool = false,
    /// 出力のバイト列（文字列の出力ストリームは全体、ファイルはまだ書き出していない分）
    out: std.ArrayList(u8) = .empty,
    /// 標準出力の書き先（th.out）
    writer: ?*Io.Writer = null,
    file: ?Io.File = null,
    /// ファイルの出力で、次に書き出す位置
    file_offset: u64 = 0,
    at_line_start: bool = true,
    /// 出力の今の桁（行の先頭からの文字数。format の ~T が使う。Phase 24）
    column: usize = 0,
    latin1: bool = false,
    /// 文字列の入力ストリームの、元の文字列の中での開始位置（file-position が返す）
    char_base: usize = 0,
    /// 標準入力を REPL と同じ Io.Reader から読み足す（REPL が先に読んだ入力を取りこぼさない。Codex のレビュー P23 #2）
    reader: ?*Io.Reader = null,
    /// 出力のファイルの長さ（書き出した範囲の終わりと、開いたときの長さの大きい方。Codex のレビュー P23 #8）
    file_len: u64 = 0,
    /// :if-exists :rename・:rename-and-delete で退避したファイル（gpa で確保）。閉じるときに使う
    backup: ?[]u8 = null,
    delete_backup: bool = false,
    /// 開いた名前（:abort で元に戻すとき）
    path: ?[]u8 = null,
    /// pretty stream の状態（kind が .pretty。Phase 24）
    pretty: ?*pretty_mod.State = null,

    fn input(st: *StreamState) []const u8 {
        return if (st.kind == .stdin) st.in_list.items else st.in_buf;
    }
};

pub fn isStream(v: Value) bool {
    return v.isOther() and Runtime.kindOf(v) == .stream;
}

pub fn ptr(v: Value) *object.Stream {
    return @ptrCast(@alignCast(v.pointer()));
}

pub fn kindOf(v: Value) StreamKind {
    return @fromBackingInt(@intCast(ptr(v).header.aux));
}

fn stateOf(v: Value) ?*StreamState {
    const s = ptr(v).state;
    return if (s == 0) null else @ptrFromInt(s);
}

fn flags(v: Value) u8 {
    return ptr(v).header.flags;
}

fn cl(th: *Thread, name: []const u8) Value {
    return (th.rt.findSymbol(th.rt.cl, name) orelse unreachable).symbol;
}

fn kw(th: *Thread, name: []const u8) ?Value {
    return th.rt.internKeyword(name) catch {
        _ = th.outOfMemory();
        return null;
    };
}

fn oom(th: *Thread) Value {
    return th.outOfMemory();
}

/// ストリームのオブジェクトを作る（state を持つなら一覧に登録する）
fn makeStream(th: *Thread, kind: StreamKind, fl: u8, ref: Value, with_state: bool) ?Value {
    const rt = th.rt;
    const obj = rt.heap.create(object.Stream, 0) catch {
        _ = th.outOfMemory();
        return null;
    };
    obj.* = .{ .header = .{ .kind = .stream, .flags = fl, .aux = @backingInt(kind) }, .ref = ref, .state = 0 };
    const v = Value.fromPointer(obj, .other);
    if (with_state) {
        rt.streams.ensureUnusedCapacity(rt.gpa, 1) catch {
            _ = th.outOfMemory();
            return null;
        };
        const st = rt.gpa.create(StreamState) catch {
            _ = th.outOfMemory();
            return null;
        };
        st.* = .{ .owner = @intFromPtr(obj), .kind = kind };
        obj.state = @intFromPtr(st);
        rt.streams.appendAssumeCapacity(st);
    }
    return v;
}

/// 状態を閉じる（出力を書き出し、ファイルを閉じ、バッファを解放する）。状態そのものは解放しない
fn closeState(rt: *Runtime, st: *StreamState) void {
    if (st.file) |f| {
        if (rt.io) |io| {
            if (st.out.items.len > 0) f.writePositionalAll(io, st.out.items, st.file_offset) catch {};
            f.close(io);
        }
        st.file = null;
    }
    finishBackup(rt, st, false);
    if (st.path) |n| rt.gpa.free(n);
    st.path = null;
    st.out.clearAndFree(rt.gpa);
    if (st.kind != .stdin) {
        rt.gpa.free(st.in_buf);
        st.in_buf = &.{};
    }
    st.in_list.clearAndFree(rt.gpa);
    if (st.pretty) |ps| ps.destroy();
    st.pretty = null;
}

/// 退避したファイルの後始末：abort なら元に戻し（新しいファイルを消す）、:rename-and-delete なら消す
fn finishBackup(rt: *Runtime, st: *StreamState, abort: bool) void {
    const b = st.backup orelse return;
    if (rt.io) |io| {
        if (abort) {
            if (st.path) |n| {
                Io.Dir.cwd().deleteFile(io, n) catch {};
                Io.Dir.cwd().rename(b, Io.Dir.cwd(), n, io) catch {};
            }
        } else if (st.delete_backup) {
            Io.Dir.cwd().deleteFile(io, b) catch {};
        }
    }
    rt.gpa.free(b);
    st.backup = null;
}

/// GC のマークの後：回収されるストリームの状態を閉じて解放する（gc.zig が呼ぶ）
pub fn finalizeDead(rt: *Runtime) void {
    var i: usize = 0;
    while (i < rt.streams.items.len) {
        const st = rt.streams.items[i];
        const alive = if (rt.heap.findObject(st.owner)) |ref| @import("../runtime/heap.zig").Heap.isMarked(ref) else false;
        if (alive) {
            i += 1;
            continue;
        }
        closeState(rt, st);
        rt.gpa.destroy(st);
        _ = rt.streams.swapRemove(i);
    }
}

/// Runtime を破棄するとき：すべてのストリームを閉じる（ファイルの出力を書き出す）
pub fn closeAll(rt: *Runtime) void {
    for (rt.streams.items) |st| {
        closeState(rt, st);
        rt.gpa.destroy(st);
    }
    rt.streams.deinit(rt.gpa);
}

/// スクリプトとして実行しているとき、エラーを表示せずに正常に終えるか：標準のストリーム（標準入力・標準出力・
/// 標準エラー出力）の end-of-file か、書けない（broken pipe）とき（SBCL 2.6.7 の --script の process-script と同じ）
pub fn isQuietScriptExit(th: *Thread) bool {
    const k = th.err.kind;
    if (k != .end_of_file and k != .stream_error) return false;
    const d = th.err.datum;
    if (!isStream(d)) return false;
    return switch (kindOf(d)) {
        .stdin => k == .end_of_file,
        .stdout, .stderr => k == .stream_error,
        else => false,
    };
}

/// REPL が標準入力を読む Io.Reader を、Lisp の標準入力のストリームにも使う（Codex のレビュー P23 #2）
pub fn shareStdinReader(th: *Thread, in: ?*Io.Reader) void {
    for (th.rt.streams.items) |st| if (st.kind == .stdin) {
        st.reader = in;
    };
}

/// 標準入力のストリームから1行を取り出す（REPL が使う。改行は含まない。終わりなら null）。
/// 返す slice は、次に標準入力を読むまで有効
pub fn takeStdinLine(th: *Thread) ?[]const u8 {
    var st: *StreamState = undefined;
    var found = false;
    for (th.rt.streams.items) |x| if (x.kind == .stdin) {
        st = x;
        found = true;
    };
    if (!found) return null;
    // 読み終えた分を捨てる（REPL の1行ごとに溜まらないように）
    if (st.pos >= st.in_list.items.len) {
        st.in_list.clearRetainingCapacity();
        st.pos = 0;
        st.last_len = 0;
    }
    while (true) {
        const rest = st.in_list.items[st.pos..];
        if (std.mem.indexOfScalar(u8, rest, '\n')) |i| {
            st.pos += i + 1;
            st.last_len = 0;
            return rest[0..i];
        }
        if (!fillStdin(th, st)) {
            if (rest.len == 0) return null;
            st.pos += rest.len;
            return rest;
        }
    }
}

/// 標準出力のストリームに溜まったものを書き出す（エラーの表示の前など）
pub fn flushStandard(th: *Thread) void {
    th.out.flush() catch {};
}

// ---------------------------------------------------------------------------
// 標準のストリーム（Thread.create が呼ぶ）

pub fn installStandardStreams(th: *Thread) bool {
    const rt = th.rt;
    const out = makeStream(th, .stdout, SF.output | SF.open, Value.nil, true) orelse return false;
    stateOf(out).?.writer = th.out;
    const in = makeStream(th, .stdin, SF.input | SF.open, Value.nil, true) orelse return false;
    const err = makeStream(th, .stderr, SF.output | SF.open, Value.nil, true) orelse return false;
    const pair = rt.cons(in, out) catch return false;
    const tio = makeStream(th, .two_way, SF.input | SF.output | SF.open, pair, false) orelse return false;
    const syn_tio = makeStream(th, .synonym, SF.input | SF.output | SF.open, rt.syms.@"*terminal-io*", false) orelse return false;
    const syn_out = makeStream(th, .synonym, SF.output | SF.open, rt.syms.@"*standard-output*", false) orelse return false;
    rt.symbolPtr(rt.syms.@"*standard-output*").value = out;
    rt.symbolPtr(rt.syms.@"*standard-input*").value = in;
    rt.symbolPtr(rt.syms.@"*error-output*").value = err;
    rt.symbolPtr(rt.syms.@"*terminal-io*").value = tio;
    rt.symbolPtr(rt.syms.@"*query-io*").value = syn_tio;
    rt.symbolPtr(rt.syms.@"*debug-io*").value = syn_tio;
    rt.symbolPtr(rt.syms.@"*trace-output*").value = syn_out;
    rt.symbolPtr(rt.syms.@"*default-pathname-defaults*").value = pathnames.initialDefaults(rt) catch return false;
    return true;
}

// ---------------------------------------------------------------------------
// ストリーム指定子

fn streamDesignatorError(th: *Thread, v: Value) ?Value {
    _ = th.typeError(v, cl(th, "STREAM"));
    return null;
}

fn closedError(th: *Thread, v: Value) ?Value {
    _ = th.signal(.stream_error, "閉じたストリームです", v, Value.unbound);
    return null;
}

/// synonym・two-way をたどって、実際に書くストリームにする
fn resolveOutStream(th: *Thread, v0: Value) ?Value {
    var v = v0;
    var depth: usize = 0;
    while (depth < 64) : (depth += 1) {
        if (!isStream(v)) return streamDesignatorError(th, v);
        // 途中の synonym・two-way も、閉じていればエラー（Codex のレビュー P23 #6）
        if (flags(v) & SF.open == 0) return closedError(th, v);
        switch (kindOf(v)) {
            .synonym => v = th.rt.symbolPtr(ptr(v).ref).value,
            .two_way => v = Runtime.consPtr(ptr(v).ref).cdr,
            else => {
                // 向きの違うストリームは type-error（SBCL 2.6.7 と同じ）
                if (flags(v) & SF.output == 0) return streamDesignatorError(th, v);
                if (flags(v) & SF.open == 0) return closedError(th, v);
                return v;
            },
        }
    }
    _ = th.signal(.stream_error, "synonym ストリームが循環しています", v0, Value.unbound);
    return null;
}

fn resolveInStream(th: *Thread, v0: Value) ?Value {
    var v = v0;
    var depth: usize = 0;
    while (depth < 64) : (depth += 1) {
        if (!isStream(v)) return streamDesignatorError(th, v);
        if (flags(v) & SF.open == 0) return closedError(th, v);
        switch (kindOf(v)) {
            .synonym => v = th.rt.symbolPtr(ptr(v).ref).value,
            .two_way => v = Runtime.consPtr(ptr(v).ref).car,
            else => {
                if (flags(v) & SF.input == 0) return streamDesignatorError(th, v);
                if (flags(v) & SF.open == 0) return closedError(th, v);
                return v;
            },
        }
    }
    _ = th.signal(.stream_error, "synonym ストリームが循環しています", v0, Value.unbound);
    return null;
}

/// 出力に使えるストリームか（閉じていない出力のストリーム。エラーは記録しない。format が、実際に書くまで
/// エラーにしないために使う）
pub fn usableOutput(th: *Thread, v0: Value) bool {
    var v = v0;
    var depth: usize = 0;
    while (depth < 64) : (depth += 1) {
        if (!isStream(v)) return false;
        if (flags(v) & SF.open == 0) return false;
        switch (kindOf(v)) {
            .synonym => v = th.rt.symbolPtr(ptr(v).ref).value,
            .two_way => v = Runtime.consPtr(ptr(v).ref).cdr,
            else => return flags(v) & SF.output != 0,
        }
    }
    return false;
}

/// 出力のストリーム指定子（NIL は *standard-output*、T は *terminal-io*）
pub fn outputDesignator(th: *Thread, v: ?Value) ?Value {
    const rt = th.rt;
    const d = v orelse Value.nil;
    const s = if (d == Value.nil) rt.symbolPtr(rt.syms.@"*standard-output*").value else if (d == rt.t) rt.symbolPtr(rt.syms.@"*terminal-io*").value else d;
    if (!isStream(s)) return streamDesignatorError(th, s);
    // 閉じたストリーム・入力だけのストリームはここでエラーにする（何も書かない fresh-line・(format s "~&")・clear-output
    // でも SBCL と同じくエラー。agy のレビュー 0.3 #1）
    _ = resolveOutStream(th, s) orelse return null;
    return s;
}

/// 入力のストリーム指定子（NIL は *standard-input*、T は *terminal-io*）
pub fn inputDesignator(th: *Thread, v: ?Value) ?Value {
    const rt = th.rt;
    const d = v orelse Value.nil;
    const s = if (d == Value.nil) rt.symbolPtr(rt.syms.@"*standard-input*").value else if (d == rt.t) rt.symbolPtr(rt.syms.@"*terminal-io*").value else d;
    if (!isStream(s)) return streamDesignatorError(th, s);
    return resolveInStream(th, s);
}

// ---------------------------------------------------------------------------
// 出力

fn flushFile(th: *Thread, st: *StreamState) bool {
    const f = st.file orelse return true;
    if (st.out.items.len == 0) return true;
    const io = th.rt.io orelse return true;
    f.writePositionalAll(io, st.out.items, st.file_offset) catch {
        _ = th.signal(.file_error, "ファイルに書けません", Value.unbound, Value.unbound);
        return false;
    };
    st.file_offset += st.out.items.len;
    st.file_len = @max(st.file_len, st.file_offset);
    st.out.clearRetainingCapacity();
    return true;
}

/// バイト列を出力のストリーム（指定子を解決したもの）に書く
pub fn emit(th: *Thread, stream: Value, bytes: []const u8) bool {
    const s = resolveOutStream(th, stream) orelse return false;
    switch (kindOf(s)) {
        .broadcast => {
            var x = ptr(s).ref;
            while (x.isCons()) : (x = Runtime.consPtr(x).cdr) if (!emit(th, Runtime.consPtr(x).car, bytes)) return false;
            return true;
        },
        else => {},
    }
    // 文字の出力は文字のストリームだけ（バイナリは type-error。SBCL 2.6.7 と同じ。Codex のレビュー P23 #4）
    if (flags(s) & SF.binary != 0) {
        _ = th.typeError(s, cl(th, "CHARACTER"));
        return false;
    }
    const st = stateOf(s) orelse return true;
    if (bytes.len == 0) return true;
    switch (st.kind) {
        .stdout => (st.writer orelse th.out).writeAll(bytes) catch {
            _ = th.signal(.stream_error, "標準出力に書けません", s, Value.unbound);
            return false;
        },
        .stderr => {
            th.out.flush() catch {};
            if (th.rt.io) |io| Io.File.stderr().writeStreamingAll(io, bytes) catch {};
        },
        .string_output => st.out.appendSlice(th.rt.gpa, bytes) catch {
            _ = th.outOfMemory();
            return false;
        },
        .pretty => {
            const ps = st.pretty orelse return true;
            ps.writeUtf8(bytes) catch return false;
            return true;
        },
        .file => {
            if (st.latin1) {
                // UTF-8 を Latin-1 にする。U+0100 以上は表せないので stream-error（SBCL 2.6.7 は stream-encoding-error。
                // Codex のレビュー P23 #16）
                var view = std.unicode.Utf8View.initUnchecked(bytes);
                var it = view.iterator();
                while (it.nextCodepoint()) |cp| {
                    if (cp >= 256) {
                        _ = th.signal(.stream_error, "Latin-1 で表せない文字です", Value.fromChar(cp), Value.unbound);
                        return false;
                    }
                    st.out.append(th.rt.gpa, @intCast(cp)) catch {
                        _ = th.outOfMemory();
                        return false;
                    };
                }
            } else st.out.appendSlice(th.rt.gpa, bytes) catch {
                _ = th.outOfMemory();
                return false;
            };
            if (st.out.items.len >= flush_threshold and !flushFile(th, st)) return false;
        },
        else => {},
    }
    st.at_line_start = bytes[bytes.len - 1] == '\n';
    if (std.mem.lastIndexOfScalar(u8, bytes, '\n')) |i| st.column = charCount(bytes[i + 1 ..]) else st.column += charCount(bytes);
    return true;
}

/// 出力のストリームの今の桁（broadcast は最初のストリームの桁。わからなければ null。format の ~T）
pub fn columnOf(th: *Thread, stream: Value) ?usize {
    const s = resolveOutStream(th, stream) orelse return null;
    if (prettyStateOf(s)) |ps| return @intCast(@max(ps.currentColumn(), 0));
    if (kindOf(s) == .broadcast) {
        const x = ptr(s).ref;
        if (!x.isCons()) return null;
        return columnOf(th, Runtime.consPtr(x).car);
    }
    const st = stateOf(s) orelse return null;
    return st.column;
}

/// pretty stream を作る（target に書き出す。column は target の今の桁。Phase 24）
pub fn makePrettyStream(th: *Thread, target: Value, column: usize) ?Value {
    const s = makeStream(th, .pretty, SF.output | SF.open, target, true) orelse return null;
    stateOf(s).?.pretty = pretty_mod.State.create(th, target, column) catch {
        _ = th.outOfMemory();
        return null;
    };
    return s;
}

/// pretty stream を閉じる（状態を解放する。with-pretty-stream の終わり）
pub fn closePrettyStream(th: *Thread, s: Value) void {
    if (stateOf(s)) |st| {
        if (st.pretty) |ps| ps.destroy();
        st.pretty = null;
    }
    ptr(s).header.flags &= ~SF.open;
    _ = th;
}

/// pretty stream の状態（pretty stream でなければ null）
pub fn prettyStateOf(s: Value) ?*pretty_mod.State {
    if (!isStream(s) or kindOf(s) != .pretty) return null;
    const st = stateOf(s) orelse return null;
    return st.pretty;
}

/// 何も書かないストリーム（*print-circle* の1回目の走査。中身のない broadcast と同じ）
pub fn makeNullOutput(th: *Thread) ?Value {
    return makeStream(th, .broadcast, SF.output | SF.open, Value.nil, false);
}

/// 文字列の出力ストリームを作る（format が使う）
pub fn makeStringOutput(th: *Thread) ?Value {
    return makeStream(th, .string_output, SF.output | SF.open, Value.nil, true);
}

/// 文字列の出力ストリームに溜まったバイト列（UTF-8）を取り出して空にする（format が使う）
pub fn takeStringOutput(th: *Thread, s: Value, out: *std.ArrayList(u8)) bool {
    const st = stateOf(s) orelse return true;
    out.appendSlice(th.rt.gpa, st.out.items) catch {
        _ = th.outOfMemory();
        return false;
    };
    st.out.clearRetainingCapacity();
    st.at_line_start = true;
    st.column = 0;
    return true;
}

/// 出力のストリームが行の先頭にいるか（fresh-line・~&）
pub fn atLineStart(th: *Thread, stream: Value) bool {
    const s = resolveOutStream(th, stream) orelse return true;
    // pretty stream は桁を答えない（SBCL の pretty-misc は charpos に NIL を返す）ので、fresh-line・~& は必ず改行する
    if (prettyStateOf(s) != null) return false;
    if (kindOf(s) == .broadcast) {
        var x = ptr(s).ref;
        while (x.isCons()) : (x = Runtime.consPtr(x).cdr) if (!atLineStart(th, Runtime.consPtr(x).car)) return false;
        return true;
    }
    const st = stateOf(s) orelse return true;
    return st.at_line_start;
}

fn emitPrinted(th: *Thread, stream: Value, v: Value, escape: ?bool) bool {
    // condition・restart は Lisp の印字の関数で書く（pprint の outputUgly が zl-sys::%print-record を呼ぶ。Phase 25）
    if (prettyOn(th) or isRecord(v)) return printPretty(th, stream, v, escape);
    var buf: Io.Writer.Allocating = .init(th.rt.gpa);
    defer buf.deinit();
    if (!printTo(th, &buf.writer, v, escape)) return false;
    return emit(th, stream, buf.written());
}

fn prettyOn(th: *Thread) bool {
    return th.rt.symbolPtr(th.rt.syms.@"*print-pretty*").value != Value.nil;
}

/// condition・restart（Phase 25）
pub fn isRecord(v: Value) bool {
    return v.isOther() and Runtime.kindOf(v) == .record;
}

/// *print-pretty* が真のときの印字：escape を指定すれば *print-escape* を束縛する（princ は *print-readably* も偽にする）
pub fn printPretty(th: *Thread, stream: Value, v: Value, escape: ?bool) bool {
    const depth = th.binding_depth;
    defer th.unbindTo(depth);
    if (escape) |e| {
        if (th.bind(th.rt.syms.@"*print-escape*", th.rt.boolean(e)) == Value.unwind) return false;
        if (!e and th.bind(th.rt.syms.@"*print-readably*", Value.nil) == Value.unwind) return false;
    }
    return pprint_mod.printTop(th, stream, v);
}

/// 今の印字の変数に従って w に書く（escape が null なら *print-escape*）。
/// *print-readably* で読み戻せないものは print-not-readable のエラー（Phase 24）
pub fn printTo(th: *Thread, w: *Io.Writer, v: Value, escape: ?bool) bool {
    if (isRecord(v)) {
        // condition・restart：Lisp の印字の関数で文字列のストリームに書いて写す（Phase 25）
        const ss = makeStringOutput(th) orelse return false;
        if (!printPretty(th, ss, v, escape)) return false;
        var bytes: std.ArrayList(u8) = .empty;
        defer bytes.deinit(th.rt.gpa);
        if (!takeStringOutput(th, ss, &bytes)) return false;
        w.writeAll(bytes.items) catch {
            _ = th.outOfMemory();
            return false;
        };
        return true;
    }
    var bad: Value = Value.nil;
    printer.writeObject(th.rt, w, v, printer.Settings.current(th.rt, escape), &bad) catch |err| switch (err) {
        error.NotReadable => {
            _ = th.signal(.print_not_readable, "読み戻せる形で印字できません", bad, Value.unbound);
            return false;
        },
        error.WriteFailed => {
            _ = th.outOfMemory();
            return false;
        },
    };
    return true;
}

/// write・write-to-string のキーワードと、束縛する印字の変数
const write_keys = [_][]const u8{ "STREAM", "ARRAY", "BASE", "CASE", "CIRCLE", "ESCAPE", "GENSYM", "LENGTH", "LEVEL", "LINES", "MISER-WIDTH", "PPRINT-DISPATCH", "PRETTY", "RADIX", "READABLY", "RIGHT-MARGIN" };

fn writeKeyVar(th: *Thread, i: usize) Value {
    const y = &th.rt.syms;
    return switch (i) {
        1 => y.@"*print-array*",
        2 => y.@"*print-base*",
        3 => y.@"*print-case*",
        4 => y.@"*print-circle*",
        5 => y.@"*print-escape*",
        6 => y.@"*print-gensym*",
        7 => y.@"*print-length*",
        8 => y.@"*print-level*",
        9 => y.@"*print-lines*",
        10 => y.@"*print-miser-width*",
        11 => y.@"*print-pprint-dispatch*",
        12 => y.@"*print-pretty*",
        13 => y.@"*print-radix*",
        14 => y.@"*print-readably*",
        15 => y.@"*print-right-margin*",
        else => unreachable,
    };
}

/// write・write-to-string のキーワードの印字の変数を束縛する（:stream 以外）。値を検査する（*print-base* は 2〜36 の整数、
/// *print-case* は :upcase・:downcase・:capitalize。SBCL 2.6.7 も型を宣言している）
fn bindWriteKeys(th: *Thread, kv: []const ?Value) bool {
    for (kv[1..], 1..) |v0, i| {
        const v = v0 orelse continue;
        if (i == 2 and !(v.isFixnum() and v.asFixnum() >= 2 and v.asFixnum() <= 36)) {
            _ = th.typeError(v, cl(th, "INTEGER"));
            return false;
        }
        if (i == 3 and v != (kw(th, "UPCASE") orelse return false) and v != (kw(th, "DOWNCASE") orelse return false) and v != (kw(th, "CAPITALIZE") orelse return false)) {
            _ = th.typeError(v, cl(th, "SYMBOL"));
            return false;
        }
        if (th.bind(writeKeyVar(th, i), v) == Value.unwind) return false;
    }
    return true;
}

/// (write-string 文字列 &optional ストリーム &key start end) などで使う：文字列の [start, end) を UTF-8 で書く
fn emitString(th: *Thread, stream: Value, str: Value, start: usize, end: usize) bool {
    var buf: std.ArrayList(u8) = .empty;
    defer buf.deinit(th.rt.gpa);
    const view = arrays.vectorView(str).?;
    const s = Runtime.stringPtr(view.data);
    for (start..end) |i| {
        var b: [4]u8 = undefined;
        const n = std.unicode.utf8Encode(s.charAt(i), &b) catch unreachable;
        buf.appendSlice(th.rt.gpa, b[0..n]) catch {
            _ = th.outOfMemory();
            return false;
        };
    }
    return emit(th, stream, buf.items);
}

fn optArg(args: []const Value, i: usize) ?Value {
    return if (args.len > i) args[i] else null;
}

pub fn print(th: *Thread, args: []const Value) Value {
    const s = outputDesignator(th, optArg(args, 1)) orelse return Value.unwind;
    if (!emit(th, s, "\n") or !emitPrinted(th, s, args[0], true) or !emit(th, s, " ")) return Value.unwind;
    th.mv_count = 1;
    return args[0];
}

pub fn prin1(th: *Thread, args: []const Value) Value {
    const s = outputDesignator(th, optArg(args, 1)) orelse return Value.unwind;
    if (!emitPrinted(th, s, args[0], true)) return Value.unwind;
    th.mv_count = 1;
    return args[0];
}

pub fn princ(th: *Thread, args: []const Value) Value {
    const s = outputDesignator(th, optArg(args, 1)) orelse return Value.unwind;
    if (!emitPrinted(th, s, args[0], false)) return Value.unwind;
    th.mv_count = 1;
    return args[0];
}

/// (pprint x &optional stream)：改行と prin1（pretty printer は未実装なので、1行に書く）
pub fn pprint(th: *Thread, args: []const Value) Value {
    const s = outputDesignator(th, optArg(args, 1)) orelse return Value.unwind;
    if (!emit(th, s, "\n") or !emitPrinted(th, s, args[0], true)) return Value.unwind;
    th.mv_count = 0;
    return Value.nil;
}

pub fn terpri(th: *Thread, args: []const Value) Value {
    const s = outputDesignator(th, optArg(args, 0)) orelse return Value.unwind;
    if (!emit(th, s, "\n")) return Value.unwind;
    return Value.nil;
}

pub fn freshLine(th: *Thread, args: []const Value) Value {
    const s = outputDesignator(th, optArg(args, 0)) orelse return Value.unwind;
    if (atLineStart(th, s)) return Value.nil;
    if (!emit(th, s, "\n")) return Value.unwind;
    return th.rt.t;
}

pub fn writeChar(th: *Thread, args: []const Value) Value {
    if (!args[0].isChar()) return th.typeError(args[0], cl(th, "CHARACTER"));
    const s = outputDesignator(th, optArg(args, 1)) orelse return Value.unwind;
    var b: [4]u8 = undefined;
    const n = std.unicode.utf8Encode(args[0].asChar(), &b) catch unreachable;
    if (!emit(th, s, b[0..n])) return Value.unwind;
    return args[0];
}

fn stringBounds(th: *Thread, str: Value, rest: []const Value) ?[2]usize {
    var kv: [2]?Value = .{ null, null };
    if (rest.len > 0 and !keyargs.parse(th, rest, &.{ "START", "END" }, &kv)) return null;
    return @import("strings.zig").bounds(th, kv[0], kv[1], arrays.vectorView(str).?.len);
}

fn writeStringImpl(th: *Thread, args: []const Value, newline: bool) Value {
    const str = args[0];
    if (!arrays.isStringLike(str)) return th.typeError(str, cl(th, "STRING"));
    const s = outputDesignator(th, optArg(args, 1)) orelse return Value.unwind;
    const b = stringBounds(th, str, if (args.len > 2) args[2..] else &.{}) orelse return Value.unwind;
    if (!emitString(th, s, str, b[0], b[1])) return Value.unwind;
    if (newline and !emit(th, s, "\n")) return Value.unwind;
    return str;
}

pub fn writeString(th: *Thread, args: []const Value) Value {
    return writeStringImpl(th, args, false);
}

pub fn writeLine(th: *Thread, args: []const Value) Value {
    return writeStringImpl(th, args, true);
}

/// finish-output・force-output：ファイルなら書き出す。clear-output：何もしない
pub fn finishOutput(th: *Thread, args: []const Value) Value {
    const s0 = outputDesignator(th, optArg(args, 0)) orelse return Value.unwind;
    if (!flushStream(th, s0)) return Value.unwind;
    return Value.nil;
}

/// ストリームの出力を書き出す（broadcast は中のストリームそれぞれ。Codex のレビュー P23 #5）
fn flushStream(th: *Thread, s0: Value) bool {
    const s = resolveOutStream(th, s0) orelse return false;
    if (kindOf(s) == .broadcast) {
        var x = ptr(s).ref;
        while (x.isCons()) : (x = Runtime.consPtr(x).cdr) if (!flushStream(th, Runtime.consPtr(x).car)) return false;
        return true;
    }
    if (stateOf(s)) |st| {
        if (st.kind == .file and !flushFile(th, st)) return false;
        if (st.kind == .stdout) (st.writer orelse th.out).flush() catch {};
    }
    return true;
}

pub fn clearOutput(th: *Thread, args: []const Value) Value {
    _ = outputDesignator(th, optArg(args, 0)) orelse return Value.unwind;
    return Value.nil;
}

/// (write オブジェクト &key stream array base case circle escape gensym length level lines miser-width pprint-dispatch
/// pretty radix readably right-margin)：キーワードの印字の変数を束縛して印字する（CLHS write）
pub fn write(th: *Thread, args: []const Value) Value {
    var kv: [write_keys.len]?Value = @splat(null);
    if (!keyargs.parse(th, args[1..], &write_keys, &kv)) return Value.unwind;
    const s = outputDesignator(th, kv[0]) orelse return Value.unwind;
    const depth = th.binding_depth;
    defer th.unbindTo(depth);
    if (!bindWriteKeys(th, &kv)) return Value.unwind;
    if (!emitPrinted(th, s, args[0], null)) return Value.unwind;
    th.mv_count = 1;
    return args[0];
}

fn toString(th: *Thread, v: Value, escape: ?bool) Value {
    if (prettyOn(th)) {
        const s = makeStringOutput(th) orelse return Value.unwind;
        if (!printPretty(th, s, v, escape)) return Value.unwind;
        return getOutputStreamString(th, &.{s});
    }
    var buf: Io.Writer.Allocating = .init(th.rt.gpa);
    defer buf.deinit();
    if (!printTo(th, &buf.writer, v, escape)) return Value.unwind;
    return th.rt.makeString(buf.written()) catch oom(th);
}

pub fn prin1ToString(th: *Thread, args: []const Value) Value {
    return toString(th, args[0], true);
}

pub fn princToString(th: *Thread, args: []const Value) Value {
    return toString(th, args[0], false);
}

/// (write-to-string オブジェクト &key …)：write と同じキーワード（:stream を除く）
pub fn writeToString(th: *Thread, args: []const Value) Value {
    var kv: [write_keys.len]?Value = @splat(null);
    if (!keyargs.parse(th, args[1..], write_keys[1..], kv[1..])) return Value.unwind;
    const depth = th.binding_depth;
    defer th.unbindTo(depth);
    if (!bindWriteKeys(th, &kv)) return Value.unwind;
    return toString(th, args[0], null);
}

// ---------------------------------------------------------------------------
// 入力

/// 標準入力から読み足す（読めたら真）
fn fillStdin(th: *Thread, st: *StreamState) bool {
    if (st.kind != .stdin or st.stdin_eof) return false;
    th.out.flush() catch {};
    if (st.reader) |in| {
        // 改行までを読む（最後の行に改行がなければ、残りをそのまま。長すぎる行はバッファの分ずつ）
        const l = in.takeDelimiterInclusive('\n') catch |err| switch (err) {
            error.ReadFailed => &.{},
            error.EndOfStream, error.StreamTooLong => blk: {
                const rest = in.buffered();
                in.toss(rest.len);
                break :blk rest;
            },
        };
        if (l.len == 0) {
            st.stdin_eof = true;
            return false;
        }
        st.in_list.appendSlice(th.rt.gpa, l) catch return stdinOom(th, st);
        return true;
    }
    const io = th.rt.io orelse {
        st.stdin_eof = true;
        return false;
    };
    var buf: [4096]u8 = undefined;
    const n = Io.File.stdin().readStreaming(io, &.{&buf}) catch 0;
    if (n == 0) {
        st.stdin_eof = true;
        return false;
    }
    st.in_list.appendSlice(th.rt.gpa, buf[0..n]) catch return stdinOom(th, st);
    return true;
}

fn stdinOom(th: *Thread, st: *StreamState) bool {
    _ = th.outOfMemory();
    st.stdin_oom = true;
    st.stdin_eof = true;
    return false;
}

/// 読み足しでメモリが足りなかったか（真なら、記録済みのエラーで巻き戻す）
fn takeStdinOom(s: Value) bool {
    if (!isStream(s)) return false;
    const st = stateOf(s) orelse return false;
    if (!st.stdin_oom) return false;
    st.stdin_oom = false;
    return true;
}

/// 位置の文字を読む（null は終わり）。進めたバイト数を len に入れる
fn decodeAt(th: *Thread, st: *StreamState, len: *usize) ?u21 {
    while (st.pos >= st.input().len) if (!fillStdin(th, st)) return null;
    const in = st.input();
    const b0 = in[st.pos];
    if (st.latin1) {
        len.* = 1;
        return b0;
    }
    const n = std.unicode.utf8ByteSequenceLength(b0) catch {
        len.* = 1;
        return 0xFFFD;
    };
    while (st.pos + n > st.input().len) if (!fillStdin(th, st)) {
        len.* = 1;
        return 0xFFFD;
    };
    const cp = std.unicode.utf8Decode(st.input()[st.pos..][0..n]) catch {
        len.* = 1;
        return 0xFFFD;
    };
    len.* = n;
    return cp;
}

fn readCharRaw(th: *Thread, st: *StreamState) ?u21 {
    var n: usize = 0;
    const c = decodeAt(th, st, &n) orelse return null;
    st.pos += n;
    st.last_len = n;
    return c;
}

fn checkCharStream(th: *Thread, s: Value) bool {
    if (flags(s) & SF.binary != 0) {
        _ = th.typeError(s, cl(th, "CHARACTER"));
        return false;
    }
    return true;
}

fn eofResult(th: *Thread, s: Value, eof_error: ?Value, eof_value: ?Value) Value {
    if (takeStdinOom(s)) return Value.unwind;
    if (eof_error == null or eof_error.? != Value.nil)
        return th.signal(.end_of_file, "ストリームの終わりです", s, Value.unbound);
    return eof_value orelse Value.nil;
}

/// (read-char &optional stream eof-error-p eof-value recursive-p)
pub fn readChar(th: *Thread, args: []const Value) Value {
    const s = inputDesignator(th, optArg(args, 0)) orelse return Value.unwind;
    if (!checkCharStream(th, s)) return Value.unwind;
    const st = stateOf(s) orelse return eofResult(th, s, optArg(args, 1), optArg(args, 2));
    const c = readCharRaw(th, st) orelse return eofResult(th, s, optArg(args, 1), optArg(args, 2));
    return Value.fromChar(c);
}

/// (read-char-no-hang &optional stream eof-error-p eof-value recursive-p)：
/// 標準入力で、まだ届いていない文字は待たずに NIL（ほかのストリームは READ-CHAR と同じ。SBCL 2.6.7 と同じ。
/// Codex のレビュー P23 #7）
pub fn readCharNoHang(th: *Thread, args: []const Value) Value {
    const s = inputDesignator(th, optArg(args, 0)) orelse return Value.unwind;
    if (!checkCharStream(th, s)) return Value.unwind;
    const st = stateOf(s) orelse return eofResult(th, s, optArg(args, 1), optArg(args, 2));
    if (st.kind == .stdin and st.pos >= st.in_list.items.len and !st.stdin_eof) {
        // REPL と共有する Io.Reader に読み込み済みのものがあれば使う
        if (st.reader) |in| {
            const rest = in.buffered();
            if (rest.len > 0) {
                st.in_list.appendSlice(th.rt.gpa, rest) catch return oom(th);
                in.toss(rest.len);
                return readChar(th, args);
            }
        }
        // 端末からの入力は待たない。ファイルやパイプは READ-CHAR と同じに読む
        const io = th.rt.io orelse return Value.nil;
        const tty = Io.File.stdin().isTty(io) catch true;
        if (tty) return Value.nil;
    }
    return readChar(th, args);
}

/// (unread-char 文字 &optional stream)：最後に読んだ文字を戻す
pub fn unreadChar(th: *Thread, args: []const Value) Value {
    if (!args[0].isChar()) return th.typeError(args[0], cl(th, "CHARACTER"));
    const s = inputDesignator(th, optArg(args, 1)) orelse return Value.unwind;
    if (!checkCharStream(th, s)) return Value.unwind;
    const st = stateOf(s) orelse return Value.nil;
    if (st.last_len == 0 or st.pos < st.last_len) return th.signal(.simple_error, "UNREAD-CHAR の前に READ-CHAR がありません", s, Value.unbound);
    st.pos -= st.last_len;
    st.last_len = 0;
    return Value.nil;
}

fn isWhitespace(c: u21) bool {
    return c == ' ' or c == '\t' or c == '\n' or c == '\r' or c == 0x0C or c == 0x0B;
}

/// (peek-char &optional peek-type stream eof-error-p eof-value recursive-p)
pub fn peekChar(th: *Thread, args: []const Value) Value {
    const peek_type = optArg(args, 0) orelse Value.nil;
    const s = inputDesignator(th, optArg(args, 1)) orelse return Value.unwind;
    if (!checkCharStream(th, s)) return Value.unwind;
    const st = stateOf(s) orelse return eofResult(th, s, optArg(args, 2), optArg(args, 3));
    while (true) {
        var n: usize = 0;
        const c = decodeAt(th, st, &n) orelse return eofResult(th, s, optArg(args, 2), optArg(args, 3));
        const stop = if (peek_type == Value.nil) true else if (peek_type == th.rt.t) !isWhitespace(c) else if (peek_type.isChar()) c == peek_type.asChar() else return th.typeError(peek_type, cl(th, "CHARACTER"));
        if (stop) return Value.fromChar(c);
        // 読み飛ばした文字は unread-char で戻せる（最後に読み飛ばした文字の長さ。SBCL と同じ。agy のレビュー 0.3 #2）
        st.pos += n;
        st.last_len = n;
    }
}

/// (read-line &optional stream eof-error-p eof-value recursive-p)：行と、改行で終わらなかったか
pub fn readLine(th: *Thread, args: []const Value) Value {
    const rt = th.rt;
    const s = inputDesignator(th, optArg(args, 0)) orelse return Value.unwind;
    if (!checkCharStream(th, s)) return Value.unwind;
    const st = stateOf(s) orelse return eofResult(th, s, optArg(args, 1), optArg(args, 2));
    var line: std.ArrayList(u8) = .empty;
    defer line.deinit(rt.gpa);
    var any = false;
    while (true) {
        const c = readCharRaw(th, st) orelse break;
        any = true;
        if (c == '\n') {
            th.mv[1] = Value.nil;
            th.mv_count = 2;
            return rt.makeString(line.items) catch oom(th);
        }
        var b: [4]u8 = undefined;
        const n = std.unicode.utf8Encode(c, &b) catch unreachable;
        line.appendSlice(rt.gpa, b[0..n]) catch return oom(th);
    }
    if (!any) {
        const r = eofResult(th, s, optArg(args, 1), optArg(args, 2));
        th.mv[1] = rt.t;
        th.mv_count = 2;
        return r;
    }
    th.mv[1] = rt.t;
    th.mv_count = 2;
    return rt.makeString(line.items) catch oom(th);
}

/// (listen &optional stream)：すぐに読める文字があるか
pub fn listen(th: *Thread, args: []const Value) Value {
    const s = inputDesignator(th, optArg(args, 0)) orelse return Value.unwind;
    const st = stateOf(s) orelse return Value.nil;
    return th.rt.boolean(st.pos < st.input().len);
}

pub fn clearInput(th: *Thread, args: []const Value) Value {
    _ = inputDesignator(th, optArg(args, 0)) orelse return Value.unwind;
    return Value.nil;
}

fn checkBinaryStream(th: *Thread, s: Value) bool {
    if (flags(s) & SF.binary == 0) {
        _ = th.typeError(s, cl(th, "INTEGER"));
        return false;
    }
    return true;
}

/// (read-byte stream &optional eof-error-p eof-value)
pub fn readByte(th: *Thread, args: []const Value) Value {
    const s = inputDesignator(th, args[0]) orelse return Value.unwind;
    if (!checkBinaryStream(th, s)) return Value.unwind;
    const st = stateOf(s) orelse return eofResult(th, s, optArg(args, 1), optArg(args, 2));
    if (st.pos >= st.input().len) return eofResult(th, s, optArg(args, 1), optArg(args, 2));
    const b = st.input()[st.pos];
    st.pos += 1;
    return Value.fromFixnum(b);
}

/// (write-byte 整数 stream)
pub fn writeByte(th: *Thread, args: []const Value) Value {
    const s0 = outputDesignator(th, args[1]) orelse return Value.unwind;
    const v = args[0];
    if (!v.isFixnum() or v.asFixnum() < 0 or v.asFixnum() > 255) return th.typeError(v, cl(th, "INTEGER"));
    if (!emitByte(th, s0, @intCast(v.asFixnum()))) return Value.unwind;
    return v;
}

/// 1 バイトを書く（broadcast は中のストリームそれぞれ。Codex のレビュー P23 #5）
fn emitByte(th: *Thread, s0: Value, byte: u8) bool {
    const s = resolveOutStream(th, s0) orelse return false;
    if (kindOf(s) == .broadcast) {
        var x = ptr(s).ref;
        while (x.isCons()) : (x = Runtime.consPtr(x).cdr) if (!emitByte(th, Runtime.consPtr(x).car, byte)) return false;
        return true;
    }
    if (!checkBinaryStream(th, s)) return false;
    const st = stateOf(s) orelse return true;
    st.out.append(th.rt.gpa, byte) catch {
        _ = th.outOfMemory();
        return false;
    };
    if (st.out.items.len >= flush_threshold and !flushFile(th, st)) return false;
    return true;
}

/// (read-sequence 列 stream &key start end)：読んだ最後の位置
pub fn readSequence(th: *Thread, args: []const Value) Value {
    const seq = args[0];
    const s = inputDesignator(th, args[1]) orelse return Value.unwind;
    var kv: [2]?Value = .{ null, null };
    if (args.len > 2 and !keyargs.parse(th, args[2..], &.{ "START", "END" }, &kv)) return Value.unwind;
    const view = arrays.vectorView(seq) orelse return th.signal(.unimplemented, "READ-SEQUENCE にベクタ以外の列を使うのは未実装です", seq, Value.unbound);
    const b = @import("strings.zig").bounds(th, kv[0], kv[1], view.len) orelse return Value.unwind;
    const st = stateOf(s) orelse return Value.fromFixnum(@intCast(b[0]));
    const binary = flags(s) & SF.binary != 0;
    var i = b[0];
    while (i < b[1]) : (i += 1) {
        const item = if (binary) blk: {
            if (st.pos >= st.input().len) break;
            const byte = st.input()[st.pos];
            st.pos += 1;
            break :blk Value.fromFixnum(byte);
        } else Value.fromChar(readCharRaw(th, st) orelse break);
        if (arrays.storageSet(th, view.data, i, item) == Value.unwind) return Value.unwind;
    }
    return Value.fromFixnum(@intCast(i));
}

/// (write-sequence 列 stream &key start end)：列を返す
pub fn writeSequence(th: *Thread, args: []const Value) Value {
    const seq = args[0];
    const s0 = outputDesignator(th, args[1]) orelse return Value.unwind;
    const s = resolveOutStream(th, s0) orelse return Value.unwind;
    var kv: [2]?Value = .{ null, null };
    if (args.len > 2 and !keyargs.parse(th, args[2..], &.{ "START", "END" }, &kv)) return Value.unwind;
    const view = arrays.vectorView(seq) orelse return th.signal(.unimplemented, "WRITE-SEQUENCE にベクタ以外の列を使うのは未実装です", seq, Value.unbound);
    const b = @import("strings.zig").bounds(th, kv[0], kv[1], view.len) orelse return Value.unwind;
    if (flags(s) & SF.binary != 0) {
        for (b[0]..b[1]) |i| if (writeByte(th, &.{ arrays.storageGet(view.data, i), s0 }) == Value.unwind) return Value.unwind;
        return seq;
    }
    if (arrays.isStringLike(seq)) {
        if (!emitString(th, s, seq, b[0], b[1])) return Value.unwind;
        return seq;
    }
    // broadcast はバイナリの印を持たないので、要素が整数なら write-byte に渡す（write-byte が出力先に配る。
    // agy のレビュー 0.3 #9・Codex のレビュー 0.3 #7）
    for (b[0]..b[1]) |i| {
        const e = arrays.storageGet(view.data, i);
        const r = if (kindOf(s) == .broadcast and (e.isFixnum() or (e.isOther() and Runtime.kindOf(e) == .bignum))) writeByte(th, &.{ e, s0 }) else writeChar(th, &.{ e, s });
        if (r == Value.unwind) return Value.unwind;
    }
    return seq;
}

// ---------------------------------------------------------------------------
// read・read-from-string

/// Reader で行うこと：read・組み込みのマクロの働き（Lisp から呼ばれた標準のマクロ関数）・read-delimited-list
const ReadOp = union(enum) {
    read,
    builtin: struct { k: reader.Builtin, cp: u21, arg: ?usize },
    delimited: u21,
};

/// st の位置から1つ読む。読めなければ（終わり）null を eof に入れる
/// 読み取りのエラーの condition に入れるストリーム（stream-error-stream）。read-from-string（s が文字列）なら、
/// 同じ中身と位置の文字列の入力ストリームを、エラーのときだけ作る（SBCL 2.6.7 と同じく condition はストリームを持つ。
/// Codex のレビュー P25 2回目 #2）。作れなければ s のまま
fn errorStream(th: *Thread, s: Value, st: *StreamState) Value {
    if (isStream(s)) return s;
    const es = makeStringInputBytes(th, st.input()) orelse return s;
    setReadPosition(es, st.pos);
    return es;
}

fn readFromState(th: *Thread, s: Value, st: *StreamState, preserve: bool, eof: *bool) Value {
    return readOp(th, s, null, st, preserve, false, .read, eof);
}

/// st の位置から op を行う。stream_obj は st を持つストリーム（reader macro に渡す。read-from-string なら null）。
/// recursive なら、外側の read の #n= の表を使う（CLHS read の recursive-p）
fn readOp(th: *Thread, s: Value, stream_obj: ?Value, st: *StreamState, preserve: bool, recursive: bool, op: ReadOp, eof: *bool) Value {
    const rt = th.rt;
    while (true) {
        // 読み始めの位置（reader macro がストリームの位置を動かすので、読んだ後は「始め + 読んだ長さ」にする）
        const start_pos = st.pos;
        const raw = st.input()[st.pos..];
        // Latin-1 の入力は UTF-8 にしてから読む（1 文字が 1 バイトなので、読んだ文字の数だけ元の位置を進める。
        // Codex のレビュー P23 #3）
        var converted: std.ArrayList(u8) = .empty;
        defer converted.deinit(rt.gpa);
        if (st.latin1) {
            for (raw) |c| {
                var u: [4]u8 = undefined;
                const n = std.unicode.utf8Encode(c, &u) catch unreachable;
                converted.appendSlice(rt.gpa, u[0..n]) catch return oom(th);
            }
        }
        const text = if (st.latin1) converted.items else raw;
        var src = reader.Source.init(text, 0);
        // 標準入力は、テキストの終わりで読み足して続きを読む（読み直さない）
        const Refill = struct {
            th: *Thread,
            st: *StreamState,
            start: usize,
            fn f(ctx: *anyopaque) ?[]const u8 {
                const c: *@This() = @ptrCast(@alignCast(ctx));
                if (!fillStdin(c.th, c.st)) return null;
                return c.st.input()[c.start..];
            }
        };
        var refill_ctx: Refill = .{ .th = th, .st = st, .start = start_pos };
        if (st.kind == .stdin and !st.latin1) src.refill = .{ .ctx = &refill_ctx, .f = Refill.f };
        // 読んだところまでストリームの位置を進める（エラーを通知する前に呼ぶ：handler がその場でストリームを読むことがある。
        // SBCL と同じ。Codex のレビュー P25 #5・2回目 #1）
        const Sync = struct {
            st: *StreamState,
            start: usize,
            src: *reader.Source,
            converted: *std.ArrayList(u8),
            fn run(c: *@This()) void {
                c.st.pos = c.start + if (c.st.latin1) charCount(c.converted.items[0..c.src.pos]) else c.src.pos;
                c.st.last_len = 0;
            }
            fn f(ctx: *anyopaque) void {
                run(@ptrCast(@alignCast(ctx)));
            }
        };
        var sync: Sync = .{ .st = st, .start = start_pos, .src = &src, .converted = &converted };
        var b: vb.ValueBuilder = .{ .rt = rt, .th = th, .stream = stream_obj orelse Value.nil, .stream_base = st.pos, .latin1 = st.latin1, .sync_position = .{ .ctx = &sync, .f = Sync.f } };
        if (recursive) if (th.read_builder) |outer| {
            b.labels_ptr = outer.labels_ptr orelse &outer.labels;
        };
        var r = reader.Reader(vb.ValueBuilder).init(rt.gpa, &src, &b, .{ .preserve_whitespace = preserve });
        defer r.deinit();
        if (recursive) if (th.read_builder) |outer| {
            r.bq_depth = outer.bq_depth;
        };
        const result = switch (op) {
            .read => r.read(),
            .builtin => |x| r.readBuiltin(x.k, x.cp, x.arg),
            .delimited => |cp| if (r.readDelimitedList(cp)) |v| @as(?Value, v) else |e| e,
        };
        const form = result catch |err| switch (err) {
            error.OutOfMemory => return oom(th),
            error.EndOfFile => {
                // 標準入力なら読み足して読み直す
                if (fillStdin(th, st)) continue;
                if (st.stdin_oom) {
                    st.stdin_oom = false;
                    return Value.unwind;
                }
                sync.run();
                return th.signal(.end_of_file, "オブジェクトの途中でストリームが終わっています", errorStream(th, s, st), Value.unbound);
            },
            error.ReaderError => {
                sync.run();
                return th.signal(.reader_error, r.diagnostic.message, errorStream(th, s, st), Value.unbound);
            },
            error.LispError => return Value.unwind,
        };
        if (op != .read) {
            // 読んだところまで位置を進める（reader macro がストリームを読み進めた分は Source に反映してある）
            st.pos = start_pos + if (st.latin1) charCount(converted.items[0..src.pos]) else src.pos;
            st.last_len = 0;
            if (form == null) {
                th.mv_count = 0;
                return Value.nil;
            }
            th.mv_count = 1;
            return form.?;
        }
        if (form == null) {
            if (fillStdin(th, st)) continue;
            if (st.stdin_oom) {
                st.stdin_oom = false;
                return Value.unwind;
            }
            st.pos = start_pos + if (st.latin1) charCount(converted.items[0..src.pos]) else src.pos;
            st.last_len = 0;
            eof.* = true;
            return Value.nil;
        }
        var consumed = src.pos;
        const now = if (st.latin1) converted.items else src.text;
        // 読んだ後ろの空白を1つ読み進める（トークンの後ろは Reader が読み進めている。SBCL 2.6.7 と同じ）
        if (!preserve and consumed > 0 and consumed < now.len and !isWhitespace(now[consumed - 1]) and isWhitespace(now[consumed])) consumed += 1;
        st.pos = start_pos + if (st.latin1) charCount(now[0..consumed]) else consumed;
        st.last_len = 0;
        return form.?;
    }
}

fn readImpl(th: *Thread, args: []const Value, preserve: bool) Value {
    const s = inputDesignator(th, optArg(args, 0)) orelse return Value.unwind;
    if (!checkCharStream(th, s)) return Value.unwind;
    const st = stateOf(s) orelse return eofResult(th, s, optArg(args, 1), optArg(args, 2));
    var eof = false;
    const recursive = if (optArg(args, 3)) |x| x != Value.nil else false;
    const v = readOp(th, s, s, st, preserve, recursive, .read, &eof);
    if (v == Value.unwind) return v;
    if (eof) return eofResult(th, s, optArg(args, 1), optArg(args, 2));
    th.mv_count = 1;
    return v;
}

pub fn read(th: *Thread, args: []const Value) Value {
    return readImpl(th, args, false);
}

pub fn readPreservingWhitespace(th: *Thread, args: []const Value) Value {
    return readImpl(th, args, true);
}

/// (read-delimited-list char &optional stream recursive-p)（Phase 24）
pub fn readDelimitedList(th: *Thread, args: []const Value) Value {
    if (!args[0].isChar()) return th.typeError(args[0], cl(th, "CHARACTER"));
    const s = inputDesignator(th, optArg(args, 1)) orelse return Value.unwind;
    if (!checkCharStream(th, s)) return Value.unwind;
    const st = stateOf(s) orelse return th.signal(.end_of_file, "ストリームの終わりです", s, Value.unbound);
    var eof = false;
    const recursive = if (optArg(args, 2)) |x| x != Value.nil else false;
    return readOp(th, s, s, st, false, recursive, .{ .delimited = args[0].asChar() }, &eof);
}

/// 標準のマクロ文字の関数（zl-sys::%READ-LIST など）の本体：(関数 stream char [arg])（Phase 24）
pub fn readBuiltin(th: *Thread, args: []const Value, k: reader.Builtin) Value {
    const s = inputDesignator(th, args[0]) orelse return Value.unwind;
    if (!checkCharStream(th, s)) return Value.unwind;
    if (!args[1].isChar()) return th.typeError(args[1], cl(th, "CHARACTER"));
    const st = stateOf(s) orelse return th.signal(.end_of_file, "ストリームの終わりです", s, Value.unbound);
    const arg: ?usize = if (args.len > 2 and args[2].isFixnum() and args[2].asFixnum() >= 0) @intCast(args[2].asFixnum()) else null;
    var eof = false;
    // reader macro の中から呼ばれた標準の関数は、外側の read の #n= の表を使う
    return readOp(th, s, s, st, false, th.read_builder != null, .{ .builtin = .{ .k = k, .cp = args[1].asChar(), .arg = arg } }, &eof);
}

/// 入力のストリームの今の位置を pos にする（ValueBuilder が reader macro を呼ぶ前。Phase 24）
pub fn setReadPosition(s: Value, pos: usize) void {
    const st = stateOf(s) orelse return;
    st.pos = @min(pos, st.input().len);
    st.last_len = 0;
}

pub fn readPosition(s: Value) usize {
    const st = stateOf(s) orelse return 0;
    return st.pos;
}

/// 入力のストリームのバッファ（UTF-8 か Latin-1 のバイト列）
pub fn readBuffer(s: Value) ?[]const u8 {
    const st = stateOf(s) orelse return null;
    return st.input();
}

/// バイト列（UTF-8）を写した文字列の入力ストリーム（ValueBuilder が、テキストを読んでいるときの reader macro に渡す）
pub fn makeStringInputBytes(th: *Thread, bytes: []const u8) ?Value {
    const text = th.rt.gpa.dupe(u8, bytes) catch {
        _ = th.outOfMemory();
        return null;
    };
    const s = makeStream(th, .string_input, SF.input | SF.open, Value.nil, true) orelse {
        th.rt.gpa.free(text);
        return null;
    };
    stateOf(s).?.in_buf = text;
    return s;
}

/// 文字列の [start, end) の UTF-8
fn substringUtf8(th: *Thread, str: Value, start: usize, end: usize) ?[]u8 {
    var buf: std.ArrayList(u8) = .empty;
    const view = arrays.vectorView(str).?;
    const s = Runtime.stringPtr(view.data);
    for (start..end) |i| {
        var b: [4]u8 = undefined;
        const n = std.unicode.utf8Encode(s.charAt(i), &b) catch unreachable;
        buf.appendSlice(th.rt.gpa, b[0..n]) catch {
            buf.deinit(th.rt.gpa);
            _ = th.outOfMemory();
            return null;
        };
    }
    return buf.toOwnedSlice(th.rt.gpa) catch {
        _ = th.outOfMemory();
        return null;
    };
}

fn charCount(bytes: []const u8) usize {
    var n: usize = 0;
    for (bytes) |b| if (b & 0xC0 != 0x80) {
        n += 1;
    };
    return n;
}

/// (read-from-string 文字列 &optional eof-error-p eof-value &key start end preserve-whitespace)：オブジェクトと次の位置
pub fn readFromString(th: *Thread, args: []const Value) Value {
    const str = args[0];
    if (!arrays.isStringLike(str)) return th.typeError(str, cl(th, "STRING"));
    const eof_error = optArg(args, 1);
    const eof_value = optArg(args, 2);
    var kv: [3]?Value = .{ null, null, null };
    if (args.len > 3 and !keyargs.parse(th, args[3..], &.{ "START", "END", "PRESERVE-WHITESPACE" }, &kv)) return Value.unwind;
    const b = @import("strings.zig").bounds(th, kv[0], kv[1], arrays.vectorView(str).?.len) orelse return Value.unwind;
    const preserve = if (kv[2]) |p| p != Value.nil else false;
    const text = substringUtf8(th, str, b[0], b[1]) orelse return Value.unwind;
    var st: StreamState = .{ .owner = 0, .kind = .string_input, .in_buf = text };
    defer th.rt.gpa.free(text);
    var eof = false;
    const v = readFromState(th, str, &st, preserve, &eof);
    if (v == Value.unwind) return v;
    const index = Value.fromFixnum(@intCast(b[0] + charCount(text[0..st.pos])));
    if (eof) {
        const signals = eof_error == null or eof_error.? != Value.nil;
        const r = eofResult(th, if (signals) errorStream(th, str, &st) else str, eof_error, eof_value);
        if (r == Value.unwind) return r;
        th.mv[1] = index;
        th.mv_count = 2;
        return r;
    }
    th.mv[1] = index;
    th.mv_count = 2;
    return v;
}

// ---------------------------------------------------------------------------
// 文字列のストリーム・合成のストリーム

/// (make-string-input-stream 文字列 &optional start end)
pub fn makeStringInputStream(th: *Thread, args: []const Value) Value {
    const str = args[0];
    if (!arrays.isStringLike(str)) return th.typeError(str, cl(th, "STRING"));
    const b = @import("strings.zig").bounds(th, optArg(args, 1), optArg(args, 2), arrays.vectorView(str).?.len) orelse return Value.unwind;
    const text = substringUtf8(th, str, b[0], b[1]) orelse return Value.unwind;
    const s = makeStream(th, .string_input, SF.input | SF.open, Value.nil, true) orelse {
        th.rt.gpa.free(text);
        return Value.unwind;
    };
    stateOf(s).?.in_buf = text;
    stateOf(s).?.char_base = b[0];
    return s;
}

/// (make-string-output-stream &key element-type)
pub fn makeStringOutputStream(th: *Thread, args: []const Value) Value {
    var kv: [1]?Value = .{null};
    if (!keyargs.parse(th, args, &.{"ELEMENT-TYPE"}, &kv)) return Value.unwind;
    return makeStream(th, .string_output, SF.output | SF.open, Value.nil, true) orelse Value.unwind;
}

/// (get-output-stream-string stream)：溜まった文字列を返して、空にする
pub fn getOutputStreamString(th: *Thread, args: []const Value) Value {
    const s = args[0];
    if (!isStream(s) or kindOf(s) != .string_output) return th.typeError(s, cl(th, "STRING-STREAM"));
    const st = stateOf(s) orelse return th.rt.makeString("") catch oom(th);
    const v = th.rt.makeString(st.out.items) catch return oom(th);
    st.out.clearRetainingCapacity();
    st.at_line_start = true;
    st.column = 0;
    return v;
}

/// (make-broadcast-stream &rest streams)
pub fn makeBroadcastStream(th: *Thread, args: []const Value) Value {
    var list = Value.nil;
    var i = args.len;
    while (i > 0) {
        i -= 1;
        // 出力のストリームでなければ type-error（CLHS make-broadcast-stream。agy のレビュー 0.3 #8）
        if (!isStream(args[i])) return th.typeError(args[i], cl(th, "STREAM"));
        if (outputStreamP(th, args[i .. i + 1]) != th.rt.t) return th.typeError(args[i], cl(th, "STREAM"));
        list = th.rt.cons(args[i], list) catch return oom(th);
    }
    return makeStream(th, .broadcast, SF.output | SF.open, list, false) orelse Value.unwind;
}

/// (make-two-way-stream 入力 出力)
pub fn makeTwoWayStream(th: *Thread, args: []const Value) Value {
    for (args) |a| if (!isStream(a)) return th.typeError(a, cl(th, "STREAM"));
    // 1つ目は入力、2つ目は出力のストリーム（CLHS make-two-way-stream）
    if (inputStreamP(th, args[0..1]) != th.rt.t) return th.typeError(args[0], cl(th, "STREAM"));
    if (outputStreamP(th, args[1..2]) != th.rt.t) return th.typeError(args[1], cl(th, "STREAM"));
    const pair = th.rt.cons(args[0], args[1]) catch return oom(th);
    return makeStream(th, .two_way, SF.input | SF.output | SF.open, pair, false) orelse Value.unwind;
}

/// (make-synonym-stream シンボル)
pub fn makeSynonymStream(th: *Thread, args: []const Value) Value {
    const sym = args[0];
    // NIL もシンボル（agy のレビュー 0.3 #7）
    if (!(sym == Value.nil or (sym.isOther() and Runtime.kindOf(sym) == .symbol))) return th.typeError(sym, th.rt.syms.symbol);
    return makeStream(th, .synonym, SF.input | SF.output | SF.open, sym, false) orelse Value.unwind;
}

fn checkKind(th: *Thread, v: Value, kind: StreamKind, type_name: []const u8) bool {
    if (isStream(v) and kindOf(v) == kind) return true;
    _ = th.typeError(v, cl(th, type_name));
    return false;
}

pub fn twoWayStreamInputStream(th: *Thread, args: []const Value) Value {
    if (!checkKind(th, args[0], .two_way, "TWO-WAY-STREAM")) return Value.unwind;
    return Runtime.consPtr(ptr(args[0]).ref).car;
}

pub fn twoWayStreamOutputStream(th: *Thread, args: []const Value) Value {
    if (!checkKind(th, args[0], .two_way, "TWO-WAY-STREAM")) return Value.unwind;
    return Runtime.consPtr(ptr(args[0]).ref).cdr;
}

pub fn synonymStreamSymbol(th: *Thread, args: []const Value) Value {
    if (!checkKind(th, args[0], .synonym, "SYNONYM-STREAM")) return Value.unwind;
    return ptr(args[0]).ref;
}

pub fn broadcastStreamStreams(th: *Thread, args: []const Value) Value {
    if (!checkKind(th, args[0], .broadcast, "BROADCAST-STREAM")) return Value.unwind;
    var items: std.ArrayList(Value) = .empty;
    defer items.deinit(th.rt.gpa);
    var x = ptr(args[0]).ref;
    while (x.isCons()) : (x = Runtime.consPtr(x).cdr) items.append(th.rt.gpa, Runtime.consPtr(x).car) catch return oom(th);
    var list = Value.nil;
    var i = items.items.len;
    while (i > 0) {
        i -= 1;
        list = th.rt.cons(items.items[i], list) catch return oom(th);
    }
    return list;
}

// ---------------------------------------------------------------------------
// ストリームの問い合わせ

fn streamArg(th: *Thread, v: Value) ?Value {
    if (isStream(v)) return v;
    _ = th.typeError(v, cl(th, "STREAM"));
    return null;
}

pub fn streamp(th: *Thread, args: []const Value) Value {
    return th.rt.boolean(isStream(args[0]));
}

/// synonym を、指している先のストリームまでたどる（問い合わせが使う。Codex のレビュー P23 #15）
fn followSynonym(th: *Thread, v0: Value) ?Value {
    var v = streamArg(th, v0) orelse return null;
    var depth: usize = 0;
    while (kindOf(v) == .synonym and depth < 64) : (depth += 1) {
        v = streamArg(th, th.rt.symbolPtr(ptr(v).ref).value) orelse return null;
    }
    return v;
}

pub fn inputStreamP(th: *Thread, args: []const Value) Value {
    const s = followSynonym(th, args[0]) orelse return Value.unwind;
    return th.rt.boolean(flags(s) & SF.input != 0);
}

pub fn outputStreamP(th: *Thread, args: []const Value) Value {
    const s = followSynonym(th, args[0]) orelse return Value.unwind;
    return th.rt.boolean(flags(s) & SF.output != 0);
}

pub fn openStreamP(th: *Thread, args: []const Value) Value {
    const s = streamArg(th, args[0]) orelse return Value.unwind;
    return th.rt.boolean(flags(s) & SF.open != 0);
}

pub fn interactiveStreamP(th: *Thread, args: []const Value) Value {
    _ = streamArg(th, args[0]) orelse return Value.unwind;
    return Value.nil;
}

pub fn streamElementType(th: *Thread, args: []const Value) Value {
    const s = followSynonym(th, args[0]) orelse return Value.unwind;
    const rt = th.rt;
    // broadcast の要素の型は、最後のストリームの要素の型（空なら T。SBCL 2.6.7 と同じ）
    if (kindOf(s) == .broadcast) {
        var x = ptr(s).ref;
        if (!x.isCons()) return rt.t;
        while (Runtime.consPtr(x).cdr.isCons()) x = Runtime.consPtr(x).cdr;
        return streamElementType(th, &.{Runtime.consPtr(x).car});
    }
    if (flags(s) & SF.binary == 0) return cl(th, "CHARACTER");
    const tail = rt.cons(Value.fromFixnum(8), Value.nil) catch return oom(th);
    return rt.cons(cl(th, "UNSIGNED-BYTE"), tail) catch oom(th);
}

/// (close stream &key abort)：閉じて T（SBCL 2.6.7 は、閉じたストリームを閉じても T）
pub fn close(th: *Thread, args: []const Value) Value {
    const s = streamArg(th, args[0]) orelse return Value.unwind;
    var kv: [1]?Value = .{null};
    if (!keyargs.parse(th, args[1..], &.{"ABORT"}, &kv)) return Value.unwind;
    if (flags(s) & SF.open == 0) return th.rt.t;
    switch (kindOf(s)) {
        // 標準のストリームは閉じない（SBCL も *standard-output* などを閉じると後が使えなくなる）
        .stdout, .stderr, .stdin => return th.rt.t,
        else => {},
    }
    const abort = if (kv[0]) |a| a != Value.nil else false;
    if (stateOf(s)) |st| {
        if (st.kind == .file) {
            const ok = flushFile(th, st);
            if (st.file) |f| if (th.rt.io) |io| f.close(io);
            st.file = null;
            th.rt.gpa.free(st.in_buf);
            st.in_buf = &.{};
            // :rename・:rename-and-delete で退避したファイル：abort なら元に戻し、:rename-and-delete なら消す
            finishBackup(th.rt, st, abort);
            if (!ok) return Value.unwind;
        }
    }
    ptr(s).header.flags &= ~SF.open;
    return th.rt.t;
}

/// (file-length stream)：ファイルの大きさ（バイト）
pub fn fileLength(th: *Thread, args: []const Value) Value {
    const s = followSynonym(th, args[0]) orelse return Value.unwind;
    // 閉じたストリームはエラー（SBCL と同じ。agy のレビュー 0.3 #10）
    if (flags(s) & SF.open == 0) return closedError(th, s) orelse Value.unwind;
    // broadcast は 0（SBCL 2.6.7 と同じ）
    if (kindOf(s) == .broadcast) return Value.fromFixnum(0);
    if (kindOf(s) != .file) return th.typeError(s, cl(th, "FILE-STREAM"));
    const st = stateOf(s) orelse return Value.nil;
    if (flags(s) & SF.output != 0) return Value.fromFixnum(@intCast(@max(st.file_len, st.file_offset + st.out.items.len)));
    return Value.fromFixnum(@intCast(st.in_buf.len));
}

/// (file-position stream &optional 位置)：今の位置（ファイルはバイト、文字列は文字）。位置を指定すれば移して T
pub fn filePosition(th: *Thread, args: []const Value) Value {
    const s = followSynonym(th, args[0]) orelse return Value.unwind;
    if (flags(s) & SF.open == 0) return closedError(th, s) orelse Value.unwind;
    if (kindOf(s) == .broadcast) return Value.fromFixnum(0);
    const st = stateOf(s) orelse return Value.nil;
    if (args.len < 2) {
        return switch (st.kind) {
            .file => Value.fromFixnum(@intCast(if (flags(s) & SF.output != 0) st.file_offset + st.out.items.len else st.pos)),
            .string_input => Value.fromFixnum(@intCast(st.char_base + charCount(st.in_buf[0..st.pos]))),
            .string_output => Value.fromFixnum(@intCast(charCount(st.out.items))),
            else => Value.nil,
        };
    }
    const p = args[1];
    const start = kw(th, "START") orelse return Value.unwind;
    const end_kw = kw(th, "END") orelse return Value.unwind;
    if (st.kind == .file and flags(s) & SF.input != 0) {
        const n: usize = if (p == start) 0 else if (p == end_kw) st.in_buf.len else if (p.isFixnum() and p.asFixnum() >= 0) @intCast(p.asFixnum()) else return th.typeError(p, th.rt.syms.integer);
        if (n > st.in_buf.len) return Value.nil;
        st.pos = n;
        st.last_len = 0;
        return th.rt.t;
    }
    if (st.kind == .file) {
        if (!flushFile(th, st)) return Value.unwind;
        const len = if (th.rt.io) |io| (if (st.file) |f| f.length(io) catch st.file_offset else st.file_offset) else st.file_offset;
        const n: u64 = if (p == start) 0 else if (p == end_kw) len else if (p.isFixnum() and p.asFixnum() >= 0) @intCast(p.asFixnum()) else return th.typeError(p, th.rt.syms.integer);
        st.file_offset = n;
        return th.rt.t;
    }
    return th.signal(.unimplemented, "このストリームの位置を変えるのは未実装です", s, Value.unbound);
}

// ---------------------------------------------------------------------------
// open

const Direction = enum { input, output, probe };

/// (open ファイル &key direction element-type if-exists if-does-not-exist external-format)
pub fn open(th: *Thread, args: []const Value) Value {
    const rt = th.rt;
    var kv: [5]?Value = .{ null, null, null, null, null };
    if (!keyargs.parse(th, args[1..], &.{ "DIRECTION", "ELEMENT-TYPE", "IF-EXISTS", "IF-DOES-NOT-EXIST", "EXTERNAL-FORMAT" }, &kv)) return Value.unwind;
    const p = pathnames.designator(th, args[0]) orelse return Value.unwind;
    const name = pathnames.osName(th, p) orelse return Value.unwind;
    defer rt.gpa.free(name);
    const io = rt.io orelse return th.signal(.unimplemented, "この環境ではファイルを開けません", args[0], Value.unbound);

    const dir: Direction = if (kv[0]) |d| blk: {
        if (d == (kw(th, "INPUT") orelse return Value.unwind)) break :blk .input;
        if (d == (kw(th, "OUTPUT") orelse return Value.unwind)) break :blk .output;
        if (d == (kw(th, "PROBE") orelse return Value.unwind)) break :blk .probe;
        if (d == (kw(th, "IO") orelse return Value.unwind)) return th.signal(.unimplemented, "OPEN の :direction :io は未実装です", d, Value.unbound);
        return th.typeError(d, cl(th, "KEYWORD"));
    } else .input;
    // 要素の型：文字か (unsigned-byte 8)
    var binary = false;
    if (kv[1]) |et| {
        const is_char = et == cl(th, "CHARACTER") or et == cl(th, "BASE-CHAR") or et == (kw(th, "DEFAULT") orelse return Value.unwind);
        const is_ub8 = et == cl(th, "UNSIGNED-BYTE") or (et.isCons() and Runtime.consPtr(et).car == cl(th, "UNSIGNED-BYTE") and
            Runtime.consPtr(et).cdr.isCons() and Runtime.consPtr(Runtime.consPtr(et).cdr).car == Value.fromFixnum(8) and Runtime.consPtr(Runtime.consPtr(et).cdr).cdr == Value.nil);
        if (is_ub8) binary = true else if (!is_char) return th.signal(.unimplemented, "OPEN の :element-type は character か (unsigned-byte 8) だけです", et, Value.unbound);
    }
    var latin1 = false;
    if (kv[4]) |ef| {
        const names_utf8 = [_][]const u8{ "DEFAULT", "UTF-8", "UTF8" };
        const names_latin1 = [_][]const u8{ "LATIN-1", "LATIN1", "ISO-8859-1" };
        var ok = false;
        for (names_utf8) |n| if (ef == (kw(th, n) orelse return Value.unwind)) {
            ok = true;
        };
        for (names_latin1) |n| if (ef == (kw(th, n) orelse return Value.unwind)) {
            ok = true;
            latin1 = true;
        };
        if (!ok) return th.signal(.unimplemented, "OPEN の :external-format は :utf-8 か :latin-1 だけです", ef, Value.unbound);
    }
    const exists = if (Io.Dir.cwd().statFile(io, name, .{})) |st| st.kind != .directory else |_| false;

    switch (dir) {
        .probe, .input => {
            if (!exists) {
                const ide = kv[3] orelse (if (dir == .probe) Value.nil else (kw(th, "ERROR") orelse return Value.unwind));
                if (ide == Value.nil) return Value.nil;
                if (ide == (kw(th, "CREATE") orelse return Value.unwind)) {
                    const f = Io.Dir.cwd().createFile(io, name, .{}) catch return th.signal(.file_error, "ファイルを作れません", args[0], Value.unbound);
                    f.close(io);
                } else return th.signal(.file_error, "ファイルがありません", args[0], Value.unbound);
            }
            if (dir == .probe) {
                // :probe のストリームは向きを持たない（input-stream-p も output-stream-p も NIL。SBCL と同じ。agy のレビュー 0.3 #11）
                const s = makeStream(th, .file, if (binary) SF.binary else 0, p, false) orelse return Value.unwind;
                return s;
            }
            const text = Io.Dir.cwd().readFileAlloc(io, name, rt.gpa, .limited(1 << 31)) catch |err| switch (err) {
                error.OutOfMemory => return oom(th),
                else => return th.signal(.file_error, "ファイルを読めません", args[0], Value.unbound),
            };
            const s = makeStream(th, .file, SF.input | SF.open | (if (binary) SF.binary else 0), p, true) orelse {
                rt.gpa.free(text);
                return Value.unwind;
            };
            const st = stateOf(s).?;
            st.in_buf = text;
            st.latin1 = latin1;
            return s;
        },
        .output => {
            const supersede = kw(th, "SUPERSEDE") orelse return Value.unwind;
            const append = kw(th, "APPEND") orelse return Value.unwind;
            const overwrite = kw(th, "OVERWRITE") orelse return Value.unwind;
            const err_kw = kw(th, "ERROR") orelse return Value.unwind;
            const if_exists = kv[2] orelse err_kw;
            var offset: u64 = 0;
            var truncate = true;
            var rename_mode: u2 = 0; // 1 = :rename, 2 = :rename-and-delete
            if (exists) {
                if (if_exists == Value.nil) return Value.nil;
                if (if_exists == err_kw or if_exists == (kw(th, "NEW-VERSION") orelse return Value.unwind))
                    return th.signal(.file_error, "ファイルが既にあります", args[0], Value.unbound);
                if (if_exists == append or if_exists == overwrite) {
                    truncate = false;
                } else if (if_exists == (kw(th, "RENAME") orelse return Value.unwind)) {
                    rename_mode = 1;
                } else if (if_exists == (kw(th, "RENAME-AND-DELETE") orelse return Value.unwind)) {
                    rename_mode = 2;
                } else if (if_exists != supersede) {
                    return th.typeError(if_exists, cl(th, "KEYWORD"));
                }
            } else {
                const default_ide = if (if_exists == append or if_exists == overwrite) err_kw else (kw(th, "CREATE") orelse return Value.unwind);
                const ide = kv[3] orelse default_ide;
                if (ide == Value.nil) return Value.nil;
                if (ide != (kw(th, "CREATE") orelse return Value.unwind)) return th.signal(.file_error, "ファイルがありません", args[0], Value.unbound);
            }
            // :rename・:rename-and-delete：元のファイルを「名前.bak」に移してから作る（SBCL 2.6.7 と同じ。既にある .bak は上書き）
            var backup: ?[]u8 = null;
            if (rename_mode != 0) {
                const b = std.mem.concat(rt.gpa, u8, &.{ name, ".bak" }) catch return oom(th);
                Io.Dir.cwd().rename(name, Io.Dir.cwd(), b, io) catch {
                    rt.gpa.free(b);
                    return th.signal(.file_error, "ファイルを退避できません", args[0], Value.unbound);
                };
                backup = b;
            }
            const f = Io.Dir.cwd().createFile(io, name, .{ .truncate = truncate }) catch {
                if (backup) |b| {
                    Io.Dir.cwd().rename(b, Io.Dir.cwd(), name, io) catch {};
                    rt.gpa.free(b);
                }
                return th.signal(.file_error, "ファイルを開けません", args[0], Value.unbound);
            };
            const len0: u64 = if (exists and !truncate) f.length(io) catch 0 else 0;
            if (exists and if_exists == append) offset = len0;
            const path_copy: ?[]u8 = if (backup != null) (rt.gpa.dupe(u8, name) catch null) else null;
            const s = makeStream(th, .file, SF.output | SF.open | (if (binary) SF.binary else 0), p, true) orelse {
                f.close(io);
                if (path_copy) |n| rt.gpa.free(n);
                if (backup) |b| {
                    Io.Dir.cwd().deleteFile(io, name) catch {};
                    Io.Dir.cwd().rename(b, Io.Dir.cwd(), name, io) catch {};
                    rt.gpa.free(b);
                }
                return Value.unwind;
            };
            const st = stateOf(s).?;
            st.file = f;
            st.file_offset = offset;
            st.file_len = len0;
            st.latin1 = latin1;
            st.backup = backup;
            st.delete_backup = rename_mode == 2;
            st.path = path_copy;
            return s;
        },
    }
}

/// ストリームの印字（#<...>。SBCL 2.6.7 に近い形）
pub fn printStream(rt: *Runtime, w: *Io.Writer, v: Value) Io.Writer.Error!void {
    const addr = v.raw() & ~@as(u64, 7);
    switch (kindOf(v)) {
        .file => {
            try w.writeAll("#<FILE-STREAM for \"");
            if (pathnames.isPathname(ptr(v).ref)) try pathnames.writeNamestring(rt, w, ptr(v).ref);
            try w.print("\" {{{X}}}>", .{addr});
        },
        .string_input => try w.print("#<STRING-INPUT-STREAM {{{X}}}>", .{addr}),
        .string_output => try w.print("#<STRING-OUTPUT-STREAM {{{X}}}>", .{addr}),
        .stdin => try w.print("#<FD-STREAM for \"standard input\" {{{X}}}>", .{addr}),
        .stdout => try w.print("#<FD-STREAM for \"standard output\" {{{X}}}>", .{addr}),
        .stderr => try w.print("#<FD-STREAM for \"standard error\" {{{X}}}>", .{addr}),
        .synonym => {
            try w.writeAll("#<SYNONYM-STREAM :SYMBOL ");
            try printer.prin1(rt, w, ptr(v).ref);
            try w.print(" {{{X}}}>", .{addr});
        },
        .two_way => try w.print("#<TWO-WAY-STREAM {{{X}}}>", .{addr}),
        .broadcast => try w.print("#<BROADCAST-STREAM {{{X}}}>", .{addr}),
        .pretty => try w.print("#<PRETTY-STREAM {{{X}}}>", .{addr}),
    }
}
