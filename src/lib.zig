//! 処理系の本体を、道具（ベンチマークなど）からモジュールとして使うための入口。
//! src/ をモジュールの根にすることで、src/ の中の相対 import がそのまま使える。

pub const value = @import("values/value.zig");
pub const object = @import("values/object.zig");
pub const heap = @import("runtime/heap.zig");
pub const roots = @import("runtime/roots.zig");
pub const runtime = @import("runtime/runtime.zig");
pub const reader = @import("reader/reader.zig");
pub const printer = @import("printer/printer.zig");
pub const thread = @import("runtime/thread.zig");
pub const value_builder = @import("reader/value_builder.zig");
pub const eval = @import("compiler/eval.zig");
pub const native = @import("native/rt.zig");
