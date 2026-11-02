# Zig 0.17.0 standard library and language features: verification results

[日本語](zig-std-usage.ja.md)

Results of checking, against the real toolchain, the Zig standard library APIs and language features that the detailed design §1.3 marked "to be verified".

| Item | Value |
|---|---|
| Date checked | 2026-11-01 |
| Zig | 0.17.0 (installed with winget; checked with `zig version`) |
| Location of std | `C:\Users\n_fuk\AppData\Local\Microsoft\WinGet\Packages\zig.zig_Microsoft.Winget.Source_8wekyb3d8bbwe\zig-x86_64-windows-0.17.0\lib\std` |
| Probe tests | `tests/zig-probe/probe.zig` (`zig test tests/zig-probe/probe.zig`), `tests/zig-probe/abi.zig` (checked by emitting assembly) |
| Environments | Run: x86_64-windows (Debug, ReleaseFast). Compile only: x86_64-linux-musl, aarch64-macos, x86_64-macos, aarch64-linux-musl, aarch64-windows |

When Zig is updated, redo these checks (`docs/version-update-checklist.md` §3).

## 1. Standard library APIs

| Purpose | Name and usage in 0.17.0 | How checked | Notes |
|---|---|---|---|
| Form of `main` | `pub fn main(init: std.process.Init) !T`. It has `init.arena`, `init.gpa`, `init.io`, `init.minimal.args` and `init.environ_map`. A form taking `std.process.Init.Minimal` also exists | `lib/std/start.zig` lines 786–837, `lib/std/process.zig` lines 31–58, the `zig init` template | The return type is `!void`, `!u8` and so on. `src/main.zig` uses `!u8` to return the exit code |
| Command-line arguments | `init.minimal.args.toSlice(arena)` → `[]const [:0]const u8` | `lib/std/process/Args.zig` line 479 | Converted to UTF-8 (WTF-8) on Windows |
| Standard output and standard error | `var w: std.Io.File.Writer = .init(.stdout(), io, &buffer);` → `&w.interface` (`*std.Io.Writer`). `flush()` is needed at the end | the `zig init` template, `lib/std/Io/File.zig` lines 91 and 104 | The new `Writer` form introduced in 0.15 |
| Writing to a fixed buffer (tests) | `std.Io.Writer.fixed(&buf)`, `buffered()` | tests in `src/main.zig` | |
| Time (measurement) | `std.Io.Timestamp.now(io, .awake)`, `t.untilNow(io, .awake).nanoseconds` (i96) | `lib/std/Io.zig` lines 836–1100 | Only constants (`ns_per_s` and so on) remain in `std.time` |
| Allocators | `std.heap.page_allocator`, `std.heap.ArenaAllocator`, `std.heap.DebugAllocator(.{})`, `std.heap.SmpAllocator`, `std.heap.SafeAllocator`, `std.heap.FixedBufferAllocator`, `std.heap.memory_pool` | `lib/std/heap.zig` lines 12–35, `probe.zig` | The general-purpose allocator is named `DebugAllocator` (formerly `GeneralPurposeAllocator`) |
| Dynamic arrays | `std.ArrayList(T)` is unmanaged (initialize with `.empty` and pass the allocator, as in `append(gpa, x)`) | `probe.zig` | |
| Hash maps | `std.StringHashMapUnmanaged(V)` (`.empty`, `put(gpa, k, v)`), `std.AutoHashMapUnmanaged` | `probe.zig` | |
| Big integers | `std.math.big.int.Managed` (`initSet`, `add`, `toConst`). `Mutable` and `Const` also exist | `probe.zig` | The design that keeps the limb array on the managed heap (detailed design §1.3) is realized by specifying the limbs of `Mutable` / `Const` (details to be checked in Phase 20) |
| Hash functions | `std.hash.Wyhash.hash(seed, bytes)`, `std.hash.Crc32.hash(bytes)` | `probe.zig` | |
| UTF-16 | `std.unicode.utf8ToUtf16LeAllocZ(gpa, s)` | `probe.zig` | Used at the Windows API boundary |
| Path of the executable | `std.process.executablePath(io, buf)`, `std.process.executablePathAlloc(io, gpa)` | `lib/std/process.zig` lines 742 and 769 | |
| Child processes | `std.process.Child` | `lib/std/process.zig` line 19 | Usage to be checked in Phase 12 (invoking `zig`) |
| Dynamic libraries | `std.DynLib` (`lib/std/dynamic_library.zig`) | `lib/std/dynamic_library.zig` line 14 | Usage to be checked in Phase 39 |
| Exiting | `std.process.exit(status: u8)`, `std.process.fatal(fmt, args)` | `lib/std/process.zig` lines 698 and 865 | |
| Allocation aligned to a large boundary | `std.heap.page_allocator.alignedAlloc(u8, .fromByteUnits(4 MiB), n)` **can fail on Windows** (found in Phase 06 on 2026-11-02) | `lib/std/heap/PageAllocator.zig` lines 45–108 | It succeeds if the first allocation happens to be aligned. Otherwise it tries to commit the region reserved as a placeholder with `NtAllocateVirtualMemory(COMMIT)`, fails and returns `OutOfMemory`. On Windows, Zilisp works around it by reserving (RESERVE) a range and committing only its aligned part (`src/support/os_memory.zig`). Other OSes use `page_allocator` |
| Directory traversal and files | `std.Io.Dir.cwd()`, `openDir(io, path, .{ .iterate = true })`, `walk(gpa)` (order is unspecified), `readFileAlloc(io, path, gpa, .limited(n))`, `writeFile(io, .{ .sub_path, .data })`, `createDirPath(io, path)` | `lib/std/Io/Dir.zig` | Used by the Phase 02 tools |
| Child processes | `std.process.run(gpa, io, .{ .argv = ... })` → `.term` (`.exited => code`), `.stdout`, `.stderr` | `lib/std/process.zig` lines 470–507 | Used by the Phase 02 language test runner |
| Writer that allocates its output | `std.Io.Writer.Allocating.init(gpa)`, `.writer`, `.written()`, `.toOwnedSlice()` | `lib/std/Io/Writer.zig` line 2644 | |

## 2. Language features

| Feature | Result | Section of the detailed design |
|---|---|---|
| `@addWithOverflow` | Usable. **Adding as i64 with the tag (low two bits) attached sets the overflow flag exactly when the result leaves the 62-bit fixnum range** (tagged `most-positive-fixnum` + tagged 1 overflows; one less does not) | §2.2 |
| Labeled `switch` and `continue :label` | Usable (tested in the shape of the VM dispatch). Used for the VM dispatch loop after Phase 10: fib(25) about 41% faster than `while` with `switch`, and the speed no longer fluctuated with changes to other code (detailed design §7.1) | §7.1 |
| `@call(.always_tail, …)` | Usable in builds that use LLVM (x86_64-windows Debug and ReleaseFast, ReleaseFast for all targets). **It is a compile error in x86_64-linux Debug builds** (Zig's own x86_64 code generator `stage2_x86_64` does not support tail calls). Code that uses tail calls must use LLVM even in Debug builds, or provide an alternative (looping or trampolines, detailed design §7A.3) | §7A.3 |
| `@"…"` identifiers | Usable (defined and called a function `@"cl-user::foo-bar?"`). How the generated symbol names appear in debuggers and linkers is not verified | §7A.5 C1 |
| `std.mem.doNotOptimizeAway` | Usable (for both values and pointers) | §3.4 |
| Saving callee-saved registers | An empty inline assembly block with clobbers compiles, but nothing guarantees that the save area lies below the local variables. After the Phase 07 review, changed to **reading the register values directly**: `asm volatile ("" : [v] "={rbx}" (-> usize))`. The constraint string must be a string literal (`"={" ++ r ++ "}"` is a compile error; the instruction string may be built with `++`) | §3.4 step 1 |
| Limits of inline assembly | (1) Memory operands such as `movq %%rbx, 0(%[r])` fail with `invalid memory operand` in Zig's own x86_64 code generator (x86_64-linux Debug). (2) The frame pointer `"={rbp}"` (ReleaseSafe, ReleaseFast) and `"={x29}"` (aarch64) fail with `Interference usage of base pointer/frame pointer` and `couldn't allocate output register`, so read them with `movq %%rbp, %[v]` / `mov %[v], x29` and `"=r"`. (3) The stack pointer: `movq %%rsp, %[sp]` / `mov %[sp], sp`. (4) Clobber names are in `std.lang.assembly.Clobbers` (condition codes are `.cc` on x86_64 and `.nzcv` on aarch64) | §3.4 |
| Error unions containing an `extern struct`, `callconv(.c)` | Both compile and run | §6.2 |
| Build modes | `@import("builtin").mode` has type `std.lang.Optimize`, with values `.debug`, `.safe`, `.fast` and `.small` (formerly `.Debug`, `.ReleaseSafe` and so on) | Phase 07 |
| `@frameAddress()` | In optimized builds, a function's own local variables can be placed above its `@frameAddress()`. Do not use the frame position of the function that holds the values as the top of the GC's conservative scan (detailed design §3.4) | §3.4 |
| Top of the stack (Windows) | `std.os.windows.teb().NtTib.StackBase` | §3.4 |
| List of struct fields | `std.meta.fields` was removed in 0.17.0 (`@compileError`). Use `@typeInfo(T).@"struct".field_names` (an array of names) and `field_types` | Phase 08 |
| Line-by-line input | `takeDelimiter('\n')` on the `interface` of `std.Io.File.Reader.init(.stdin(), io, &buf)` (null at the end; `error.StreamTooLong` if a line is longer than the buffer) | Phase 08 REPL |
| Type of `@frameAddress()` | In 0.17.0 it returns `usize` (not a pointer; `@intFromPtr` is not needed) | Phase 12 |
| Caching of the build.zig configuration | The result of configuring build.zig (running the `build` function) is cached and is not rebuilt unless build.zig changes. A test list built by reading a directory at configure time does not pick up new files. Build the test list with a tool that reads the directory at run time (`tools/native_test`) | Phase 12 |
| build.zig paths and Zig | The package directory is `b.root.root_dir.handle` (`Io.Dir`) and `b.root.sub_path`; Io is `b.graph.io`; the Zig executable is `b.graph.zig_exe` | Phase 12 |
| Compiling together with an external module | `zig build-exe --dep zilisp -Mroot=gen.zig -Mzilisp=src/lib.zig --stack 67108864 -femit-bin=out.exe` (`--dep` applies to the `-M` module that follows it) | Phase 12 |
| Time limit and working directory of child processes | `std.process.run(gpa, io, .{ .argv = …, .cwd = .{ .path = dir }, .timeout = .{ .duration = .{ .raw = .fromSeconds(10), .clock = .awake } }, .stdout_limit = .limited(n) })`. A timeout is `error.Timeout` (the child is killed). `cwd` is a `Child.Cwd` (`.inherit`, `.dir`, `.path`), not a string | Phase 13 |
| Discarding Writer | There is no `std.Io.Writer.discarding`. Use `.fixed(&buf)` (`error.WriteFailed` when it overflows) | Phase 08 benchmark |
| Naked functions (`callconv(.naked)`) | A function whose body is only assembly is declared `noreturn`. If it is cast with `@ptrCast` to a function pointer of another type and called, the ReleaseSafe and ReleaseFast optimizers see the callee's `noreturn`, treat the call as never returning and remove the code after it (it crashes at run time; this does not happen in Debug). Instead, write the function in module-level global assembly (`comptime { asm (…); }`, with registers written with a single `%`, as in `%rbx`), declare it as `extern fn name(…) callconv(.c) …;` and call it directly (`tests/bench/nonlocal.zig`; checked on x86_64-windows Debug, ReleaseSafe and ReleaseFast). Global assembly cannot be used in x86_64-linux Debug (Zig's own code generator; see the "Global assembly" row below) | §6.4 (Phase 18 method-2 prototype) |
| Memory operands in inline assembly | Writing `stmxcsr %[m]` with the output `[m] "=m" (m)` caused an access violation at run time in x86_64-windows Debug. Passing a pointer in a register, `stmxcsr (%[p])` with `[p] "r" (&m)` and the clobber `.{ .memory = true }`, works correctly | Phase 18 |
| Contents after `Allocator.alignedAlloc` | Debug builds fill the allocated memory with an undefined marker (0xAA), even for `page_allocator`. To use the zero-filled memory from the OS as is, use `allocator.rawAlloc(len, alignment, @returnAddress())` and `rawFree` (found by the Linux tests) | §3.1 |
| Global assembly (`comptime { asm (…); }`) | Not emitted by Zig's own code generator (x86_64-linux Debug); functions defined there become undefined symbols. Usable with LLVM (all modes on Windows, ReleaseFast on Linux). Distinguish with `builtin.zig_backend == .stage2_llvm` | Phase 18 |
| Stack range on Linux | Without libc the pthread functions are not available, so read `/proc/self/maps` with `std.os.linux.open` and `read`, and use the end of the line that contains the current frame as the top of the stack (main thread). On macOS, use `pthread_get_stackaddr_np` from libSystem | §3.4 |
| `if (true) break :label value;` | Written in the middle of a labeled block, it compiles even when statements follow (no "unreachable code" error). Used for return-from in the native backend | §6.4 (Phase 18) |
| Converting between enums and integers | `@intFromEnum` / `@enumFromInt` are replaced by `@backingInt` / `@fromBackingInt` in 0.17.0. `zig fmt` rewrites the old forms automatically (`@enumFromInt(x)` → `@fromBackingInt(@intCast(x))`) | §2 (used when Value is an `enum(u64)`) |

## 3. How return values are returned (item to be verified in detailed design §6.2)

Checked by compiling `tests/zig-probe/abi.zig` with ReleaseFast and reading the emitted assembly.

| Return type | x86_64-windows | x86_64-linux | aarch64-macos |
|---|---|---|---|
| `Error!Ret` (`Ret` is a 16-byte `extern struct`) | memory | memory | memory |
| A 16-byte struct like `Ret` (Zig's default calling convention) | memory | memory | memory |
| `Ret` as an `extern struct`, `callconv(.c)` | memory (Windows x64 C ABI rules) | **registers** (`rax:rdx`) | **registers** (`x0:x1`) |
| Value as an 8-byte `extern struct` (default calling convention) | memory | memory | memory |
| **Value as an 8-byte `enum(u64)` (default calling convention)** | **register** (`rax`) | **register** (`rax`) | **register** (`x0`) |
| `Error!Value` (Value is an `enum(u64)`) | memory | memory | memory |

"memory" means the value is written to the area pointed to by a hidden pointer passed by the caller (`rcx`, `rdi`, `x0`).

### Impact on the design (decided on 2026-11-01 as option A and reflected in detailed design §2.1, §6.2, §6.4, §6.6 and §7A.2)

1. **`Value` is defined as an `enum(u64)`.** Defined as an `extern struct`, even 8 bytes are returned through memory.
2. **`Error!Ret` in detailed design §6.2 goes through memory on every target.** The calling convention has to change to one of the following (to be decided before Phase 08 and confirmed by measurement in Phase 12).
   - Option A: return only the primary value as a `Value` (an `enum(u64)`, returned in a register). Errors such as non-local exits are represented by returning a fixed special immediate value (a value that never appears as a Lisp value), and the value count is written to a field of `Thread`.
   - Option B: return the primary value and the count in a 16-byte struct with `callconv(.c)`. It is returned in registers on Linux and macOS, but **through memory on Windows, the primary development target**.
3. The single-value fast entry's `Error!Value` also goes through memory, so it must use the same scheme as option A (a special immediate value for errors).

## 4. Build

| Item | Result |
|---|---|
| The `zig init` template | `build.zig` uses `b.addExecutable(.{ .root_module = b.createModule(...) })`, `b.addTest(.{ .root_module = ... })` and `run_cmd.addPassthruArgs()` |
| `build.zig.zon` | `.fingerprint` is required. The first `zig build` suggests a value (Zilisp uses `0xedb879257924792a`) |
| Cross builds (ReleaseFast) | Succeed for all of x86_64-windows, x86_64-linux-musl, aarch64-macos, x86_64-macos, aarch64-linux-musl and aarch64-windows (behavior on real hardware not verified) |
| Specifying from PowerShell | Quote the argument, as in `zig build "-Dtarget=$t"` (without quotes the variable is not expanded) |
