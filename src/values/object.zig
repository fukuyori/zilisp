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
    /// GC が中を走査しない数の配列（ハッシュ表のバケットの表・鎖・ハッシュ値。Phase 21.6）。Lisp からは見えない
    raw_vector,
    /// ストリーム（Phase 23。src/primitives/streams.zig）
    stream,
    /// パス名（Phase 23。src/primitives/pathnames.zig）
    pathname,
    /// readtable（Phase 24。src/reader/readtable.zig）
    readtable,
    /// pprint-dispatch の表（Phase 24。src/printer/pprint.zig）
    pprint_dispatch,
    /// condition と restart（Phase 25。src/primitives/conditions.zig）。CLOS（Phase 27）で instance にまとめる
    record,
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

/// ストリーム（Phase 23）。header.aux は種類（StreamKind）、header.flags は StreamFlags。
/// 入出力のバッファやファイルのハンドルは Zig の側の状態（streams.zig の StreamState）に置き、state がそれを指す（なければ 0）。
/// Lisp の値は ref に置く（GC が走査する）：synonym はシンボル、two-way は (入力 . 出力)、broadcast は出力のリスト、
/// ファイルはパス名
pub const Stream = extern struct {
    header: ObjHeader,
    ref: Value,
    state: usize,
};

pub const StreamKind = enum(u16) { file, string_input, string_output, stdin, stdout, stderr, synonym, two_way, broadcast, pretty };

pub const StreamFlags = struct {
    pub const input: u8 = 1 << 0;
    pub const output: u8 = 1 << 1;
    /// 要素が (unsigned-byte 8)
    pub const binary: u8 = 1 << 2;
    pub const open: u8 = 1 << 3;
};

/// パス名（Phase 23。CLHS 19 章）。各欄は Lisp の値（NIL、文字列、:wild、:newest、ディレクトリのリストなど）
pub const Pathname = extern struct {
    header: ObjHeader,
    host: Value,
    device: Value,
    directory: Value,
    name: Value,
    type: Value,
    version: Value,
};

/// readtable（Phase 24。CLHS 2.1.1）。header.aux は readtable-case（0 :upcase、1 :downcase、2 :preserve、3 :invert）、
/// header.flags の standard は「標準の readtable と同じ構文とマクロ」（Reader が速い経路で読める）。
/// syntax は ASCII の文字の構文型（reader.SyntaxType の番号）。Lisp の値（GC が走査する）：
///   macros   ASCII の文字のマクロ関数の simple-vector（128 要素。マクロでなければ NIL）
///   other    ASCII 以外の文字の ((文字 構文型の番号 . 関数) …)
///   dispatch dispatch 文字ごとの ((文字 . 表) …)。表は 129 要素の simple-vector（ASCII の後ろの文字（大文字にしたもの）の
///            関数と、最後に ASCII 以外の ((文字 . 関数) …)）
pub const Readtable = extern struct {
    header: ObjHeader,
    syntax: [128]u8,
    macros: Value,
    other: Value,
    dispatch: Value,

    pub const standard_flag: u8 = 1 << 0;
};

/// pprint-dispatch の表（Phase 24）。entries は ((優先度 型 関数) …)（優先度の高い順）、cons_entries は
/// ((シンボル 優先度 型 関数) …)。header.flags の initial は「標準の表のまま」（振り分けを Zig で直接行う）
pub const PprintDispatch = extern struct {
    header: ObjHeader,
    entries: Value,
    cons_entries: Value,

    pub const initial_flag: u8 = 1 << 0;
};

/// condition と restart（Phase 25）。class はクラスの記述（Lisp で作る simple-vector。record_class_* の位置に
/// 名前と、自身を含む上位のクラスの名前のリスト（CPL）を置く。src/lisp/boot.lisp）、slots はスロットの値の simple-vector。
/// CLOS（Phase 27）で instance にまとめる
pub const Record = extern struct {
    header: ObjHeader,
    class: Value,
    slots: Value,
};

/// クラスの記述（simple-vector）の中の位置（boot.lisp の %make-class と合わせる）
pub const record_class_name = 0;
pub const record_class_cpl = 1;

/// GC が中を走査しない数の配列。header.len は要素の数、header.aux は要素のバイト数（4 か 8）
pub const RawVector = extern struct {
    header: ObjHeader,

    pub fn items(v: *RawVector, comptime T: type) []T {
        std.debug.assert(v.header.aux == @sizeOf(T));
        const base: [*]T = @ptrCast(@alignCast(@as([*]u8, @ptrCast(v)) + @sizeOf(RawVector)));
        return base[0..v.header.len];
    }
};

/// ハッシュ表（詳細設計 §2.6。Phase 21.6 から SBCL 2.6.7 と同じ並べ方）。header.aux は比較の種類（HashTest）、
/// header.flags の 1 は flat の表、2 は rehash が増やす枠の数（src/primitives/hashtables.zig）、header.len はバケットの数。
/// - kv：simple-vector。枠 i（1〜size）のキーが kv[2i]、値が kv[2i+1]。枠 0 は使わない。空きの枠はキーが unbound
/// - links：raw_vector（u32）。先頭の header.len 個がバケットの表（バケット（ハッシュ値 & (header.len - 1)）ごとの
///   鎖の先頭の枠の番号。0 は空。header.len は 2 の冪）、その後ろの size + 1 個が鎖（next：鎖の次の枠。
///   空きの枠では空き枠の一覧の次）。確保の回数を減らすため 1 つの配列にまとめる
/// - hashes：raw_vector（u64、size + 1 個）。equal・equalp の表の枠のハッシュ値（比べる前に照合し、作り直しで再計算しない）。
///   eq・eql の表は NIL
/// 枠は 1 から順に使い（hwm が使った最大の番号）、削除した枠は空き枠の一覧（free から next でたどる）に積んで、
/// 後に入れたものから再利用する。maphash は枠の番号の順にたどる。
/// 非移動型の GC なので、eq・eql のハッシュ値にアドレスを使える（§3）
pub const HashTable = extern struct {
    header: ObjHeader,
    kv: Value,
    links: Value,
    hashes: Value,
    count: u32,
    /// 使った枠の最大の番号
    hwm: u32,
    /// 空き枠の一覧の先頭（0 は空）
    free: u32,
    /// 枠の数
    size: u32,
    /// :rehash-size（header.flags の 2 が立っていれば増やす枠の数、立っていなければ倍率の single-float のビット）
    rehash: u32,
};

pub const HashTest = enum(u16) { eq, eql, equal, equalp };
