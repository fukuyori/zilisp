# Zilisp Detailed Design

[日本語](Zilisp_詳細設計書_v0.2.md)

**Version 0.2 / 2026-11-01**

| Item | Content |
|---|---|
| Parent document | `docs/Zilisp_企画・基本設計書_v0.3.md` (hereafter "the basic design") |
| Scope | The 12 items of basic design §19 "Detailed design items to decide first", plus the related module structure, error model, native backend, and build scripts |
| Priority | **Execution speed is the top priority** (basic design §17). Standard semantics are a precondition and are not traded for speed |
| Conformance | As in the basic design (a practical compatible subset; implemented features are faithful to the standard) (D-0) |
| License | MIT (D-6). Copyright holder: fukuyori |
| Status | Version that reflects all decisions D-0 to D-10 in §17 |

| Version | Date | Changes |
|---|---|---|
| 0.1 | 2026-11-01 | First draft |
| 0.2 | 2026-11-01 | Changed to speed first. Decided and applied D-0 to D-10 (8-byte Value, page-based heap, conservative stack scan, native backend as the main path, new §7A) |
| 0.2 (addendum) | 2026-11-01 | Applied the results of checking the SBCL source and Web information (§2.2, §2.5, §3.1, §3.4, §7A.6, §15.1). Added the conditions for a single executable to §16.3. Added references to §20 |
| 0.2 (addendum 32) | 2026-11-05 | Phase 25: conditions, handlers and restarts (§2, §6.6, the instruction table of §7, §9; `record` for conditions and restarts, handler and restart stacks as special variables, signaling errors found in Zig to handlers, SBCL's report texts, `typep`, type dispatch with `check-type` and `assert`, `eval` as a function) |
| 0.2 (addendum 31) | 2026-11-04 | Phase 24 (P24d): the pretty printer (§11.2; pretty streams, `pprint-logical-block` and the other pretty printing functions, `*print-pprint-dispatch*` tables and the standard printers, `~<...~:>` `~_` `~I` `~:T` of `format`, `*print-pretty*` T at startup; `#nA` reading and the round-trip acceptance) |
| 0.2 (addendum 30) | 2026-11-03 | Phase 24 (P24c): reader extensions (§11.2; readtable objects, user reader macros, `#.`, `#n=`/`#n#`, `readtable-case` for reading and printing, `*read-base*` and the other reader variables, `with-standard-io-syntax`) |
| 0.2 (addendum 29) | 2026-11-03 | Phase 24 (P24b): `format` with all directives except the pretty printer ones (§11.2; SBCL's tokenizer and directive semantics, `flonum-to-string` ported for `~F ~E ~G ~$`, `formatter`, stream columns for `~T`) |
| 0.2 (addendum 28) | 2026-11-03 | Phase 24 (P24a): printer variables (§11.2; `*print-base*`, `*print-case*`, `*print-circle*`, `*print-readably*` and the others, all `write` keywords, `print-not-readable`) |
| 0.2 (addendum 27) | 2026-11-03 | Phase 23: streams and pathnames (§2.4, §11.2; standard streams, file and string streams, #P, file operations, GC cleanup of streams left open) |
| 0.2 (addendum 26) | 2026-11-03 | Phase 22: packages (§8.2; `*package*`, package functions, defpackage and in-package, name conflicts, load, qualified native constants). Change in how shadowing symbols are kept |
| 0.2 (addendum 25) | 2026-11-03 | Phase 21.6: hash tables replaced with SBCL 2.6.7's layout (§2.6; maphash order, slot counts, flat tables). `raw_vector`, an array the GC does not scan (§2.4) |
| 0.2 (addendum 24) | 2026-11-03 | Phase 21.5: Unicode 15.0.0 character classes and case (§11.2; the table generator and the comparison with SBCL 2.6.7 at every code point). Case folding in `equalp` (§2.6) |
| 0.2 (addendum 23) | 2026-11-03 | Investigation and decisions: comparison of hash table entry layouts and replacement with SBCL's layout (§2.6; Phase 21.6), Unicode 15.0.0 support (§11.2; Phase 21.5), startup time per phase and the threshold for countermeasures (§11.2) |
| 0.2 (addendum 22) | 2026-11-02 | Phase 21: general arrays (multidimensional, fill pointers, adjustable; §2.4), `equalp` and `equalp` hash tables (§2.6), and the character, string, sequence, list and set functions (§11.2) |
| 0.2 (addendum 21) | 2026-11-02 | Phase 20: implementation of the numeric tower (bignums and ratios, mixing with floats, integer division, powers, square roots and elementary functions, bit operations; §2.4). Complex numbers come in a later phase |
| 0.2 (addendum 20) | 2026-11-02 | Phase 19: implementation of tagbody and go (§6.4); iteration macros, loop, mapping and reduction, a minimal format, and the functions used by the iteration curriculum (§11.2) |
| 0.2 (addendum 19) | 2026-11-02 | Corrected the timing of `define-symbol-macro` and related features in §5.2 (moved to Phase 30) and the description of native resumption in `ControlEntry` in §6.4 (matching the Phase 18 implementation). Created this English version (the Japanese version is `docs/Zilisp_詳細設計書_v0.2.md`). From now on, every change updates both versions in the same change. `docs/zig-std-usage.md` is now English and the Japanese version is `docs/zig-std-usage.ja.md` |
| 0.2 (addendum 18) | 2026-11-02 | Preparation for the 0.2.0 release: installer scripts (§18.1, §18.2), tests and releases with GitHub Actions (§18.4), stack top on Linux and macOS (§3.4) |
| 0.2 (addendum 17) | 2026-11-02 | Applied the Codex and agy reviews (Phase 18): the implicit block encloses only the body (also added to the compile-time definition of defmacro), the stack-size invariant of in-progress exits, saving the error contents during cleanup, control stack checks by the verifier, fixes to the method 2 prototype (saving the floating-point control state, direct calls) and re-measurement (§6.4, §7.4) |
| 0.2 (addendum 16) | 2026-11-02 | Phase 18: implementation of block, return-from, catch, throw, and unwind-protect (control stack, Transfer, exits inside cleanup, VM resumption, native labeled blocks), the implicit block of defun, flet, labels, and defmacro, a prototype and measurement of non-local exit method 2 (method 1 is kept; §6.4, §7.4) |
| 0.2 (addendum 15) | 2026-11-02 | Phase 17: implementation of multiple values (ValueMode, VM instructions, multiple-value positions in function bodies, REPL printing) and of &optional, &rest, &key, and &aux (§5.5, §6.2, §6.3) |
| 0.2 (addendum 14) | 2026-11-02 | Phase 16: setf and place expansion, in-order processing of top-level forms in eval, eval-when, minimal hash tables and one-dimensional arrays (§2.6, §5.2) |
| 0.2 (addendum 13) | 2026-11-02 | Phase 15: macro expander, defmacro, destructuring binding, backquote expansion, loading the standard library written in Lisp (§5.2, §11.2) |
| 0.2 (addendum 12) | 2026-11-02 | Phase 14: implementation of dynamic binding (binding stack, VM instructions, restoration when leaving by an error, representation of special declarations, compile-time declarations of defvar and defparameter; §6.5) |
| 0.2 (addendum 11) | 2026-11-02 | Phase 13: running curriculum blocks and comparing with SBCL (`zig build eval-check`; §13.1), call history in error reports (§9.4) |
| 0.2 (addendum 10) | 2026-11-02 | Phase 12: IR verifier, minimal native backend (§7A.8), VM/native agreement tests (`zig build native-test`), measurement of VM vs. native speed and of the cost of the `Value.unwind` check (§6.4, §7A.8) |
| 0.2 (addendum 9) | 2026-11-02 | Fixed VM instruction dispatch as labeled `switch` and `continue` (based on measurement; §7.1). Expansion of `defun` (§5.2) |
| 0.2 (addendum 8) | 2026-11-02 | To match the Phase 08 implementation, added error handling before conditions exist (§6.6), the interpretation of `call-arguments-limit` (§7.3), the instructions and frame layout implemented in Phase 08 (§7.4), and CLI behavior (§19) |
| 0.2 (addendum 7) | 2026-11-02 | Following the Codex review (10 items) of the Phase 07 implementation, fixed the register save method and the lower bound of the scan (§3.4). On the implementation side, fixed violations of the §3.5 rule (Lisp values placed on the Zig heap must be registered as explicit roots) |
| 0.2 (addendum 6) | 2026-11-01 | Following the Phase 01 check results (`docs/zig-std-usage.md`), defined Value as `enum(u64)` (§2.1), changed the return value convention to option A (only the primary value is returned in a register, the count in `th.mv_count`, non-local exits and errors use the special immediate value `Value.unwind` and `th.fault`; §2.2, §6.1 to §6.4, §6.6, §7A.2), made the generic entry `callconv(.c)` (§6.2) |
| 0.2 (addendum 5) | 2026-11-01 | Applied 15 findings from the agy (Antigravity) review (referred to as "agy #number" in the text). Set the native entry in code instead of recreating closures (§2.4, §6.2, §7A.6), unwinding the dynamic environment before cleanup (§6.4), rules for derived pointers (§3.4), unified restoring the dynamic environment by depth (§6.4), arguments of `call-next-method` and handling of `:after` (§10.3), recursive processing of top-level forms (§4.1, §16.1), `setf` functions and the fast entry in symbol slots (§6.2, §8.1), Phases 12 to 34 do not go through `.zfasl` (§5.1, §15.2), turning self-recursion into loops and the type constraints of `musttail` (§6.2, §7A.3), batch compilation, the process count limit, and cache cleanup (§7A.6), direct calls to CL functions (§5.2), hashing for `equalp` (§2.6), `defconstant` (§8.1, §16.1), `unintern` and shadowing (§8.2), timing of `&environment` and `define-symbol-macro` (§5.2) |
| 0.2 (addendum 4) | 2026-11-01 | Applied the findings of the Codex review (24 items; #25 rejected after checking the CLHS, #5 only partly adopted). Hashing for `eql` (§2.6), GC resource reclamation and allocation volume (§3.1, §3.2), the "liveness contract" of conservative scan (§3.4), FFI lending (§3.6), the single-thread constraint (§6.1), ABI with shared libraries (§6.2), saving multiple values (§6.3), `unwind-protect` and nested exits (§6.4), unbound special variables (§6.5, §7.4), encoding of argument counts (§7.3), bytecode verification (§7.4, §14.1), tail call conditions (§7A.3), background jobs, `compile`, and caching (§7A.6), Reader `#+` and `#.` (§8.5, §12), the standard procedure for class redefinition (§10.2), standard method combination (§10.3), cache invalidation (§10.4), tests of mixed paths and reconsidering the GC (§13), `.zfasl` load order (§14.1), scope of state restoration at startup (§15.3) |
| 0.2 (addendum 3) | 2026-11-01 | Applied the results of surveying SICL, Janet, and Carp. Dispatch by class number (stamp) and cache invalidation (§10.2, §10.4), representing instances with a rack (§2.4, §10.2), generating discriminating code (§10.4), mapping Zig identifiers to source locations (§7A.5), startup time measures (§11.3, §15.3), references (§20) |
| 0.2 (addendum 2) | 2026-11-01 | Applied the results of surveying ECL, Clasp, Gambit, and Emacs. Option C for NIL (§2.2), a calling convention that returns the primary value and the count (§6.2), comparative measurement of non-local exit methods (§6.4), alternatives to tail calls (§7A.3), changed D-10 to option ④ background native compilation (§5.1, §7.1, §7A.6, §17), size rules for functions in generated code (§7A.7), running ansi-test under both methods (§13.1), references (§20) |

> **Conventions**
> - "Fixed" marks a design item decided in this document. "To be verified" marks an item that must be checked against the real thing, such as Zig 0.17.0. "To be investigated" marks an item that needs external investigation.
> - The names of Zig standard library and Zig language features were not checked against the real thing when this document was written. Every place that names one is **to be verified**, and they are checked in Phase 01 (§1.3).
> - Statements about performance effects are assumptions made before measurement.
> - The commands, APIs, and file names in this document are plans and do not mean they are implemented.

---

## Contents

1. Zig version, target architectures, and scope of standard library use
2. Value representation and heap object header
3. Heap and GC: page management, roots, FFI handles
4. Source location information
5. Compiler pipeline and Core IR
6. Common runtime base: calling convention, multiple values, non-local exits, dynamic binding
7. Bytecode VM
7A. Native backend and native compilation of the REPL
8. Namespaces, packages, intern table
9. Runtime structure of conditions / restarts
10. CLOS: class table, standard method combination, cache invalidation
11. Bootstrap order and loading the standard library
12. A to E classification of curriculum samples and list of dependent functions (procedure)
13. Differential testing against SBCL and performance measurement
14. Compiled module format (`.zfasl`)
15. Generating executables (`zilisp build`)
16. Difference between `compile-file` and `zilisp build`, multi-OS distribution conditions
17. Decisions
18. Build and release scripts for the implementation itself
19. Breakdown into implementation units for Phases 01 to 08
20. References

---

## 1. Zig version, target architectures, and scope of standard library use

### 1.1 Zig version (fixed)

- Pin to **Zig 0.17.0** (confirmed on 2026-11-01 that `zig version` in the development environment is 0.17.0).
- Put `0.17.0` in `minimum_zig_version` in `build.zig.zon`.
- Zig updates are done in a dedicated work unit. The procedure is written in `docs/version-update-checklist.md` (§18.3).

### 1.2 Targets

| Class | Target (Zig notation, to be verified) | Role |
|---|---|---|
| Primary | `x86_64-windows` | Development machine. All tests and benchmarks run every time |
| Primary | `x86_64-linux` (musl static linking as the first option) | Run on CI/WSL |
| Primary | `aarch64-macos` | Tests on real hardware are done before release |
| Secondary | `x86_64-macos`, `aarch64-linux`, `aarch64-windows` | Only cross-build success is reported. Operation on real hardware is reported separately |

All targets are 64-bit (a precondition of the Value representation in §2). "The cross-compilation succeeded" and "it ran on real hardware" are always reported separately.

### 1.3 Scope of Zig standard library and language feature use

| Purpose | Features planned for use (all names to be verified) | Policy |
|---|---|---|
| Memory | Page allocator, general-purpose allocator, ArenaAllocator | Used only for heap page allocation (obtained from the OS in large units) and for the compiler's temporary areas |
| Collections | Hash map, ArrayList equivalent | Used only for non-GC-managed data on the Zig side |
| Bignums | limb operations of `std.math.big.int` | limb arrays live in the managed heap; only the operations are borrowed |
| Hashing | Non-cryptographic hashes such as Wyhash, CRC32 | sxhash, intern, `.zfasl` checksums |
| Arithmetic | Operations with overflow detection such as `@addWithOverflow` | fixnum fast path (§2.2) |
| Dispatch | Labeled `switch` and `continue` (branching equivalent to threaded code) | VM instruction dispatch (§7) |
| Tail calls | `@call(.always_tail, …)` | Tail calls in native code (§7A) |
| Register save | Inline assembly, or an alternative method | Save registers to the stack before the conservative stack scan (§3.4) |
| Files and processes | Files, directories, environment variables, own executable path, child processes | Called only from `src/platform/` |
| I/O | std I/O and Writer/Reader interfaces | These changed greatly from 0.15 on, so `src/platform/io.zig` absorbs the changes |
| Character encoding | UTF-8 / UTF-16 conversion | Used only at the Windows API boundary |

**Rule**: Dependencies on `std` are collected in `src/platform/` and `src/support/`. Upper layers refer only to Zilisp's own interfaces.

**Phase 01 verification items**: For each feature in the table above, record in `docs/zig-std-usage.md` that it exists in 0.17.0, its signature, and a usage example. If a feature does not exist, revise this document.

---

## 2. Value representation and heap object header (D-9)

### 2.1 Policy

- `Value` is **one 8-byte (64-bit) word**, with **a type tag in the low 3 bits**. Heap objects are aligned on 8-byte boundaries (cons on 16-byte boundaries), so the low 3 bits of a pointer are always 0 and can be used for the tag.
- Bit operations on `Value` are done only inside `src/values/`. Other layers handle it only through methods (`isCons()`, `asFixnum()`, `Value.fromFixnum()`, etc.).
- **The Zig definition is `enum(u64)` (a non-exhaustive enum)** (fixed on 2026-11-01). With the default calling convention of Zig 0.17.0, an `enum(u64)` value is returned in a register, but an 8-byte `extern struct` is returned through memory (confirmed in `docs/zig-std-usage.md` §3 by checking the assembly for x86_64-windows, x86_64-linux, and aarch64-macos).

```zig
pub const Value = enum(u64) {
    _,
    // Special immediate values are defined as constants (e.g. pub const nil: Value = …;)
};
```
- The fixnum range is 62 bits (`most-positive-fixnum` = 2^61−1, `most-negative-fixnum` = −2^61).

### 2.2 Tag assignment (fixed)

```text
 63                                              3 2 1 0
┌───────────────────────────────────────────────┬─┬─┬─┐
│ signed integer (62 bits)                      │x│0│0│  fixnum      (low 2 bits are 00; bit2 is part of the value)
│ address of a cons                             │0│0│1│  cons
│ address of an object with a header            │0│1│1│  other
│ address of a function object                  │1│0│1│  function
│ immediate value                               │1│1│1│  immediate (the low 8 bits select the kind)
└───────────────────────────────────────────────┴─┴─┴─┘
  010 and 110 are reserved
```

**Breakdown of immediate values (low 3 bits are 111)** (distinguished by the low 8 bits)

| Kind | Contents of the upper bits |
|---|---|
| `nil` | None (one fixed word) |
| `unbound` | None. Never exposed to the Lisp side |
| `unwind` | None. **As a function return value, it means a non-local exit or an error is in progress** (§6.2). Never exposed to the Lisp side |
| `character` | Code point in bits 8 to 28 (21 bits) |
| `single_float` | f32 bit pattern in bits 32 to 63 |
| `forward_marker` etc. | Internal use (reserved) |

| Decision | Content | Reason |
|---|---|---|
| fixnum arithmetic | Add and subtract with the tag attached (the sum of two values with low `00` has low `00`). Overflow is detected with `@addWithOverflow` and switches to bignum | One add instruction plus an overflow check |
| Type checks | Done only by comparing the low 3 bits (low 8 bits for immediate values) | Only one branch |
| NIL | A fixed immediate value. `symbol-name` etc. map it to the NIL symbol object held by the runtime (**fixed on 2026-11-02**, based on the comparison measurement below) | The `null` check is one comparison with a constant |
| T | An ordinary symbol (`other`) | Minimize special cases |
| single-float | Immediate value | The default CL float (the default value of `*read-default-float-format*` is `single-float`) is not allocated on the heap |
| double-float | Allocated on the heap (`other`, ObjKind `double_float`) | Does not fit in a 64-bit word. Native code avoids boxing through type inference (§7A.3) |
| function tag | Type checks for `funcall` / `apply` are done without reading the header | Calling is one of the most frequent operations |
| Characters | 0 to #x10FFFF. `char-code-limit` = #x110000 | Unicode is assumed |

**Comparison of NIL representations (decided by measurement in Phase 05)**

| Method | Content | Speed of `car` / `cdr` | Notes |
|---|---|---|---|
| A: immediate value (current provisional plan) | NIL is a fixed immediate value | Applying `car` to a list needs two checks: "is it a cons" and "is it NIL" | Simple to implement |
| B: shared cons and symbol (SBCL's method) | NIL is an object with a special layout that can be read both with the cons tag and as a symbol. NIL itself is placed at NIL's car and cdr positions | A single "is it the list tag" check lets `car` be applied directly to NIL as well | Confirmed in SBCL `src/compiler/generic/early-objdef.lisp` lines 20 to 22 ("NIL is both a cons and a symbol (at the same address)"). Constrains the offset relation between the cons tag and the other tag |

| C: fixed value with the list tag (ECL's method) | NIL is a fixed address value with the cons tag (in ECL, `ECL_NIL` = 1; `src/h/object.h` line 289). Before `car` and `cdr`, compare with NIL | A single "is it the list tag" check tells "is it a list". `car` needs one comparison with NIL first | Simpler than B, and `listp` is as fast as in B |

Because speed comes first, **Phase 05 measures A, B, and C with the same benchmark and adopts the fastest** (R5).

**Measurement results (2026-11-02, Phase 05)**: median of 5 runs of `tests/bench/nil_repr.zig` (`zig build bench -- nil-repr`) on x86_64-windows with ReleaseFast (ns per operation).

| Representation | length (traverse a 1000-element list) | safe-cadr (`(car (cdr x))` on lists of length 0 to 3) |
|---|---|---|
| A: immediate value | 1.005 | 0.694 |
| B: shared cons and symbol | 1.006 | 0.709 |
| C: fixed value with the cons tag | 1.002 | 0.689 |

The three differ by less than 3%, about the same as the variation between measurements of the same representation (2 to 3% between minimum and maximum). Since there is no meaningful difference, **A, the simplest to implement, is adopted** (B requires laying out NIL as both a cons and a symbol, and C needs the same number of checks as A). This measurement comes from a single small operation, so it is reconsidered if a difference appears in the native code benchmarks from Phase 12 on.

**Comparison with SBCL (x86-64)**: SBCL uses the low 4 bits for tags, and a fixnum has a low bit of 0 (63 bits) (`early-objdef.lisp` lines 37 to 69, and confirmed `most-positive-fixnum` = 2^62−1 in SBCL 2.6.7). Zilisp uses 62-bit fixnums, so the range is 1 bit narrower than SBCL's.

### 2.3 Heap object header (other than cons)

```zig
pub const ObjHeader = packed struct(u64) {
    kind: ObjKind,   // u8
    flags: u8,       // per-kind flags (needs finalize, pinned, etc.)
    aux: u16,        // small per-kind value
    len: u32,        // length, element count, etc.
};                   // 8 bytes
```

- **The mark bit is not placed in the header** (it is placed in a bit table outside the page; §3.2).
- There is no list that links all objects.

### 2.4 ObjKind list (initial version)

| ObjKind | Tag | Main contents | Corresponding CL type |
|---|---|---|---|
| (cons) | cons | **No header**. car (8) + cdr (8) = 16 bytes | `cons` |
| `symbol` | other | name, package, value, function, plist, flags | `symbol` (including the NIL object) |
| `string` | other | Length, width (u8/u32), separately allocated buffer | `simple-string` (`character` elements) |
| `simple_vector` | other | Values placed directly in the body | `simple-vector` |
| `byte_vector` | other | u8 placed directly in the body | `(simple-array (unsigned-byte 8) (*))` |
| `double_vector` | other | f64 placed directly in the body | `(simple-array double-float (*))` |
| `fixnum_vector` | other | i64 placed directly in the body | `(simple-array fixnum (*))` |
| `bit_vector` | other | Bit string | `simple-bit-vector` |
| `array` | other | Dimensions, fill-pointer, adjustable, displaced target, actual data | Non-simple arrays and multidimensional arrays |
| `double_float` | other | f64 | `double-float` |
| `bignum` | other | Sign, limb sequence | `bignum` |
| `ratio` | other | Numerator and denominator (reduced, denominator positive) | `ratio` |
| `complex` | other | Real and imaginary parts | `complex` |
| `hash_table` | other | Comparison function, key/value array, bucket index and chains, hash value array (Phase 21.6; §2.6) | `hash-table` |
| `raw_vector` | other | u32 or u64 elements placed directly in the body (the GC does not scan them; Phase 21.6) | (Internal: bucket index, chains and hash values of hash tables) |
| `package` | other | §8 | `package` |
| `code` | other | Bytecode, constant table, lambda list descriptor, line number table, **native entry** (if native compilation is done; §7A.6) | (Internal. Shared by all closures made from the same lambda) |
| `closure` | function | Entry address, code, array of captured values (the layout is shared by the VM and native code; §7A.6) | `function` |
| `native_function` | function | Entry address, name, lambda list descriptor | `function` (native code, primitives) |
| `value_cell` | other | One Value | (Internal: box for a variable that is both captured and assigned) |
| `instance` | other | class, pointer to the rack (§10.2) | `standard-object`, condition |
| `rack` | other | Number (stamp), layout, sequence of slot values | (Internal: body of an instance's slots) |
| `structure` | other | layout, slot array | `structure-object` |
| `class` / `layout` | other | §10 | `class` / (internal) |
| `generic_function` | function | §10 | `generic-function` |
| `method` | other | §10 | `method` |
| `stream` | other | Kind, Lisp values (ref), Zig-side state (OS handle, input and output buffers, encoding; Phase 23) | `stream` |
| `pathname` | other | host, device, directory, name, type, version (Phase 23) | `pathname` |
| `environment` | other | Compiler environment (valid only within dynamic extent) | Value of `&environment` |
| `foreign_pointer` | other | Address, ownership flag | (Extension) |
| `random_state` / `readtable` | other | | `random-state` / `readtable` |

- There is no ObjKind dedicated to macros. A macro function is represented by a function object, and is distinguished by a "macro" flag on the symbol's function cell.
- A condition is an `instance` of a condition-class (§9).
- Arrays with specialized element types (`double_vector`, `fixnum_vector`) store values without boxing. They are provided from 1.0 for the speed of numeric computation.

**Phase 20 implementation (numeric tower)**
- **Bignums**: limbs (usize) follow the header, least significant first (`object.Bignum`; header.len is the number of limbs, header.aux is 1 for negative numbers). Values never change (operations always create new bignums), so no separate buffer and no finalization are needed. **A value that fits in a fixnum is always a fixnum** (`Runtime.makeInteger`). So whether an integer is a fixnum or a bignum depends only on its value, and `eql` only needs to compare bignums by value.
- **Ratios**: hold the numerator and denominator Values (`object.Ratio`). Always reduced, with a denominator of at least 2 (a denominator of 1 gives an integer).
- Multi-precision arithmetic borrows `std.math.big.int.Managed`. Intermediate values live on the Zig heap (gpa); only results are created on the Lisp heap. Addition, subtraction and multiplication of fixnums are computed in i128 and become bignums when they do not fit (the VM and native fast paths fall back to this on overflow).
- **Mixing rules** (CLHS 12.1.4): operations on integers and ratios are exact. If a float is involved the result is a float (double-float if a double-float is involved, otherwise single-float). Comparisons are exact (floats are converted to exact rationals; fixnums use a fast path).
- **Rational to float conversion**: if the numerator and denominator fit in the mantissa width, a single float division (correctly rounded). Otherwise a quotient of at least 64 bits is computed and, if there is a remainder, its lowest bit is set (sticky) before rounding, so rounding happens once and is correct. Conversion from float to rational (`rational`) is exact.
- **Functions**: `floor`, `ceiling`, `truncate`, `round` (two values, quotient and remainder; round goes to even on ties), `mod`, `rem`, `gcd`, `lcm`, `numerator`, `denominator`, `rational`, `float`, `expt` (exact numbers to integer powers are exact; ratio or float exponents give floats), `sqrt`, `isqrt`, `exp`, `log`, `sin`, `cos`, `tan`, `asin`, `acos`, `atan`, `logand`, `logior`, `logxor`, `lognot`, `ash`, `integer-length`, `logcount` (two's complement semantics) and the type predicates (`integerp`, `rationalp`, `floatp`, `realp`, `complexp`). The reader reads integers beyond fixnum range and ratios (`1/2`, `#x…`, `#b-101/11`); the printer writes them in decimal (`*print-base*` in Phase 24).
- **Complex numbers are not implemented** (decided on 2026-11-02; a later phase): operations whose result would be complex (`sqrt` and `log` of negative numbers, fractional powers of negative bases, `asin` and `acos` out of range) are explicit errors. `complexp` always returns NIL.
- **Differences from SBCL 2.6.7**: fixnums are 62 bits (63 in SBCL; `most-positive-fixnum` differs). Transcendental functions use Zig's implementations (`@exp` and so on), so the last bit of a double-float may differ (for example `(exp 1d0)` is `2.718281828459045d0` in SBCL and `2.7182818284590455d0` in Zilisp; both are within 1 ulp. Presumably CLHS does not specify the accuracy of floating-point results of transcendental functions; this has not been verified against the CLHS text). Recorded in `tests/differential/impl-dependent.toml`.
- Tests: 192 cases compared with SBCL 2.6.7 (also under GC stress, and natively in `number-cases.lisp`), the fixnum boundary, read/print round trips, `eql` and hash tables, and error kinds. Language test `numbers.lisp` (and a gc-stress version).

**Phase 21 implementation (general arrays)**
- **Representation**: a one-dimensional array without a fill pointer and not adjustable stays a simple-vector (element type T) or a string (element type character). Every other array (multidimensional, with a fill pointer, or adjustable) is an `array` object (`object.Array`): header.len is the rank, header.flags has the adjustable and fill-pointer bits, then the fill pointer, the data (a simple-vector or a string holding the elements in row-major order) and the dimensions. The GC marks only the data.
- **Element types**: T and character (the symbols `character`, `base-char` and `standard-char`). Other element types, including all compound type specifiers such as `(or character integer)`, are upgraded to T (CLHS 15.1.2.1; T can hold any element, so this is a valid upgrade). Specialized numeric vectors come with 1.0 as planned above.
- **A vector with a fill pointer is adjustable** (`adjustable-array-p` is T; `vector-push-extend` can always grow it), as in SBCL 2.6.7. When `vector-push-extend` grows a vector, the default extension is the current size (1 if it is 0); an explicit extension is used as is. `adjust-array` changes an adjustable array in place and returns it; otherwise it returns a new array. Elements whose subscripts fit in both the old and the new dimensions are kept.
- `adjust-array` with a non-NIL `:fill-pointer` requires an array that already has a fill pointer (otherwise a `type-error`; SBCL 2.6.7 signals a `simple-type-error`, and a `simple-error` for a zero-dimensional array).
- **Displaced arrays are not implemented** (explicit error).
- **Functions**: `make-array` (dimension lists, `:element-type`, `:initial-element`, `:initial-contents` nested to the rank, `:adjustable`, `:fill-pointer`), `aref` and `(setf aref)` with any number of subscripts, `row-major-aref`, `array-dimensions`, `array-dimension`, `array-rank`, `array-total-size`, `array-row-major-index`, `array-in-bounds-p`, `array-element-type`, `array-has-fill-pointer-p`, `adjustable-array-p`, `fill-pointer` (and setf), `vector-push`, `vector-push-extend`, `vector-pop`, `adjust-array`, `stringp`, `simple-string-p`. `length`, `copy-seq`, `elt`, the sequence functions, `equal`, the `equal` hash and the printer use the active part (up to the fill pointer) of a non-simple vector. A non-simple string is a string (`stringp`, `equal`, the string functions).
- **Printing** (as in SBCL 2.6.7): a one-dimensional array prints like a vector or string (active part only); a multidimensional one prints as `#2A((1 2) (3 4))`, and a zero-dimensional one as `#0A7`.

### 2.5 Strings

- The type is `(simple-array character (*))`. Internally there are two representations: 1-byte width (code ≤ #xFF) and 4-byte width. When a character above #xFF is stored with `setf` into a 1-byte-wide string, only the buffer is reallocated at 4-byte width (the object does not move).
- `base-char` is a character with code < 128. SBCL uses the same boundary in its Unicode build (confirmed: `src/compiler/generic/early-vm.lisp` line 121 `base-char-code-limit #-sb-unicode 256 #+sb-unicode 128`; in SBCL 2.6.7, `sb-int:base-char-code-limit` = 128 and `(typep (code-char 200) 'base-char)` = NIL).
- Conversion to UTF-8 is done only at the stream and FFI boundaries.

### 2.6 Hash tables

**Phase 16 minimal version** (`src/primitives/hashtables.zig`): comparison is `eq`, `eql`, and `equal` (`equalp` was added in Phase 21; see below). Entries are stored as (key value) pairs in a simple-vector using open addressing (linear probing; capacity is a power of 2; rebuilt when the load exceeds 3/4). An empty slot has the key unbound, and a deleted slot has a tombstone symbol. The GC is non-moving, so addresses are used as hash values for `eq` and `eql`. The hash value for `equal` is computed from conses up to depth 4 and from the contents of strings. `gethash` also places the second value (whether the entry was found) in the multiple-value registers. Weak hash tables are not implemented.

- **Hashing for `eq`**: the GC is non-moving, so the address (for immediate values, the word itself) can be used.
- **Hashing for `eql`** (review #4): addresses cannot be used, because `eql` treats numbers of the same type and equal value (bignum, ratio, double-float, complex) and characters as equal (e.g. `(eql (expt 2 100) (expt 2 100))` is T while `eq` is NIL; confirmed in SBCL 2.6.7). Numbers and characters compute the hash from their value; other objects use the address.
- **Hashing for `equal` and `equalp` uses separate functions** (agy #12).
  - For `equal`: consistent with CLHS `sxhash` (two `equal` objects get the same value).
  - For `equalp`: objects that are `equalp` get the same value. Specifically, **numbers that are numerically equal get the same value** (`1`, `1.0f0`, `1.0d0`, `#c(1.0 0.0)`, etc., because `equalp` compares numbers with `=`), **characters are case-insensitive** (`char-equal`), **strings and vectors of characters use the same computation** (`"abc"` and `#(#\A #\b #\c)` are `equalp`), and arrays, structures, and hash tables use their elements recursively. `sxhash` is for `equal` and cannot be used for `equalp` (CLHS `equalp`, `sxhash`).
  - The result is undefined if an object is modified while it is used as a key (CLHS 18.1.2).
- **Entry layout** (review #21): the initial plan is an insertion-ordered entry array plus an open-addressing index table. The CLHS does not specify the order of `maphash`, and differential testing sorts the order before comparing (§13.1), so insertion order need not be kept. **In Phase 21, compare with a method that does not keep insertion order on the speed of lookup, insertion, deletion, and traversal and on memory use, and adopt the faster one.**
- The `:weakness` argument is not supported in 1.0, and specifying it is an error.

**Phase 21 implementation (`equalp`)**
- `equalp` (`src/primitives/equalp.zig`): characters with `char-equal`, numbers with `=`, conses recursively, arrays with the same dimensions and `equalp` elements (vectors compare their active parts, so a string and a vector of characters can be `equalp`), hash tables with the same test and count whose every key is found in the other with an `equalp` value; everything else with `eq`. Case is folded with the value of `char-downcase` (the same as `char-equal`; it follows Unicode 15.0.0 from Phase 21.5, ASCII characters only before that).
- **`equalp` hash tables**: the hash of a number is computed from its correctly rounded double-float value (numbers that are `=` round to the same double-float, so they get the same hash; `-0.0` and `0.0` are made the same). Characters are case-folded. A vector hashes its length and up to 16 elements (depth-limited); a multidimensional array its total size; a hash table its count; conses go to depth 4.
- The `equal` hash and `equal` handle non-simple strings by their contents. `sxhash` returns the `equal` hash as a non-negative fixnum.
- **Comparison of entry layouts (2026-11-03)**: four layouts were written as a standalone Zig program outside the repository and compared (ReleaseFast, x86_64-windows, minimum of 3 runs; fixnum keys in an `eql` table and string keys in an `equal` table looked up with a different object of the same contents; memory from malloc, not the GC heap). OA is the current table (keys and values interleaved, open addressing with tombstones, no stored hash); OAH adds an array of hash values; CH is SBCL's layout (a key/value vector, a bucket index, `next` chains and a free list; hash values stored only for `equal`-type tables); DI is the initial plan (an insertion-ordered dense array plus an open-addressing index, as in Python's dict). Results (ns per operation):
  - Tables of up to 1,000 entries: lookups of present keys take the same time in all layouts (1.5–2.1 ns for fixnums). CH is faster at deletion followed by insertion (17 vs 31 ns for OA: tombstones force repeated same-size rehashes in OA), traversal (0.2 vs 0.3–0.7 ns per entry) and lookups of absent keys, and uses less memory (25 vs 33 bytes per entry).
  - String keys: CH takes about 1/3 of OA's time to build a table and about 1/2 for deletion followed by insertion (stored hash values avoid recomputing hashes and comparing contents).
  - Fixnum tables of 100,000 entries or more: OA is about 1.6 times faster for lookups of present keys (5.6 vs 9.1 ns at 100,000; 21.5 vs 35.8 ns at 1,000,000; presumably because CH reads the bucket index and the entry, two memory accesses). CH is faster in the other operations.
  - DI was about the same as CH or slightly slower and used more memory than CH.
- **Decision**: replace the table with CH (SBCL's layout) in Phase 21.6 (tque #343, after Phase 21.5 and before Phase 22). First check that a non-scanned array of u32 can be placed in the GC heap (for the bucket index and the chains). The slower lookup of present keys in fixnum tables of more than 100,000 entries is accepted.

**Implementation in Phase 21.6 (hash table layout)**
- **Layout** (`HashTable` in `src/values/object.zig`, `src/primitives/hashtables.zig`): a simple-vector of keys and values (the key of slot i at 2i and its value at 2i+1; slot 0 is unused; an empty slot has the key unbound), one u32 array holding both the bucket index and the `next` chains (combined to reduce allocations; the number of buckets is in `header.len`), and an array of u64 hash values only for `equal` and `equalp` tables. The table holds the count, the highest slot number used (hwm), the head of the free list and the number of slots. Tombstones (`ZILISP-SYSTEM::%TOMBSTONE`) are gone.
- **Arrays the GC does not scan**: a new object kind `raw_vector` (`header.len` is the number of elements, `header.aux` the element size, 4 or 8). The GC does not scan its contents. It is not visible from Lisp (printed as `#<object …>`).
- **Lookup**: the hash value selects a bucket and the chain is followed. `equal` and `equalp` tables compare the stored hash value before comparing keys (fewer content comparisons), and rebuilding a table does not recompute hash values.
- **Deletion**: the slot is unlinked from its chain and pushed on the free list (the most recently freed slot is reused first).
- **Order is the same as SBCL 2.6.7**: `maphash` and `loop`'s `being the hash-keys` (`%hash-pairs`) visit slots in slot-number order, which is insertion order when nothing was deleted. For this, the slot counts and slot reuse also follow SBCL (`%recompute-ht-vector-sizes`, `grow-hash-table` and `define-puthash/flat` in `target-hash-table.lisp`):
  - The initial number of slots is `:size` (7 if smaller than 7 or omitted).
  - Small `eq` and `eql` tables (`:size` up to 32 for `eq` and 16 for `eql`) start as flat tables. A flat table does not push deleted slots on the free list; insertion uses the empty slot with the highest number (SBCL searches flat tables linearly; Zilisp still uses the chains to search them). A flat table without `:size` has 8 slots.
  - A full table grows to 1.5 times its size (at least one more); if the ratio to the power-of-two bucket count exceeds 0.9 it becomes 0.85, and below 0.55 it becomes 0.65. A flat table whose bucket count stays within the limit takes the bucket count as its new size and stays flat; otherwise it becomes a non-flat table.
  - A table made with `:rehash-size` grows by that value (an integer adds that many slots, a float multiplies; the ratio adjustment applies only to the default 1.5). As in SBCL, its type is `(or (integer 1 *) (float (1.0) *))`, otherwise a type-error (Codex review P21.6 #3).
  - `:rehash-threshold` is type-checked (a real from 0 to 1) and raised to 1/16 if smaller. It is used only for the initial slot count of a flat table without `:size` (the bucket count derived from size / threshold). How SBCL 2.6.7 grows tables with a threshold does not follow the rules readable from its source, so the order can differ (`hash-table-rehash-threshold-order` in `tests/differential/impl-dependent.toml`).
  - The maximum number of slots is 2^28 (so that the lengths of the key/value array and of the bucket index and chains fit in the u32 header field). Growing beyond it signals a storage-condition (Codex review P21.6 #1). The flat flag is cleared only after the rebuild succeeds (#2).
  - `clrhash` resets the highest slot number to 0 and clears only the used slots and the bucket index (the chains are rewritten on insertion; #4).
- **Checks**: insertion order, order after growing, insertion after deletion (flat and non-flat tables, around 32 entries for `eq` and 16 for `eql`, `:size` from 0 to 100), after `clrhash`, `remhash` and `setf` inside `maphash`, `loop` order, and `equalp` between hash tables all give the same results as SBCL 2.6.7 (language test `hash-tables.lisp`, also a GC stress version).
- **Speed** (ReleaseFast, x86_64-windows, median of 7 runs excluding startup; ratio to `42fd447` before the change): inserting and looking up 200,000 fixnum keys 1.02, 50,000 string keys 0.92, 300,000 deletions and insertions in a table of 1,000 entries 0.56, creating 30,000 tables of 8 entries 1.02, `maphash` over 100,000 entries 0.76, deletion and insertion with string keys 0.81.
- Results: the curriculum blocks still match in 421 cases (0 output differences). Startup time is 8.74 ms.

**Implementation in Phase 23 (streams and pathnames)**
- **Streams** (`src/primitives/streams.zig`; objects are `object.Stream`): kinds file, string-input, string-output, stdin, stdout, stderr, synonym, two-way and broadcast. Lisp values (the synonym symbol, the two-way pair, the broadcast list, the pathname of a file) are kept in the object's `ref`, which the GC scans. Buffers and file handles are kept in Zig-side state (`StreamState`, allocated with gpa) listed in `Runtime.streams`. **The GC closes and frees the state of streams that are collected** (file output is written before closing; the "files left open are closed at GC" rule of §3.2). Destroying the Runtime also writes out and closes everything.
- **Input**: every input stream is handled as UTF-8 bytes with a position (so `read-line`, `read-char` and `read` share it). File and string input streams read everything when opened; standard input is read as needed (in the REPL, from the same reader the REPL uses, so lines the REPL has read ahead are not lost). Line endings are not translated: a CR of CR LF is read as a character (as SBCL 2.6.7 does; checked with `read-char` and `read-line`; output writes only LF). Latin-1 input given to `read` is converted to UTF-8 first. `file-position` and `file-length` count bytes (characters for string streams). `read` consumes one whitespace character after the object (as SBCL does).
- **Output**: output functions first produce bytes and then write them (`emit`). Files are written out when the buffer exceeds 64 KiB, on `finish-output` and on `close`. Each stream records whether it is at the start of a line, used by `fresh-line` and `~&` in `format`. `print`, `prin1`, `princ`, `terpri` and `format` take an output stream (before, they wrote directly to `th.out`).
- **Standard streams** (created by `Thread.create`): `*standard-output*` (writes to `th.out`), `*standard-input*`, `*error-output*` (flushes standard output first), `*terminal-io*` (two-way), `*query-io*` and `*debug-io*` (synonyms of `*terminal-io*`), `*trace-output*` (a synonym of `*standard-output*`).
- **Functions**: `open` (`:direction` `:input`, `:output` or `:probe`, `:io` not implemented; `:element-type` character or `(unsigned-byte 8)`; `:if-exists` defaults to an error as in SBCL, also `:supersede`, `:append`, `:overwrite`, `:rename`, NIL; `:external-format` `:utf-8` or `:latin-1`), `close`, `with-open-file`, `with-open-stream`; `read-char`, `peek-char`, `unread-char`, `read-char-no-hang`, `read-line` (with its second value), `read-byte`, `read-sequence`, `listen`, `clear-input`, `read`, `read-preserving-whitespace`, `read-from-string` (the second value is the next position); `write-char`, `write-string`, `write-line`, `write-byte`, `write-sequence`, `terpri`, `fresh-line`, `finish-output`, `force-output`, `clear-output`; `print`, `prin1`, `princ`, `pprint` (on one line until Phase 24; the pretty printer since P24d), `write` (`:stream` and `:escape` only), `prin1-to-string`, `princ-to-string`, `write-to-string`; `make-string-input-stream`, `make-string-output-stream`, `get-output-stream-string`, `with-output-to-string`, `with-input-from-string`, `make-broadcast-stream`, `make-two-way-stream`, `make-synonym-stream` and their accessors; `streamp`, `input-stream-p`, `output-stream-p`, `open-stream-p`, `interactive-stream-p`, `stream-element-type`, `file-length`, `file-position`.
- **Pathnames** (`src/primitives/pathnames.zig`; objects are `object.Pathname`): fields host (always NIL), device (the Windows drive), directory, name, type and version. Parsing and namestrings follow SBCL 2.6.7 (separated by `/`; on Windows `\` is also read; `*` is `:wild`, `**` is `:wild-inferiors`, `..` is `:up`, `.emacs` is a name, and version is `:newest` when there is a name). `#P"..."` is read and printed. Functions: `pathname`, `pathnamep`, the field accessors such as `pathname-host`, `make-pathname`, `merge-pathnames` (a relative directory is appended to the default directory; `:up` is kept), `namestring`, `file-namestring`, `directory-namestring`, `host-namestring`, `enough-namestring`, `parse-namestring`, `wild-pathname-p`, `pathname-match-p`, `probe-file`, `truename`, `directory` (matching `*`, `?` and `**`, returned in name order), `ensure-directories-exist`, `delete-file`, `rename-file`, `file-write-date`. `*default-pathname-defaults*` is the working directory at startup; files are opened after merging with it. `equal`, `equalp` and their hash tables compare pathnames field by field, except the version (SBCL 2.6.7's `pathname=` does not compare the version of physical pathnames). `load` also takes pathname designators.
- **How scripts end**: when a file is being run (`zilisp FILE` and native programs), end-of-file on standard input and failure to write standard output (broken pipe) end the program normally without printing an error (as SBCL 2.6.7's `--script` does in process-script).
- **Error kinds**: added `stream-error` (closed streams). File problems are `file-error`, the end of a stream is `end-of-file`, and a stream of the wrong direction or element type is a type-error (all the same kinds as SBCL).
- **Fix**: parsing a pathname collected the strings of directory components in a Zig array, so a GC at the next allocation could collect them (found under GC stress; they are now linked into a Lisp list immediately).
- **Codex review fixes (Phase 23)**, 16 issues, each checked against SBCL 2.6.7: `:if-exists :rename` and `:rename-and-delete` now move the old file to `name.bak` (the backup is deleted at close for `:rename-and-delete`, and restored on `:abort`); the REPL and `*standard-input*` read from the same reader; the CR LF translation was removed (SBCL does not translate) and Latin-1 `read` works; character output to a binary stream is a type-error from every function (`write-char`, `write-string`, `format`, ...); broadcast streams pass on `write-byte`, `finish-output` and `force-output`, and their element type is that of the last stream (T when empty); closed synonym and two-way streams signal closed-stream errors; `read-char-no-hang` does not wait for a terminal; `file-length` of an output stream counts the existing length (`:overwrite`); `pathname-match-p` matches every field (a NIL field in the wildcard matches anything; directories with `*` and `**`; `?` is one character); `merge-pathnames` resolves `:back` and falls back to the default version; `make-pathname` takes the version from `:defaults` only (otherwise NIL, as in SBCL); `directory` also returns directories whose name and type match, without duplicates; `equalp` on pathnames; characters Latin-1 cannot encode signal a stream-error.
- **Differences from SBCL 2.6.7** (`tests/differential/impl-dependent.toml`): the pathname host, how a `*` inside a name is represented (SBCL uses pattern objects), how streams are printed and their type names, `:abort` in `close` (SBCL deletes or restores the new file; Zilisp only closes, except that a `:rename` backup is restored), how `*query-io*` and the others are built, and `file-position` through a synonym stream (SBCL returns the end of its buffer; Zilisp returns the position).
- **Tests**: language tests `streams.lisp` (reading and writing files, binary, UTF-8, string streams, composite streams, standard output) and `pathnames.lisp` (parsing, namestrings, merge-pathnames, comparison, file operations). Both give the same output as SBCL 2.6.7, also in the GC stress versions and natively. Unit tests for the error kinds (file-error, stream-error, end-of-file, type-error, unimplemented).
- Results: the curriculum blocks went from 429 to 467 matches. Level 9 went from 7 to 27 matches (the 3 blocks that read standard input now match SBCL through "How scripts end" above; eval-check gives no standard input), and the only remaining Zilisp-only errors are 7 `format` directives (Phase 24). **The main code of Level 17 (`text-tools`) also uses `handler-case` (Phase 25) and `format` directives such as `~8D` (Phase 24), so it does not run within Phase 23.** With a copy that removes `handler-case`, the input and output up to the first such `format` directive were confirmed to match SBCL. Startup time is 9.47 ms.

**Implementation in Phase 24 (format, reader extensions, the printing system)**
Phase 24 is done in four steps: P24a printer variables, P24b `format`, P24c reader extensions (readtables, user reader macros, `#.`, `#n=`), P24d the pretty printer (decided on 2026-11-03: the pretty printer and all the reader extensions are in Phase 24).
- **P24a: printer variables** (`src/printer/printer.zig`). Before printing, the values of `*print-escape*`, `*print-readably*`, `*print-base*`, `*print-radix*`, `*print-case*`, `*print-circle*`, `*print-level*`, `*print-length*`, `*print-array*`, `*print-gensym*` and `*read-default-float-format*` are read into `Settings` (`Settings.current`). Messages of the implementation itself (error reports, native constants) use `Settings.standard`, which does not depend on the variables. The variables have SBCL 2.6.7's initial values (`*print-pretty*` was NIL until the pretty printer existed; it is T since P24d).
  - Integers and ratios in `*print-base*` with uppercase letter digits; `*print-radix*` adds `#b`, `#o`, `#x`, `#Nr`, or a trailing `.` (`#10r` for base-10 ratios). Symbols that read as numbers in `*print-base*` are written in `|...|` (`ABC` is `|ABC|` in base 16).
  - `*print-case*`: only characters that the reader would upcase are changed; `:capitalize` treats runs of alphanumeric characters as words (`Foo1bar`, `A-1b`), as SBCL does. Names written in `|...|` keep their case.
  - `*print-level*` (`#`) and `*print-length*` (`...`) for lists, vectors and the axes of multidimensional arrays (`#2A((1 ...) ...)`, `#2A#`).
  - `*print-circle*`: a first pass over the same range (inside `*print-level*` and `*print-length*`) marks objects seen twice; they get `#n=` and `#n#`. All heap objects except numbers and interned symbols are marked (uninterned symbols, strings, functions, hash tables and pathnames too), and a shared list tail is written as `. #n#`, all as in SBCL.
  - `*print-readably*` forces escaping, `*print-array*` and `*print-gensym*` and ignores `*print-level*` and `*print-length*`. Objects that cannot be read back (functions, streams, packages, hash tables, NaN and infinities) signal `print-not-readable` (a new error kind).
  - `*print-array*` NIL writes `#<(SIMPLE-VECTOR 3) {...}>`, `#<(VECTOR T 2) {...}>` or `#<(SIMPLE-ARRAY T (2 2)) {...}>`; strings are always written.
  - `*read-default-float-format*`: the exponent marker is left out for the default format (`1.5f0` and `1.5` when it is `double-float`).
  - `write` and `write-to-string` take all their keywords (`:array :base :case :circle :escape :gensym :length :level :lines :miser-width :pprint-dispatch :pretty :radix :readably :right-margin`) and bind the variables while printing. `:base` must be an integer from 2 to 36 and `:case` one of the three keywords (type-error otherwise). `prin1`, `princ`, `print`, the `-to-string` functions, `~A` and `~S` of `format`, and the values printed by the REPL follow the variables.
  - **Fix**: Zig 0.17.0's `toStringAlloc` gives wrong digits for bignums in bases 8 and 32 (`(expt 2 70)` came out as 2^72 in base 8 and as 2^71 in base 32; checked with a small test). Bases 4, 8 and 32 are now built from the base-2 string.
  - Tests: language test `printer.lisp` (also a gc-stress version; the same output as SBCL 2.6.7) and unit tests for `print-not-readable` and the keyword checks.
- **P24b: `format`** (`src/primitives/format.zig`; replaces the minimal `format` of Phase 19). Written in Zig after SBCL 2.6.7's `target-format.lisp`, `format.lisp` and `print.lisp` (public domain).
  - The control string is split into directives as SBCL does (`%tokenize-control-string`, `parse-directive` and `combine-directives`: `~` + newline, `~%`, `~~` and `~|` become text). Parameters: integers, `'c`, `v` (a NIL argument means the default), `#`, and empty ones.
  - Directives: `~A ~S` (field width, padding, `:` for `()`), `~W`, `~C` (`:` writes names such as `Space` and `Soh`, `@` writes `#\a`), `~D ~B ~O ~X` (width, pad character, `:` digit groups, `@` sign; non-integers are written by `princ` in that base), `~R` (radix, English cardinals and ordinals up to vigintillion, new and old Roman numerals), `~P`, `~F ~E ~G ~$`, `~% ~& ~| ~~`, `~T` (absolute and relative, using the column of the stream), `~*` (`:` and `@`), `~?` (`@`), `~( ~)` (the four case conversions, applied to the whole inner output), `~[ ~; ~]` (`:`, `@`, `~:;` default, `#`), `~{ ~}` (`:`, `@`, `~:}`, a count, an empty body that takes the control from the argument), `~^` (with 0 to 3 parameters; `~:^` inside `~:{`), `~< ~>` justification (`:`, `@`, `~:;` with the line width, default 72), and `~/name/` (the name is upcased and interned in CL-USER unless it names a package; the function gets the stream, the argument, the colon and at-sign flags and the parameters).
  - `~^` leaves through Zig errors (`Up`, `UpUp`) caught where SBCL has its catch (`~{`, `~<` and `format` itself). Output is collected in a buffer and written to the stream at the end and before user functions are called (`~/name/` and function controls get the real stream, or a string output stream when the destination is a string). Streams now keep their column (`StreamState.column`) for `~T`.
  - Floating point: `flonum-to-string` and `%flonum-to-digits` (Burger and Dybvig's method with rounding at a digit position) were ported with big integers, so rounding is exactly SBCL's (`(format nil "~,2F" 0.005)` gives `0.01`, `~,1F` of 0.25 gives `0.3`). Rationals are converted to single-float. Non-numbers are written as by `~A` in base 10 with the width as `mincol`.
  - `formatter` (a macro in `boot.lisp` that calls `zilisp-system:%format-rest`) and function controls work.
  - Pretty printer directives were handled as for a stream that is not a pretty-printing stream until P24d (`~_`, `~I` and `~:T` did nothing; `~<...~:>` was an explicit error). P24d implements them.
  - Errors: SBCL's `format-error` is a `simple-error` in Zilisp (as in Phase 19). Where SBCL signals a type-error (a non-list argument to `~{`, a parameter of the wrong type), Zilisp does too.
  - Results: the curriculum blocks went from 467 to 478 matches; no block fails only on Zilisp because of `format` any more. Tests: language test `format.lisp` (145 lines of output, the same as SBCL 2.6.7; also a gc-stress version) and unit tests for 24 error cases compared with SBCL.
- **P24c: reader extensions** (`src/reader/readtable.zig`, `src/reader/reader.zig`, `src/reader/value_builder.zig`).
  - **Readtables** are a new object kind (`object.Readtable`): the syntax types of ASCII characters, a 128-element simple-vector of macro functions, an alist for other characters, and the dispatch tables (129-element vectors per dispatching character). The standard readtable is `zilisp-system:*standard-readtable*`; `*readtable*` starts as a copy of it (as in SBCL). The standard readtable cannot be modified.
  - The standard macro characters are built-in functions (`zilisp-system::%READ-LIST`, `%READ-SHARP-QUOTE` and so on, one per `reader.Builtin`). When the macro function of a character is one of them, the reader calls the Zig code directly, so copying a standard macro to another character works (`(set-macro-character #\] (get-macro-character #\)))`). `get-macro-character` returns the name symbol for them (SBCL returns symbols such as `SB-IMPL::READ-LIST`).
  - The reader asks the builder for `charInfo` and `dispatchInfo`; when the readtable still has the standard flag, the static standard tables are used (the fast path). `beginRead` refreshes the options from `*read-base*`, `*read-default-float-format*`, `*read-suppress*` and `*readtable*` at every `read`, so a form that changes them affects the next form read from the same file.
  - **User reader macros** are called with a stream positioned at the reader's position (the stream being read, or a string input stream over the same text for `load` and `read-from-string`); afterwards the reader continues at the stream's new position. A macro that returns no values reads as nothing. `read` with `recursive-p` true shares the `#n=` labels of the outer read. Errors inside reader macros keep their kind (a new reader error `LispError` carries them out).
  - `#.` evaluates when `*read-eval*` is true (otherwise reader-error). `#n=` and `#n#` work with circular structure (a placeholder cons is replaced inside conses, simple vectors and arrays). `*read-suppress*` makes lists and vectors read as NIL too (as in SBCL).
  - `readtable-case` (`:upcase`, `:downcase`, `:preserve`, `:invert`) is applied to tokens and to printing (escaping and `*print-case*`, SBCL's `output-symbol-case-dispatch`; with `*print-readably*` symbols are written for the standard readtable). Symbols starting with a macro character or containing a terminating macro character of the current readtable are escaped (SBCL's `symbol-quotep`).
  - Functions: `readtablep`, `copy-readtable`, `set-macro-character`, `get-macro-character`, `make-dispatch-macro-character`, `set-dispatch-macro-character`, `get-dispatch-macro-character`, `set-syntax-from-char`, `readtable-case` and its `setf`, `read-delimited-list`, and the macro `with-standard-io-syntax`.
  - Native backend: constants are written with `*print-circle*`, so circular constants (`'#1=(a . #1#)`) survive; reader macros used by later forms must be defined inside `eval-when`, as with `compile-file`.
  - Tests: language test `readtable.lisp` (the same output as SBCL 2.6.7; also a gc-stress version and natively) and unit tests for 17 error cases compared with SBCL.
- **P24d: the pretty printer** (`src/printer/pretty.zig`, `src/printer/pprint.zig`). Written in Zig after SBCL 2.6.7's `pprint.lisp` (public domain).
  - **Pretty streams** are a new stream kind (`.pretty`): a queue of operations (conditional newlines, indentations, tabs, starts and ends of logical blocks) with sequence numbers, the stack of logical blocks, the prefix and the suffix, and a buffer. Output is decided as in SBCL (`enqueue-newline`, `maybe-output`, `fits-on-line-p`, `output-line`, `expand-tabs`). The line length is `*print-right-margin*`, or 80. `*print-miser-width*` and `*print-lines*` (` ..` and the suffix, then nothing more) work.
  - When `*print-pretty*` is true, `print`, `prin1`, `princ`, `write`, the `-to-string` functions and `~A ~S ~W` print through `output-object`. `*print-circle*` uses two passes over the object (the first writes to a null stream) and marks inside logical blocks, as SBCL's `check-for-circularity`. `*print-level*` and `*print-length*` apply to logical blocks (`pprint-pop`).
  - **Dispatch tables** are a new object kind (`object.PprintDispatch`): entries with priorities and types, and entries for conses keyed by the car symbol. `pprint-dispatch`, `set-pprint-dispatch` and `copy-pprint-dispatch` work; the initial table (`zilisp-system:*standard-pprint-dispatch-table*`) is handled in Zig and turned into entries only when a copy of it is changed. The standard printers for special forms and macros (`let`, `defun`, `cond`, `case`, `do`, `dolist`, `loop`, `tagbody`, `prog`, `setq`, `lambda` lists, `quote` and backquote, arrays) were ported from SBCL, some as SBCL's format control strings. Function calls and macros with `&body` are indented by their lambda list; `defmacro` now keeps the lambda list on the property list (`zilisp-system::%macro-lambda-list`).
  - Functions: `pprint`, `pprint-newline`, `pprint-indent`, `pprint-tab`, `pprint-fill`, `pprint-linear`, `pprint-tabular`, and the macros `pprint-logical-block`, `pprint-pop`, `pprint-exit-if-list-exhausted`. On a stream that is not a pretty stream, `pprint-newline`, `pprint-indent` and `pprint-tab` do nothing. A pretty stream does not report its column (SBCL's `pretty-misc` returns NIL for `charpos`), so `fresh-line` and `~&` on it always start a new line. Inside `~<...~:>` the arguments are taken from the list one at a time, as `pprint-pop` does (so circular lists stop with `*print-circle*`), and `~:*`, `~@*` and `~@[` move back in that list. `format`: `~<...~:>` (logical blocks, `~@;` per-line prefix, `~:@>` fill style), `~_`, `~I`, `~:T`, and `~T` on pretty streams.
  - `*print-pretty*` is now T at startup, as in SBCL (decided on 2026-11-04). Printing a small list 40000 times took about 2.3 times as long as with NIL (70 ms and 162 ms; SBCL 39 ms and 91 ms, also about 2.3 times). The curriculum blocks stay at 478 matches.
  - Tests: language test `pretty.lisp` (231 lines of output, the same as SBCL 2.6.7; also a gc-stress version) and `pretty-default.lisp` (73 lines, printing with the initial values of the variables, the same as SBCL 2.6.7).
- **Acceptance of Phase 24 (round trip)**: objects printed with `*print-readably*` read back as `equalp` objects, with `*print-pretty*` NIL and T and with a narrow `*print-right-margin*` (language test `round-trip.lisp`, also a gc-stress version; the same output as SBCL 2.6.7). For this, two gaps were filled:
  - The reader reads `#nA` (SBCL's `sharp-A`: the length of each axis is the length of the first element of the axis above; after an axis of length 0 the remaining axes are 0) and SBCL's `#A(dimensions element-type . contents)`. The array is built in the builder without calling `make-array`, because native programs read their constants without a thread. Errors have SBCL's kinds: reader-error for the form, simple-error when a length does not match the dimension, type-error for a bad dimension, a dotted list or a non-character element (with a thread; otherwise reader-error).
  - Native programs: constants are now written with `*print-readably*` (so they keep their dimensions and element type); a constant that cannot be read back (a hash table from `#.`, a function, ...) is an error at `--emit-zig` instead of a broken program.
  - With `*print-readably*`, arrays that `#nA` cannot represent (a character array, or an axis of length 0 followed by a nonzero axis, such as `(make-array '(0 3))`) are written as `#A((0 3) T)` (SBCL's `array-readably-printable-p` and `output-unreadable-array-readably`; with the pretty printer the list is written by the pretty printer, as in SBCL).

**Review of the 0.3 changes (2026-11-04)**
After Phase 24, the changes of Phases 19 to 24 were reviewed by agy (Antigravity CLI; two of five rounds finished before its quota ran out) and by Codex (the other three rounds). 41 issues were reproduced with Zilisp and SBCL 2.6.7 and fixed; the list is in CHANGELOG.md (Fixed). Design changes among them:
- Native programs read the constants of each toplevel form just before running it (`Toplevel.nconsts`/`nlambdas`, `rt.zig` `loadUpTo`), as a fasl does, and the emitter prints the whole constant table with one set of `*print-circle*` labels (`printer.writeObjects`); the reader keeps the labels across the constants.
- `reader.Source` has a refill hook: reading from standard input continues the same read when more input is needed instead of reading the form again.
- Reader macros called while skipping (`#+`, `*read-suppress*`) get `*read-suppress*` bound to T and their value is NIL; a recursive `read` inside a reader macro takes the backquote depth of the outer read (`ValueBuilder.bq_depth`).
- Object constructors refuse lengths that do not fit in the 32-bit header length (OutOfMemory, i.e. storage-condition).
- Errors for malformed `do`/`loop` forms are program-error (SBCL signals simple-error for some of them; `error` comes in Phase 25). In Phase 25, `do`, `do*` and `psetq` signal simple-error as in SBCL 2.6.7 (`loop` is program-error in SBCL too).

**Implementation in Phase 25 (conditions, handlers, restarts)**
Decided on 2026-11-05: conditions are represented by a dedicated `record` and merged into CLOS instances in Phase 27; the report texts of the standard conditions follow SBCL 2.6.7; errors found in Zig call the handlers right where `th.signal` is called; the REPL shows the list of restarts (choosing one by number comes in a later phase). The structure is in §9.
- **Zig side**: `ObjKind.record` (`object.Record`; the GC traces the class and the slots), `src/primitives/conditions.zig` (`zl-sys::%make-record`, `%record-p`, `%record-class`, `%record-slots`, `%object-address`, `%unhandled-condition`), calling handlers from `th.signal` (`signalDetail`, `callSignalHook`), `th.stackExhausted` for stack overflows, recording conditions that were not handled (`ErrorKind.condition`, `th.unhandledCondition`) and the list of restarts (`LispError.restarts`, `th.writeRestarts`; written by the REPL, scripts and native programs). The printing entry points pass conditions and restarts to `zl-sys::%print-record`.
- **`typep`** (`src/primitives/types.zig`; the first implementation as a CL function): type names (numbers, characters, strings, sequences, arrays, symbols, functions, streams, ...), ranges such as `(integer low high)`, `mod`, `unsigned-byte`, `signed-byte`, `member`, `eql`, `and`, `or`, `not`, `satisfies`, `cons`, `(vector element-type length)`, `(simple-array ...)`, `(string length)`, and condition and restart types (by the class's CPL). CL type specifiers it cannot decide signal `zilisp:unimplemented`; symbols that are not types signal simple-error. The type test of set-pprint-dispatch (the partial one in pprint.zig) now uses it too. `type-of`, `subtypep` and `deftype` are not implemented (the curriculum does not use them).
- **Lisp side** (end of `src/lisp/boot.lisp`): class descriptions, `define-condition` and `make-condition`, the hierarchy and reports of the standard condition types, `signal`, `error`, `cerror`, `warn`, `invoke-debugger`, `handler-bind`, `handler-case`, `ignore-errors`, the restart functions and macros, `typecase`, `etypecase`, `ctypecase`, `ecase`, `ccase` (falling through signals `zl-sys::case-failure`, a kind of type-error, with SBCL's text), `check-type` (simple-type-error with SBCL's text and `store-value`), `assert` (`continue`; when the test is a function call, the values of its non-constant arguments are reported as `failed with X = 3.`; the values of places are not asked for), and `zl-sys::%zig-condition`, which makes conditions from errors found in Zig.
- **Operation and operands of division by zero**: division by zero in `/`, `floor` and the others passes `(/ dividend divisor)` (floats as floats, as SBCL does) and `expt` passes `(EXPT base power)` to the condition. `log` of 0 has no operation (as in SBCL).
- **`eval`** was added as a function (the curriculum's `safe-eval` in Level 13; it calls the compiler's `eval`).
- **VM value stack**: while handlers run, `vm.sp` is raised to the deepest point the top frame can use (§9.2). Without this, when a handler set up by the caller returns to a `catch` in the same frame, the arguments of `list` that had not been written back were overwritten by the values used to call the handler; this was checked (the unit test and `p25-mid` in the language test `conditions.lisp`).
- **Differences from SBCL 2.6.7** (`tests/differential/impl-dependent.toml`): SBCL's internal types (`SB-INT:SIMPLE-PROGRAM-ERROR` and the like are `zl-sys::simple-program-error` and the like), texts that come from constant folding in SBCL's compiler (`Value of "a" in (+ "a" 1) is "a", not a NUMBER.` is the type-error text that reports the value's type in Zilisp), the toplevel restarts (RETRY, CONTINUE and ABORT of SBCL's `--script`), the text of file errors (SBCL includes the absolute path and the OS message), the description texts of errors found in Zig (Japanese), and conditions inside lists printed with `*print-pretty*` NIL.
- **Tests**: the language test `conditions.lisp` (the same output as SBCL 2.6.7; also a gc-stress version and native), and unit tests (reports of conditions that were not handled and the list of restarts, errors in the middle of a VM instruction with GC).
- **Fixes from the Codex review (Phase 25)**, six issues (each checked against SBCL 2.6.7): `cerror` inside `restart-case` evaluates its arguments in the written order; `restart-case` macroexpands its form before checking whether it is a signaling form (global macros only); control-error when an `abort` or `muffle-warning` restart returns; the sizes in `typep`'s `(vector t n)`, `(string n)` and the like are compared with the dimension, not the fill pointer; the reader advances the stream position to what it has read before signaling reader-error or end-of-file (handlers may read the stream right there; errors signaled from inside ValueBuilder, such as wrong `#A` contents, do not advance it yet); the reader-error condition holds the stream.
- **Fixes from the second Codex review (Phase 25)**, four issues (each checked against SBCL 2.6.7): errors signaled from inside ValueBuilder (wrong `#A` contents) also advance the stream position before signaling (readOp passes `ValueBuilder.sync_position`); reader-error and end-of-file from `read-from-string` hold a string input stream with the same contents and position (made only on error); `ccase` and `ctypecase` evaluate the subforms of the place once, through the setf expansion (`check-type` reads the place once per check, as SBCL does); `*debugger-hook*`, when set, is called for errors found in Zig even with no handler and no restart (the §9.4 limitation is gone).
- **Fixes from the third Codex review (Phase 25)**, three issues: `ccase` and `ctypecase` read the place only the first time and, after `store-value`, redo the dispatch with the value of the store form (as in SBCL 2.6.7); places with several store variables bind all of them with `multiple-value-bind` (missing values are NIL, as in SBCL); if allocating the stream for a `read-from-string` error fails, it returns without signaling the original error (so the recorded storage-condition is not overwritten; there is no test that makes allocation fail).
- **Fixes from the fourth Codex review (Phase 25)**, five issues (including ones that came with making `zilisp:unimplemented` not a subtype of error; each checked against SBCL 2.6.7): calling a macro or special operator as a function stays undefined-function (the unimplemented flag is also set on macros and special operators, so they are excluded); `typep` treats as unimplemented only the CLHS standard type names it cannot decide yet (`bit-vector`, `random-state`, stream subtypes, CLOS classes and the like) and element types of specialized arrays (symbols that are not types and malformed specifiers are simple-error); specifying both `:prefix` and `:per-line-prefix` to `pprint-logical-block` is simple-error, and `loop` clauses not in CLHS are program-error (only CLHS clause names that cannot be handled yet are unimplemented); `otherwise` in `etypecase` and `ctypecase` is a type specifier; added the expansion of `(setf (values place ...))` (`define-setf-expander`) and `setf` of places with several store variables (`multiple-value-bind`).
- **Fixes from the fifth Codex review (Phase 25)**, six issues (each checked against SBCL 2.6.7): `zl-sys::%bind-stores` binds the store variables with `multiple-value-bind` unless there is exactly one, and `setf`, `incf`, `decf`, `push` and `pop` use it (`(setf (values) …)` and `(incf (values a b))`). `typep` checks the form of a type specifier without looking at the value (`validate` in types.zig: ok, unimplemented or invalid): a malformed specifier (`(random-state 3)`, `(mod 0)`, `(integer 1 2 3)`, an element type that is not a type) is simple-error; a well-formed one that cannot be decided yet (`(bit-vector 3)`, a specialized element type such as `(unsigned-byte 8)`) is unimplemented; `(base-string n)`, `(simple-base-string n)` and `(complex type)` are false (there are no base strings or complex numbers). The parts of `and`, `or`, `not` and `cons` are checked only when they are used. `loop` handles every CLHS clause before the last branch, so a clause that reaches it (a misplaced `named`, a misspelling) is program-error; of the `being` kinds only the symbol kinds (CLHS 6.1.2.1.7) and `elements` (an SBCL 2.6.7 extension) are unimplemented, other names are program-error.
- **Fixes from the sixth Codex review (Phase 25)**, five issues (the code was written by Codex and checked here; each checked against SBCL 2.6.7): the `getf` setf-expander binds every store variable of the inner place with `%bind-stores`, and the `values` setf-expander takes no value for a place with no store variables (that position returns NIL). `validate` checks only the outer form of `and`, `or`, `not` and `cons` (a proper list and the number of arguments) and `typep` always calls it before deciding, while the parts are checked when they are used (`(typep 1 '(or fixnum car))` stays T); `completeType` checks the parts too and is used for array element types and the argument of `complex`. The bounds of `integer` must be integers, of `rational` rationals, of `single-float`/`short-float` single floats, of `double-float`/`long-float` double floats, and of `float` and `real` any real (SBCL also accepts `(float 1 3)`). The argument of `complex` is `*` or a subtype of `real` (`realSubtype`).
- **Fixes from the seventh Codex review (Phase 25)**, three issues (each checked against SBCL 2.6.7): `incf` and `decf` (`zl-sys::%expand-incf`) evaluate the place's subforms, then the delta (into a temporary unless it is a number), then read the place, so a delta that changes the place adds to the new value. The argument of `complex` is rejected only when it is surely not a subtype of `real` (`surelyNotReal`: a type that is not real, an `or` with such a part, `not`, `eql`/`member` of a non-number, `(and)`); other `and` forms and `satisfies` are accepted, since an intersection can be empty or real and Zilisp has no complex numbers anyway. The element type `base-char` is false for every array (Zilisp strings always have element type `character`, like `base-string`).
- **Codex review fixes (Phase 25, eighth round)**, 2 issues (both checked against SBCL 2.6.7): `surelyNotReal` is replaced by `realness`, which returns yes (surely a subtype of `real`), no (surely contains a non-real) or unknown. Real type names and `nil` are yes; other atoms are no. `and` drops `t`: no parts is `t` (no), one part is that part, and otherwise it is yes if some part is yes and unknown if not. `or` is no if some part is no and yes if all parts are. `(not (not X))` is X, `(not t)` is yes, `not` of an atom or of a compound type other than `and`/`or`/`satisfies` is no (such a type never contains every non-real), and otherwise `not` is no for a yes part and unknown if not. `eql`/`member` is yes when every element is real and no if not, and `satisfies` is unknown. No is a `simple-error`; unknown signals `zilisp:unimplemented`, so empty intersections such as `(complex (and string symbol))` are unimplemented (SBCL returns NIL; telling disjoint types apart needs `subtypep`).
- **Codex review fix (Phase 25, ninth round)**, 1 issue (checked against SBCL 2.6.7): `realness` of a `cons` type is yes when a part is `nil` (the type is empty), no when both parts are surely non-empty (`*`, an atom other than `nil`, or a type whose `realness` is no), and unknown otherwise. A compound `complex` type is no only for `(complex)` and `(complex *)`; otherwise it is unknown, since `(complex nil)` and `(complex (integer 0 0))` are empty in SBCL.
- **Codex review fix (Phase 25, tenth round)**, 1 issue (checked against SBCL 2.6.7): `zl-sys::%find-restart-or-lose`, used by `invoke-restart` and `invoke-restart-interactively`, accepts a restart object when it is in `zl-sys::*restart-clusters*` (`zl-sys::%restart-active-p`) and does not call its `:test` again; calling it without the condition rejected a restart found with `(find-restart name condition)`, which also broke `continue`, `store-value` and `use-value` with a condition. A name is still looked up with `find-restart`, so its `:test` receives NIL, as in SBCL. Invoking a restart object after leaving its `restart-case` signals a control-error in Zilisp (restarts have dynamic extent, so the result is undefined; SBCL 2.6.7 reports a memory fault), and this is tested in `eval_test.zig`, not in the language tests.
- **Codex review fix (Phase 25, eleventh round)**, 1 issue (checked against SBCL 2.6.7): `assert` binds the arguments of the test form to temporaries (to report their values) only for a function call. Special operators are `fboundp` in Zilisp, so `(assert (if t t (incf n)))` evaluated the branch not taken and `(assert (let ((x 1)) (= x 1)))` evaluated `((x 1))` as a form; the test now also requires `(not (special-operator-p op))`. `special-operator-p` is a new primitive (`functions.specialOperatorP`) that reads the `special_operator` flag of the symbol; the external symbols of CL for which it is true are the same 25 as in SBCL 2.6.7.
- **Codex review fix (Phase 25, twelfth round)**, 1 issue (checked against SBCL 2.6.7): a symbol given to `:report` in `define-condition` was stored quoted, so printing always called the global function. CLHS says `(function report-name)` is evaluated in the current lexical environment, so a local function of `flet` or `labels` must be found. The macro now expands a symbol to `(lambda (c s) (funcall (function name) c s))`: inside the lambda, `function` refers to the local function if there is one, and otherwise looks up the global function when it is called (so a function defined after the `define-condition` form still works, as in SBCL).
- `*break-on-signals*` is left to the debugger phase (tque #351, which starts by studying what kind of debugger to build).
- Results (acceptance: the main code of Level 13): of the 33 blocks of Level 13, apart from those where both end with an error (examples that show errors, fragments), all give the same output as SBCL 2.6.7 except one with the text of a file error (L455; implementation-dependent) and one that calls `get-universal-time`, which is not implemented yet (L704; since `zilisp:unimplemented` is not an `error`, `ignore-errors` does not catch it). Curriculum blocks matching went from 478 to 513 (L455 is the only output difference). No block fails only in Zilisp because of conditions any more. Startup time is 13.55 ms (boot.lisp grew from 1192 to 1933 non-blank lines).

---

## 3. Heap and GC: page management, roots, FFI handles (D-8, D-9)

### 3.1 Heap structure

```text
Heap = regions obtained from the OS in large units, divided into fixed-size pages
 ├─ cons pages        : filled in 16-byte units
 ├─ size-class pages  : objects of 16, 32, 48, 64, 96, 128, … bytes placed in per-size pages
 └─ large objects     : dedicated page runs (aligned to page boundaries)
Page table (outside the heap)
 └─ per page: stored size, mark bit table (1 bit per 16 bytes), in-use bit table, head of free space
```

- The page size is decided by measurement (initial plan 32 KiB; measurements comparing different sizes are done in P39). For reference, SBCL's x86-64 version also uses 32768 bytes (`src/compiler/x86-64/parms.lisp` line 33 `gencgc-page-bytes`).
- **Allocation**: each size class has a "current page", and free space in it (contiguous regions built from the free bit table) is taken from the front. While free space is contiguous, allocation only advances a pointer.
- **GC trigger**: when the bytes allocated since the last GC exceed a threshold. The initial plan for the threshold is max(8 MiB, bytes live after the last GC × 2), adjusted by measurement. **The allocated byte count also includes growth and shrinkage of buffers that objects allocate separately and own (string buffers, hash table arrays, bignum limbs, etc.)** (review #18; this prevents memory from growing without GC when a small header owns a large buffer).
- A GC can happen only at the point of allocation from the managed heap.

### 3.2 Mark and sweep

- Marking uses an explicit mark stack (so that the Zig stack does not overflow even on deep lists).
- Mark bits are recorded in the page table's bit table. A cons has no header, so nothing is written inside the object.
- **Lazy sweep**: at GC time only marking is done. Page sweeping (comparing in-use bits with mark bits) is done at the next allocation in that size class. This shortens pause times.
  - **Before starting the next GC, sweep all pages that have not been swept** (review #18). This lets the mark bits be reused in the next GC without mixing with the results of the previous GC.
- **Objects that hold internal resources** (string buffers, hash table arrays, bignum limbs, OS handles of file streams, foreign_pointers with the ownership flag) are registered in a "pending finalize list" separate from the pages (review #18). When marking ends, only this list is scanned, and the resources of unmarked entries are freed on the spot. Even with delayed page sweeping, resources are freed at every GC.
- User-defined finalizers and weak references are not supported in 1.0. File streams left open are closed at each GC by the procedure above, and a warning is issued if the debug option is enabled.

### 3.3 Root kinds and scan methods

| Root | Scan method |
|---|---|
| References between objects in the heap | **Precise** (follows the per-ObjKind layout) |
| VM value stack, frames, multiple-value registers | Precise |
| Dynamic binding stack, control stack, handler/restart stacks | Precise |
| All packages, class table, generic function caches | Precise |
| FFI handle table, explicitly registered roots (§3.5), list of objects lent to C (§3.6) | Precise |
| State of in-progress non-local exits (the `Transfer` value and saved multiple values in §6.4) | Precise |
| **Native stack** (frames of the Zig runtime and of native code) | **Conservative** |
| **CPU registers** | **Conservative** (at GC start, the values of callee-saved registers are read and scanned; §3.4 step 1) |

### 3.4 Conservative scan procedure

1. In the function that starts the GC (`gc.scanStack`), read the values of the callee-saved registers with inline assembly, and check each value in the same way as in step 2 below (fixed in Phase 07).
   - x86_64: `rbx` `rbp` `rdi` `rsi` `r12` to `r15` (`rdi` and `rsi` are callee-saved on Windows). On Windows, also the low 64 bits of `xmm6` to `xmm15`.
   - aarch64: `x19` to `x29` and `d8` to `d15`.
   - Read them using register output constraints (`"={rbx}"`). Memory operand forms (`0(%[r])`) cannot be used with Zig's x86_64 code generator. The frame pointer (`rbp`, `x29`) cannot be specified, so it is read with a `mov` instruction (`docs/zig-std-usage.md` §2).
2. For each word from the top of the thread's stack (the position recorded at startup) to the **current stack pointer** (read with inline assembly; the address of a local variable is not used), do the following checks.
   1. Is the untagged address within the heap range?
   2. Look up the page table and compute the start of the object from the page's size class (`start = page start + ⌊(addr − page start) / size⌋ × size`; for large objects, the start of the page run). **A pointer into the middle of an object is also treated as a reference to that object.**
   3. If the in-use bit is set, mark it.
3. Scanning inside the heap is precise, so only objects pointed to directly from the stack and registers are treated conservatively.

**How the stack top is determined (fixed in Phase 07)**
- Windows: use `NtTib.StackBase` of the thread information block (TEB) (`std.os.windows.teb()`).
- Other than Windows: use the `@frameAddress()` recorded at the start of `main` (`runtime.main_stack_top`). `main` itself holds no Lisp values, and all Lisp values are in frames below it (callees).
- **Do not use the `@frameAddress()` of a function that itself holds Lisp values as the top.** In optimized builds, that function's local variables may be placed at addresses higher than `@frameAddress()`, fall outside the scan range, and be collected (confirmed in Phase 07 tests with ReleaseSafe and ReleaseFast). In tests, separate the outer function that records the top from the inner function that handles values (`@call(.never_inline, …)`).
- Addresses kept by tests to check that "it was collected" are stored bit-inverted. If stored as-is, the conservative scan treats them as pointers and the objects are not collected.

- **Advantage of this method**: native code and the Zig runtime do not need to register Lisp values held in local variables with the GC. There is no shadow stack cost (registering and unregistering values). However, the following "liveness contract" must be kept.
- **Disadvantage of this method**: if an integer happens to look like a heap address, an unneeded object may be retained. This is monitored with GC statistics.
- **Requires a non-moving GC**: conservatively referenced objects cannot be moved. If a moving GC is adopted, it is a method that pins only conservatively referenced objects (mostly-copying) (basic design §5.2).
- **Relation to compiler optimization**: optimization of native code may remove a pointer to an object from both the stack and registers (for example, when only a derived value of the pointer remains). Treating interior pointers as references cannot prevent the case where no address within the object's range remains. **Passing stress tests does not guarantee safety under other optimization results** (review #1).

**Liveness contract (review #1)**

For the conservative scan to work correctly, native code and the runtime's Zig code follow these rules.

1. **A Lisp value used after a call that can cause a GC** (allocation from the managed heap, a Lisp function call, a runtime function that can cause a GC) **is kept in `Value` form (a tagged word) across that call.** Do not write (runtime Zig code) or generate (native backend) code that keeps only a pointer to a field inside the object or a pointer to the end of an array and drops the original `Value`.
2. The native backend generates a `Value` used after a call that can cause a GC as a variable that stays live until after that call. To guarantee it is not optimized away, a means of moving the value outside the optimization boundary (an equivalent of Zig's `std.mem.doNotOptimizeAway`; the means is to be verified) is placed **after the call that can cause a GC, immediately after the last use of that value (and of pointers taken from it)** (agy #3; if placed before the call, and the value is not used after the call, the slot holding the value may be reused at the time of the call).
2a. **Rule for derived pointers** (agy #3): pointers taken from a `Value` (pointers to object fields, and pointers and slices into **separately allocated buffers**: string contents, hash table arrays, bignum limbs, etc.) are **not held across a call that can cause a GC**. If needed after the call, take them from the `Value` again.
   - Reason: separately allocated buffers are outside the heap pages, so even if a pointer to the buffer remains on the stack, the owner object is not marked. If the owner is collected, the buffer is also freed by the procedure in §3.2, and freed memory is then used.
   - From the Zig compiler's point of view, using a derived pointer does not count as using the original `Value`. So contracts 1 and 2 alone are not enough, and this rule is needed.
3. In the page range check, an address just past the end of an object is not treated as a reference to that object (it cannot be distinguished from the next object). By contract 1, code in which only such an address remains is not created.
4. The contract is not only documented as rules but also checked by the following: `--gc-stress` on generated code with ReleaseFast, inlining, and link-time optimization (LTO) enabled; runs on each ABI of Windows, Linux, and macOS; and adding it to the review points for the runtime's Zig code.
5. If measurement or verification shows the contract cannot be met, use explicit roots (§3.5) only in the affected places.
6. In Phase 07 and Phase 12, measure and compare the speed of this method (conservative scan and the contract) against precise root management with a shadow stack (agy #3).
- **Comparison with SBCL**: SBCL's x86-64 version also scans the stack and registers conservatively and pins the referenced objects (confirmed: `src/runtime/gencgc.c` lines 1335 to 1341; in SBCL 2.6.7 the feature `:c-stack-is-control-stack` is enabled, and the condition at `genesis.lisp` line 3163 makes `GENCGC_IS_PRECISE` 0). However, SBCL does not treat interior pointers as references except for code objects. SBCL can control the shape of the code its own compiler generates, but Zilisp cannot control the code generated by Zig and LLVM, so it also treats interior pointers as references.

### 3.5 Explicit root registration API

Register explicitly only when a Lisp value is held in a place other than the native stack (structs on the Zig heap, static variables, etc.).

```zig
// When holding a Lisp value in a struct on the Zig heap
const h = try rt.roots.register(value);  // h.get() stays valid during GC
defer rt.roots.unregister(h);
```

**Rules (code review points)**
1. Lisp values held in local variables and arguments need no registration as long as the "liveness contract" in §3.4 is kept (they are covered by the conservative scan).
2. Lisp values held in structs on the Zig heap, static variables, or structs passed to C libraries must always be registered.
3. Pass an FFI handle to the C side, not the address of a Lisp object (§3.6).

### 3.6 FFI handles

- A **handle** is passed to the C side. The handle table is part of the roots and keeps the target until `(zilisp-ffi:free-handle h)` is called.
  - A handle is a pair of "table index" and "generation number". Using a freed handle, or an old handle after its index has been reused, is an error (review #12).
- **Lending buffers to C** (review #12)
  - Lending is done in a limited scope with the form `(zilisp-ffi:with-borrowed-buffer (ptr obj) …)`. A lent object is registered in the "lent list" (part of the roots; §3.3) and managed with a reference count.
  - **While lent, operations that recreate the buffer are prohibited.** Examples: storing a character above #xFF with `setf` into a 1-byte-wide string (§2.5), resizing an adjustable array. Performing a prohibited operation signals an error.
  - If the C side needs to hold the buffer for a long time, pass a copy of the buffer outside the managed heap (the caller frees the copy explicitly).
- The detailed FFI design (reentry from callbacks, calls from other threads: see the note in §6.1) is written separately as `docs/ffi.md` in Phase 31.

### 3.7 Diagnostics

- `--gc-stress`: run a GC on every allocation.
- poison (debug builds): fill swept areas with 0xAA.
- Statistics: GC count, pause time (ns), allocated bytes, live bytes, number of references found by the conservative scan. Shown with `(zilisp:gc-statistics)` and `--gc-stats`.

---

## 4. Source location information

### 4.1 Data structure (fixed)

```zig
pub const SourceLoc = extern struct {
    file: u32,   // index into Runtime.source_files. 0 means "unknown"
    line: u32,   // 1-based
    col: u32,    // 1-based (in characters)
};
```

- The Reader records locations in a `SourceMap` keyed by the identity (address) of each cons it reads. Atoms get no location.
- The `SourceMap` is discarded when processing of **the top-level form that the Reader read in one `read`** (including splitting by the top-level processing in §16.1) ends (agy #6). Only the location tables remain in the compiled result (VM: pc → SourceLoc; native: §7A.5).
- Conses newly created by macro expansion have no location. The compiler inherits the location of "the nearest enclosing form that has a location".
- Input from the REPL is assigned `file = <repl>`, and the input's sequence number is used instead of the line number.

### 4.2 Uses

- Compile-time warnings and errors: in the form `file:line:col: warning: ...`.
- Runtime backtraces: VM frames are looked up from the pc, native frames from the function name and the location table.
- `.zfasl` stores the location table and the file name table (§14).

---

## 5. Compiler pipeline and Core IR

### 5.1 Pipeline (D-1, D-7, D-10)

```text
Form (Value)
  │ macroexpand (local/global macros, symbol-macro)
  ▼
Resolver: name resolution, special declarations, computation of captured / assigned
  ▼
Core IR (on an ArenaAllocator. Discarded after each top-level form)
  │ Type inference, applying declarations (type, optimize, inline), constant folding
  ▼
  ├─▶ Native backend (main path): IR → Zig source → LLVM (used for zilisp build and for building the standard library. The input is **the in-memory Core IR**. From Phase 35, Core IR saved in `.zfasl` can also be the input: agy #8)
  ├─▶ Background native (Phase 39): IR → Zig source → shared library built by Zig in a separate process → load it and replace the entry (REPL, eval, load. §7A.6)
  └─▶ Bytecode backend: IR → bytecode (the path for immediate execution in REPL, eval, load. In environments without Zig, only this path is used)
```

- **No evaluator (AST/IR interpreter) is built** (D-1). `eval` also always compiles before it executes.
- The three backends take the same Core IR as input and run on the common foundation of §6 (calling convention, control stack, dynamic binding). They can call each other's functions.
- Semantic equivalence is checked by running all language tests on both the VM and native code.

### 5.2 Core IR nodes (initial version)

```zig
pub const Node = union(enum) {
    constant: Value,
    lex_ref: *Var,                 lex_set: struct { v: *Var, value: *Node },
    special_ref: Value,            special_set: struct { sym: Value, value: *Node },
    global_fn: Value,              local_fn: *FnBinding,
    call: struct { callee: *Node, args: []*Node },
    call_global: struct { sym: Value, args: []*Node, same_file: ?*LambdaInfo },
    prim: struct { op: PrimOp, args: []*Node },
    if_: struct { cond: *Node, then: *Node, else_: *Node },
    progn: []*Node,
    let_: struct { bindings: []Binding, body: *Node },
    lambda: *LambdaInfo,
    labels: struct { fns: []*FnBinding, body: *Node },
    block: struct { b: *BlockInfo, body: *Node },
    return_from: struct { b: *BlockInfo, value: *Node },
    tagbody: struct { t: *TagbodyInfo, segments: []Segment },
    go: struct { t: *TagbodyInfo, index: u32 },
    catch_: struct { tag: *Node, body: *Node },
    throw: struct { tag: *Node, value: *Node },
    unwind_protect: struct { protected: *Node, cleanup: *Node },
    mv_call: struct { callee: *Node, args: []*Node },
    mv_prog1: struct { first: *Node, rest: *Node },
    progv: struct { syms: *Node, vals: *Node, body: *Node },
    load_time_value: struct { form: Value, read_only: bool },
    the: struct { type: TypeId, value: *Node },
};
// Every node has an inferred type `ty: TypeId` and a SourceLoc
```

- `defun` is expanded directly by the Resolver as a bootstrap macro written in Zig (item 6 of §11.1) (Phase 10). `(defun name lambda-list body…)` becomes `(zl-sys::%defun 'name (lambda lambda-list body…))`, and the lambda is given the function's name (printed as `#<FUNCTION name>`, the same as SBCL 2.6.7). Wrapping the body in `(block name …)` is added in Phase 18, which implements `block`. Defining a function on a symbol of the COMMON-LISP package is a `package-error` (CLHS 11.1.2.1.2. In SBCL it is a package lock error). Even after the macro expander (Phase 15) exists, `defun` expands to this form.
- `flet`, `labels` (Phase 11): Resolver scopes hold function-namespace bindings (a name, and a hidden local variable that holds the function value). `flet` produces the same IR as `(let ((f (lambda …)) …) body)`, and `labels` the same IR as `(let ((f nil) …) (setq f (lambda …)) … body)`. In `labels`, the variables of functions that refer to each other (or to themselves) are captured and assigned, so they go into a value_cell. Local functions take precedence over global functions and macros (CLHS 3.1.2.1.2.3). Symbols of the COMMON-LISP package and names of special operators cannot be local functions (`program-error`, the same as SBCL 2.6.7). Wrapping the function body in `(block name …)` is added in Phase 18.
- **Macro expansion** (Phase 15): if the head of a form is a macro symbol, the Resolver calls the macro function with `(form env)` to expand it, and resolves the result (local functions take precedence over macros. Special operators are checked before macros). The expansion of a top-level form is also top-level (CLHS 3.2.3.1). Expansion results and forms created by the Resolver are pushed onto Pins (§5.4). In Phase 15, the environment argument is always NIL (the global environment).
- **defmacro**: becomes `(zl-sys::%defmacro 'name (lambda (#:whole #:env) (let ((#:args (cdr #:whole))) (let* (destructuring bindings…) body…))))`. A top-level `defmacro` is also defined at compile time (so that later forms in the same file and native backend code generation can expand it). A macro function prints as `#<FUNCTION (:MACRO name) {…}>`.
- **Destructuring binding** (lambda lists of `defmacro` and `destructuring-bind`. CLHS 3.4.4, 3.4.5): required, `&optional` (default values, supplied-p variables), `&rest`, `&body`, dotted tail, `&key` (`((:k v) …)`, `&allow-other-keys`, `:allow-other-keys t`), `&aux`, `&whole`, `&environment`, and nested lambda lists are turned into a sequence of `let*` bindings. Wrong argument counts, an odd number of keyword arguments, and unknown keywords are `program-error`.
- **backquote**: `zl-sys:quasiquote` is turned into calls to `list`, `list*`, `append`, `(apply #'vector …)` (CLHS 2.4.6). Parts without unquote become `quote` (they may be shared: CLHS 2.4.6). `,.` is the same as `,@`: it splices without destroying. Nested backquotes are handled by counting the depth.
- **Not implemented in Phase 15** (removed from the original plan of §5.2. Done in Phase 30: tque #341): `macrolet`, `symbol-macrolet`, `define-symbol-macro`, environment objects (the value of `&environment`. Currently NIL), `compiler-macro`. Uses in curriculum blocks: 0 (as of Phase 15).
- **setf** (Phase 16): written in Lisp in `src/lisp/boot.lisp`. A place expansion is represented by the five elements of CLHS 5.1.1.2 (temporary variables, value forms, store variables, store form, access form), and is returned as a list until Phase 17 adds multiple values (`zl-sys::%setf-expansion`. `get-setf-expansion` and `define-setf-expander` are Phase 17). Expansion order: place expander (defined with `defsetf` and stored in the symbol property `zl-sys::setf-expander`) → macro expansion → setf function (`(funcall #'(setf name) value args…)`). `incf`, `decf`, `push`, `pop` are built on the same expansion (subforms of the place are evaluated only once, from left to right: CLHS 5.1.2). `(defun (setf name) …)` is stored in the symbol's `setf_function` field, and `#'(setf name)` is read with the VM instruction `LOAD_SETF_FUNCTION`.
- **Processing of top-level forms in eval** (Phase 16): the VM's `eval` compiles and executes, one at a time, the forms inside a top-level `progn`, macro expansion results, and `eval-when` (`:execute`) (the same as SBCL 2.6.7's eval. In `(progn (defsetf f g) (setf (f x) 1))`, the second form is expanded after the first is executed).
- **eval-when** (Phase 16): in eval semantics (VM), only `:execute` is considered. In compile-file semantics (native backend), at top level, `:compile-toplevel` evaluates the body on the spot, and `:load-toplevel` treats the body as a top-level `progn` (CLHS 3.2.3.1). `defsetf` expands to `(eval-when (:compile-toplevel :load-toplevel :execute) …)`.
- `let*` is represented as nested single-variable `let_` nodes (Phase 09). Each initial value is resolved in a scope where the earlier variables are visible. Unlike `let`, the same variable name may be bound twice (the later binding shadows the earlier one. Verified with SBCL 2.6.7). Local variable numbers of `let` and `let*` variables are reused after leaving the body (a closure captures the value at creation time or a value_cell, so it is not affected by number reuse).
- `Var` has `captured` and `assigned`. Only variables for which both are true are put into a `value_cell` (assignment conversion).
- `Var` and `Node` have an inferred type (`TypeId`: fixnum, double-float, cons, simple-vector, `t`, etc.). The native backend omits boxing and type checks according to the type (§7A.3).
- `BlockInfo` / `TagbodyInfo` have `nonlocal` (exited from an inner closure). When it is false, the exit becomes a jump.
- The 25 special operators of CL are interpreted directly by the Resolver.
- `prim` (inlining) applies only to functions of the CL package, and only when they are not locally shadowed by `flet` / `labels` (redefining a CL package function is undefined behavior: CLHS 11.1.2.1.2).
- **Direct calls to CL package functions** (agy #11): for the same reason, CL package functions that are not inlined (`format`, `mapcar`, `sort`, etc.) are also called through their native entry directly, without going through the function cell (except when locally shadowed by `flet` / `labels`).
- **`&environment` and `define-symbol-macro`** (agy #15): `&whole` of `defmacro` was implemented in Phase 15. The value of `&environment` (the `environment` object of §2.4; NIL for now), `define-symbol-macro` (the symbol flag `global_symbol_macro`) and `symbol-macrolet` were originally planned for Phase 15 but are done in Phase 30 (see "Not implemented in Phase 15" above; tque #341).
- `call_global.same_file`: a call to a function defined in the same file. Unless `notinline` is declared, the native backend may make it a direct call (within what CLHS 3.2.2.3 permits).

### 5.3 Declarations and safety

| Declaration | Handling |
|---|---|
| `(declare (type …))` / `the` | With `safety` ≥ 1, the type is checked and then trusted. With `safety` 0, it is trusted without checking |
| `(optimize (speed n) (safety n) (debug n))` | The default is `speed 1 safety 1 debug 1`. With `safety 0`, argument count and type checks are omitted |
| `inline` / `notinline` | Respected |
| `dynamic-extent` | In 1.0, used by the native backend for stack allocation of closures and `&rest` lists (implemented later) |

**With `safety` ≥ 1, a type error always becomes a condition such as `type-error`** (basic design §3.1: never silently return a different value).

### 5.4 GC safety at compile time

Macro expansion results and top-level forms are held in the compiler's working structures (on the Zig heap), so they are registered with the API of §3.5. Constants held by the IR are kept reachable from the registered forms.

### 5.5 ValueMode

For each expression, the compiler generates code with a specified way of receiving the result: `ValueMode = single | multiple | discard`.

**Phase 17 implementation**
- The last expression of a function body is in a multiple position. In a multiple position, a function call uses the count written by the called function as is, `values` writes the count, and `if`, `progn`, `let`, `multiple-value-bind`, `multiple-value-prog1` propagate multiple to their inner expressions. Any other single-valued expression sets the count to 1 (VM instruction `SINGLE`. In native code, `th.mv_count = 1`). A primitive's entry sets the count to 1 before calling the body (primitives that return multiple values rewrite it in the body. Primitives that call functions from a Zig function reset the count to 1 before returning).
- VM instructions: `VALUES n`, `SINGLE`, `MV_LIST` (list of all values), `MV_PUSH_N n` (push n values), `MV_RESTORE` (turn a list back into multiple values). `multiple-value-prog1` saves the values of the first form into a list and restores them. `multiple-value-call` becomes `(apply f (append (multiple-value-list …) …))` (this involves allocation. If speed becomes a problem, it becomes a dedicated instruction).
- The REPL prints every value, one per line (`(values)` prints nothing. The same as SBCL 2.6.7).
- **&optional, &rest, &key, &aux**: the arguments after the required arguments are collected by the VM (in native code, by the generated code) into an unnamed argument list, and that list is bound to variables by destructuring binding (§5.2, the same mechanism as Phase 15). In a call that omits the optional arguments, the list is NIL, so nothing is allocated. A call that passes keyword arguments creates the list on every call (speed improvements are for a later Phase, to be considered together with the fast entry of §7A.3).

---

## 6. Common runtime foundation: calling convention, multiple values, non-local exits, dynamic binding

The VM and native code share the structures of this chapter.

### 6.1 Thread state

```zig
pub const Thread = struct {
    mv: [MV_LIMIT]Value,         // Multiple-value registers (MV_LIMIT = 1024). mv[0] is unused (the primary value is the return value)
    mv_count: u32,               // Number of values returned most recently (§6.2)
    fault: Fault,                // Reason when the return value is Value.unwind (§6.6)
    bindings: []Binding,         // Dynamic binding (shallow binding)
    control: []ControlEntry,     // block / tagbody / catch / unwind-protect
    handlers: []HandlerCluster,
    restarts: []RestartEntry,
    unwinds: []Transfer,         // Stack of in-progress non-local exits (§6.4. A stack, to support nested exits)
    stack_base: usize,           // Start position of the conservative scan
    vm: Vm,                      // VM value stack and frames (§7)
};
```

1.0 is single-threaded. `Thread` is a struct to prepare for future multithreading.

**Constraints from being single-threaded (review #19)**
- When a callback from a C library re-enters Lisp **from the same thread**, the re-entry point saves the contents of the multiple-value registers and restores them on return. A Lisp non-local exit from a callback across C frames is forbidden and is converted to `control-error` at the boundary (so that cleanup of C frames is not skipped).
- Callbacks **from another thread** (such as a thread created by an external library) are rejected in 1.0 (return an error, or stop the implementation). Details are defined in `docs/ffi.md` (Phase 31).

### 6.2 Calling convention (final)

Every function object (`closure`, `native_function`, `generic_function`) has an **entry address** at its head.

```zig
// Generic entry (the same type for all function objects)
pub const Entry = *const fn (th: *Thread, self: Value, args: [*]const Value, nargs: u32) callconv(.c) Value;
// Fast entry (fixed number of arguments. Used within the same compilation unit. Example: 2 arguments)
//   fn (th: *Thread, a: Value, b: Value) Value
```

**Return value convention (Option A. Decided 2026-11-01. Confirmed by measurement in Phase 12)**

- **The return value is only the primary value `Value` (`enum(u64)`)**, returned in a register. When there are zero values, the primary value is NIL.
- **The number of values is written to `th.mv_count`.** The second and later values are written to `th.mv[1..]`.
  - To keep the count correct, **a function writes `th.mv_count` every time it returns** (it writes 1 when returning a single value). However, when the return value is exactly the return value of a function call in tail position, the count written by the callee can be used as is, so it is not written.
  - The caller reads `th.mv_count` and `th.mv` only where multiple values are needed (such as `multiple-value-bind`; the `multiple` mode of §5.5). In single-value positions, only the return value is used.
- **Non-local exits and errors are represented by returning the special immediate value `Value.unwind` (§2.2).** The reason is placed in `th.fault` (§6.6). On every call, the caller compares whether the return value is `Value.unwind` (one comparison of a register with a constant), and if so, it also returns `Value.unwind` (§6.4).
- **Why this convention**: in Zig 0.17.0, `Error!Ret`, types containing errors, and 16-byte structs are returned through memory on all of x86_64-windows, x86_64-linux, and aarch64-macos. A 16-byte struct with `callconv(.c)` is returned in registers on Linux and macOS, but through memory on Windows, the primary development target. Only an `enum(u64)` value is returned in a register on all three targets (`docs/zig-std-usage.md` §3).
- Reference: Clasp returns the primary value and the count in registers (`include/clasp/core/lispCallingConvention.h` lines 36-46). Because Zilisp's convention writes the count to a field of `Thread`, it adds one memory write per return. This cost is measured in Phase 12.

**Kinds of calling conventions**

- **The generic entry uses `callconv(.c)`.** This lets VM closures, native code, and functions in separately compiled shared libraries (§7A.6) have entries of the same type. With the C calling convention, a `u64` return value is returned in a register (`rax` / `x0`) on all three targets.
- **The fast entry uses Zig's default calling convention**, and is used only within the same compilation unit (direct calls within the same file, inline expansion).
- The cost of making the generic entry `callconv(.c)` (such as the 32-byte area reserved on Windows x64 calls) is measured in Phase 12 against the default calling convention.

**Boundary with separately compiled shared libraries** (review #11)
1. Only the `callconv(.c)` generic entry above and the initialization entry cross the boundary. Arguments and return values are only `Value` (`u64`), pointers, and integers.
2. An **ABI version number** is attached to the layout of `Value` and `Thread`, the order of the runtime function table, and the format of the constant table. The initialization entry of a shared library first checks the version number, and refuses to load if it does not match (execution stays on the VM).
3. Fast entries inside a shared library are used only within that shared library.
- The entry of a **VM closure** is a trampoline that starts the VM dispatch loop. Every time it is called, the trampoline checks whether the closure's code has a native entry, and if so, calls it (§7A.6, agy #1). When a VM closure is called from inside the VM, the trampoline is not used, and a frame is pushed within the same dispatch loop (the native entry of the code is checked in this case too).
- **Handling of received arguments** (agy #9): at the start of the function, the generic entry copies `args[0..nargs]` into local variables (and the `&rest` list if needed), and does not refer to `args` after that. This keeps it safe even if the area that `args` points to (the caller's area, or the argument area for tail calls: §7A.3) is overwritten by a later call.
- **Native code** is generated as a Zig function per function, and its entry address is placed in the function object. For functions with a fixed number of arguments, a **fast entry** that receives arguments in registers without an array is also generated (used from direct calls within the same file and from inline caches).
- A global function call refers to the symbol's function cell every time (so a redefinition takes effect immediately). In native code, the function cell lookup and the entry call are combined into one indirect call.
- **Symbol fast entry** (agy #11. An idea equivalent to SBCL's FDEFN): a symbol has a **fast entry** field for calls with a fixed number of arguments (§8.1). This field is updated every time the function is defined or redefined. When the function is undefined, when it is a VM function, or when the argument count does not match, the field holds a **trampoline that falls back to the generic path**. This lets the caller call the fast entry with one indirect call, without a cache check. Whether this is faster than the inline cache of §7A.3 is measured in Phase 12, and the faster one is adopted.
- The rules for argument parsing (required, `&optional`, `&rest`, `&key`) follow CLHS 3.4.1. A wrong count, an odd number of keyword arguments, and unknown keywords signal `program-error`. When the same keyword appears more than once, the leftmost one is used.

### 6.3 Multiple values

- The primary value is the return value, the count is in `th.mv_count`, and the second and later values are in `th.mv[1..]` (§6.2).
- `th.mv` is overwritten by the next call to a function that returns multiple values. **Processing that calls another function after values have been returned** (`multiple-value-prog1`, `unwind-protect` cleanup, `handler` calls, etc.) saves all values to the stack or to a `Transfer` (§6.4), and restores them when done.
- `multiple-value-prog1`: saves all values of the first form, and restores them after evaluating the remaining forms.
- `multiple-value-call`: concatenates all values of each argument form in order, and passes them to the function.

### 6.4 Non-local exits

**Control stack entries**

```zig
pub const ControlEntry = struct {
    kind: enum { block, tagbody, catch_tag, unwind_protect, native_frame },
    token: Value,          // Identifier of block/tagbody, or catch tag
    binding_depth: u32,
    handler_depth: u32,
    restart_depth: u32,
    resume: Resume,        // VM: frame number, sp, ip. Native: unused (code that receives Value.unwind checks whether it is the target; Phase 18 implementation)
};
```

**State of an in-progress exit** (review #3)

```zig
pub const Transfer = struct {
    target: u32,              // Control stack entry number of the exit target
    values: []Value,          // All values carried by the exit (including the primary value. Copied from the multiple-value registers)
    tag_index: u32,           // Tag number for go
};
```

- A `Transfer` is pushed onto `th.unwinds` **as a stack**. Its values are scanned precisely as GC roots (§3.3).

**Method (common to the VM and native code)**

- A non-local exit (`return-from`, `go`, `throw` when the exit target is in another frame) determines the target entry, pushes onto `th.unwinds` a `Transfer` with copies of all carried values, sets `th.fault = .unwind`, and leaves functions one by one **by returning the special value `Value.unwind`** (§6.2).
- In native code, `block`, `tagbody`, and `catch` push an entry, and when the call to the body returns `Value.unwind`, they check "is `th.fault` `.unwind`, and is the target at the top of `th.unwinds` this one?" If it is, they remove the `Transfer`, receive the values, and continue. If not, they return `Value.unwind` as is.

**`unwind-protect`** (review #2, #3)

The cleanup runs **however control leaves** the protected form.

| Way of leaving | Steps |
|---|---|
| Normal completion | Save **all values** of the protected form → run the cleanup → restore all values and return |
| Non-local exit to another frame (`Value.unwind` returned) | Run the cleanup (the `Transfer` at the top of `th.unwinds` and `th.fault` are saved and kept) → return `Value.unwind` again to continue the exit |
| A jump within the same function (`return-from`, `go`) that crosses the cleanup's scope | Before the jump, run all crossed cleanups in order from the innermost, and undo the crossed dynamic bindings (below) |

- **Dynamic environment when the cleanup runs** (agy #2. CLHS 5.2 "Transfer of Control to an Exit Point"): the cleanup runs in the dynamic environment at the time the `unwind-protect` was entered. Therefore, for every way of leaving, **just before** running the cleanup, the dynamic bindings, handlers, restarts, and catch tags created inside the protected form are unwound to the depths recorded in that `unwind_protect` entry (`binding_depth`, `handler_depth`, `restart_depth`). Bindings and the like outside the `unwind-protect` (between it and the exit target) remain in effect while the cleanup runs. When an exit passes through several `unwind-protect`s, "unwind the depths → run the cleanup" is repeated from the innermost.
- **Exits that occur inside a cleanup**
  - An exit that occurs inside a cleanup and **is caught inside the cleanup** (its target is a `catch` or `block` inside the cleanup) is pushed as a new `Transfer` and removed when caught. The outer in-progress exit (the `Transfer` below) is **not cancelled**. When the cleanup finishes, the outer exit continues.
  - Only an exit that occurs inside a cleanup and **leaves the cleanup** replaces the outer in-progress exit. In this case, the outer `Transfer` is removed, and the exit continues with the new `Transfer`.
  - This distinction is made by comparing the target's entry number with the number of the `unwind_protect` entry whose cleanup is running.
- Inside a cleanup, `th.mv` is overwritten by function calls, so the carried values are always taken from the `Transfer` or the save area (§6.3).
- Basis: the CLHS definitions of `unwind-protect`, `throw`, and `multiple-value-prog1`, and 5.2 "Transfer of Control to an Exit Point".

**Jumps within the same function** (`nonlocal = false`)

- They become ordinary branches in native code and jumps in the VM. There is no cost of returning an error.
- However, when a jump **crosses** the scope of `unwind-protect`, dynamic binding, `handler-bind`, or `restart-bind`, the compiler generates, at that point, calls to the crossed cleanups, undoing of bindings (`UNBIND_TO`), and restoration of the handler and restart stack depths. Only jumps that cross none of these scopes become simple branches.
- When the VM dispatch loop receives an exit that crosses a `native_frame` boundary, it leaves by returning `Value.unwind`. With this mechanism, exits and cleanups work correctly even across nested calls such as VM → native → VM.
- When the exit target is not found (such as when the dynamic extent of the block has ended), `control-error` is signaled.

**Phase 18 implementation**
- The `Thread` control stack `control` (`ControlEntry`: kind, token, dynamic binding depth, VM resume position. Default 65536 elements) and the in-progress exit stack `unwinds` (`Transfer`: target entry number, primary value, count, list of the second and later values, depth `cleanup_at` at which it is stopped in a cleanup, saved error reason). Both are GC roots.
- A block's token is a fixnum created on each entry to the block (`th.next_token`). An exit searches the control stack from the top, and if not found, it is a `control-error` (a block whose dynamic extent has ended, a throw without a matching catch). When the value count is 1, nothing is allocated.
- **Resolver**: `return-from` is a **jump** if it does not cross the scope of an unwind-protect (protected form or cleanup) within the same lambda; otherwise it is a **runtime exit** (the block gets `needs_entry`, and the token's local variable is captured). A block that needs no entry generates nothing. The token's local variable number is assigned after the numbers in use, once the lambda body has been resolved. The bodies of `defun` (for `(setf name)`, name), `flet`, `labels`, and `defmacro` are wrapped in a block with the name. `return` is a standard library macro.
- **return-from that leaves by a jump**: unwinds the crossed dynamic bindings to the depth before the outermost binding (`UNBIND_TO`), removes the crossed entries (catch, blocks with entries) (`CONTROL_POP n`), discards intermediate values (`SLIDE n`), and jumps to the block's exit.
- **VM**: instructions `BLOCK_ENTER i rel`, `CATCH_ENTER rel`, `UWP_ENTER rel` (push an entry. rel is the position to resume at after an exit), `CONTROL_POP n`, `UWP_SAVE`, `UWP_END`, `RETURN_FROM_NL`, `THROW` (execution does not proceed past these), `SLIDE n`. When the dispatch loop returns with `Value.unwind`, `vm.run` examines the entries it pushed from the top; for an unwind-protect, it continues from the start of the cleanup, and for the target block or catch, from its exit, after restoring frames, the value stack, and dynamic bindings to what the entry recorded (`resumeAfterUnwind`). When none of its own entries remain, it returns `Value.unwind` (native code or an outer `vm.run` handles the rest). The verifier checks the rel of entry-pushing instructions against "the depth after an exit (for block and catch, the depth with one value pushed; for unwind-protect, the depth with a value and a marker pushed)". In addition, for each instruction position it computes the sequence of entries pushed by the function and the running cleanup, and confirms that the sequence is the same at the same position on every path, that `CONTROL_POP` removes only block and catch entries and `UWP_SAVE` removes an unwind-protect entry, that `UWP_END` is used only inside a cleanup, and that no entries or cleanups remain at `RETURN` (Codex and agy review P18). At runtime too, it confirms the count of `CONTROL_POP` and that the exit continued by `UWP_END` belongs to this cleanup (the recorded `cleanup_at` equals the current depth); otherwise it is an internal error.
- **Native**: the bodies of a block, catch, or unwind-protect with an entry become Zig labeled blocks, and when `Value.unwind` is received inside the body, control leaves that block (instead of returning from the function). After a block or catch, `N.land` checks whether it is the exit target. A return-from that leaves by a jump is `if (true) break :bN value;` (a form that still allows the code after it to be generated as is).
- **Scope of implicit blocks** (Codex and agy review P18): an implicit block wraps only the body (after the declarations), and does not wrap the initial value forms of the lambda list (`&optional`, `&key`, `&aux`) (CLHS flet "The body forms (but not the lambda list)"). For `defmacro`, the same block is attached to the body of the expander function in both the compile-time definition (top level) and the runtime definition.
- **Size of the in-progress exit stack** (Codex review P18 #1): each time an error enters a cleanup, one record is added (for example, when another error occurs inside the cleanup and enters a nested cleanup. The control stack does not grow). Therefore the size of `unwinds` is the control stack size + 1, and when an entry is pushed, it is checked that "control stack depth + number of records" does not exceed the control stack size (if it does, `storage-condition`). Entering a cleanup removes one entry and then pushes one record, so the sum does not grow; the only increase is the one at the start of an exit, so the records do not overflow.
- **Saving the error contents** (Codex review P18 #4): when an error enters a cleanup, in addition to the error reason, the contents (`th.err`) and the call history are also saved (`th.saved_errors`. A GC root), and restored after the cleanup. Even if an error that occurs and is caught inside the cleanup overwrites the contents, the original error is reported.
- **unwind-protect**: when the protected form is left, the entry is removed and the values are saved (`uwpSave`. For one value, fixnum 1; for two or more, a list of all values. In the middle of an exit or error, the marker -1, and dynamic bindings are unwound to the entry's depth, and the in-progress exit is stopped or the error reason is saved into a Transfer). `uwpEnd` after the cleanup either restores the values or continues the stopped exit or error. The cleanup is also run when leaving due to an error (the same output as SBCL 2.6.7's `--script`).
- **Exits inside a cleanup**: when a new exit starts, and when an error enters a cleanup, stopped exits whose `cleanup_at` is deeper than the target (for an error, the current depth) are cancelled (because control leaves that cleanup). An exit caught inside a cleanup does not cancel stopped exits. When an error returns to the top level, the remaining records are cleared (`clearError`).
- Tests: 63 cases compared with SBCL 2.6.7 results (also run under GC stress. Each time, it is also confirmed that the control stack, exit records, and dynamic bindings return to empty), combinations of errors and cleanups, and the language tests `exits.lisp`, `exit-cases.lisp` (the 63 cases also run natively), and `error-cleanup.lisp`.

**Phase 19 implementation (tagbody and go)**
- **Resolver**: the arguments of tagbody are split into tags (symbols and integers, including bignums, compared with eql) and forms (compound forms). Other atoms and duplicate tags are a program-error (as in SBCL 2.6.7). go follows the same rule as return-from: a jump if it does not cross an unwind-protect within the same lambda, otherwise a run-time exit (the tagbody gets `needs_entry`). The value is NIL.
- **Control stack**: a new entry kind `tagbody`. The value carried by a run-time go is the tag number (a fixnum). Unlike block, **the entry is not removed when the exit lands on it** (execution continues inside the tagbody; `landTransfer`). It is removed when the tagbody exits normally.
- **VM**: instructions `TAGBODY_ENTER i rel` (stores the token in local i and pushes an entry; rel is the resume position after landing) and `GO_NL` ([token tag-number]; execution does not continue past it). After landing, the tag number is stored in a local variable and compared to branch to the tag's position (proportional to the number of tags, since run-time go is rare). A go within the same function discards intermediate values (`POP`), undoes crossed dynamic bindings, removes crossed entries and jumps (including backward jumps). The verifier treats tagbody entries as a kind that remains after landing.
- **Native**: a tagbody becomes a labeled Zig switch (prong 0 is the part before the first tag, prong k+1 is the part after tag k). A go within the same function is `if (true) continue :sN k+1;`. If the tagbody is the target of run-time exits, the switch is wrapped in a loop; on `Value.unwind`, `N.land` lands and the switch is re-entered at the tag's prong.
- Tests: 24 tagbody/go cases compared with SBCL 2.6.7 (139 cases together with the iteration macros and loop described below; also under GC stress, and natively in `iteration-cases.lisp`).

**Unified method for restoring the dynamic environment** (agy #4)

Undoing dynamic bindings, handlers, and restarts does not rely on Zig's `defer` / `errdefer`; **all of it is unified into restoring by the depths of the `Thread` stacks** (the same idea as the VM's `UNBIND_TO`. Runtime function `th.unwindTo(depths)`).

- On normal exit: the generated code calls `th.unwindTo(depths before entry)` at the end of the scope.
- On non-local exit: the exit target (`block`, `tagbody`, `catch`) and each `unwind-protect` restore to the depths recorded in their control stack entries (above).
- With this method, the undo procedure is the same whichever is adopted: propagation by Zig errors, or a method equivalent to `setjmp`/`longjmp` (compared below).
- Zig's `defer` / `errdefer` are used only for cleanup of runtime-internal resources unrelated to the Lisp dynamic environment (such as temporarily allocated Zig memory). If a method equivalent to `setjmp`/`longjmp` is adopted, those resources are also registered on the control stack and released.

**Why propagation by return value was chosen**: without `setjmp`/`longjmp`, every function is left by a normal return, so the Zig runtime's cleanup is reliably executed. In normal execution, the check is one comparison of the return value (a register) with a constant and one branch. Presumably the cost of the branch is small, but it will be confirmed by measurement.

**Methods of other implementations, and confirmation by measurement (R3)**

| Implementation | Method | Basis |
|---|---|---|
| ECL | `setjmp`/`longjmp` (both bytecode and C) | `src/h/stacks.h` lines 282-296 `ecl_frs_push`, `src/c/stacks.d` lines 759-771 `ecl_unwind` |
| Clasp | Normally `setjmp`/`longjmp`. C++ exceptions only when there are non-cooperating C++ frames. C++ exceptions are recorded as "thousands of times slower than setjmp/longjmp" | `src/lisp/kernel/cleavir/unwind-notes.md` lines 10-16, 46, 88 |
| Zilisp | Returns one level at a time with the special return value `Value.unwind` (no exception tables. One comparison and branch per call) | This section |

Zilisp's method costs one branch even on ordinary calls that do not exit, and an exit costs in proportion to the number of intermediate frames. `setjmp`/`longjmp` costs at the time an exit point is created (on entry to block, catch, unwind-protect). **In Phase 12, the following two are compared on the same benchmark, and the faster one is adopted.**

**Phase 12 measurement results (2026-11-02)**: fib(30) generated by the native backend (ReleaseFast, x86_64-windows, median of 7 runs) was compared with a version that removes the per-call `Value.unwind` check (a comparison-only version that works correctly only when no error occurs). Excluding startup time (about 5.7 ms), it was about 9.7 ms with the check and about 8.5 ms without, so **the cost of the check was about 12%**. Since this workload is dominated by function calls, this value is close to the upper bound of the cost. For method 2 (a method equivalent to `setjmp`/`longjmp`), Zig 0.17.0 has no mechanism for "functions that return twice" (`returns_twice`), and C's `setjmp` cannot be called safely from Zig, so a custom mechanism that saves and restores registers and the stack position with inline assembly would have to be built. **This comparison (prototyping and measuring method 2) is done in Phase 18, which implements block, catch, and unwind-protect, including real non-local exits** (decided 2026-11-02. tque #339). Until then, method 1 is used. The cost of the check can also be reduced by direct calls within the same file and by type inference (omitting the check for calls known not to raise errors).

1. Propagation by a special return value (the method of this section)
2. A method equivalent to `setjmp`/`longjmp` (save registers and the stack position at the exit point, and return directly. Because this skips Zig's cleanup, processing that relies on `errdefer` on the runtime side must be registered on the control stack)

**Phase 18 comparison results (2026-11-02. tque #339)**
- Prototype of method 2 (`tests/bench/nonlocal.zig`): since Zig 0.17.0 has no `returns_twice`, instead of `setjmp` itself, the steps up to "save the registers (on Windows x64, rbx, rbp, rdi, rsi, r12-r15, xmm6-xmm15; on System V, rbx, rbp, r12-r15), the floating-point control state (MXCSR and the x87 control word, callee-saved in both ABIs), and the stack position, then call the function" were made into one assembly function `zl_catch_call`. When `zl_jump_to` exits, `zl_catch_call` returns with that value. To the compiler, `zl_catch_call` is an ordinary call that returns only once, so register handling on the caller side is correct. The assembly is written as module-level global assembly, declared as an `extern` function, and called directly (the same form as calling runtime functions in the real implementation).
  - Note: it was first written as a naked function, but a naked function is `noreturn` in its Zig declaration, so when it was converted to a function pointer and called, ReleaseSafe and ReleaseFast optimization treated it as a "call that does not return" and removed the code after it (this does not happen in Debug). With global assembly and an `extern` declaration, this problem does not occur.
- Measurement (`zig build bench -- nonlocal`, ReleaseFast, x86_64-windows, median of 7 runs. One iteration = create an exit point → call to depth D → exit or return normally. Both include pushing and popping the control stack and a tag search with two entries for other tags pushed above the exit point, and use the search result. Values re-measured after the Codex and agy reviews)

| Operation | Method 1 | Method 2 |
|---|---|---|
| Only create an exit point (D = 0, no exit) | 1.51 ns | 5.50 ns |
| Call to depth 10 and return normally | 8.90 ns | 12.01 ns |
| Call to depth 100 and return normally | 90.1 ns | 106.4 ns |
| Exit at D = 0 | 2.08 ns | 10.67 ns |
| Exit from depth 10 | 9.85 ns | 17.05 ns |
| Exit from depth 20 | 17.4 ns | 20.5 ns |
| Exit from depth 100 | 89.0 ns | 50.8 ns |
| Exit from depth 1000 | 820.8 ns | 408.8 ns |

- Reading: method 2 costs about 4 ns more to create an exit point (saving 18 registers and the floating-point control state), and the exit itself takes about 5-8 ns regardless of depth. A method 1 exit costs about 0.4-0.5 ns per level (return and check). The break-even point is a depth of about 25 levels (method 1 is faster at 20 levels, method 2 at 100), and method 2 is faster only for exits deeper than that. The per-call check cost showed no difference in this measurement (calls through function pointers) (about 12% in Phase 12's fib(30)).
- **Decision: continue with method 1** (2026-11-02). Reasons: (1) The cost of each entry into block, catch, and unwind-protect (which also appear in the expansions of `with-open-file`, `handler-case`, etc.) is smaller with method 1, and leaving without an exit is more common. (2) To eliminate the per-call check with method 2, errors would also have to return directly, which would skip the runtime's Zig cleanup (such as unregistering roots via `defer`). The cost and risk of re-registering all of it on the control stack are large. (3) If method 1 becomes a problem for workloads with many deep exits (such as `throw` from deep recursion), it will be re-measured at that point.

### 6.5 Dynamic binding

- Shallow binding is used. Binding saves the old value of the symbol's value cell on the binding stack and then writes the new value. Unbinding and unwinding restore the old value.
- **When the old value is unbound, it is saved and restored as unbound** (review #9). Example: after `(defvar *x*)`, `(let ((*x* 1)) *x*)` returns 1, and on leaving the `let`, `*x*` is unbound again (verified with SBCL 2.6.7).
- **The unbound error (`unbound-variable`) is signaled only when the value is read.** Assignment (`setq`, `setf`) and dynamic binding (`let`, `progv`) can be applied to unbound special variables as well.
- When `progv` has fewer values than symbols, the remaining symbols are bound but have no value (they become unbound). Unbinding restores the old values (CLHS `progv`).
- When threads are introduced, this is extended to a method in which each symbol has a TLS index.

**Phase 14 implementation**
- The binding stack is `Thread.bindings` (pairs of a symbol and its old value. Default 65536 elements. On overflow, `storage-condition`). It is scanned precisely as a GC root.
- VM instructions: `BINDING_DEPTH` (push the depth), `BIND_SPECIAL k`, `UNBIND_TO` ([value depth] → [value]), `PROGV_BIND`. `let`, `let*`, special variable parameters, and `progv` keep the depth before binding in an unnamed local variable, and restore it with `UNBIND_TO` after the body. The native backend uses the same procedure (`N.bindingDepth`, `N.bindSpecial`, `N.unbindTo`).
- **Restoration when leaving due to an error**: `vm.run` remembers the binding depth at the time it was entered, and restores to it when leaving with `Value.unwind`. Exit targets (block, catch) and unwind-protect restore to the depth recorded in their control stack entries (§6.4, Phase 18).
- Resolver: a binding is made a dynamic binding when the name is a special variable (`defvar`, `defparameter`, `proclaim`) and when the binding has a `special` declaration. A special variable within a scope is represented by a variable marked `special` (a name that is only declared `special` without being bound is also added as a variable of that scope). References and assignments to this variable become `global_ref` and `global_set`, and the same applies from inner lambdas (verified with SBCL 2.6.7). A special variable parameter is received in a hidden local variable, and the body is wrapped in a `let` of the special variable.
- `defvar` and `defparameter` are bootstrap macros written in Zig (item 6 of §11.1). The name is declared special **at the time of execution** (`zl-sys::%proclaim-special`) and, **for a top-level form, at compile time** (so that bindings become dynamic in the compilation of later parts of the same form and of later forms. CLHS 3.2.3.1. Inside a top-level `progn` is also top level). A non-top-level `defvar` that is not executed (`(if nil (defvar x) nil)`) is not declared (Codex review P14 #3. Verified with SBCL 2.6.7).
- **Difference between `load` and `compile-file`**: a form that binds a name with `let` after a `defvar` of the same name inside a function has been executed becomes a dynamic binding on the VM (`--script`, REPL; `load` semantics that compile and execute forms one at a time), and a lexical binding on the native backend (`compile-file` semantics that compile the whole file first). SBCL 2.6.7 also gives the former with `--script` and the latter with `compile-file` (a difference permitted by CLHS 3.2.3.1). Therefore tests of this form are done only in VM unit tests.
- Native programs also restore the dynamic bindings created inside a top-level form when that form is left due to an error (Codex review P14 #2).

### 6.6 Reasons for `Value.unwind`, and Zig error sets

```zig
// Reason when the return value is Value.unwind (th.fault)
pub const Fault = enum(u8) {
    none,
    unwind,         // In the middle of a non-local exit (not abnormal. The top of th.unwinds is the exit target)
    out_of_memory,  // Allocation failure. Converted to storage-condition when possible
    internal,       // Internal failure of the implementation (bug). Not turned into a Lisp condition
    lisp_error,     // Provisional for Phase 08-24: a Lisp error. Contents in th.err (kind, description, value)
};

// Error set used only inside the runtime (between Zig functions)
pub const Error = error{ LispUnwind, OutOfMemory, VmInternal };
```

- For values passed through function entries (the generic entry and fast entry of §6.2), Zig errors are not used; `Value.unwind` and `th.fault` are used instead.
- Inside the runtime, processing where speed does not matter (loading, the compiler, FFI preparation, etc.) may use the Zig error set `Error!T`. It is converted to `Value.unwind` and `th.fault` at the entry boundary (the `fault` value corresponds to the kind of error).
- When a CL error occurs in a Zig primitive, it calls `return th.signalError(class, initargs)`. This runs handlers without unwinding (§9), and always returns `Value.unwind` in the end.
- `th.fault = .internal` prints diagnostic information and stops the implementation.
- **Provisional handling until conditions exist (Phase 08-24)** (decided in Phase 08): Lisp errors found by primitives, the VM, or the compiler are recorded with `th.signal(kind, message, datum, expected)` into `th.fault = .lisp_error` and `th.err`, and `Value.unwind` is returned. `kind` corresponds to a CL condition type (`type-error`, `unbound-variable`, `undefined-function`, `program-error`, `division-by-zero`, `floating-point-overflow`, `storage-condition`, etc. Unimplemented features use the Zilisp extension `zilisp:unimplemented`). Control returns to the top level (REPL, script, `--eval`), which reports the type name and description on one line.
- **From Phase 25**: when there is at least one handler or restart, `th.signal` makes a condition right there and signals it to the handlers (§9.2). If a handler exits, it returns `Value.unwind` (with `fault` `.unwind`); if no handler takes it, it records `th.err` and returns to the top level as above (with the same report text). No toplevel `abort` restart is made; returning to the top level plays that role. A condition from Lisp's `error` that no handler takes is recorded as `ErrorKind.condition` (`th.err.datum` is the condition, `expected` the class name, `detail` the report string). A Lisp string description is passed with `th.signalDetail`.

### 6.7 Stack size

- The native stack size is specified at startup (on Windows, in the executable header; elsewhere, by recreating the main thread). The default is decided by measurement (initial proposal 64 MiB. To be verified).
- When the stack is about to overflow, `storage-condition` is signaled. The remaining amount is checked at the entry of native code functions (a page-protection method will be considered later).
- Constants (initial proposal): `call-arguments-limit` = 65536, `multiple-values-limit` = 1024, `lambda-parameters-limit` = 1024.

---

## 7. Bytecode VM

### 7.1 Role

- The VM is the method for executing code defined by the REPL, `eval`, and source `load` **immediately**. From Phase 39 on, it is used until background native compilation finishes, and in environments without Zig (§7A.6).
- The main path for speed is native code, so the VM is a **stack-based** VM that is simple to implement. However, instruction dispatch uses a labeled `switch` with `continue` (equivalent to threaded code) (**decided by measurement on 2026-11-02**).
  - Measurement (`zig build bench -- vm/`, x86_64-windows, ReleaseFast, median of 5 runs): with a `while` and `switch` dispatch loop, fib(25) took 5.08 ms; with a labeled `switch` and `continue`, it took 2.97 ms (about 41% shorter). 10,000 closure calls went from 0.40 ms to 0.27 ms.
  - With the `while` and `switch` form, changes unrelated to the dispatch loop (such as adding one error kind) made fib(25) vary in the range 3.7–5.1 ms. With the labeled `switch`, the same kind of change left it almost unchanged at 2.88–2.98 ms.
  - Therefore, when adding instructions to the dispatch loop, keep the form in which each instruction reads the next instruction at its end and branches with `continue :dispatch`.
- The VM value stack has a fixed length and is allocated at startup (default 1M elements = 8 MiB, changed with `--stack-size`). The value stack is scanned precisely.

### 7.2 VM frame

```zig
pub const VmFrame = struct {
    closure: Value,        // VM closure
    ip: u32,
    base: u32,             // start of local variables (arguments come first)
    ret_sp: u32,
    control_base: u32,
};
```

### 7.3 Encoding (decided)

- Opcodes are u8. Operands are little-endian, with a fixed width per instruction (`k` = constant table index u16, `i` = local variable index u16, `n` = count u8, `rel` = relative jump i32).
- When an index or a **count** exceeds u16 or u8, the prefix instruction `WIDE` makes the index u32 and the count u32 (review #17). This allows passing arguments up to `call-arguments-limit` (65536) in a direct call.
- Tests check argument counts of 255, 256, 65535, 65536, and 65537 (the u8 boundary, and just below the limit, at the limit, and over the limit).
- **Interpretation of `call-arguments-limit`** (decided in Phase 08): CLHS `call-arguments-limit` is "the upper exclusive bound on the number of arguments", so with `call-arguments-limit` = 65536, up to **65535 arguments** can be passed. Calls with 65536 or 65537 arguments signal `program-error` at compile time (at run time for `apply`). The "at the limit" case (65536) in the tests above checks that an error occurs.
- Bytecode is an internal format, and compatibility is not guaranteed. If the format version in the `.zfasl` header does not match, loading is refused.

### 7.4 Instruction table

| Category | Instruction | Operands | Stack effect / meaning |
|---|---|---|---|
| Constants | `CONST` / `NIL` / `T` / `SMALLINT` | k / — / — / i16 | → v |
| Stack | `POP` / `DUP` / `POPN` | — / — / n | |
| Locals | `LOAD_LOCAL` / `STORE_LOCAL` / `LOAD_CAPTURED` | i | |
| | `MAKE_CELL` / `CELL_REF` / `CELL_SET` | — | |
| Special variables | `LOAD_SPECIAL` | k | `unbound-variable` if unbound |
| | `STORE_SPECIAL` / `BIND_SPECIAL` | k | Can execute even when unbound (§6.5) |
| | `BINDING_DEPTH` / `UNBIND_TO` / `PROGV_BIND` | — | |
| Functions | `LOAD_FUNCTION` / `LOAD_SETF_FUNCTION` | k | `undefined-function` if undefined |
| | `MAKE_CLOSURE` | k n | |
| | `CALL` / `CALL_MV` / `CALL_GLOBAL` / `CALL_GLOBAL_MV` / `APPLY` | n / n / k n / k n / n | Calls with the convention of §6.2 |
| | `RETURN` | — | |
| Arguments | `ARG_SUPPLIED_P` | i | |
| Control | `JUMP` / `JUMP_IF_NIL` / `JUMP_IF_NOT_NIL` | rel | |
| Multiple values | `TO_MV` / `MV_PRIMARY` / `VALUES` / `VALUES_LIST` / `MV_SAVE` / `MV_RESTORE` / `MV_BIND` / `MV_MARK` / `MV_SPREAD` / `MV_CALL_MARKED` | | §6.3 |
| Non-local | `BLOCK_ENTER` / `BLOCK_EXIT` / `RETURN_FROM_NL` | i rel / — / i | §6.4 (the Phase 18 implementation is in "Phase 18 implementation" of §6.4: `BLOCK_EXIT` and `CATCH_EXIT` became `CONTROL_POP n`, and `UWP_EXIT` became `UWP_SAVE`) |
| | `TAGBODY_ENTER` / `TAGBODY_EXIT` / `GO_NL` | i n rel[n] / — / i u16 | |
| | `CATCH_ENTER` / `CATCH_EXIT` / `THROW` | rel / — / — | |
| | `UWP_ENTER` / `UWP_EXIT` / `UWP_END` | rel / — / — | |
| Conditions | (not made; handlers and restarts are dynamic bindings of special variables. Phase 25) | — | §9.2 |
| Fast paths | `CONS` `CAR` `CDR` `EQ` `NULL` `ADD2` `SUB2` `LT2` `GT2` `NUMEQ2` etc. | — | fixnum fast path with fallback to generic processing |
| Other | `LOAD_TIME_VALUE` / `WIDE` | k / — | |

**Instructions implemented in Phase 08** (`src/vm/opcodes.zig`): `CONST` `NIL` `T` `SMALLINT` `POP` `LOAD_LOCAL` `STORE_LOCAL` `LOAD_CAPTURED` `MAKE_CELL` `CELL_REF` `CELL_SET` `LOAD_SPECIAL` `STORE_SPECIAL` `LOAD_FUNCTION` `MAKE_CLOSURE` `CALL` `CALL_GLOBAL` `RETURN` `JUMP` `JUMP_IF_NIL`, the fast-path instructions `CONS` `CAR` `CDR` `EQ` `NOT` (`null` and `not`) `ADD2` `SUB2` `LT2` `GT2` `LE2` `GE2` `NUMEQ2` `ADD1` `SUB1`, and `WIDE`.
- `STORE_LOCAL` and `STORE_SPECIAL` leave the written value on the stack (it becomes the value of `setq`). Where the value is not needed, a `POP` follows.
- Layout of a frame on the value stack: `[base, base+nlocals)` holds the local variables (arguments come first), and the `max_stack` slots above it are the area used for expression evaluation. The GC scans `[0, sp)` of the value stack precisely (values left in slots that are no longer in use are not scanned; Codex review P08 #2). The dispatch loop keeps `sp` in a local variable, so it **always writes it back to `Vm.sp` before an allocation (an operation that may trigger GC) and before calling a non-VM function**. Missing write-backs are detected by the `--gc-stress` tests. The value stack is filled with NIL at startup.
- Every path that calls a function from a Zig function (`funcall`, `apply`, etc.) goes through `Thread.call`. Nesting depth is counted in `vm.run` for VM closures and in `Thread.call` for other primitives (never counted twice; limit 1000; it also stops chains that do not go through the VM, such as `apply` calling `apply`; P08 #1).
- For a `lambda` with no captures, a single closure is created at compile time and placed in the constant table (no allocation at run time).
- **`(funcall f …)` compiles to the `CALL` instruction** (it calls the function value directly). When calling a VM closure, a frame is pushed within the same dispatch loop.

**Verifier** (review #20)
- In debug builds, bytecode just generated by the compiler is verified for stack depth consistency, jump target range, and constant table index range.
- **Bytecode loaded from `.zfasl` undergoes the same verification at load time, even in release builds (ReleaseFast).** The file comes from outside the implementation, so a CRC32 checksum (§14) alone cannot guarantee that its structure is safe. Verification runs only once at load time, so it does not affect execution speed.

---

## 7A. Native backend and native compilation of the REPL (D-7, D-10)

### 7A.1 Method

- Generate **Zig source** from Core IR and compile it with Zig (LLVM). One Lisp source file corresponds to one Zig source file.
- The generated Zig source is compiled together with the runtime's Zig source (D-5). As a result, small runtime functions (`car`, fixnum checks, the allocation fast path, etc.) are inlined into the generated code.
- Use cases: `zilisp build` (§15) and building the implementation's own standard library (§11.3).

### 7A.2 Shape of the generated code

```zig
// Image of the code generated from (defun add1 (x) (1+ x)) (design example)
// Generic entry (Entry in §6.2) and a fast entry that returns a single value
fn lisp_add1(th: *Thread, self: Value, args: [*]const Value, nargs: u32) callconv(.c) Value {
    if (nargs != 1) return th.argCountError(self, nargs, 1, 1);   // returns Value.unwind
    const r = add1_fast(th, args[0]);
    if (r == Value.unwind) return r;
    th.mv_count = 1;
    return r;
}
fn add1_fast(th: *Thread, x: Value) Value {
    if (x.isFixnum()) {
        const r = @addWithOverflow(x.raw(), Value.fixnumOne().raw());
        if (r[1] == 0) return Value.fromRaw(r[0]);
    }
    return rt.genericAdd(th, x, Value.fromFixnum(1));  // bignum, floating point, type error (Value.unwind on error)
}
```

The fast entry (`add1_fast`) is generated only for functions known to return a single value, and it does not write `th.mv_count` (the generic entry writes it on its behalf). Both entries represent errors with `Value.unwind` (§6.2, review #24).

### 7A.3 Transformations for speed

| Transformation | Description |
|---|---|
| fixnum fast path | Operate on tagged values as they are, and call generic processing only on overflow |
| Avoiding boxing | Local variables that type inference proves to be double-float are kept as f64. They are allocated on the heap only when they leave the function |
| Specialized arrays | Elements of `double_vector` and `fixnum_vector` are read and written without boxing |
| Direct calls within the same file | Unless `notinline` is declared, the fast entry is called directly without going through the function cell (CLHS 3.2.2.3) |
| Inline cache | For calls to functions in other files, the value of the function cell and its fast entry are cached |
| Tail calls (agy #9) | **Self tail calls** (the most common case) are **converted into a loop inside the function** at the Core IR stage (not into a call). `@call(.always_tail, …)` (LLVM `musttail`) can be used only when the caller and callee types (arguments, return value, calling convention) match, so it is used only **between generic entries** (`Entry` has the same type for all functions) and **between fast entries of the same type**. Other tail calls go through the generic entry. |
| Conditions for tail calls | Conditions for making a tail call (review #16): (1) there are no dynamic entries (bindings, catch, unwind-protect, handler, restart); (2) the arguments passed to the callee do not point into the caller's frame area (do not pass the `args` array, or a `&rest` list or closure allocated on the stack); (3) no captured closure refers to a block or tagbody token in the caller's frame. To satisfy (2), a tail call first moves its arguments to a **dedicated per-thread argument area** and then calls. Tail calls between fast entries (register passing) and tail calls through the generic entry (array passing) are verified separately. The implementation uses `@call(.always_tail, …)` (to be verified); if that cannot be used, use Gambit's method (branch within the same function, return to a trampoline to go outside; `include/gambit.h.in` lines 6790–6952, `___trampoline` at line 3223 of `lib/setup.c`) |
| Omitting type checks | `safety 0`, or places where type inference has determined the type |
| CLOS | For generic function calls, generate a fast path that looks up the cache of §10.4 |

### 7A.4 Relation to GC

- Generated code does not register Lisp values held in local variables with the GC (they are found by the conservative scan of §3.4). The native backend generates code that satisfies the "liveness contract" of §3.4.
- Clasp also scans the native stack conservatively for code generated by LLVM, and scans the heap precisely using per-type layout information. It does not use LLVM's GC mechanisms (statepoint, gc.root) (`include/clasp/gctools/roots.h` lines 27–46, `src/gctools/gc_boot.cc` lines 398–420).
- GC can occur only in allocation calls. The allocation fast path is inlined, and the runtime is called only when a page is exhausted.

### 7A.5 Debug information

- The names of generated Zig functions include the Lisp function name (so that backtraces show Lisp function names).
  - **C1**: Zig's syntax for using an arbitrary string as an identifier (`@"cl-user::foo-bar"`) is expected to allow using Lisp names as they are, without conversion (to be verified; also check whether the generated symbol names are displayed as they are in debuggers and linkers).
  - If this cannot be used, define a reversible conversion based on Carp's conversion scheme (`-` → `_MINUS_`, `?` → `_QMARK_`, non-ASCII → `_U<code>U_`, etc.: `src/SymPath.hs` lines 29, 85).
- The generated Zig source contains comments with the corresponding Lisp source positions.
- **C2**: How to look up "native address → Lisp source position" at run time is **to be verified**. Carp, which generates C, maps C code to Lisp source lines with C `#line` directives (only when `--line-directives` is given; `src/Emit.hs` lines 145–156). Check whether Zig has an equivalent directive (presumably it does not); if it does not, generate a per-function table of "generated Zig line → Lisp source position" and combine it with Zig's debug information. Until this is decided, backtraces show only function names.

### 7A.6 Native compilation of REPL, eval, and load (D-10, Phase 39)

**Survey of candidates (2026-11-01)**

Survey conditions: the license is compatible with MIT, it supports x86-64 and AArch64, and it runs on Windows, Linux, and macOS.

| Candidate | License | Windows | Required at run time | Verdict |
|---|---|---|---|---|
| MIR (vnmakarov/mir) | MIT | **No official statement of support** | None | Rejected because it does not satisfy the condition on Windows, the primary target |
| libgccjit (used by Emacs native compilation) | GPL (GCC) | Works with MinGW. File names are ANSI only (Emacs `src/comp.c` lines 4795–4815) | **gcc and binutils (`as`, `ld`)** (Emacs `doc/lispref/compile.texi` lines 761–763). Output is a DLL | Rejected because of the license and the need for external tools |
| LLVM JIT (ORC; used by Clasp: `src/llvmo/runtimeJit.cc`) | Understood to be Apache 2.0 (with LLVM exception) (not verified) | Supported | Links the LLVM libraries (the executable becomes larger; size to be verified) | Future candidate for speeding up `eval` inside a distributed executable |
| **(4) Build a DLL with Zig in the background (adopted)** | — | Supported | **Zig** (present in a development environment with the SDK installed) | **Adopted as the first choice** because it needs no new external library and runs on all three OSes |

**Method (4)** (based on Clasp's auto-compile thread `src/lisp/kernel/cleavir/auto-compile.lisp` and Emacs's asynchronous native compilation `lisp/emacs-lisp/comp-run.el`)

1. Functions defined by the REPL, `eval`, or source `load` are first compiled to bytecode and executed **immediately** by the VM (no waiting).
2. At the same time, Zig source is **generated on the spot (synchronously)** from the function's Core IR and compiled into a shared library (DLL on Windows, `.so` on Linux, `.dylib` on macOS) by **Zig in a separate process**. Core IR is discarded when processing of the top-level form finishes (§5.1), so conversion to Zig source is completed before it is discarded (review #13).
3. When it is finished, the shared library is loaded (`LoadLibraryW` on Windows, `dlopen` elsewhere), and **the native entry is set on the code object** (agy #1).
4. **Existing closures also start running on native code.** Closures are not re-created, and the closure in the function cell is not replaced. All closures created from the same lambda share the same code, so once the native entry is set on the code, native code is used from the next call (because the VM trampoline checks the code's entry; §6.2). The identity of closures (`eq`) and the sharing of captured variables (including `value_cell`) are preserved as they are.
   - Example: for `next-id` in `(let ((count 0)) (defun next-id () (incf count)))`, the closure in the function cell itself starts running on native code.
   - Inner closures returned by functions and function objects stored in data structures switch in the same way, as long as they share the same code.
   - Therefore, **the layout of the captured-value array and the use of `value_cell` are the same in the VM and native code** (decided from the results of the same Core IR `captured` / `assigned` analysis; §5.2).
   - Native code refers to the captured-value array through the second argument `self` (the closure itself; §6.2).

**Job management** (review #13)
- Each compilation job holds the target **function object** and the **definition generation number** of its function name (a number that increases each time the function is redefined by `defun` etc.).
- **Batch compilation** (agy #10): when a source is `load`ed, compile **per file into one Zig source and one shared library**, not per function. For REPL definitions, batch those defined within a short period (initial proposal: 1 second).
- **Limit the number of Zig processes running at the same time** (initial proposal: 1–2). Excess jobs go into a job queue.
- **Checking for completion and replacing entries happen only at safe points of the main execution** (because 1.0 is single-threaded). Safe points are when the REPL shows its prompt, when GC starts, and a check every fixed number of function calls (so that replacement progresses even during long-running Lisp processing).
- If the generation number of a completed job differs from the current generation number of the function name (it was redefined during compilation), **the output is discarded**. Native code for an old definition is never applied to a new definition.
- Compilation failures (Zig errors, abnormal termination of the child process) produce a warning, and execution continues on the VM. When the implementation exits, running child processes are stopped and unfinished jobs are discarded.

**Behavior of `compile`** (review #15)
- When `compile` is called explicitly in an environment with Zig, it waits until native compilation finishes (synchronous).
- **In an environment without Zig (such as inside a distributed executable), `compile` compiles to bytecode and returns.** In both cases, the CLHS `compile` contract is kept (it returns three values: the function, whether there were warnings, and whether it failed; when a name is given, it replaces that function's definition; `compiled-function-p` is true for the result). CLHS `compile` does not require producing machine code with an external tool.

**Design notes**
- Shared libraries do not contain a duplicate of the implementation's runtime. Runtime functions are called through a **table of function pointers** passed at load time. Constants are referenced from a **constant table** filled in at load time (the same idea as Emacs's `freloc_link_table` and `d_reloc`: `src/comp.c` lines 477–487, 5290–5323). Small functions such as Value tag operations are inlined into the generated code.
- The calling convention at the shared library boundary and the ABI version check follow "Boundary with separately compiled shared libraries" in §6.2 (review #11).
- On Windows, a DLL that is loaded cannot be overwritten. Shared library file names are made unique for each generation (based on the countermeasure in Emacs `lisp/emacs-lisp/comp.el` lines 3508–3530).
- In 1.0, loaded shared libraries are not unloaded (code is not reclaimed).
- **Cache cleanup** (agy #10): on Windows, shared libraries that are no longer used due to redefinition etc. cannot be deleted while loaded, so they are deleted **the next time Zilisp starts** (before they are loaded). The total cache size has a limit (initial proposal: 1 GiB); when it is exceeded, the oldest entries are deleted first.

**Cache and trust boundary** (review #14, #20)
- The cache key includes, in addition to the hash of the generated Zig source, **the Zig version, the Zilisp SDK version, the ABI version number (§6.2), the target (CPU, OS), the optimization settings, and the hashes of the runtime files referenced by the generated code**. If any of these changes, it becomes a different cache entry.
- The cache is placed only in a directory managed by Zilisp (per-user `.zilisp-cache/`). A shared library is written to a temporary file and then renamed into place (a partially written file is never loaded). It is loaded by **absolute path**, and the ABI version number is checked.
- The libraries that a shared library depends on are not searched for in OS search paths (such as the current directory). Shared libraries are generated so that they depend on nothing other than the implementation itself.

**What this method cannot satisfy (stated explicitly)**
- **In an environment without Zig (such as inside a distributed executable), `eval` and `load` run on the VM and do not reach native speed.** The application itself is entirely native code (§15), so only code loaded at run time with `eval` or `load` is affected.
- To resolve this, either LLVM JIT (ORC) must be embedded or an original code generator (option (3) of D-10) must be built. This will be decided after 1.0, based on measurements and executable size.

### 7A.7 Compile time

- Compilation with Zig (LLVM) takes time. Presumably a few seconds per file (to be measured in Phase 12).
- Results are cached (`.zilisp-cache/`). The key is the combination of the hash of the generated Zig source and the versions and settings listed in "Cache and trust boundary" of §7A.6. Unchanged files are not recompiled.
- **Rule for generated code (R2): one Lisp function becomes one Zig function; do not generate huge functions.** Gambit warns that for the method of putting an entire module into one C function, "clang/LLVM takes more than 30 minutes and uses a lot of memory (about 1 minute with GCC)" (`configure.ac` lines 3969–3975). For large modules it also lowers optimization per function (`configure.ac` lines 516–528, `include/gambit.h.in` lines 1255–1265). Zilisp also provides a mechanism that lowers optimization when a function's size exceeds a threshold (the threshold is determined by measurement).

### 7A.8 Phase 12 implementation (minimal native backend)

- `src/native/emit.zig`: generates Zig source from Core IR. It creates one generic entry (`Entry`, `callconv(.c)`) function per lambda, and one function with no arguments per top-level form. Function names are `@"lisp:name:number"` (C1 of §7A.5: confirmed that Lisp names can be used as identifiers as they are; display in debuggers and linkers is not verified).
- Expression values are put into Zig local constants; after every function call, the code checks whether the value is `Value.unwind` and, if so, returns it (method 1 of §6.4). fixnum fast paths (`car`, `+`, `<`, etc.) are inline functions in `src/native/rt.zig` and are expanded into the generated code.
- Constants (quoted data, symbols, etc.) are embedded as text printed with `prin1` and read back by the Reader at startup. After them come each lambda's Code (the name for printing and the number of arguments) and the closures of lambdas with no captures (the constant table; registered as GC roots). An uninterned symbol becomes a separate symbol for each constant (identity within the same file is not preserved across constants). Since Phase 24 the constants are printed with `*print-circle*`, so shared and circular structure inside one constant, including a shared uninterned symbol, is kept (`#n=` and `#n#`).
- Generated code does not register Lisp values in local variables with the GC (§7A.4). At function entry, it checks the remaining native stack (§6.7; the stack of the generated executable is 64 MiB).
- Not done yet (§7A.3): direct calls within the same file, fast entries, tail call conversion, type inference. Calls always go through the function cell.
- Development command `zilisp --emit-zig FILE OUT.zig`, and `zig build native-test` (generates, compiles, and runs `tests/language/eval/*.lisp` and compares them with the same expected values as the VM; `-Doptimize` specifies optimization). `zilisp build` (Phase 36), which builds a stand-alone executable, is built on top of this mechanism.
- **Measurement** (fib(30), ReleaseFast, x86_64-windows, median of 7 runs, excluding startup time): VM about 34.9 ms, native about 9.7 ms (about 3.6 times faster). Startup time is 6.1 ms for the VM and 5.7 ms for native (including preparation of the 978 CL symbols).

---

## 8. Namespaces, packages, and the intern table

### 8.1 Symbols

```zig
pub const Symbol = extern struct {
    header: ObjHeader,
    name: Value,        // string (not changed after intern)
    package: Value,     // package, or NIL (uninterned)
    value: Value,       // global value / dynamic value (may be unbound)
    function: Value,    // function / macro function (may be unbound)
    setf_function: Value, // function for (setf name) (may be unbound)
    plist: Value,
    fast_entry: usize,  // fast entry (§6.2; when undefined, VM, or argument count mismatch, a trampoline back to generic processing)
    // header.flags: special, constant, keyword, macro, global_symbol_macro, unimplemented, shadowing
};                      // 64 bytes (8-byte header + 7 words). Fits in the 64-byte size class
```

- **Function names of the form `(setf foo)` are stored in the symbol's `setf_function` field** (agy #7). Like ordinary functions, they can be called with one indirection. Because they are not put into a table (hash table), they are collected together with the symbol when the symbol is no longer used (no weak table is needed).
- **Constants** (agy #13; CLHS `defconstant`, 3.1.2.1.1.3 "Constant Variables")
  - Assignment (`setq`, `setf`) to and binding (`let`, `let*`, `lambda` parameters, `progv`, `multiple-value-bind`, etc.) of a symbol with the `constant` flag is an error **at compile time if it can be detected at compile time, and otherwise at run time**.
  - `defconstant` is accepted if the symbol is already a constant and the new value is `eql` to the old value (for example, when the same file is `load`ed again). If not `eql`, an error is signaled (CLHS leaves the result undefined, but the value is not changed silently).
  - For compile-time handling, see §16.1.
- `unimplemented` flag: set on CL symbols for functions and macros that Zilisp does not implement yet. **An error is signaled as soon as a call is detected at compile time** ("`COMMON-LISP:XXX` is not implemented in Zilisp").

### 8.2 Packages

```zig
pub const Package = struct {
    header: ObjHeader,
    name: Value, nicknames: Value,
    internal: SymbolTable,   // UTF-8 name → symbol (keys are copied into a non-GC area)
    external: SymbolTable,
    shadowing: Value,
    use_list: Value, used_by: Value,
    local_nicknames: Value,  // Phase 22 or later
};
```

- Search order of `find-symbol`: the package's own external → internal → external of used packages (in use-list order).
- Name conflict detection is implemented in Phase 22 and provides `package-error` and restarts (CLHS 11.1.1.2.5).
- `unintern` sets `symbol-package` to NIL only when the symbol is removed **from its home package** (CLHS `unintern`; agy #14).
- ~~Whether a symbol is a shadowing symbol is determined not by searching a list but by a symbol flag (`shadowing`; since this can differ per package, it is used together with a set on the package side).~~
- Shadowing symbols are kept in a list per package (`PackageData.shadowing`) and found by searching it (changed in Phase 22 from the plan to use a symbol flag: the check is used only when looking for name conflicts, never when reading or looking up symbols, and a package usually has only a few shadowing symbols).

**Implementation in Phase 22 (packages)**
- **`*package*`** holds its value as a CL special variable (CL-USER at startup) and can be bound with `let`. `Runtime.current` is gone; the reader, the printer, `intern` and the others read the value of `*package*` (`Runtime.currentPackage`; if it is not a package or is a deleted package, the reader signals a reader error).
- **Package body** (`PackageData`): name and nicknames, internal and external tables, the packages it uses and the packages that use it, shadowing symbols, and local nicknames (an SBCL 2.6.7 extension; `:local-nicknames` in `defpackage`). `find-package` and the reader look at local nicknames first, and the printer qualifies with a local nickname (as in SBCL).
- **Functions** (`src/primitives/packages.zig`): `packagep`, `find-package`, `make-package` (`:use` defaults to empty, as in SBCL), `rename-package`, `delete-package`, `list-all-packages`, `package-name`, `package-nicknames`, `package-use-list`, `package-used-by-list`, `package-shadowing-symbols`, `intern`, `find-symbol` (the second value is `:internal`, `:external` or `:inherited`), `unintern`, `export`, `unexport`, `import`, `shadow`, `shadowing-import`, `use-package`, `unuse-package`, `find-all-symbols`, `symbol-package`, `keywordp`, `make-symbol`.
- **Macros** (`src/lisp/boot.lisp`): `in-package`; `defpackage` (`:nicknames`, `:use`, `:shadow`, `:shadowing-import-from`, `:import-from`, `:intern`, `:export`, `:documentation`, `:size`, `:local-nicknames`; processed in the CLHS order: shadow and shadowing-import-from, use, import-from and intern, export; an unknown option, a repeated `:documentation` or `:size`, names shared by `:shadow`, `:shadowing-import-from`, `:import-from` and `:intern`, and names shared by `:intern` and `:export` are program-errors; an existing package gets the settings added); `do-symbols`, `do-external-symbols`, `do-all-symbols`. `in-package` and `defpackage` expand into `(eval-when (:compile-toplevel :load-toplevel :execute) ...)`, so the package also changes before later forms are read when the whole file is compiled first (native).
- **Name conflicts** (CLHS 11.1.1.2.5): `use-package` (including between packages used together), `export` (a distinct symbol of the same name in a using package), `import` (a distinct accessible symbol of the same name), `unintern` (removing a shadowing symbol would make external symbols of the same name in several used packages conflict). All are checked before any table is changed, and a conflict is a package-error (SBCL 2.6.7 signals name-conflict, a kind of package-error). Restarts come with conditions in Phase 25.
- **`delete-package`** moves the body to `Runtime.deleted_packages` (so the package object can keep pointing at it) and sets the home package of its symbols to NIL. Standard packages and packages used by other packages cannot be deleted (package-error; SBCL unuses them through a continue restart and then deletes).
- **`load`** (`src/primitives/load.zig`) evaluates the forms of a file (a string; pathnames come in Phase 23) one at a time as they are read, binding `*package*` during the load (an `in-package` in the file is undone when the load ends). With `:if-does-not-exist nil` a missing file returns NIL. A true `:verbose` or `:print` is an unimplemented error. New error kinds: `file-error`, `reader-error`, `end-of-file`.
- **Native backend**: constants write every symbol except keywords and uninterned symbols as "package::name" (`printer.qualify_all`), so the same symbols are read regardless of `*package*` at startup or of the export order. When the constants are read at startup, packages that have not been created yet become pending packages (`Runtime.pending_packages`, via `ValueBuilder.create_packages`). Pending packages are not in the package list, so `find-package` and the others do not see them (as on the VM, `find-package` before `defpackage` returns NIL). When `make-package` or `defpackage` creates a package of the same name, the pending package is registered and used (Codex review P22 #1; a `make-package` done both at compile time and at run time no longer duplicates the name).
- **Note on CL style**: when a whole file is compiled first (native, `compile-file`), `load`, `use-package` and other forms that change how later forms are read must be wrapped in `eval-when` at top level (`defpackage` and `in-package` already expand into `eval-when`). A `defpackage` that is not at top level, for example inside `print`, is not executed at compile time either. All of this is the same as SBCL's `compile-file`.
- **Fixes from the Codex review of P22**: #1 is the pending packages above. #2 importing a symbol without a home package into a package where it is already present now sets the home package. #3 `shadowing-import` does not change the home package (as in SBCL). #4 making KEYWORD use another package is a simple-error (as in SBCL). #5 with escaping, `NIL` is also qualified as `COMMON-LISP:NIL` when it is not visible from the current package (with a local nickname if there is one; native constants use `COMMON-LISP::NIL`). #6 `defpackage` takes exactly one non-negative integer for `:size` and exactly one string for `:documentation` (a wrong count is a program-error and a non-string a type-error, as in SBCL). Added `ZILISP-SYSTEM::%TYPE-ERROR` to signal type-errors.
- **Fixes**: `collect` in `seqfns.zig` (Phase 21) reserved the total capacity (`ensureTotalCapacity`) when collecting a vector, so `concatenate` could run out of capacity when appending after earlier sequences (an assertion failure in Debug, possible memory corruption in ReleaseFast); it now reserves unused capacity (`ensureUnusedCapacity`). `Thread.create` did not free the VM and other buffers when loading the standard library failed.
- **Tests**: language tests `packages.lisp` (package functions, `defpackage`, `in-package`, printing, the curriculum's shape) and `multi-file.lisp` (name resolution across two loaded files; the acceptance test). Both give the same output as SBCL 2.6.7, also in the GC stress versions and natively. Unit tests for the error kinds (package-error, type-error, program-error, reader errors).
- Results: of the 32 blocks of Level 15, 8 match and 23 fail in both (they use packages defined in earlier blocks); the only Zilisp-only error is `with-open-file` (Phase 23). The curriculum blocks went from 421 to 429 matches.

### 8.3 Standard packages (decided)

| Package | Nickname | use | Contents |
|---|---|---|---|
| `COMMON-LISP` | `CL` | — | All 978 external CL symbols are created at startup |
| `COMMON-LISP-USER` | `CL-USER` | `CL` | The user's default package |
| `KEYWORD` | — | — | |
| `ZILISP` | `ZL` | `CL` | Public extensions (`exit`, `gc-statistics`, etc.) |
| `ZILISP-SYSTEM` | `ZL-SYS` | `CL` | Internal use (primitives starting with `%`, quasiquote, etc.) |

- `CL-USER` uses only `CL` (to avoid name conflicts between curriculum code and extensions).
- The list of the 978 symbol names is kept in the generated file `src/runtime/cl_symbols.zig`, created from the CLHS index. Creating it requires Web access, so permission is obtained at the start of Phase 05. The HyperSpec text is not reproduced.

### 8.4 Case in the Reader and printer

- The default `readtable-case` is `:upcase`, and `*print-case*` is `:upcase`.
- Escapes (`|...|`, `\`), package qualifiers, `#:`, and keywords are implemented in Phases 03–05.

### 8.5 Conditional reading and read-time evaluation (review #23)

| Feature | Handling | Timing |
|---|---|---|
| `#+` / `#-` | Follow `*features*`. Skipped branches are read with `*read-suppress*` true (no error even for nonexistent package qualifiers or unreadable number syntax; CLHS 2.4.8.17, `*read-suppress*`) | Phase 04 |
| `*features*` | At startup, contains `:zilisp`, `:common-lisp`, `:ansi-cl` (names to be decided after checking CLHS conventions), and keywords for the OS and CPU. **In cross builds (§16.2), read with `*features*` for the target OS and CPU, not the build PC** | Phase 04, Phase 36 |
| `#.` | Evaluated only when `*read-eval*` is true. When false, `reader-error` is signaled (CLHS `*read-eval*`) | Phase 24 |
| Default of `*read-eval*` | True (the CLHS default). However, the automatic curriculum collection (§12) reads with it false | Phase 02, Phase 24 |

---

## 9. Run-time structure of conditions and restarts

### 9.1 Condition types

- **Representation in Phase 25** (decided on 2026-11-05): conditions and restarts are `record`s (an ObjKind holding the class description and a simple-vector of slot values; `src/values/object.zig`, `src/primitives/conditions.zig`). Once CLOS exists (Phase 27) they are merged into `instance`s of condition-classes (so as not to decide in advance the outcome of Phase 27's comparison of racks and direct placement).
- The class description is a simple-vector built in Lisp: `#(name CPL direct-superclasses slots report default-initargs direct-slots)`. It is kept in the property `zl-sys::%class` of the class name's symbol. Zig reads only position 0 (the name, for printing) and position 1 (the CPL, for `typep`). The slots are a list of `(name initargs initform-function)`, including those of the superclasses (the value vector follows this order).
- The CPL is computed depth-first, left to right, keeping the last of any repeated class (not the computation of CLHS 4.3.5, but it gives the same result for the diamond in the standard condition hierarchy (`reader-error`); the CLOS phase will use the CLHS computation).
- The hierarchy of the standard condition types is built with `define-condition` in `src/lisp/boot.lisp` (instead of the planned Zig table at bootstrap). Errors found in Zig that carry a description use Zilisp types (`zl-sys::simple-program-error`, `simple-control-error`, `simple-parse-error`, `simple-reader-error`, `simple-package-error`, `simple-stream-error`, `simple-end-of-file`, `simple-file-error`, `simple-storage-condition`; they correspond to SBCL's `SB-INT:SIMPLE-PROGRAM-ERROR` and the like). Unimplemented features signal `zilisp:unimplemented` (a subtype of `simple-condition` and `serious-condition`; **not a subtype of `error`**, so that `ignore-errors` and `(handler-case ... (error ...))` do not silently take unimplemented features; basic design §3.1; decided on 2026-11-05). Unimplemented functions of the COMMON-LISP package (symbols with the unimplemented flag) and CL special variables without a value are also signaled to handlers as `zilisp:unimplemented` (the top-level report keeps the undefined-function and unbound-variable texts).
- `define-condition` handles the slot options `:initarg`, `:initform`, `:reader`, `:writer` and `:accessor` (`:type`, `:documentation` and `:allocation` are accepted and not used), and the options `:report` (a string, a function name or a lambda expression), `:default-initargs` and `:documentation`. `make-condition` takes a slot's value from the initargs, then the default initargs, then the initform. Reading a slot without a value signals `unbound-slot`.
- **The report texts are the same as SBCL 2.6.7** (decided on 2026-11-05): `type-error` is `~@<The value ~@:_~2@T~S ~@:_is not of type ~@:_~2@T~S~:@>`, `arithmetic-error` is `arithmetic error ~S signalled` followed by `Operation was (...).` when there is an operation, `undefined-function` prints the name with its package (printed with `*package*` bound to KEYWORD, like SBCL's `print-symbol-with-prefix`), types without a report print `Condition ~S was signalled.` (with `*package*` COMMON-LISP), and so on. Printing with `*print-escape*` true has SBCL's forms too: `#<SIMPLE-ERROR "control string" {address}>`, `#<TYPE-ERROR expected-type: type datum: value>`, `#<UNBOUND-VARIABLE name {address}>`, `#<type {address}>`. With `*print-readably*` it signals `print-not-readable`.
- Printing is done by the Lisp function `zl-sys::%print-record`, which the Zig printing entry points call (pprint's `outputUgly`; conditions and restarts take the pretty printer's path even when it is off: `streams.emitPrinted`, `printTo`, `format`'s `printed`). With `*print-pretty*` NIL, a condition inside a list is written in Zig's default form `#<type {address}>` (a Phase 25 limitation).
- **Conditions for errors found in Zig**: the type is chosen from the error kind (`ErrorKind`) by `zl-sys::%zig-condition`. type-error (when there is no description and there is an expected type), unbound-variable, undefined-function, division-by-zero (`:operation` and `:operands`; the division sites pass `(operation operand ...)` in `expected`; as in SBCL, `floor`, `mod` and the others use `/` as the operation), floating-point-overflow and the like are the standard types with values and SBCL's report texts. The others are the Zilisp types above, reported with the existing description (Japanese) and the value.

### 9.2 Handlers

- **The handler stack is the special variable `zl-sys::*handler-clusters*`** (changed on 2026-11-05; no stack in Thread and no VM instructions such as `HANDLER_PUSH`). Its value is a list of clusters (newest first); a cluster is `((type . function) ...)`. `handler-bind` dynamically binds the list with a new cluster in front. Exiting non-locally restores it together with the dynamic bindings (the same mechanism as "restore by depth" in §6.4). The VM and native code use the same macro expansion, so neither needs special handling.
- `signal` scans the clusters newest first and calls the handlers whose type satisfies `typep`. While a handler runs, `*handler-clusters*` is bound to the clusters outside that cluster (CLHS 9.1.4.1).
- A handler runs in the dynamic environment of the signaling point (no unwinding).
- `handler-case` (including `:no-error`) and `ignore-errors` are macros in boot.lisp using `handler-bind` + `block`/`tagbody`/`go`.
- **Errors found in Zig** (`th.signal` in §6.6): when there is at least one handler or restart, or `*debugger-hook*` is set, `zl-sys::%signal-zig-error` is called, which makes the condition and signals it to the handlers (and calls `*debugger-hook*` if no handler takes it). If no handler takes it, it returns descriptions of the available restarts and Zig records the error. With none of these, Lisp is not called (and nothing is allocated; as fast as before).
  - For errors in the middle of a VM instruction (`load_special` of an unbound variable and the like), `vm.sp` may not have been written back. So that running the handlers does not overwrite the in-progress values of the current frame, `vm.sp` is raised to the deepest point the top frame can use (`base + nlocals + max_stack`) before the call and restored afterwards. The old values in between are scanned as GC roots too, but they are marked only after `findObject` confirms they point to allocated objects, so this is safe (at worst some garbage is kept).
  - Handlers are Lisp code, so a GC can occur inside `th.signal`. Values in Zig local variables are protected by the conservative scan of the native stack. All the places that continue after calling `th.signal` (about 30 that are not of the form `return th.signal(...)`) were checked to return failure right away. The state of printing and reading in progress (`pp_circle`, `pp_level`, `read_builder`) is not passed on to the handlers. Calls to handlers nest at most 32 deep (`max_signal_depth`, so that an implementation bug cannot raise the same error forever).
  - **Stack overflows are not signaled to handlers** (`th.stackExhausted`: the VM value stack and frames, the native stack, nesting of Zig functions, the dynamic binding and control stacks). There is no reserve area to run handlers in (a Phase 25 limitation; SBCL has one).

### 9.3 Restarts

- The restart stack is the special variable `zl-sys::*restart-clusters*` (a list of lists of restarts, newest first), dynamically bound by `restart-bind`. A restart is a record with the slots {name, function, report function, interactive function, test function, associated conditions}.
- `restart-case` is a macro using `restart-bind` + `block`/`tagbody`/`go`. When the form is a call of `error`, `cerror`, `signal` or `warn`, the condition is made first and the restarts are associated with it by `with-condition-restarts` (CLHS restart-case). Restarts associated with a condition are visible only when that condition is given (CLHS 9.1.4.2.4).
- Functions and macros: `restart-bind`, `restart-case`, `with-simple-restart`, `with-condition-restarts`, `compute-restarts`, `find-restart`, `invoke-restart`, `invoke-restart-interactively`, `restart-name`, and the standard restart functions `abort` and `muffle-warning` (control-error without a restart), `continue`, `store-value` and `use-value` (NIL without a restart).
- No toplevel restarts are made (SBCL's `--script` has RETRY, CONTINUE and ABORT; `compute-restarts` differs only in these).

### 9.4 Debugger (D-4)

| Execution mode | Behavior on an unhandled `error` |
|---|---|
| REPL | Shows the condition's type, report and location, the list of available restarts (number, name and report), and the call history (newest first, up to 16 entries) (from Phase 25; before that, the type, description, location and the call history). Running `invoke-restart` by entering a number comes in a later phase (decided on 2026-11-05) |
| `--script` / source execution / built executable | Prints the condition, the list of restarts (if any) and the call history to standard error and exits with **exit code 1** |

- `invoke-debugger` calls `*debugger-hook*` (with it bound to NIL), and if that returns, returns to the top level (`zl-sys::%unhandled-condition`). For errors found in Zig too, `*debugger-hook*` is called when no handler takes the error (§9.2). The frames of the standard library functions that signal conditions, such as `error` and `invoke-debugger`, are left out of the call history.
- An unhandled `warning` is written to `*error-output*` as `WARNING: report` and execution continues (as in SBCL). The `muffle-warning` restart stops it.

---

## 10. CLOS: class table, standard method combination, cache invalidation

### 10.1 Classes

```zig
pub const Class = struct {
    header: ObjHeader,
    name: Value,
    metaclass: enum { standard, structure, built_in, condition },
    direct_superclasses: Value, direct_slots: Value, default_initargs: Value,
    cpl: Value,              // computed with the algorithm of CLHS 4.3.5 "Determining the Class Precedence List"
    layout: Value,           // current layout
    finalized: bool,
    direct_subclasses: Value,
};
```

- The table for `find-class` (symbol → class) is held in `Runtime.classes`.
- Classes and CPLs of built-in types are defined in a Zig table as described in CLHS (e.g. `null` → `(null symbol list sequence t)`). `class-of` is computed by looking up the table from the Value tag and ObjKind.
- If the CPL is inconsistent, it is an error at `defclass` time.

### 10.2 Instances and redefinition

**Class numbers (stamps)** (S1; SICL's method: `Specification/chap-object-system.tex` lines 44–49)
- A class is assigned a **new number** when it is created and when it is changed. Numbers are assigned sequentially from 0, and **old numbers are never reused**.
- When a class is redefined (changes to slots or superclasses), that class and **all of its subclasses** are assigned new numbers (because the CPL and slot layout may change).
- Built-in classes and structure classes also have numbers. The number can be obtained from any Value with the same table lookup as `class-of`.

**Instance representation** (S2; SICL's method: `Specification/chap-data-representation.tex` lines 97–190)

```text
instance                      rack
┌──────────────┐          ┌──────────────────┐
│ header       │          │ header           │
│ class        │          │ stamp (at create)│
│ rack ────────┼────────▶ │ layout           │
└──────────────┘          │ slot 0 … n       │
                          └──────────────────┘
```

- The instance body holds only pointers to the class and the rack. Values of **local slots** (`:allocation :instance`) are placed in the rack. Values of **shared slots** (`:allocation :class`) are placed in the class, not in the rack. Uninitialized slots are unbound.
- The instance body does not move, so even when the rack is replaced, object identity and the assumption of a non-moving GC are preserved.
- **Cost**: each slot read requires one more load through the rack. **In Phase 27, compare speed with a method that places slots directly in the instance body (placing a forwarding pointer on redefinition), and adopt the faster one.**

**Class redefinition and instance update** (review #7; CLHS 4.3.6 "Redefining Classes", `make-instances-obsolete`, `update-instance-for-redefined-class`)

- If the stamp of an instance's rack differs from the class's current number, the instance is obsolete. The obsolescence check is always performed on every dispatch and slot access, by the procedure of §10.4.
- When an obsolete instance is accessed, it is updated by the **standard procedure**.
  1. Create a rack with the new layout.
  2. Slots defined as local slots in both the old and the new class keep their values.
  3. Compute the list of added local slots, and the discarded local slots (including those changed to shared slots) with a property list of their values.
  4. After replacing the rack, call `update-instance-for-redefined-class` with the instance, the added slots, the discarded slots, and the property list as arguments. Its default method is `shared-initialize`, which initializes the added slots with their initforms.
- **`change-class`** (CLHS `change-class`, `update-instance-for-different-class`): make a copy of the original instance, replace the rack with one for the new class, carry over the values of local slots common to both, and call `update-instance-for-different-class` with the copy, the instance, and the initialization arguments as arguments.
- If the user defines methods on these generic functions, those methods are called (supported in 1.0).
- Redefinitions not supported in 1.0 (such as changing the metaclass) **signal an error instead of executing with changed meaning** (basic design §3.1: never silently return a different result).

### 10.3 Generic functions and methods

- Method functions are generated as functions with the hidden arguments `%next-methods` / `%args`. `call-next-method` and `next-method-p` refer to them.
- **Arguments of `call-next-method`** (agy #5; CLHS `call-next-method`): when called with no arguments, it passes the arguments the current method received (`%args`). When called with arguments, those arguments are passed to all subsequent methods (when called from `:around`, all of the remaining `:around`, `:before`, primary, and `:after` methods). If the ordered set of applicable methods for the new arguments differs from that for the original arguments, an error is signaled (as specified by CLHS; the check may be omitted at `safety` 0).
- **Standard method combination** (review #5; CLHS 7.6.6.2 "Standard Method Combination")
  1. If **there are no applicable methods**, call `no-applicable-method`.
  2. If **there are applicable methods but no applicable primary method**, signal an error. The same applies when there are applicable `:around` methods (CLHS 7.6.6.2: "if there is an applicable method but no applicable primary method, an error is signaled". It was confirmed that in SBCL 2.6.7 too, calling a generic function that has only `:around` results in `NO-PRIMARY-METHOD-ERROR`).
  3. If there are `:around` methods, call the most specific `:around`. `call-next-method` calls the next `:around`; when called from the last `:around`, it calls the combined processing of steps 4–6 below. The return value of `:around` becomes the return value of the generic function.
  4. Call all `:before` methods, most specific first. Their return values are not used. Using `call-next-method` inside `:before` signals an error (CLHS 7.6.6.2).
  5. Call the most specific primary method. `call-next-method` calls the next most specific primary (primaries are **not all called automatically**; they are called through a chain of `call-next-method`). Calling `call-next-method` when there is no next primary calls `no-next-method`. **All values** of the most specific primary become the return values of the processing of steps 4–6.
  6. If there are `:after` methods, **save all values** of step 5 (§6.3), then call all `:after` methods, least specific first. Return values of `:after` are not used. When finished, return the saved values (agy #5). Using `call-next-method` inside `:after` signals an error (CLHS 7.6.6.2; agy #5).
  - Inside `:before` and `:after`, `next-method-p` is also made unavailable (the hidden arguments are not passed).
- Specificity is determined by comparing the position of each argument's class in the CPL, in argument precedence order (left to right by default). An `eql` specializer is more specific than any class.
- `define-method-combination` and method combinations other than `standard` are not supported in 1.0, and specifying them is an error.

### 10.4 Dispatch cache and invalidation

- Each generic function has a cache of "**tuple of numbers (stamps)** of the arguments in specializer positions → effective method function" (S1). The fast path of a call only extracts the argument numbers and looks up the cache by **integer comparison**. At positions with an `eql` specializer, the value is also compared.
- Which argument positions are used as specializers (the specializer profile) is recorded per generic function, and numbers are not extracted for arguments in unused positions (SICL `Code/CLOS/compute-discriminating-function-support.lisp` lines 24–49).
- Invalidation rules
  - `add-method` / `remove-method`: clear the cache of that generic function.
  - Class definition and redefinition: **do not clear the whole cache**. Assign new numbers to the redefined class and its subclasses, and **at that moment remove only the cache entries that contain old numbers** (review #6).
    - The racks of obsolete instances still hold old numbers. If entries with old numbers were left in place, obsolete instances would match them and be processed by the old effective method without being updated. Therefore, entries are always removed at redefinition time, not "deleted when the cache is full".
    - To narrow the removal targets, each class holds a list of "generic functions and accessors whose caches contain this class's number". On redefinition, only the caches of the generic functions and accessors in that list are examined.
  - Since entries with old numbers are gone, obsolete instances never match the cache. On the slow path after a miss, **first check whether the instance is obsolete**; if so, update it with the procedure of §10.2 and look up again. A new cache entry is never created with an old number.
  - This corresponds to SICL's method (`Specification/chap-data-representation.tex` lines 180–186: obsolete instances fail discrimination and are updated).
- Accessors (`:reader`, `:accessor`) cache the slot index **per number**, and on a match read directly from the rack by index. Accessor caches also remove entries with old numbers by the same rules as above.
- **Later-stage speedup (S3)**: from the call records, generate code that branches by comparing numbers (discrimination code) and place it at the entry of the generic function (SICL's discriminating automaton: `Code/CLOS/discriminating-automaton.lisp`, `compute-discriminating-function-support-c.lisp` lines 11–80). In the native backend, this branching is compiled to machine code. On a miss, it falls back to generic dispatch.

### 10.5 defstruct

- Defined as a `structure-class`. Slots are a fixed array, and accessors are ordinary functions subject to inlining.
- Supports `:include` (single inheritance), `:constructor` (including BOA), `:copier`, `:predicate`, `:conc-name`, and `:print-object` / `:print-function`.
- When `:type` is specified for a slot, it is used by the native backend's type inference.

---

## 11. Bootstrap order and loading the standard library

### 11.1 Startup steps

1. Initialize the heap (page table) and the thread state, and record the top-of-stack position.
2. Create the NIL symbol object, and create `CL`, `KEYWORD`, `CL-USER`, `ZILISP` and `ZILISP-SYSTEM`.
3. Intern the 978 CL symbols, and set up constants and special variables. Mark the ones that are not implemented with `unimplemented`.
4. Register the Zig primitives (the registration tables in `src/primitives/`).
5. Create the built-in classes and the condition class hierarchy.
6. Register the bootstrap macros written in Zig: `defmacro`, `defun`, `lambda`, `zl-sys:quasiquote`, `setf` (minimal version), `in-package` (minimal version).
7. Initialize the standard library (§11.3).
8. Set `*package*` to `CL-USER`, and start the REPL, the script, or the entry function.

### 11.2 Load order of the standard library written in Lisp

**As of Phase 15**: `src/lisp/boot.lisp` (embedded in the executable) is loaded by the VM each time a thread is created (`src/compiler/boot.zig`). It contains the standard macros built on top of the Zig `defmacro` and `defun` (`when`, `unless`, `cond`, `and`, `or`, `case`, `prog1`, `prog2`, and `incf`, `decf`, `push`, `pop` when the place is a variable). During loading, definitions on CL package symbols are allowed (`Runtime.booting`). The startup time increases by about 1 ms (ReleaseFast, x86_64-windows: `zilisp --eval nil` goes from 6.1 ms to 7.1 ms). When the standard library grows, we move to the two-stage build of §11.3 (compile it to native code and build it in).

**Startup time per phase (measured 2026-11-03)**: the commit of each phase was built with ReleaseFast and `zilisp --eval nil` was run 31 times (median, x86_64-windows). An empty Zig program measured the same way takes 4.08 ms.

| Phase | boot.lisp (non-empty lines) | Median | Executable size |
|---|---|---|---|
| P14 | 0 | 5.80 ms | 1.27 MB |
| P15 | 93 | 6.33 ms | 1.31 MB |
| P16 | 218 | 6.65 ms | 1.35 MB |
| P17 | 246 | 6.88 ms | 1.37 MB |
| P18 | 249 | 7.08 ms | 1.42 MB |
| P19 | 698 | 7.95 ms | 1.48 MB |
| P20 | 708 | 8.21 ms | 1.60 MB |
| P21 | 949 | 8.80 ms | 1.72 MB |
| P21.5 | 949 | 8.82 ms | 1.79 MB |
| P21.6 | 949 | 8.74 ms | 1.79 MB |
| P22 | 1016 | 9.08 ms | 1.85 MB |
| P23 | 1061 | 9.47 ms | 1.97 MB |
| P25 | 1933 | 13.55 ms | 2.35 MB |

- Each 100 non-empty lines of boot.lisp add about 0.3 ms. In P21, about 4.1 ms is the process startup that an empty program also takes, about 1.7 ms is the setup before boot.lisp, and about 3.0 ms is loading boot.lisp.
- **Rule (2026-11-03 decision)**: at the end of each phase, measure the startup time in the same way and record it in the CHANGELOG and in this table. When it exceeds **20 ms**, move the two-stage build of §11.3 forward.

| Order | File (`lisp/bootstrap/`) | Contents |
|---|---|---|
| 00 | `00-base.lisp` | `when` `unless` `cond` `and` `or` `prog1` `psetq` `do` `dotimes` `dolist` `case` `typecase` etc. |
| 10 | `10-setf.lisp` | `defsetf`, `define-setf-expander`, `get-setf-expansion`, `push` `pop` `incf` etc. |
| 20 | `20-list-seq.lisp` | The list and sequence functions that are written in Lisp |
| 30 | `30-loop.lisp` | The `loop` macro (**our own implementation**. D-3. It adds type declarations to variables so that it expands to fast code) |
| 40 | `40-conditions.lisp` | `handler-case` `ignore-errors` `restart-case` `check-type` `assert` etc. |
| 50 | `50-defstruct.lisp` | `defstruct` |
| 60 | `60-clos.lisp` | `defclass` `defgeneric` `defmethod` `with-slots` etc. (the dispatch core is in Zig) |
| 70 | `70-package.lisp` | `defpackage`, the `do-symbols` family |
| 80 | `80-io.lisp` | `with-open-file` `with-output-to-string` etc. |

- The cores of `print`, `read` and `format` are implemented in Zig.

**As of Phase 19**: to pass the iteration curriculum (Level 6), parts of rows 00, 20 and 30 of the table above and a minimal `format` were implemented ahead of schedule (decided on 2026-11-02).
- The iteration section of `src/lisp/boot.lisp`: `psetq`, `dolist` and `dotimes` (the body is an implicit tagbody; the result is evaluated with the variable bound to NIL for dolist and to the count for dotimes, as in CLHS), `do`, `do*`, `mapcar`, `mapc`, `mapcan`, `nconc`, `reduce` (`:key`, `:from-end`, `:start`, `:end`, `:initial-value`) and `loop`.
- **loop** (our own implementation): `named`, `with`, `for`/`as` (`from`, `upfrom`, `downfrom`, `to`, `upto`, `below`, `downto`, `above`, `by`; `in` and `on` (with `by`); `= … then`; `across`; `being the hash-keys`/`hash-values` (with `using`)), `repeat`, `initially`/`finally`, `do`, accumulation (`collect`, `append`, `nconc`, `sum`, `count`, `maximize`, `minimize`, with `into`), `while`/`until`, `always`/`never`/`thereis`, `return`, `when`/`if`/`unless` (with `and`, `else`, `end`, `it`), `loop-finish` and destructuring of variables. The expansion is `(block name (let* (bindings...) (tagbody prologue first-tests body-tag body steps-and-tests (go body-tag) end-tag epilogue (return-from name default-value))))`. The for clauses step, test and assign in clause order (the same order as SBCL 2.6.7). always, never and thereis return without running the epilogue (CLHS 6.1.4). The end tag is `zl-sys::%loop-end` (`loop-finish` goes there; in nested loops the inner tag is visible). Unsupported clauses (parallel binding with `and` in for and with, `being` with `elements`, `symbols` and so on) are explicit errors. No type declarations are added to the variables yet (speed improvements in a later phase).
- Functions written in Zig: `evenp`, `oddp`, `zerop`, `plusp`, `minusp`, `max`, `min`, `abs`, `mod`, `rem`, `reverse`, `nreverse`, `copy-list`, `last`, `endp`, `symbol-name`, `string=`, `string-upcase`, `string-downcase`, `char=`, `princ` and a minimal `format`. Case conversion handles ASCII characters only (the same as the reader; SBCL 2.6.7 also converts Unicode characters).
- **Minimal format**: the destination is `T` (standard output) or `NIL` (returns a string). Directives: `~A`, `~S`, `~D`, `~%`, `~&`, `~~` and `~` followed by a newline. Directives with parameters or modifiers (`~5D`, `~:A`), other directives and other destinations are explicit errors (the full implementation comes in Phase 24). For `~&`, the thread remembers whether standard output is at the start of a line (`Thread.line_start`). A missing argument is a `simple-error` (SBCL 2.6.7 uses its own `format-error`).
- Result: of the 48 Level 6 blocks, 41 match and 7 fail on both (none fail only on Zilisp). Matching curriculum blocks went from 244 to 347.

**As of Phase 21**: the character, string, sequence, list and set functions (row 20 of the table above). The functions that take `:test`, `:key` and similar arguments are written in Zig for speed; the rest are in `boot.lisp`.
- **Zig** (`src/primitives/seqfns.zig`): `member`, `assoc`, `rassoc`, `find`, `position`, `count`, `remove`, `delete`, `substitute`, `nsubstitute` (each with the `-if` and `-if-not` forms), `remove-duplicates`, `delete-duplicates`, `sort`, `stable-sort` (a stable merge sort for both; lists are sorted by permuting the cars, vectors in place), `search`, `mismatch`, `elt` (and setf), `subseq`, `fill`, `replace`, `concatenate`, `coerce`, `make-sequence`, `map`, `map-into`, `some`, `every`, `notany`, `notevery`, `make-list`, `list-length` (NIL for circular lists). `:test` and `:test-not` of `eq`, `eql` and `equal` are compared without calling the function; `member` without keywords takes a fast path. `delete` and its variants return a new sequence (allowed by CLHS 17.2). The `:test` and `:key` functions are called in element order (also with `:from-end`; CLHS does not specify the order). Elements may be kept temporarily in a Zig array; they stay reachable from the original sequence, so the GC does not collect them (results are written back only at the end).
- **Result types** (`concatenate`, `coerce`, `make-sequence`, `map`, `merge`): `list` (and `cons`, `null`), `vector`, `simple-vector`, `array`, `simple-array`, `string`, `simple-string`, `base-string`, `simple-base-string`, and compound specifiers such as `(vector character)` and `(simple-array character (*))`. A length in the specifier is checked, and so are `cons` (at least one element), `null` (no elements) and the rank of `array` specifiers (`(array t (2 3))` is not a sequence type); a mismatch is a `type-error` as in SBCL 2.6.7. Other types are explicit errors. Lists given to `map`, `map-into`, `some`, `every`, `notany` and `notevery` must be proper lists (`type-error` otherwise). `coerce` also handles `character`, the float types, `t`, `function` and the number types (`number`, `real`, `rational`, `integer`; the object is returned when it is of that type).
- **Zig** (`src/primitives/strings.zig`): `characterp`, `char-code`, `code-char` (`char-code-limit` is #x110000), `char-int`, `char-upcase`, `char-downcase`, `upper-case-p`, `lower-case-p`, `both-case-p`, `alpha-char-p`, `alphanumericp`, `digit-char-p`, `digit-char`, `graphic-char-p`, `standard-char-p`, the `char=` and `char-equal` families, `string`, the `string=` and `string-equal` families (the result is the mismatch index), `string-upcase`, `string-downcase`, `string-capitalize` and their `nstring-` forms, `string-trim`, `string-left-trim`, `string-right-trim`, `make-string`, `parse-integer` (bignums; `parse-error`, or NIL with `:junk-allowed`). Character classes and case cover ASCII characters only (SBCL 2.6.7 uses Unicode; recorded in `tests/differential/impl-dependent.toml`). **Unicode support (2026-11-03 decision)**: Phase 21.5 (tque #342) makes the CL character functions and the case conversion of the Reader and Printer follow Unicode 15.0.0, the version used by SBCL 2.6.7, in the same way as SBCL's CL functions (general category, simple one-to-one case mappings that round-trip; tables generated from the bundled UCD files, which are under the Unicode License v3). The implementation is described below under "Implementation in Phase 21.5". Unicode character names (`char-name`) and SBCL's `sb-unicode` functions are out of scope. A new error kind `parse_error` was added.
- **Lisp** (`src/lisp/boot.lisp`): `identity`, `complement`, `constantly`, `acons`, `pairlis`, `copy-alist`, `copy-tree`, `revappend`, `nreconc`, `butlast`, `nbutlast`, `tailp`, `ldiff`, `mapl`, `maplist`, `mapcon`, `subst`, `subst-if`, `subst-if-not`, `nsubst`, `nsubst-if`, `nsubst-if-not`, `sublis`, `nsublis` (the `n` forms replace cars and cdrs of the tree), `tree-equal` (returns T or NIL), `adjoin`, `union`, `intersection`, `set-difference`, `set-exclusive-or`, `subsetp` (and their `n` forms, which do not destroy their arguments). `butlast` and `nbutlast` accept dotted lists, `merge`, the macros `pushnew` and `remf`, and the places `elt` and `subseq`. The order of the results of the set functions is the same as SBCL 2.6.7 (`union` scans the shorter list and pushes onto the longer one).
- Errors as in SBCL 2.6.7: a bad `:start`/`:end` and an out-of-range `elt` are `type-error`s (SBCL's `bounding-indices-bad-error` and `index-too-large-error` are subtypes of `type-error`); a wrong number of subscripts is a `simple-error`.
- Result: of the 25 Level 11 blocks, 19 match and 6 fail on both (none fail only on Zilisp). In Level 7 and Level 10, the remaining Zilisp-only failures are `defstruct` (Phase 26) and `format` directives (Phase 24). Matching curriculum blocks went from 362 to 421.
- Tests: 139 cases compared with SBCL 2.6.7 (also under GC stress, and natively in `sequence-cases.lisp`), large sequences under GC stress, and error kinds. Language test `sequences.lisp` (a data processing sample; also a gc-stress version).

**Implementation in Phase 21.5 (Unicode 15.0.0)**
- **Data**: `data/unicode/` holds `UnicodeData.txt` and `SpecialCasing.txt` of UCD 15.0.0 (taken from the SBCL 2.6.7 tag; their SHA-256 matches the files in `Public/15.0.0/ucd/` on unicode.org) and the text of the Unicode License v3 (`LICENSE.txt`). The distribution packages (ZIP, tar.gz and the installer) include it as `LICENSE-UNICODE.txt`.
- **Generator**: `tools/gen_unicode/main.zig` (`zig build gen-unicode`) writes `src/unicode/tables.zig` (formatted with `std.zig.Ast`, in the same form as `zig fmt`). **The tables are committed**, because the native backend compiles `src/lib.zig` directly with `zig build-exe -Mzilisp=src/lib.zig`, so tables generated during the build cannot be used (a change from the 2026-11-03 decision to generate them at build time). `zig build test` checks that the committed tables are the ones generated from the UCD (`--check`; CRLF line endings count as the same). The reader comparison tool (reader-check) now uses the `src/lib.zig` module instead of a reader-only module (which cannot read `src/unicode/`, outside its module root).
- **Tables** (about 70 KB in all): a two-stage table of character properties (pages of 256 characters; the first stage is 4,352 bytes, the second 118 pages, 30,208 bytes; one byte holds "letter" (general category L*), Nd, and the decimal digit value) and a case table (pages of 64 characters; the first stage is 1,958 bytes, the second 65 pages with 4,160 lowercase and 4,160 uppercase code points).
- **Construction** is the same as SBCL 2.6.7's `tools-for-build/ucd.lisp`: the unconditional entries of `SpecialCasing.txt` override the simple mappings of `UnicodeData.txt`, and only one-to-one mappings that round-trip make characters with case (2,708 characters; mappings to several characters, such as the uppercase of ß, are excluded).
- **Difference from SBCL 2.6.7**: the four characters that are neither uppercase nor lowercase (U+01C5 ǅ, U+01C8, U+01CB and U+01F2; titlecase) are characters without case (CLHS 13.1.4.3). In SBCL `both-case-p` is T, `char-upcase` returns the uppercase letter and `char-equal` is not symmetric (`(char-equal ǅ ǆ)` is T, `(char-equal ǆ ǅ)` is NIL). All other characters are the same as SBCL, so `char-equal`, `char-lessp` and `equalp` only need to compare the values of `char-downcase`.
- **Functions** (`src/unicode/unicode.zig`): `isAlpha`, `isAlnum`, `isUpper`, `isLower`, `hasCase`, `upcase`, `downcase`, `digitWeight`. ASCII characters do not look up the tables. As in SBCL 2.6.7, `digit-char-p` does not treat U+0080 to U+0660 as digits (SBCL checks code points up to U+0660 with the ASCII rule, so ARABIC-INDIC DIGIT ZERO U+0660 is NIL while U+0661 and later are digits). `graphic-char-p` does not use the tables (32 to 126, and 160 or more).
- **Used by**: the character and string functions (`src/primitives/strings.zig`), `equalp` and its hashing, the reader's conversion to uppercase (`syntax.upcase`; `λx` reads as `ΛX`, `é` as `É`), and the printer's decision to put a symbol name in bars (names with Unicode lowercase letters are put in bars). `parse-integer` also reads non-ASCII decimal digits (as in SBCL).
- **Remaining differences** (`tests/differential/impl-dependent.toml`): `char-case-titlecase` (the four characters above), `reader-symbol-normalization` (SBCL's reader normalizes symbol names with NFKC), `reader-number-non-ascii-digits` (SBCL's reader reads `١٢` as 12; Zilisp reads a symbol), and character names (`reader-character-unicode-names`, `printer-character-names`; out of scope). The three Unicode items (`reader-upcase-non-ascii`, `string-case-non-ascii`, `char-class-non-ascii`) and `printer-non-ascii-symbol-escape` were removed because the differences are gone.
- **Tests**: every code point (0 to #x10FFFF) is compared with nine results of SBCL 2.6.7 (`alpha-char-p`, `alphanumericp`, `upper-case-p`, `lower-case-p`, `both-case-p`, `graphic-char-p`, `digit-char-p` in radix 36, `char-upcase`, `char-downcase`) in `src/unicode/testdata/sbcl-2.6.7-chars.txt` (one line per run of equal results, 3,409 lines; produced by running `tools/gen_unicode/sbcl-chars.lisp` with SBCL 2.6.7). Round-trip of case pairs (CLHS 13.1.4.3). Reader tests. Language test `unicode.lisp` (the same output as SBCL 2.6.7; the three different lines are recorded in comments).
- Results: the curriculum blocks still match in 421 cases (0 output differences). Startup time is 8.82 ms (8.80 ms in P21; the tables are constants embedded in the executable and add no work at startup; the executable grows from 1.72 MB to 1.79 MB).

### 11.3 Building the standard library

- **Phase 08–11**: The Lisp standard library is embedded with `@embedFile` and compiled for the VM at every startup (a temporary arrangement until the native backend exists).
- **Phase 12 and later**: `build.zig` has two stages.
  1. The first-stage zilisp (stage1; the version that runs the standard library on the VM) converts the standard library from Core IR to Zig source.
  2. The second stage compiles the generated Zig source together with the runtime and produces the final zilisp. **The standard library becomes native code**, and compilation at startup is no longer needed.
- `zilisp build` uses the same mechanism (§15).
- For the startup time of the implementation itself, we make the same decision as in "Startup time measures (J1)" in §15.3.

---

## 12. A–E classification of curriculum samples and the list of required functions (procedure)

The classification work itself is done separately, as the deliverables `compatibility/curriculum-inventory.md` and `compatibility/manifest.toml`.

1. Fetch `fukuyori/CommonLispBasicMaster` from GitHub, and pin the target commit SHA.
2. With `tools/extract_samples/` (Zig), extract the `lisp` code blocks from the Markdown, and give each an ID of the form `level / file / line number`.
3. Read each block with SBCL 2.6.7 (confirmed to be present on the development machine), and automatically collect whether there are Reader errors, references to external packages, and the CL symbols used.
   - **Only read; do not evaluate.** Set `*read-eval*` to false to forbid read-time evaluation via `#.` (review #23. At the stage where we only collect curriculum code, we do not run arbitrary code).
   - Record blocks that reference a non-existent package as errors (used to detect dependencies on external packages).
   - Work that needs to run code and examine the results (such as creating expected values for differential testing) is kept separate from this collection and done by the procedure in §13.
4. Based on the automatically collected results, finalize the A–E classification by hand (basic design §2.2).
5. Build a usage frequency table of CL symbols, and use it to prioritize which `unimplemented` marks to remove.

---

## 13. Differential testing against SBCL and performance measurement

### 13.1 Differential testing

**Running curriculum blocks** (from Phase 13): `zig build eval-check -Dsbcl=<path to SBCL>` runs the curriculum blocks whose candidate classification is A (955 blocks) with Zilisp (VM, `--script`) and SBCL 2.6.7 (`--script`), each block in its own empty working directory (time limit 10 seconds), and compares the results. The results are written to `compatibility/eval-status.md` (totals, and a breakdown of the first error of the blocks where only Zilisp fails) and `compatibility/eval-check.tsv` (per block). They serve as input for prioritizing features that are not implemented. As of Phase 13: 82 match, 362 fail in both (for example, blocks that use definitions from previous blocks), 0 differ in output, 511 fail only in Zilisp (all due to features that are not implemented).

- The test Lisp files are written to run on both SBCL and Zilisp, and they print their results as normalized strings.
- `tools/compare_sbcl/` (Zig) runs both, compares the outputs, and classifies the differences (bug / implementation-dependent / not implemented). The expected SBCL output is stored in `tests/differential/*.expected`.
- **The same tests are run on both the Zilisp VM and Zilisp native code**, and the three (SBCL, Zilisp VM, Zilisp native) are compared.
- **The ANSI test suite (ansi-test) is run in both a VM-only configuration and a native configuration** (R6). ECL runs ansi-test in both a bytecode-only configuration and a configuration with a C compiler, and maintains a list of items expected to fail (`src/tests/config.lsp.in` lines 94–97 and 137–139, `src/tests/ansi-test-expected-failures.sexp`). Zilisp also manages the items that fail outside the implemented scope in `tests/ansi/expected-failures`. The source and license of ansi-test are **not verified** (check before importing it).

| Compared | Not compared (normalized or excluded) |
|---|---|
| Return values (`prin1` representation), number of multiple values | The address part of `#<...>` |
| Standard output and standard error output | Hash table iteration order (sorted before comparison) |
| Type of the signaled condition (`typep` against standard types) | Wording of error messages |
| Side effects (file contents, etc.) | Least significant digits of floats (tolerance specified per test) |
| | Implementation constants, output of `room` and `time` |
| | Behavior that the CLHS states as undefined or implementation-dependent |

Implementation-dependent differences are recorded in `tests/differential/impl-dependent.toml` with their justification (CLHS section number) and excluded. SBCL's results are not treated as the standard.

**Tests of paths that mix methods** (review #22)

Passing the same tests with the VM only and with native code only does not find bugs at the boundary between the methods. Tests for the following combinations are placed in `tests/language/mixed/`.

| Test target | Combinations |
|---|---|
| Call paths | VM → native → VM, native → VM → native. Includes code in shared libraries (§7A.6) |
| Processing that crosses the boundary | Passing multiple values, `unwind-protect` cleanup (normal exit, non-local exit, exit inside cleanup), undoing dynamic bindings, exits across `handler-bind` / `restart-case`, GC in the middle of a boundary (`--gc-stress`) |
| Entry replacement | Function objects obtained before replacement, closures created before replacement, redefinition during compilation (the job generation number in §7A.6) |
| FFI | Re-entry from the same thread in a callback (§6.1) |

### 13.2 Performance measurement (the foundation for speed first)

- Benchmarks are placed in `tests/bench/` and run with `zig build bench`. The results (execution time, allocated bytes, GC count and pause time) are recorded in `bench-results/` and compared with the previous results.
- Target workloads: fixnum arithmetic, float arithmetic, list operations, recursion (fib, tak), closures, hash tables, strings, CLOS dispatch, file I/O, startup time.
- The same benchmarks are also run on SBCL as reference values for comparison (with the optimization settings stated).
- **When a change that lowers performance is introduced, record the measurement values and the reason** (basic design §17).
- **Reconsidering the GC method** (review #21): 1.0 uses a non-moving mark-and-sweep GC, but in Phase 30 we measure the share of GC time and the pause time in workloads that mix long-lived data and short-lived conses (assuming curriculum data processing and long REPL sessions). **If GC time exceeds a certain share of execution time (initial proposal 20%), we reconsider introducing generational GC before 1.0.**

---

## 14. Compiled module format (`.zfasl`)

### 14.1 Structure (decided)

```text
Header
  magic          "ZLFASL\0\0" (8 bytes)
  format_version u32         ── version of the format, IR and bytecode. Loading is refused on mismatch
  zilisp_version string
  flags          u32
  checksum       u32 (CRC32 over everything except the header)
Sections
  STRS   string table (UTF-8)
  SYMS   symbol references (package name + symbol name, identifiers of uninterned symbols)
  OBJS   literal objects. Shared and circular structure is expressed by object IDs
  CIR    Core IR (with type information) ── the input from which zilisp build generates native code
  CODE   bytecode (used when loading into the VM)
  TOPL   sequence of top-level forms. Each form holds references to the symbols and constants it uses
  LTV    list of load-time-value forms
  SRCS   source file name table
```

- By **storing the Core IR**, `zilisp build` can generate native code without macroexpanding the source again.
- **Load order** (review #8): symbols and constants are **not resolved all at once**. The TOPL forms are processed in order from the start, and just before each form runs, only the symbols and constants that form uses are resolved.
  - This way, the effects of earlier top-level forms in the same file (`defpackage`, `in-package`, `use-package`, `shadow`, `import`, etc.) are reflected in the symbol resolution of later forms (the same order as when the source is `load`ed. CLHS `defpackage`, 3.2.4).
  - Packages are not created ahead of time at load. If the package does not exist at the time of symbol resolution, `package-error` is signaled.
  - **Uninterned symbols** (such as `#:foo`) are created separately from the `intern` path, exactly one per identifier in the file. All places in the same file that refer to the same identifier share the same symbol (identity is preserved).
  - Once resolved, symbols and constants are reused, keyed by their ID within the file.
- The evaluation order and meaning of top-level forms are the same for `load` in the REPL and for startup of a built executable.
- Loaded bytecode is verified before use, even in release builds (§7.4, review #20). The lengths of the header and sections, indices and reference ranges are also checked at load time.
- Identity and similarity of literals follow CLHS 3.2.4. Structure and instance literals require `make-load-form`; if there is none, it is an error at compile time.
- The format does not depend on endianness and is shared by all targets.

---

## 15. Generating executables (`zilisp build`) (D-2, D-5, D-7)

### 15.1 Method

`zilisp build` compiles all functions of the application to native code and links them with the runtime. Data and machine code go into the regular sections of the executable, so it can be signed on Windows (Authenticode) and on macOS (codesign).

**Comparison with SBCL's method**: SBCL's `save-lisp-and-die :executable t` **appends the core to the end** of the runtime, and finds the position of the core from a marker at the end of the file (verified: `src/runtime/coreparse.c` lines 104–112). On macOS, there is a report that because the appended data lies after the signature area, `codesign` strict validation fails, and a workaround that splits the core into a separate file is needed (see the references in §20; this is a report in a developer's release notes, not SBCL's official documentation). To avoid this problem, Zilisp links instead of appending (D-2).

### 15.2 Processing flow

```text
zilisp build --manifest zilisp.toml
 1. Read the manifest (entry, sources, target, optimize)
 2. In a fresh compilation environment, "compile-file → load" the sources in order
    (so that later files can use the macros and packages of earlier files)
 3. Generate Zig source from the Core IR of each source (§7A). Phase 12–34 generate directly from the in-memory Core IR; Phase 35 and later use the Core IR stored in .zfasl and skip compiling unchanged files (agy #8)
 4. Generate main.zig and the build description in the working directory (.zilisp-cache/build/<target>/)
 5. Using the ZIG environment variable or zig on PATH, compile the generated source together with the runtime source bundled with the SDK (D-5)
 6. Output: app(.exe) and app.deps.txt (Zilisp version, target, optimization mode, linked external libraries)
```

- The default optimization mode is **ReleaseFast** (speed first). If safety checks inside the runtime (such as Zig bounds checks) are needed, specify `optimize = "ReleaseSafe"`. Lisp safety checks (such as `type-error`) are independent of the Zig optimization mode and follow `safety` in the `optimize` declaration.
- The executable includes the compiler and the VM for `eval`, `compile` and `load` at run time. Because Zig is not present on the target machine, code that is `eval`ed or `load`ed at run time runs on the VM (see "limitations" in §7A.6).

### 15.3 Startup order

1. Initialize the runtime (steps 1–6 of §11.1).
2. Initialize the standard library (native code).
3. Initialize the application modules in manifest order (run their top-level forms).
4. Call the `entry` function (for example `app:main`) with no arguments. Command-line arguments are available in `zilisp:*command-line-arguments*` (a list of strings).
5. On normal return, flush the streams and exit with exit code 0. `(zilisp:exit :code n)` returns an arbitrary exit code. Unhandled errors follow §9.4 (exit code 1).

**Startup time measures (J1)**: in steps 2 and 3, the top-level forms are re-run to create packages, symbols, classes and global variables. In Phase 36 we measure startup time; if it is slow, then **for the standard library only (step 2)**, we switch to a method that serializes the initialized state (packages, symbols, constants, class tables, etc.) into a byte sequence, embeds it in the executable, and restores it at startup. Janet embeds the standard library environment as a byte sequence (a C array) and restores it at startup (`src/boot/boot.janet` lines 5396–5404, `src/core/corelib.c` lines 1400–1418, `src/core/marsh.c`). Because functions are native code, the byte sequence holds only the entry names (or numbers), which are looked up in a table at restore time.

- **The application's top-level forms (step 3) are not replaced and are always run at startup** (review #10). If they were replaced with the build-time state, values that should change on every run, such as the date and time, random numbers, environment variables, command-line arguments and file contents, would be fixed to their build-time values, and the behavior would change.
- Even within the standard library initialization, the parts that depend on the execution environment (the initial value of `*random-state*`, `*default-pathname-defaults*`, the standard I/O streams, code that reads environment variables, etc.) are kept separate as processing that runs at startup after the restore.
- If a feature that saves an application's initialized state to speed up startup is provided in the future, it will be a separate feature that the user specifies explicitly (because the user must judge whether it is acceptable to save the initialized state as is).

---

## 16. Differences between `compile-file` and `zilisp build`, and multi-OS distribution conditions

### 16.1 Differences between the two operations

| Item | `compile-file` | `zilisp build` |
|---|---|---|
| Input | One `.lisp` file | A manifest, or one `.lisp` file |
| Output | One `.zfasl` file (Core IR + bytecode; shared by all targets) | An OS-native executable and `.deps.txt` |
| Required at run time | The Zilisp implementation (loaded with `load`) | Nothing |
| Execution method | VM after `load` (from Phase 39, compiled to native code in the background where Zig is available) | Native code |
| `eval-when` | Follows the table in CLHS 3.2.3.1 | Applies the same processing as `compile-file` to each source |
| Zig toolchain | Not required | Required |

- **Processing of top-level forms** (agy #6. CLHS 3.2.3.1 "Processing of Top Level Forms"): not only the forms at the top of the file, but also the forms in the bodies of the following forms are processed **recursively**, one at a time, as top-level forms.
  - The body of `progn`
  - The body of `locally` (the declarations carry over)
  - The bodies of `macrolet` and `symbol-macrolet` (the environment of the defined local macros and symbol macros carries over)
  - The body of `eval-when` (following the table in CLHS 3.2.3.1)
  - Macro expansion results (expand, then apply the rules above)
  - The bodies of `let`, `flet`, etc. are not treated as top level (for example, the `defun` in `(let ((x 1)) (defun foo () x))` is not a top-level form).
  - One entry of TOPL in `.zfasl` (§14.1) corresponds to one top-level form after this splitting.
- Compile-time effects of top-level forms (CLHS 3.2.3.1.1): `defmacro` registers the macro in the compilation environment, `defun` records that the function exists, `defvar` / `defparameter` declare the variable special, and `defpackage` / `in-package` expand to `eval-when (:compile-toplevel :load-toplevel :execute)`. **`defconstant` evaluates the value form at compile time if it can be evaluated, records it as a constant, and uses it for constant folding in subsequent forms and for detecting assignment and binding (§8.1)** (agy #13. CLHS `defconstant`).
- Undefined function warnings are collected and output as a `style-warning` at the end of the compilation unit.

### 16.2 Multi-OS distribution conditions (all to be verified)

| OS | Policy | Run-time dependencies |
|---|---|---|
| Windows x86-64 | The first option is a configuration that does not link libc | Only OS DLLs (kernel32, etc.) |
| Linux x86-64 | Statically link with musl | None (except when using GUI or TLS) |
| macOS AArch64 | Dynamically link to libSystem | libSystem |

Applications that use external native libraries such as GUI (Tk) or TLS list their dependencies in `.deps.txt` and are not labeled "fully statically linked".

### 16.3 Conditions for a single executable

| Item | Condition |
|---|---|
| Output | One executable (`app.exe` / `app`). The dependency list `app.deps.txt` is for reference and not needed to run |
| Contents of the executable | The application's native code, the standard library (native code), the runtime (GC, CLOS, conditions, etc.), and the compiler and VM for `eval`, `compile` and `load` at run time |
| Build PC | Requires the Zilisp SDK and Zig |
| Run PC | Requires neither Zilisp nor Zig |
| External files | No `.lisp` sources or `.zfasl` files are needed to run |
| Builds for other OSes | Created with Zig cross-compilation. Whether the cross build succeeds and whether it runs on real hardware are reported separately |
| When to verify | "Only OS DLLs on Windows" and "a single dependency-free file on Linux" are **to be verified**. Check them in the Phase 12 prototype, and verify operation in a clean environment in Phase 38 |

---

## 17. Decisions

Decision criterion (2026-11-01, instruction from the user (Lemon)): **If the recommendation satisfies the conditions (execution speed first, with standard semantics as a precondition), adopt the recommendation.**

| ID | Item | Decision | Where reflected |
|---|---|---|---|
| D-0 | Scope of conformance | As in the basic design (a practical compatible subset; implemented features are faithful to the standard) | Whole document |
| D-1 | Whether to build an evaluator | No. Everything is compiled before it runs | §5.1, §19 |
| D-2 | How executables are generated | Link with Zig | §15 |
| D-3 | Implementation of `loop` | Our own implementation | §11.2 |
| D-4 | Exit code on unhandled error | 1 | §9.4, §15.3 |
| D-5 | How the SDK bundles the runtime | Bundle it as source (to optimize it together with the generated code) | §7A.1, §15.2 |
| D-6 | License of the implementation | MIT (copyright holder fukuyori) | Beginning, §18 |
| D-7 | Whether native code generation is the main path | Yes, it is the main path | §5.1, §7A, §11.3, §14, §15 |
| D-8 | How GC roots are found in native frames | Conservative scan of the native stack and registers. The heap is scanned precisely | §3.3–§3.5 |
| D-9 | Value representation and heap | 8-byte Value (low-bit tags), 16-byte cons, page-based heap, mark bits outside the pages | §2, §3 |
| D-10 | Speed of REPL, `eval` and `load` | Phase 08 starts with the VM. Phase 39 implements the method (④) that builds a shared library with Zig in the background and replaces the entry (changed on 2026-11-01 after the investigation of MIR and libgccjit). In environments without Zig, `eval` and `load` stay on the VM (stated as a limitation) | §5.1, §7.1, §7A.6 |

---

## 18. Build and release scripts for the implementation itself

### 18.1 Scripts

| File | Role |
|---|---|
| `scripts/build-release.ps1` | Runs `zig build -Doptimize=ReleaseFast` for each target and outputs to `dist/<target>/`. Runs unit tests, language tests and benchmarks |
| `scripts/build-installer.ps1` | Creates the Windows installer with Inno Setup (`ISCC.exe`; confirmed to be present in `C:\Program Files (x86)\Inno Setup 6\` on the development machine) |
| `installer/zilisp.iss` | The Inno Setup script |
| `LICENSE` | MIT license. Copyright notice `Copyright (c) 2026 fukuyori` (created in Phase 01) |

### 18.2 Code signing (`-Sign` option)

- When `scripts/build-installer.ps1 -Sign` is given, the following three are code-signed.
  1. `zilisp.exe` (signed before it is put into the installer)
  2. The uninstaller (signed via Inno Setup's `SignTool` / `SignedUninstaller` settings. `ISCC.exe` is passed `/Szlsign=$q<signtool>$q sign /n $q<CODESIGN_CERT>$q /fd sha256 /tr <timestamp> /td sha256 $f` and `/DSign`. Created in 0.2.0. Whether signing actually works is checked when the user runs `-Sign`)
  3. The installer itself
- The certificate used for signing is specified by the value of the environment variable `CODESIGN_CERT`. The value is the certificate's subject name, selected from the current user's certificate store with `signtool sign /n` (confirmed on the development machine to match the certificate in the store). If `-Sign` is given while it is not set, the script stops with an error. Timestamps use RFC 3161 (default `http://timestamp.digicert.com`; can be changed with `-TimestampUrl`).
- Distribution packages are output to `dist/release/`: `zilisp-<version>-x86_64-windows-setup.exe` and, for each target, `zilisp-<version>-<target>.zip` (the executable in `bin/`, `LICENSE`, `README.md` and `README.ja.md`, `CHANGELOG.md` and `CHANGELOG.ja.md`). The installer is a per-user installation (no administrator rights required; all users if selected), and adding to PATH can be selected.
- **Distribution packages (ZIP, installer) are created by the user (Lemon) with `-Sign`.** Claude does not create distribution packages.

### 18.3 Version update checklist

`docs/version-update-checklist.md` lists the files to update when the version changes (`version` in `build.zig.zon`, `src/version.zig`, `AppVersion` in `installer/zilisp.iss`, `CHANGELOG.md` (English) and `CHANGELOG.ja.md` (Japanese), `format_version` of `.zfasl` (only when the IR or bytecode changes), etc.). Created in Phase 01.


### 18.4 GitHub Actions (added in 0.2.0)

| Workflow | Trigger | Contents |
|---|---|---|
| `.github/workflows/test.yml` | Push to `main`, pull request, call from `release.yml` | `zig fmt --check`, `zig build test`, `lang-test`, `native-test` on Linux, macOS (arm64) and Windows |
| `.github/workflows/release.yml` | Push of a `v*` tag | ① Check that the tag matches the version in `build.zig.zon` and `src/version.zig` and the headings of `CHANGELOG.md` and `CHANGELOG.ja.md` ② Tests (`test.yml`) ③ Build: for x86_64 and aarch64 Linux (musl) and macOS, `.tar.gz` with ReleaseFast (`bin/zilisp`, `LICENSE`, English and Japanese versions of README and CHANGELOG); for x86_64 Windows, the installer and ZIP with `scripts/build-installer.ps1` (unsigned). The ones that can be run (x86_64 Linux, aarch64 macOS, Windows) are checked with `--version` and one language test ④ Use the sections for the version in `CHANGELOG.md` (English) and `CHANGELOG.ja.md` (Japanese) as release notes, and register the GitHub release |

- Zig 0.17.0 is installed with `mlugg/setup-zig@v2`.
- **CI distribution packages are not signed** (decided 2026-11-02: the certificate is in the development machine's certificate store and is not used in CI). The release notes state that the packages are unsigned (SmartScreen and Gatekeeper warnings). Signed Windows distribution packages are created by the user with `-Sign`, and they replace the release files (`docs/version-update-checklist.md`). The rule in §18.2 that "distribution packages are created by the user with `-Sign`" applies to signed distribution packages.
- Not verified: the operation of the workflows is checked with the first tag push (or push to `main`).

---

## 19. Breakdown of Phase 01–08 into implementation units

| Phase | Work units | Acceptance criteria |
|---|---|---|
| 01 | `build.zig` / `build.zig.zon`, `src/main.zig` (CLI argument parsing), `src/version.zig`, `LICENSE`, `docs/zig-std-usage.md` (verification results of §1.3), `docs/version-update-checklist.md`, skeleton of `scripts/build-release.ps1`, **benchmark runner** (`zig build bench`) | `zilisp --version` and `zilisp --help` work. `zig build test` and `zig build bench` work |
| 02 | `tools/extract_samples/`, template of `compatibility/manifest.toml`, language test runner (`zig build lang-test`) | The curriculum commit is pinned, and code blocks can be extracted with IDs |
| 03 | `src/reader/`: lexical analysis, integers and floats, symbols, comments, `SourceMap` | Representative S-expressions can be read, and position information is recorded |
| 04 | Reader: quote, strings, lists, dotted pairs, `#(`, `#\`, `#'`, backquote | The Reader tests pass |
| 05 | `src/values/` (8-byte Value, tag operations), `src/runtime/package.zig`, `cl_symbols.zig`, minimal printer | Unit tests of tag operations, identity with `eq`, print round-trip |
| 06 | `src/runtime/heap.zig` (page table, size classes, allocation fast path), `roots.zig` (explicit roots, FFI handles) | Allocation and references work safely. Allocation speed is recorded with benchmarks |
| 07 | `src/runtime/gc.zig` (marking with bitmaps, lazy sweep, conservative stack scan, `--gc-stress`, poison, statistics) | Circular structures can be reclaimed. Unit tests pass in stress mode. Pause times are recorded |
| 08 | Minimal Resolver + IR + bytecode generation + VM (`quote` `if` `progn` `let` `setq` `lambda` `funcall`, arithmetic, lists), REPL | `(+ 1 2)`, `(list 1 2 3)` and closure examples work in the REPL and when running a file |

**Phase 08 CLI** (basic design §12.1): `zilisp` (REPL; ends when input ends), `zilisp FILE` and `zilisp --script FILE` (evaluates each form as it is read; stops on error with exit code 1; the same as SBCL's `--script`), `zilisp --eval TEXT` (does not print the value; the same as SBCL's `--eval`), `zilisp --load FILE` (evaluates, then starts the REPL). Errors are written to standard error output in the form `file:line:column: type name: description`.

In Phase 12, we build a minimal native backend (IR → Zig) and confirm that VM and native results match, the compile time with Zig, performance, and that a single executable can be produced (§16.3) (basic design §15).

---

## 20. References

| Source | Version / date accessed | What was referenced |
|---|---|---|
| SBCL source (local `D:\home\source\lisp\sbcl`) | `sbcl-2.6.10-68-g05b7eef0a` (referenced 2026-11-01) | `COPYING`, `src/compiler/generic/early-objdef.lisp`, `src/compiler/generic/early-vm.lisp`, `src/compiler/x86-64/parms.lisp`, `src/runtime/gencgc.c`, `src/runtime/coreparse.c`, `src/compiler/generic/genesis.lisp` |
| SBCL 2.6.7 (installed) | Run on 2026-11-01 | `most-positive-fixnum`, `*evaluator-mode*`, cons size, internal feature flags, `base-char-code-limit` |
| SBCL license | Same as above, `COPYING` | Public domain (partly BSD-style; LOOP and PCL require retaining the copyright notices). No code is imported into Zilisp |
| [utc-status-app v0.2.0 release notes](https://github.com/lispnik/utc-status-app/releases/tag/v0.2.0) | Referenced 2026-11-01 | The problem that SBCL executables cannot be codesigned on macOS, and the workaround (a report by a developer) |
| [MIR (vnmakarov/mir)](https://github.com/vnmakarov/mir) | Referenced 2026-11-01 | License, supported targets, C API, performance of generated code |
| ECL source (local `D:\home\source\lisp\ecl`) | `26.5.5-193-g2476efb4f` (referenced 2026-11-01) | The two-path structure (bytecode and C), non-local exits with `setjmp`/`longjmp`, multiple values, Boehm GC, `build-program`, tag assignment, how ansi-test is run. License LGPL 2.1 or later (`COPYING`, `LICENSE`) |
| Clasp source (local `D:\home\source\lisp\clasp`) | `3.0.1-432-g90f0ff882` (referenced 2026-11-01) | Combining LLVM with conservative stack scan, the non-local exit method and its speed records, the calling convention that returns the primary value and the count, bytecode with background native compilation, tag assignment. License LGPL 2.1 or later (`licenses/clasp_Copyright`, `licenses/LGPL`) |
| Gambit source (local `D:\home\source\lisp\gambit`) | `v4.9.8-35-gf1c787a0` (referenced 2026-11-01) | Tail calls in a C-generating design (trampolines), measures for the compile time of generated code, module linking and initialization order. License: choice of Apache 2.0 or LGPL 2.1 (`doc/gambit.txi` lines 20022–20025) |
| Emacs source (local `D:\home\source\lisp\emacs`) | `emacs-31.1-1315-g9008bf64c33` (referenced 2026-11-01) | Structure of native compilation with libgccjit, handling on Windows, loading and relocation of shared libraries, conservative stack scan. License GPL 3 or later (`COPYING`) |
| SICL source (local `D:\home\source\lisp\sicl`) | Commit `fce5770d4` (referenced 2026-11-01) | Dispatch by class number (stamp) and cache invalidation, instance representation with racks, generation of discriminating code, tag assignment, staging of intermediate representations. License BSD 2-clause (`LICENSE-BSD`). Licenses of external repositories such as `loop` (Khazern) and `format` (Invistra) are not verified |
| Janet source (local `D:\home\source\lisp\janet`) | `v1.42.1-97-ga2c0d0c8` (referenced 2026-11-01) | NaN-boxing (integers up to ±2^53), instruction format and branching of the register-based VM, GC that runs only at fixed points in the VM, embedding the initialized environment as a byte sequence. License MIT (`LICENSE`) |
| Carp source (local `D:\home\source\lisp\carp`) | `v0.6.0-58-gcda0b32d` (referenced 2026-11-01) | C generation and name mangling, REPL execution method (static code is rebuilt in full every time), mapping source positions with `#line`. License Apache 2.0 (`LICENSE`) |
| About the licenses of the implementations above | — | No code from any of them is imported into Zilisp (MIT); they are referenced only as design references |
| [Common Lisp HyperSpec](https://www.lispworks.com/documentation/HyperSpec/Front/index.htm) | — | Reference for the standard |
