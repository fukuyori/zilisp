//! 時刻（CLHS 25.1.4。get-universal-time と、その土地の時刻との差）。
//! decode-universal-time・encode-universal-time・get-decoded-time は src/lisp/boot.lisp に Lisp で書く。
//! ここには、今の時刻と、ある時刻のその土地の時刻との差（夏時間を含む）を OS から得る操作を置く。
//!   - Windows：SystemTimeToTzSpecificLocalTime（その年の夏時間の規則を使う）と GetTimeZoneInformation
//!   - それ以外：/etc/localtime（TZif。std.tz）の切り替わりの表。読めなければ UTC。環境変数 TZ は見ない

const std = @import("std");
const builtin = @import("builtin");
const Value = @import("../values/value.zig").Value;
const Thread = @import("../runtime/thread.zig").Thread;

/// 1900-01-01 から 1970-01-01 までの秒数（universal time と Unix の時刻の差）
pub const unix_to_universal = 2208988800;

/// (get-universal-time)：今の時刻（1900-01-01 00:00:00 UTC からの秒数）
pub fn getUniversalTime(th: *Thread, args: []const Value) Value {
    _ = args;
    const io = th.rt.io orelse return th.signal(.unimplemented, "この環境では時刻を読めません", Value.nil, Value.unbound);
    const secs = @divFloor(std.Io.Timestamp.now(io, .real).nanoseconds, std.time.ns_per_s);
    th.mv_count = 1;
    return Value.fromFixnum(@intCast(secs + unix_to_universal));
}

/// ZILISP-SYSTEM::%TIMEZONE Unix の時刻（fixnum）：その時刻の、その土地の時刻の UTC からの西向きの秒数（夏時間を含む）と、
/// 夏時間かどうか（SBCL の sb-unix::get-timezone と同じ 2 つの値）
pub fn sysTimezone(th: *Thread, args: []const Value) Value {
    if (!args[0].isFixnum()) return th.typeError(args[0], th.rt.syms.integer);
    const z = localOffset(th, args[0].asFixnum());
    th.mv[1] = th.rt.boolean(z.dst);
    th.mv_count = 2;
    return Value.fromFixnum(-z.east);
}

const Zone = struct {
    /// UTC から東向きの秒数（その土地の時刻 − UTC）
    east: i64,
    dst: bool,
};

fn localOffset(th: *Thread, unix: i64) Zone {
    if (builtin.os.tag == .windows) return win.offset(unix);
    return posix.offset(th, unix);
}

const win = struct {
    const SYSTEMTIME = extern struct {
        year: u16,
        month: u16,
        day_of_week: u16,
        day: u16,
        hour: u16,
        minute: u16,
        second: u16,
        milliseconds: u16,
    };
    const TIME_ZONE_INFORMATION = extern struct {
        bias: i32,
        standard_name: [32]u16,
        standard_date: SYSTEMTIME,
        standard_bias: i32,
        daylight_name: [32]u16,
        daylight_date: SYSTEMTIME,
        daylight_bias: i32,
    };
    extern "kernel32" fn FileTimeToSystemTime(ft: *const u64, st: *SYSTEMTIME) callconv(.winapi) c_int;
    extern "kernel32" fn SystemTimeToFileTime(st: *const SYSTEMTIME, ft: *u64) callconv(.winapi) c_int;
    extern "kernel32" fn SystemTimeToTzSpecificLocalTime(tz: ?*const TIME_ZONE_INFORMATION, utc: *const SYSTEMTIME, local: *SYSTEMTIME) callconv(.winapi) c_int;
    extern "kernel32" fn GetTimeZoneInformation(tz: *TIME_ZONE_INFORMATION) callconv(.winapi) u32;

    /// 1601-01-01 から 1970-01-01 までの秒数（FILETIME と Unix の時刻の差）
    const filetime_to_unix = 11644473600;

    fn offset(unix: i64) Zone {
        // 1970 年より前は 1970 年として扱う（SBCL 2.6.7 の Windows 版と同じ：localtime が負の時刻を扱えないため）
        const when: u64 = @intCast(@max(unix, 0));
        // FILETIME は 100 ナノ秒の単位の 64 ビットの数（下位・上位の順の 2 つの DWORD と同じ並び）
        const utc_ft: u64 = (when +| filetime_to_unix) *| 10_000_000;
        var utc: SYSTEMTIME = undefined;
        var local: SYSTEMTIME = undefined;
        var local_ft: u64 = 0;
        if (FileTimeToSystemTime(&utc_ft, &utc) == 0) return .{ .east = 0, .dst = false };
        if (SystemTimeToTzSpecificLocalTime(null, &utc, &local) == 0) return .{ .east = 0, .dst = false };
        if (SystemTimeToFileTime(&local, &local_ft) == 0) return .{ .east = 0, .dst = false };
        const east = @as(i64, @intCast(local_ft / 10_000_000)) - @as(i64, @intCast(utc_ft / 10_000_000));
        var tzi: TIME_ZONE_INFORMATION = undefined;
        if (GetTimeZoneInformation(&tzi) == 0xFFFFFFFF) return .{ .east = east, .dst = false };
        // 標準時の差（分）は −(Bias ＋ StandardBias)。それと違えば夏時間
        const standard_east: i64 = -@as(i64, tzi.bias + tzi.standard_bias) * 60;
        return .{ .east = east, .dst = east != standard_east };
    }
};

const posix = struct {
    /// /etc/localtime の切り替わりの表（最初に使うときに読む。プロセスが終わるまで持つ）
    var loaded: bool = false;
    var tz: ?std.tz.Tz = null;

    fn load(th: *Thread) void {
        loaded = true;
        const io = th.rt.io orelse return;
        const gpa = std.heap.page_allocator;
        const bytes = std.Io.Dir.cwd().readFileAlloc(io, "/etc/localtime", gpa, .limited(1 << 20)) catch return;
        defer gpa.free(bytes);
        var reader = std.Io.Reader.fixed(bytes);
        tz = std.tz.Tz.parse(gpa, &reader) catch null;
    }

    fn offset(th: *Thread, unix: i64) Zone {
        if (!loaded) load(th);
        const z = tz orelse return .{ .east = 0, .dst = false };
        // unix 以前の最後の切り替わり。なければ、最初の夏時間でない型（なければ最初の型）
        var found: ?*const std.tz.Timetype = null;
        for (z.transitions) |t| {
            if (t.ts > unix) break;
            found = t.timetype;
        }
        if (found == null) {
            for (z.timetypes) |*t| {
                if (!t.isDst()) {
                    found = t;
                    break;
                }
            }
            if (found == null and z.timetypes.len > 0) found = &z.timetypes[0];
        }
        const t = found orelse return .{ .east = 0, .dst = false };
        return .{ .east = t.offset, .dst = t.isDst() };
    }
};
