//! pretty printer（Phase 24 の P24d。CLHS 22.2「The Lisp Pretty Printer」）。
//! SBCL 2.6.7 の src/code/pprint.lisp（public domain）の pretty stream を Zig に移植した：
//!   - 出力はバッファに溜め、条件付きの改行・字下げ・論理ブロックの始まりと終わり・タブを、位置（posn）付きの
//!     キューに積む。改行を決められるようになったら（maybe-output）、行を書き出す。
//!   - 論理ブロックは、始まりの桁・節の桁・行ごとの接頭辞の長さ・接頭辞の長さ（字下げ）・接尾辞の長さを持つ。
//! pretty stream は、ストリームの種類 .pretty（state.pretty がこの State を指す。ref が書き出し先のストリーム）。

const std = @import("std");
const Value = @import("../values/value.zig").Value;
const Thread = @import("../runtime/thread.zig").Thread;
const Runtime = @import("../runtime/runtime.zig").Runtime;
const streams_mod = @import("../primitives/streams.zig");

pub const Fail = error{Lisp};

pub const NewlineKind = enum { linear, fill, miser, literal, mandatory };
pub const IndentKind = enum { block, current };
pub const TabKind = enum { line, line_relative, section, section_relative };

const OpKind = enum { newline, block_start, block_end, indentation, tab };

const Op = struct {
    kind: OpKind,
    posn: i64,
    // 節の始まり（newline・block_start）
    depth: usize = 0,
    section_end: ?u64 = null,
    // newline
    nl: NewlineKind = .linear,
    // block_start
    block_end: ?u64 = null,
    per_line_prefix: ?[]const u21 = null,
    suffix: ?[]const u21 = null,
    // indentation
    ind: IndentKind = .block,
    amount: i64 = 0,
    // tab
    sectionp: bool = false,
    relativep: bool = false,
    colnum: i64 = 0,
    colinc: i64 = 0,
};

const Block = struct {
    start_column: i64 = 0,
    section_column: i64 = 0,
    per_line_prefix_end: usize = 0,
    prefix_length: usize = 0,
    suffix_length: usize = 0,
    section_start_line: usize = 0,
};

const Pending = struct { seq: u64, suffix: []const u21 };

pub const State = struct {
    th: *Thread,
    gpa: std.mem.Allocator,
    /// 接頭辞・接尾辞の文字列（このストリームの間だけ）
    arena: std.heap.ArenaAllocator,
    target: Value,
    line_length: i64,
    buffer: std.ArrayList(u21) = .empty,
    buffer_offset: i64 = 0,
    buffer_start_column: i64 = 0,
    line_number: usize = 0,
    print_lines: ?usize = null,
    blocks: std.ArrayList(Block) = .empty,
    prefix: std.ArrayList(u21) = .empty,
    /// 接尾辞（有効な部分は末尾の suffix_length 文字。SBCL と同じく右に詰める）
    suffix: std.ArrayList(u21) = .empty,
    ops: std.ArrayList(Op) = .empty,
    /// ops.items[0] の通し番号と、まだ処理していない最初の要素の位置（SBCL の queue-tail）
    ops_base: u64 = 0,
    ops_start: usize = 0,
    pending: std.ArrayList(Pending) = .empty,
    significant_spaces: std.ArrayList(i64) = .empty,
    /// 次の文字が . か @ なら空白を入れる（, の後。SBCL の char-out-oneshot-hook）
    comma_hook: bool = false,
    /// *print-lines* で打ち切った（以後の出力は捨てる。SBCL は throw で印字を抜ける）
    abbreviated: bool = false,

    pub fn create(th: *Thread, target: Value, column: usize) error{OutOfMemory}!*State {
        const gpa = th.rt.gpa;
        const s = try gpa.create(State);
        const rt = th.rt;
        const margin = rt.symbolPtr(rt.syms.@"*print-right-margin*").value;
        const lines = rt.symbolPtr(rt.syms.@"*print-lines*").value;
        s.* = .{
            .th = th,
            .gpa = gpa,
            .arena = .init(gpa),
            .target = target,
            .line_length = if (margin.isFixnum() and margin.asFixnum() > 0) margin.asFixnum() else 80,
            .buffer_start_column = @intCast(column),
            .print_lines = if (lines.isFixnum() and lines.asFixnum() >= 0) @intCast(lines.asFixnum()) else null,
        };
        try s.blocks.append(gpa, .{});
        return s;
    }

    pub fn destroy(s: *State) void {
        const gpa = s.gpa;
        s.buffer.deinit(gpa);
        s.blocks.deinit(gpa);
        s.prefix.deinit(gpa);
        s.suffix.deinit(gpa);
        s.ops.deinit(gpa);
        s.pending.deinit(gpa);
        s.significant_spaces.deinit(gpa);
        s.arena.deinit();
        gpa.destroy(s);
    }

    fn oom(s: *State) Fail {
        _ = s.th.outOfMemory();
        return error.Lisp;
    }

    fn top(s: *State) *Block {
        return &s.blocks.items[s.blocks.items.len - 1];
    }

    fn fill(s: *State) usize {
        return s.buffer.items.len;
    }

    fn indexPosn(s: *State, index: usize) i64 {
        return @as(i64, @intCast(index)) + s.buffer_offset;
    }

    fn posnIndex(s: *State, posn: i64) i64 {
        return posn - s.buffer_offset;
    }

    fn posnColumn(s: *State, posn: i64) i64 {
        return s.indexColumn(s.posnIndex(posn));
    }

    fn live(s: *State) []Op {
        return s.ops.items[s.ops_start..];
    }

    fn seqOf(s: *State, i: usize) u64 {
        return s.ops_base + i;
    }

    fn op(s: *State, seq: u64) ?*Op {
        if (seq < s.ops_base + s.ops_start) return null;
        const i: usize = @intCast(seq - s.ops_base);
        if (i >= s.ops.items.len) return null;
        return &s.ops.items[i];
    }

    fn enqueue(s: *State, o: Op) Fail!u64 {
        var x = o;
        x.posn = s.indexPosn(s.fill());
        s.ops.append(s.gpa, x) catch return s.oom();
        return s.seqOf(s.ops.items.len - 1);
    }

    fn dupe(s: *State, chars: []const u21) Fail![]const u21 {
        return s.arena.allocator().dupe(u21, chars) catch s.oom();
    }

    /// 書き出し先に文字を書く
    fn writeTarget(s: *State, chars: []const u21) Fail!void {
        if (chars.len == 0) return;
        var buf: std.ArrayList(u8) = .empty;
        defer buf.deinit(s.gpa);
        for (chars) |cp| {
            var b: [4]u8 = undefined;
            const n = std.unicode.utf8Encode(cp, &b) catch 1;
            buf.appendSlice(s.gpa, b[0..n]) catch return s.oom();
        }
        if (!streams_mod.emit(s.th, s.target, buf.items)) return error.Lisp;
    }

    // ------------------------------------------------------------------
    // 出力（SBCL の pretty-out・pretty-sout）

    pub fn writeChar(s: *State, cp: u21) Fail!void {
        if (s.abbreviated) return;
        if (s.comma_hook) {
            s.comma_hook = false;
            if (cp == '.' or cp == '@') try s.writeChar(' ');
        }
        if (cp == '\n') return s.enqueueNewline(.literal);
        s.buffer.append(s.gpa, cp) catch return s.oom();
    }

    pub fn writeChars(s: *State, chars: []const u21) Fail!void {
        for (chars) |cp| try s.writeChar(cp);
    }

    pub fn writeUtf8(s: *State, bytes: []const u8) Fail!void {
        var it = std.unicode.Utf8View.initUnchecked(bytes).iterator();
        while (it.nextCodepoint()) |cp| try s.writeChar(cp);
    }

    // ------------------------------------------------------------------
    // 論理ブロック

    fn reallyStartLogicalBlock(s: *State, column: i64, prefix: ?[]const u21, suffix: ?[]const u21) Fail!void {
        const prev = s.top().*;
        s.blocks.append(s.gpa, .{
            .start_column = column,
            .section_column = column,
            .per_line_prefix_end = prev.per_line_prefix_end,
            .prefix_length = prev.prefix_length,
            .suffix_length = prev.suffix_length,
            .section_start_line = s.line_number,
        }) catch return s.oom();
        try s.setIndentation(column);
        const col: usize = @intCast(@max(column, 0));
        if (prefix) |p| {
            s.top().per_line_prefix_end = col;
            try s.ensurePrefix(col);
            if (col >= p.len) @memcpy(s.prefix.items[col - p.len .. col], p);
        }
        if (suffix) |sfx| {
            const old_len = prev.suffix_length;
            const new_len = old_len + sfx.len;
            // 有効な接尾辞は末尾に詰める：全体を伸ばして、新しい接尾辞を既存の部分の前に置く
            if (new_len > s.suffix.items.len) {
                const grow = new_len - s.suffix.items.len;
                s.suffix.insertSlice(s.gpa, 0, s.arena.allocator().alloc(u21, grow) catch return s.oom()) catch return s.oom();
            }
            const total = s.suffix.items.len;
            @memcpy(s.suffix.items[total - new_len .. total - old_len], sfx);
            s.top().suffix_length = new_len;
        }
    }

    fn ensurePrefix(s: *State, n: usize) Fail!void {
        while (s.prefix.items.len < n) s.prefix.append(s.gpa, ' ') catch return s.oom();
    }

    fn setIndentation(s: *State, column0: i64) Fail!void {
        const b = s.top();
        const current = b.prefix_length;
        const minimum = b.per_line_prefix_end;
        const column: usize = @max(minimum, @as(usize, @intCast(@max(column0, 0))));
        try s.ensurePrefix(column);
        if (column > current) @memset(s.prefix.items[current..column], ' ');
        s.top().prefix_length = column;
    }

    fn reallyEndLogicalBlock(s: *State) Fail!void {
        const old = s.blocks.pop().?;
        const new = s.top();
        if (new.prefix_length > old.prefix_length) {
            try s.ensurePrefix(new.prefix_length);
            @memset(s.prefix.items[old.prefix_length..new.prefix_length], ' ');
        }
    }

    pub fn startLogicalBlock(s: *State, prefix: ?[]const u21, per_line: bool, suffix: []const u21) Fail!void {
        if (s.abbreviated) return;
        if (prefix) |p| try s.writeChars(p);
        const pfx = if (per_line and prefix != null) try s.dupe(prefix.?) else null;
        const sfx = try s.dupe(suffix);
        const seq = try s.enqueue(.{ .kind = .block_start, .posn = 0, .per_line_prefix = pfx, .suffix = sfx, .depth = s.pending.items.len });
        s.pending.append(s.gpa, .{ .seq = seq, .suffix = sfx }) catch return s.oom();
    }

    pub fn endLogicalBlock(s: *State) Fail!void {
        if (s.abbreviated) return;
        const p = s.pending.pop() orelse return;
        const end = try s.enqueue(.{ .kind = .block_end, .posn = 0 });
        if (p.suffix.len > 0) try s.writeChars(p.suffix);
        if (s.op(p.seq)) |o| o.block_end = end;
    }

    // ------------------------------------------------------------------
    // キュー

    pub fn enqueueNewline(s: *State, kind: NewlineKind) Fail!void {
        if (s.abbreviated) return;
        const depth = s.pending.items.len;
        const seq = try s.enqueue(.{ .kind = .newline, .posn = 0, .nl = kind, .depth = depth });
        for (s.live(), s.ops_start..) |*e, i| {
            if (s.seqOf(i) == seq) continue;
            if ((e.kind == .newline or e.kind == .block_start) and e.section_end == null and depth <= e.depth) e.section_end = seq;
        }
        _ = try s.maybeOutput(kind == .literal or kind == .mandatory);
    }

    pub fn enqueueIndent(s: *State, kind: IndentKind, amount: i64) Fail!void {
        if (s.abbreviated) return;
        _ = try s.enqueue(.{ .kind = .indentation, .posn = 0, .ind = kind, .amount = amount });
    }

    pub fn enqueueTab(s: *State, kind: TabKind, colnum: i64, colinc: i64) Fail!void {
        if (s.abbreviated) return;
        _ = try s.enqueue(.{
            .kind = .tab,
            .posn = 0,
            .sectionp = kind == .section or kind == .section_relative,
            .relativep = kind == .line_relative or kind == .section_relative,
            .colnum = colnum,
            .colinc = colinc,
        });
    }

    fn computeTabSize(tab: *const Op, section_start: i64, column: i64) i64 {
        const origin = if (tab.sectionp) section_start else 0;
        var colnum = tab.colnum;
        const colinc = tab.colinc;
        const position = column - origin;
        if (tab.relativep) {
            if (colinc > 1) {
                const newposn = position + colnum;
                const r = @rem(newposn, colinc);
                if (r != 0) colnum += colinc - r;
            }
            return colnum;
        }
        if (position < colnum) return colnum - position;
        if (colinc == 0) return 0;
        return colinc - @rem(position - colnum, colinc);
    }

    /// バッファの index の桁（SBCL の index-column）
    pub fn indexColumn(s: *State, index: i64) i64 {
        var column = s.buffer_start_column;
        var section_start = s.top().section_column;
        const end_posn = index + s.buffer_offset;
        for (s.live()) |*o| {
            if (o.posn >= end_posn) break;
            switch (o.kind) {
                .tab => column += computeTabSize(o, section_start, column + s.posnIndex(o.posn)),
                .newline, .block_start => section_start = column + s.posnIndex(o.posn),
                else => {},
            }
        }
        return column + index;
    }

    /// 今の桁（fresh-line・format の ~T）
    pub fn currentColumn(s: *State) i64 {
        return s.indexColumn(@intCast(s.fill()));
    }

    fn expandTabs(s: *State, through: ?u64) Fail!void {
        const Ins = struct { index: usize, size: usize };
        var insertions: std.ArrayList(Ins) = .empty;
        defer insertions.deinit(s.gpa);
        var additional: usize = 0;
        var column = s.buffer_start_column;
        var section_start = s.top().section_column;
        for (s.live(), s.ops_start..) |*o, i| {
            switch (o.kind) {
                .tab => {
                    const index = s.posnIndex(o.posn);
                    const size = computeTabSize(o, section_start, column + index);
                    if (size != 0) {
                        insertions.append(s.gpa, .{ .index = @intCast(index), .size = @intCast(size) }) catch return s.oom();
                        additional += @intCast(size);
                        column += size;
                    }
                },
                .newline, .block_start => section_start = column + s.posnIndex(o.posn),
                else => {},
            }
            if (through) |t| if (s.seqOf(i) == t) break;
        }
        if (insertions.items.len == 0) return;
        const fill_ptr = s.fill();
        s.buffer.appendNTimes(s.gpa, ' ', additional) catch return s.oom();
        s.buffer_offset -= @intCast(additional);
        const buf = s.buffer.items;
        var end = fill_ptr;
        var add = additional;
        var k = insertions.items.len;
        while (k > 0) {
            k -= 1;
            const ins = insertions.items[k];
            const dst = ins.index + add;
            std.mem.copyBackwards(u21, buf[dst .. dst + (end - ins.index)], buf[ins.index..end]);
            @memset(buf[dst - ins.size .. dst], ' ');
            add -= ins.size;
            end = ins.index;
        }
    }

    fn miseringP(s: *State) bool {
        const rt = s.th.rt;
        const w = rt.symbolPtr(rt.syms.@"*print-miser-width*").value;
        if (!w.isFixnum()) return false;
        return s.line_length - s.top().start_column <= w.asFixnum();
    }

    const Fit = enum { yes, no, dont_know };

    fn fitsOnLineP(s: *State, until: ?u64, force: bool) Fit {
        var available = s.line_length;
        const rt = s.th.rt;
        const readably = rt.symbolPtr(rt.syms.@"*print-readably*").value != Value.nil;
        if (!readably) if (s.print_lines) |pl| if (pl == s.line_number) {
            available -= 3;
            available -= @intCast(s.top().suffix_length);
        };
        if (until) |u| if (s.op(u)) |o| return if (s.posnColumn(o.posn) <= available) .yes else .no;
        if (force) return .no;
        if (s.indexColumn(@intCast(s.fill())) > available) return .no;
        return .dont_know;
    }

    fn popOp(s: *State) void {
        s.ops_start += 1;
        if (s.ops_start == s.ops.items.len) {
            s.ops_base += s.ops.items.len;
            s.ops.clearRetainingCapacity();
            s.ops_start = 0;
        }
    }

    fn maybeOutput(s: *State, force: bool) Fail!bool {
        var output_anything = false;
        while (s.ops_start < s.ops.items.len) {
            // *print-lines* で打ち切ったら、残りは書かない
            if (s.abbreviated) return output_anything;
            const seq = s.seqOf(s.ops_start);
            const next = s.ops.items[s.ops_start];
            switch (next.kind) {
                .newline => {
                    const go = switch (next.nl) {
                        .literal, .mandatory, .linear => true,
                        .miser => s.miseringP(),
                        .fill => blk: {
                            if (s.miseringP() or s.line_number > s.top().section_start_line) break :blk true;
                            break :blk switch (s.fitsOnLineP(next.section_end, force)) {
                                .yes => false,
                                .no => true,
                                .dont_know => return output_anything,
                            };
                        },
                    };
                    if (go) {
                        output_anything = true;
                        try s.outputLine(&next);
                    }
                },
                .indentation => {
                    if (!s.miseringP()) {
                        const base = switch (next.ind) {
                            .block => s.top().start_column,
                            .current => s.posnColumn(next.posn),
                        };
                        try s.setIndentation(base + next.amount);
                    }
                },
                .block_start => switch (s.fitsOnLineP(next.section_end, force)) {
                    .yes => {
                        // 論理ブロック全体を、ひと続きの文字として扱う
                        const end = next.block_end orelse return output_anything;
                        try s.expandTabs(end);
                        while (s.ops_start < s.ops.items.len and s.seqOf(s.ops_start) <= end) s.popOp();
                        continue;
                    },
                    .no => try s.reallyStartLogicalBlock(s.posnColumn(next.posn), next.per_line_prefix, next.suffix),
                    .dont_know => return output_anything,
                },
                .block_end => try s.reallyEndLogicalBlock(),
                .tab => try s.expandTabs(seq),
            }
            s.popOp();
        }
        return output_anything;
    }

    fn outputLine(s: *State, until: *const Op) Fail!void {
        const literal = until.nl == .literal;
        const consume: usize = @intCast(s.posnIndex(until.posn));
        const buf = s.buffer.items;
        const amount_to_print: usize = if (literal) consume else blk: {
            var pos = consume;
            while (pos > 0) {
                pos -= 1;
                const sig = for (s.significant_spaces.items) |x| {
                    if (x == pos) break true;
                } else false;
                if (buf[pos] != ' ' or sig) break :blk pos + 1;
            }
            break :blk 0;
        };
        try s.writeTarget(buf[0..amount_to_print]);
        const line_number = s.line_number + 1;
        const rt = s.th.rt;
        const readably = rt.symbolPtr(rt.syms.@"*print-readably*").value != Value.nil;
        if (!readably) if (s.print_lines) |pl| if (line_number >= pl) {
            // *print-lines* の行数に達した：「 ..」と接尾辞を書いて、印字を打ち切る（SBCL の line-limit-abbreviation-happened）
            try s.writeTarget(&.{ ' ', '.', '.' });
            const sl = s.top().suffix_length;
            if (sl != 0) try s.writeTarget(s.suffix.items[s.suffix.items.len - sl ..]);
            s.abbreviated = true;
            return;
        };
        s.line_number = line_number;
        try s.writeTarget(&.{'\n'});
        s.buffer_start_column = 0;
        const fill_ptr = s.fill();
        const block = s.top();
        const prefix_len = if (literal) block.per_line_prefix_end else block.prefix_length;
        const shift = @as(i64, @intCast(consume)) - @as(i64, @intCast(prefix_len));
        const rest = s.gpa.dupe(u21, s.buffer.items[consume..fill_ptr]) catch return s.oom();
        defer s.gpa.free(rest);
        try s.ensurePrefix(prefix_len);
        s.buffer.clearRetainingCapacity();
        s.buffer.appendSlice(s.gpa, s.prefix.items[0..prefix_len]) catch return s.oom();
        s.buffer.appendSlice(s.gpa, rest) catch return s.oom();
        s.buffer_offset += shift;
        if (s.significant_spaces.items.len > 0) {
            var j: usize = 0;
            for (s.significant_spaces.items) |x| {
                const nx = x - shift;
                if (nx >= 0) {
                    s.significant_spaces.items[j] = nx;
                    j += 1;
                }
            }
            s.significant_spaces.shrinkRetainingCapacity(j);
        }
        if (!literal) {
            block.section_column = @intCast(prefix_len);
            block.section_start_line = line_number;
        }
    }

    /// 残りをすべて書き出す（SBCL の force-pretty-output）
    pub fn forceOutput(s: *State) Fail!void {
        if (s.abbreviated) return;
        _ = try s.maybeOutput(false);
        try s.expandTabs(null);
        try s.writeTarget(s.buffer.items);
        s.buffer_offset += @intCast(s.buffer.items.len);
        s.buffer_start_column = s.indexColumn(0) + @as(i64, @intCast(s.buffer.items.len));
        s.buffer.clearRetainingCapacity();
    }

    /// 直前に書いた空白を、行末でも消さない（SBCL の note-significant-space）
    pub fn noteSignificantSpace(s: *State) Fail!void {
        s.significant_spaces.append(s.gpa, @as(i64, @intCast(s.fill())) - 1) catch return s.oom();
    }
};
