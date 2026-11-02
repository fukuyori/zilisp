//! equalp（Phase 21。CLHS equalp）：
//!   - 文字は char-equal（大文字・小文字を区別しない）、数は =（型を問わない）
//!   - cons は car と cdr が equalp
//!   - 配列は次元が同じで、要素がすべて equalp（ベクタは fill-pointer までの有効な部分を比べる。文字列も同じ規則）
//!   - ハッシュ表は、比較の種類と項目の数が同じで、一方の各キーがもう一方にあり、値が equalp
//!   - それ以外は eq
//! 大文字・小文字の区別をなくすのは ASCII の文字だけ（string-upcase などと同じ。SBCL 2.6.7 は Unicode の文字も対象にする）。

const std = @import("std");
const Value = @import("../values/value.zig").Value;
const Thread = @import("../runtime/thread.zig").Thread;
const Runtime = @import("../runtime/runtime.zig").Runtime;
const numbers = @import("numbers.zig");
const arrays = @import("arrays.zig");
const hashtables = @import("hashtables.zig");

/// 大文字・小文字を区別しないための文字（ASCII の大文字を小文字にする）
pub fn foldChar(c: u21) u21 {
    if (c >= 'A' and c <= 'Z') return c + ('a' - 'A');
    return c;
}

/// equalp。数の比較でメモリが足りなければ null（エラーを記録済み）
pub fn equalp2(th: *Thread, a: Value, b: Value) ?bool {
    var x = a;
    var y = b;
    while (true) {
        if (x == y) return true;
        if (x.isChar()) return y.isChar() and foldChar(x.asChar()) == foldChar(y.asChar());
        if (numbers.isNumber(x)) {
            if (!numbers.isNumber(y)) return false;
            return numbers.numEqual(th, x, y);
        }
        if (x.isCons()) {
            if (!y.isCons()) return false;
            if (!(equalp2(th, Runtime.consPtr(x).car, Runtime.consPtr(y).car) orelse return null)) return false;
            x = Runtime.consPtr(x).cdr;
            y = Runtime.consPtr(y).cdr;
            continue;
        }
        if (arrays.isArray(x)) {
            if (!arrays.isArray(y)) return false;
            return arraysEqualp(th, x, y);
        }
        if (hashtables.isHashTable(x)) {
            if (!hashtables.isHashTable(y)) return false;
            return hashtables.tablesEqualp(th, x, y);
        }
        return false;
    }
}

fn arraysEqualp(th: *Thread, x: Value, y: Value) ?bool {
    // 1次元どうしは、有効な長さ（fill-pointer）で比べる
    if (arrays.vectorView(x)) |vx| {
        const vy = arrays.vectorView(y) orelse return false;
        if (vx.len != vy.len) return false;
        for (0..vx.len) |i| {
            if (!(equalp2(th, arrays.storageGet(vx.data, i), arrays.storageGet(vy.data, i)) orelse return null)) return false;
        }
        return true;
    }
    if (arrays.vectorView(y) != null) return false;
    var bx: [1]usize = undefined;
    var by: [1]usize = undefined;
    const dx = arrays.dimsOf(x, &bx);
    const dy = arrays.dimsOf(y, &by);
    if (!std.mem.eql(usize, dx, dy)) return false;
    const ex = arrays.dataOf(x);
    const ey = arrays.dataOf(y);
    for (0..arrays.storageLen(ex)) |i| {
        if (!(equalp2(th, arrays.storageGet(ex, i), arrays.storageGet(ey, i)) orelse return null)) return false;
    }
    return true;
}

pub fn equalp(th: *Thread, args: []const Value) Value {
    const r = equalp2(th, args[0], args[1]) orelse return Value.unwind;
    return th.rt.boolean(r);
}
