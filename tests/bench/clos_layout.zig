//! P27 layout prototype. Four slots, cached index, and a stamp check on every read.
//! Measures mostly steady-state reads before/after forwarding; setup is also timed.
//! Does not model production allocation, GC or migration.
const std = @import("std");

const count = 4096;
const Direct = extern struct {
    header: u64 = 0,
    class: u64 = 1,
    stamp: u64 = 1,
    layout: u64 = 1,
    forward: ?*Direct = null,
    slots: [4]u64,
};
const Rack = extern struct {
    header: u64 = 0,
    stamp: u64 = 1,
    layout: u64 = 1,
    slots: [4]u64,
};
const Instance = extern struct {
    header: u64 = 0,
    class: u64 = 1,
    rack: *Rack,
};

fn run(comptime rack_mode: bool, comptime forwarded: bool, iterations: u64) void {
    const allocator = std.heap.page_allocator;
    const Body = if (rack_mode) Rack else Direct;
    const bodies = allocator.alloc(Body, count) catch unreachable;
    defer allocator.free(bodies);
    const originals = allocator.alloc(Body, count) catch unreachable;
    defer allocator.free(originals);
    const instances = allocator.alloc(Instance, count) catch unreachable;
    defer allocator.free(instances);
    for (bodies, 0..) |*body, i| {
        body.* = .{ .slots = .{ i, i + 1, i + 2, i + 3 } };
        originals[i] = body.*;
        if (rack_mode) {
            // A redefined rack is replaced without changing the instance address.
            instances[i] = .{ .rack = if (forwarded) body else &originals[i] };
        } else if (forwarded) {
            originals[i].forward = body;
        }
    }
    var sum: u64 = 0;
    var index: usize = 0;
    var i: u64 = 0;
    while (i < iterations) : (i += 1) {
        index = (index * 1664525 +% 1013904223) & (count - 1);
        const body = if (rack_mode) blk: {
            const instance = &instances[index];
            std.mem.doNotOptimizeAway(instance);
            break :blk instance.rack;
        } else blk: {
            const original = &originals[index];
            std.mem.doNotOptimizeAway(original);
            break :blk original.forward orelse original;
        };
        if (body.stamp != 1) @panic("obsolete prototype body"); // Migration slow path excluded.
        sum +%= body.slots[index & 3];
    }
    std.mem.doNotOptimizeAway(sum);
}

fn directReads(n: u64) void {
    run(false, false, n);
}
fn directForwarded(n: u64) void {
    run(false, true, n);
}
fn rackReads(n: u64) void {
    run(true, false, n);
}
fn rackReplaced(n: u64) void {
    run(true, true, n);
}

pub const benchmarks = .{
    .{ "clos-layout/direct", directReads },
    .{ "clos-layout/rack", rackReads },
    .{ "clos-layout/direct-forwarded", directForwarded },
    .{ "clos-layout/rack-replaced", rackReplaced },
};
