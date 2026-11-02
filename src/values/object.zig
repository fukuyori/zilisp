//! ヒープ上のオブジェクトの形（詳細設計 §2.3・§2.4）。
//! Phase 05 では、シンボル・文字列・単純ベクタ・double-float・パッケージを定義する。
//! Phase 08 で、関数（code・closure・native_function。形は src/runtime/function.zig）と value_cell を追加した。
//! 他の種類（bignum、ハッシュ表など）は、それぞれの Phase で追加する。

const std = @import("std");
const Value = @import("value.zig").Value;

pub const ObjKind = enum(u8) {
    symbol = 1,
    string,
    simple_vector,
    double_float,
    package,
    /// バイトコードと定数表（同じ lambda から作った closure すべてが共有する）
    code,
    /// VM の closure（function タグ）
    closure,
    /// Zig で書いたプリミティブ（function タグ）
    native_function,
    /// 捕捉され、かつ代入される変数の箱
    value_cell,
    /// ハッシュ表（Phase 16。詳細設計 §2.6）
    hash_table,
    /// fixnum の範囲を超える整数（Phase 20）
    bignum,
    /// 比（Phase 20）
    ratio,
    /// 単純でない配列（多次元・fill-pointer・adjustable。Phase 21）
    array,
    _,
};

/// cons 以外のオブジェクトの先頭に置く 8 バイトのヘッダ
pub const ObjHeader = packed struct(u64) {
    kind: ObjKind,
    flags: u8 = 0,
    aux: u16 = 0,
    len: u32 = 0,
};

/// cons（ヘッダなし。16 バイト境界に置く）
pub const Cons = extern struct {
    car: Value,
    cdr: Value,
};

pub const SymbolFlags = struct {
    pub const special: u8 = 1 << 0;
    pub const constant: u8 = 1 << 1;
    pub const keyword: u8 = 1 << 2;
    pub const macro: u8 = 1 << 3;
    pub const global_symbol_macro: u8 = 1 << 4;
    pub const unimplemented: u8 = 1 << 5;
    /// CL の特殊演算子（Resolver が直接解釈する）
    pub const special_operator: u8 = 1 << 6;
};

/// 詳細設計 §8.1。64 バイト（ヘッダ 8 ＋ 7 語）
pub const Symbol = extern struct {
    header: ObjHeader,
    /// 文字列（intern 後は変更しない）
    name: Value,
    /// パッケージ、または NIL（uninterned）
    package: Value,
    /// 大域値・動的値（unbound 可）
    value: Value,
    /// 関数・マクロ関数（unbound 可）
    function: Value,
    /// (setf 名前) の関数（unbound 可）
    setf_function: Value,
    plist: Value,
    /// 高速入口（§6.2。関数の実装後に使う）
    fast_entry: usize,

    pub fn hasFlag(s: *const Symbol, f: u8) bool {
        return s.header.flags & f != 0;
    }
};

comptime {
    std.debug.assert(@sizeOf(Symbol) == 64);
    std.debug.assert(@sizeOf(Cons) == 16);
}

/// 文字列（詳細設計 §2.5）。幅 1 バイト（コード ≤ #xFF）と幅 4 バイトの 2 通り。
/// 文字の並びは別に確保したバッファに置く。header.len は文字数、header.aux は幅（1 または 4）。
pub const String = extern struct {
    header: ObjHeader,
    data: [*]u8,

    pub fn length(s: *const String) usize {
        return s.header.len;
    }
    pub fn width(s: *const String) u16 {
        return s.header.aux;
    }
    pub fn charAt(s: *const String, i: usize) u21 {
        std.debug.assert(i < s.length());
        if (s.width() == 1) return s.data[i];
        const p: [*]const u32 = @ptrCast(@alignCast(s.data));
        return @intCast(p[i]);
    }
};

pub const DoubleFloat = extern struct {
    header: ObjHeader,
    value: f64,
};

/// bignum（Phase 20。詳細設計 §2.4）。limb（usize）をヘッダの直後に下位から並べる（header.len が limb の数）。
/// header.aux が 1 なら負。値は変わらない（演算はいつも新しい bignum を作る）。値が fixnum の範囲に収まる bignum は作らない
pub const Bignum = extern struct {
    header: ObjHeader,

    pub fn limbs(b: *Bignum) []usize {
        const base: [*]usize = @ptrCast(@alignCast(@as([*]u8, @ptrCast(b)) + @sizeOf(Bignum)));
        return base[0..b.header.len];
    }

    pub fn positive(b: *const Bignum) bool {
        return b.header.aux == 0;
    }
};

/// 比（Phase 20）。分子と分母は整数（fixnum か bignum）。約分してあり、分母は 2 以上
pub const Ratio = extern struct {
    header: ObjHeader,
    numerator: Value,
    denominator: Value,
};

/// 単純でない配列（Phase 21）：多次元の配列、fill-pointer のあるベクタ、adjustable な配列。
/// 1次元で fill-pointer も adjustable もない配列は、単純ベクタか文字列で表す（このオブジェクトは使わない）。
/// 要素は data（単純ベクタか文字列）に行優先で並べる。各次元の大きさはヘッダの直後に並べる（header.len が次元の数）。
/// adjustable な配列は、大きさを変えると data と次元を書き換える
pub const Array = extern struct {
    header: ObjHeader,
    /// fill-pointer（flags に fill_pointer があるときだけ意味がある）
    fill_pointer: usize,
    data: Value,

    pub const adjustable: u8 = 1 << 0;
    pub const has_fill_pointer: u8 = 1 << 1;

    pub fn dims(a: *Array) []usize {
        const base: [*]usize = @ptrCast(@alignCast(@as([*]u8, @ptrCast(a)) + @sizeOf(Array)));
        return base[0..a.header.len];
    }
};

/// 単純ベクタ。要素はヘッダの直後に並べる（header.len が要素数）。
pub const SimpleVector = extern struct {
    header: ObjHeader,

    pub fn items(v: *SimpleVector) []Value {
        const base: [*]Value = @ptrCast(@alignCast(@as([*]u8, @ptrCast(v)) + @sizeOf(SimpleVector)));
        return base[0..v.header.len];
    }
};

/// パッケージ（詳細設計 §8.2）。表などの本体は Zig のヒープに置く（PackageData）。
pub const Package = extern struct {
    header: ObjHeader,
    data: *anyopaque,
};

/// 捕捉され、かつ代入される変数の箱（詳細設計 §5.2 の assignment conversion）
pub const ValueCell = extern struct {
    header: ObjHeader,
    value: Value,
};

/// ハッシュ表（詳細設計 §2.6。Phase 16 の最小版）。header.aux は比較の種類（HashTest）。
/// 要素は simple-vector entries に (キー 値) の組で並べる（開番地法。空きはキーが unbound、削除した枠は墓標のシンボル）。
/// 非移動型の GC なので、eq・eql のハッシュ値にアドレスを使える（§3）
pub const HashTable = extern struct {
    header: ObjHeader,
    entries: Value,
    count: u32,
    /// 削除した枠の数（増えたら作り直す）
    tombstones: u32,
};

pub const HashTest = enum(u16) { eq, eql, equal, equalp };
