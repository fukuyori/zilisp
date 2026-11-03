# Changelog

[日本語](CHANGELOG.ja.md)

## Unreleased

### Added
- Phase 21: general arrays (multidimensional arrays, fill pointers, adjustable arrays; `aref` with any number of subscripts,
  `row-major-aref`, `array-dimensions` and the other array inquiries, `vector-push`, `vector-push-extend`, `vector-pop`,
  `adjust-array`, printing as `#2A(...)`); `equalp`, `equalp` hash tables and `sxhash`; the character functions (`char-code`,
  `code-char`, `char-upcase`, `alpha-char-p`, `digit-char-p`, the `char<` and `char-equal` families, ...); the string functions
  (`string`, the `string<` and `string-equal` families, `string-capitalize`, `nstring-upcase`, `string-trim`, `make-string`,
  `parse-integer`); the sequence functions with `:test`, `:test-not`, `:key`, `:start`, `:end`, `:from-end` and `:count` (`find`,
  `position`, `count`, `remove`, `delete`, `substitute`, `remove-duplicates`, `sort`, `stable-sort`, `search`, `mismatch`, `subseq`,
  `elt`, `fill`, `replace`, `concatenate`, `coerce`, `map`, `map-into`, `some`, `every`, `merge`, ...); list, tree and set functions
  (`member`, `assoc`, `rassoc`, `acons`, `pairlis`, `butlast`, `ldiff`, `maplist`, `subst`, `sublis`, `union`, `intersection`,
  `set-difference`, `adjoin`, `pushnew`, `remf`, ...). Displaced arrays are not implemented (explicit error). Character classes and
  case cover ASCII only. Tests: 139 cases compared with SBCL 2.6.7 (also under GC stress), language tests `sequences.lisp` (a data
  processing sample; also a gc-stress version) and `sequence-cases.lisp` (matches natively too). Matching curriculum blocks went
  from 362 to 421
- README in English and Japanese; the changelog is split into English (`CHANGELOG.md`) and Japanese (`CHANGELOG.ja.md`)
- Phase 20: the numeric tower. Bignums (limbs stored inside the object; values that fit a fixnum are always fixnums), ratios
  (always reduced), mixing with floats (exact comparisons, correctly rounded conversions), `floor`, `ceiling`, `truncate`, `round`
  (two values), `mod`, `rem`, `gcd`, `lcm`, `numerator`, `denominator`, `rational`, `float`, `expt`, `sqrt`, `isqrt`, `exp`, `log`,
  trigonometric functions, `logand`, `logior`, `logxor`, `lognot`, `ash`, `integer-length`, `logcount` and the type predicates. The
  reader reads large integers and ratios. Complex numbers are not implemented (explicit errors). Tests: 192 cases compared with
  SBCL 2.6.7 (also under GC stress), language tests `numbers.lisp` (and a gc-stress version) and `number-cases.lisp` (matches
  natively too)
- Phase 19: `tagbody` and `go` (a jump within the same function, otherwise a run-time exit; the entry stays after landing; VM
  instructions `TAGBODY_ENTER` and `GO_NL`; a labeled switch in the native backend), `psetq`, `dolist`, `dotimes`, `do`, `do*`, `loop`
  (our own implementation; the main clauses), `mapcar`, `mapc`, `mapcan`, `nconc`, `reduce`, `evenp`, `oddp`, `zerop`, `plusp`, `minusp`,
  `max`, `min`, `abs`, `mod`, `rem`, `reverse`, `nreverse`, `copy-list`, `last`, `endp`, `symbol-name`, `string=`, `string-upcase`,
  `string-downcase`, `char=`, `princ`, and a minimal `format` (`T` and `NIL`; `~A ~S ~D ~% ~& ~~`; anything else is an explicit error).
  Tests: 139 cases compared with SBCL 2.6.7 (also under GC stress), language tests `iteration.lisp` (and a gc-stress version) and
  `iteration-cases.lisp` (matches natively too). No iteration curriculum block (Level 6) fails only on Zilisp any more. Matching
  curriculum blocks went from 244 to 347
- English versions of the detailed design (`docs/Zilisp_Detailed_Design_v0.2.md`) and of the Zig 0.17.0 notes (`docs/zig-std-usage.md`; the Japanese version moves to `docs/zig-std-usage.ja.md`)
- Phase 21.5: Unicode 15.0.0 (the version used by SBCL 2.6.7) for the character classes and case of `alpha-char-p`,
  `alphanumericp`, `upper-case-p`, `lower-case-p`, `both-case-p`, `char-upcase`, `char-downcase`, `digit-char-p`,
  `char-equal`, `char-lessp`, the string case and comparison functions, `parse-integer` and `equalp`; the reader converts
  non-ASCII lowercase letters to uppercase (`λx` reads as `ΛX`) and the printer puts such names in bars. The tables are
  generated from the bundled UCD files (`data/unicode/`, Unicode License v3; `zig build gen-unicode`) and committed in
  `src/unicode/tables.zig`; `zig build test` checks them and compares every code point with SBCL 2.6.7. The distribution
  packages include the Unicode license as `LICENSE-UNICODE.txt`. Startup time 8.82 ms (ReleaseFast, `--eval nil`)
- Phase 21.6: hash tables use SBCL 2.6.7's layout (a key/value vector, a bucket index with chains, a free list, and stored
  hash values for `equal` and `equalp` tables; no tombstones). `maphash` and `loop`'s `being the hash-keys` now visit
  entries in the same order as SBCL (insertion order, with the same slot reuse after `remhash`, the same growth and the
  same small "flat" tables). Deletion followed by insertion is about 1.8 times as fast and `maphash` about 1.3 times;
  other operations are about the same. Startup time 8.74 ms

### Fixed
- Codex review (Phase 21), 9 issues: `adjust-array` with `:fill-pointer` on an array without one did not signal an error
  (and crashed for a zero-dimensional array); `(setf (aref a) x)` on a zero-dimensional array was an argument count error;
  `nsubst`, `nsubst-if`, `nsubst-if-not` and `nsublis` did not modify the tree; `remf` read the place before evaluating
  the indicator; compound element types such as `(or character integer)` made character arrays; `make-sequence`, `coerce`,
  `concatenate` and `map` ignored the constraints of `null`, `cons` and multidimensional `array` types; `butlast` and
  `nbutlast` rejected dotted lists; `tree-equal` returned the extra values of the test; `map`, `map-into`, `some` and
  `every` silently ignored the end of a dotted list
- Codex review (Phases 19 and 20), 11 issues: `(gcd most-negative-fixnum 0)` and `(floor 1d308 1d-308)` crashed the
  process; `expt` with a zero base or a zero non-integer exponent gave 0.0 (now 1.0 or division-by-zero, as in SBCL 2.6.7);
  rational-to-float conversion rounded twice near subnormals; a huge right shift in `ash` built a huge integer; `log` of very
  large or very small exact numbers overflowed; the `dolist` result form lost the body's declarations; `reduce :from-end`
  called `:key` in the wrong order; `loop with x of-type fixnum` was not initialized to 0; bignums could not be `tagbody`
  tags (tags are now compared with `eql`); `last` rejected a bignum count

## 0.2.0 - 2026-11-02

First public release. On top of the reader, printer, GC, bytecode VM and a minimal native backend,
it implements functions, macros, multiple values, dynamic binding and non-local exits
(block, catch, unwind-protect) (Phases 01–18).
LOOP, DOLIST, FORMAT, DEFSTRUCT, CLOS, conditions and more are not implemented yet (`compatibility/eval-status.md`).

### Added
- Release scripts: `scripts/build-installer.ps1` (Windows installer built with Inno Setup and per-target ZIPs;
  `-Sign` signs `zilisp.exe`, the uninstaller and the installer with the certificate named by the `CODESIGN_CERT`
  environment variable) and `installer/zilisp.iss` (per-user installation, optional addition to `PATH`)
- GitHub Actions: tests on Linux, macOS and Windows for every push and pull request (`.github/workflows/test.yml`).
  Pushing a tag `v<version>` runs the tests, builds Linux (musl) and macOS for x86_64 and aarch64 and Windows for
  x86_64, and publishes a GitHub release (`.github/workflows/release.yml`; unsigned, with SHA256SUMS.txt)
- Project plan and basic design (v0.3) and detailed design (v0.2) documents
- MIT license
- Phase 01: `build.zig` / `build.zig.zon` (Zig 0.17.0), CLI skeleton (`--version` / `--help`),
  benchmark runner (`zig build bench`, `scripts/run-bench.ps1`),
  release build script (`scripts/build-release.ps1`),
  version update checklist, and a check of the Zig 0.17.0 standard library and language features (`docs/zig-std-usage.md`)
- Phase 02: language test runner (`zig build lang-test`), extraction of the curriculum code blocks (`zig build extract-samples`),
  read-only classification with SBCL (`tools/classify_samples/classify.lisp`),
  `scripts/curriculum-inventory.ps1`, `compatibility/curriculum-inventory.md`, `compatibility/manifest.toml` (initial version)
- Phase 03: reader basics (`src/reader/`): whitespace, comments (`;` and nested `#| |#`), integers, ratios and floats
  (`*read-base*`, `*read-default-float-format*`, exponent markers), symbols (escapes, package prefixes,
  upcasing) and source locations (line and column). Value construction is a replaceable Builder (connected to Value in Phase 05).
  Implementation-dependent differences from SBCL are recorded in `tests/differential/impl-dependent.toml`
- Phase 04: reader macro characters: quote, strings, lists (dotted pairs), `#'`, `#(` (including `#n(`), `#\` (standard and
  semi-standard names, `U+XXXX`), `#:`, `#b #o #x #nR`, backquote (`zl-sys:quasiquote` and friends), `#+` / `#-`
  (`*read-suppress*`, `*features*`). `#P #S #C #A #. #= ##` signal an explicit reader-error until a later phase.
  A tool that reads the curriculum blocks with the Zilisp reader and compares the result with SBCL (`zig build reader-check`)
- Phase 05: 8-byte Value (`enum(u64)` with low-bit tags, `src/values/`), object layouts (64-byte symbols, 16-byte conses,
  strings, simple vectors, double-floats, packages), a provisional heap (replaced in Phase 06),
  packages and interning (CL, CL-USER, KEYWORD, ZILISP, ZILISP-SYSTEM; the 978 CL symbols are generated from SBCL by
  `tools/gen_cl_symbols/gen.lisp`), a Builder connecting the reader to Value, the printer (like prin1, same output as SBCL 2.6.7),
  `zilisp --read FILE`, language tests `tests/language/reader/` (matching SBCL), and a measurement of NIL representations
  A/B/C (A adopted)
- Phase 06: page-based heap (`src/runtime/heap.zig`): 4 MiB chunks (4 MiB aligned), 32 KiB pages,
  cons-only pages, 28 size classes, contiguous pages for large objects, out-of-page allocation and mark bits,
  finding the start of an object from any address (including interior pointers), and allocation statistics.
  Explicit roots and FFI handles (with generation numbers, `src/runtime/roots.zig`).
  `src/support/os_memory.zig` for large-alignment allocation on Windows (working around a Zig 0.17.0 page_allocator issue).
  Allocation benchmarks (`tests/bench/alloc.zig`)
- Phase 07: mark-and-sweep GC (`src/runtime/gc.zig`): mark stack, precise roots (packages, NIL, explicit roots,
  FFI handles) and conservative roots (native stack and registers), a finalization list (freeing string buffers),
  immediate reclamation of large objects, lazy sweeping of small pages, reuse of empty pages, the collection trigger
  (max(8 MiB, live × 2)), `--gc-stress`, filling reclaimed memory with 0xAA (Debug), statistics and `--gc-stats`.
  Language tests `tests/language/gc-stress/` and a GC pause benchmark (`tests/bench/gc.zig`)
- Phase 08: a minimal compiler and VM, and the REPL.
  Resolver (`src/compiler/resolver.zig`: `quote` `if` `progn` `let` `setq` `function` `lambda`, capture and assignment analysis),
  Core IR (`ir.zig`), bytecode generation (`codegen.zig`; captured and assigned variables live in value cells) and a verifier (`src/vm/verify.zig`),
  a stack-based VM (`src/vm/vm.zig`; calls between VM closures push frames inside the same dispatch loop, fixnum fast paths, `WIDE`),
  function objects (`src/runtime/function.zig`: code, closure, native_function), thread state (`src/runtime/thread.zig`),
  primitives (`src/primitives/`: `+ - * / 1+ 1- = /= < > <= >=`, `cons car cdr first rest list list* null not atom consp listp
  symbolp numberp functionp eq eql`, `funcall apply`, `print prin1 terpri`),
  CLI (`zilisp` = REPL, `zilisp FILE` / `--script FILE`, `--eval TEXT`, `--load FILE`).
  Until conditions are implemented (Phase 25), Lisp errors are reported by type name and description.
  Language tests `tests/language/eval/` (matching SBCL) and VM benchmarks (`tests/bench/vm.zig`)
- Phase 09: `let*` (sequential binding; the same name may be bound twice, as in SBCL 2.6.7).
  Tests of `let` / `let*` binding and shadowing (20 cases compared with SBCL 2.6.7, also under GC stress),
  language test `tests/language/eval/let.lisp` (and a gc-stress version)
- Phase 10: `defun` (a bootstrap macro written in Zig, expanding to `zl-sys::%defun`; named functions print as
  `#<FUNCTION name>`; defining functions on COMMON-LISP symbols signals package-error), `fboundp`, `symbol-function`.
  The VM frame limit is a quarter of the value stack (262144 by default). Tests of recursion, mutual recursion, redefinition
  and higher-order functions (compared with SBCL 2.6.7), language test `tests/language/eval/functions.lisp` (and a gc-stress version)
- Phase 11: `flet` and `labels` (local functions). Function-namespace bindings are kept in resolver scopes and function values
  in hidden local variables. Mutually referencing `labels` functions are stored in value cells. Local functions take precedence over
  global functions and macros and can be referenced with `#'name`. COMMON-LISP symbols and special operator names cannot be local
  function names (program-error, as in SBCL 2.6.7). Printed as `#<FUNCTION (FLET name) {address}>`. Tests of flet/labels and closure
  lifetimes (20 cases compared with SBCL 2.6.7; closures and shared variables stay correct after GC), language test
  `tests/language/eval/local-functions.lisp` (and a gc-stress version)
- Phase 12: IR verifier (`src/compiler/verify_ir.zig`, run on every compilation in debug builds and tests),
  a minimal native backend (`src/native/emit.zig`, `src/native/rt.zig`: IR → Zig source → compiled together with the runtime),
  the development command `zilisp --emit-zig FILE OUT.zig`, `zig build native-test` (runs the language tests natively and checks that
  the results match the VM; all 8 matched), language test `tests/language/eval/cases.lisp` (about 160 expressions from the P08–P11 unit tests).
  Measurement: fib(30) takes about 34.9 ms on the VM and about 9.7 ms natively; checking for `Value.unwind` costs about 12%
- Phase 13: a tool that runs the curriculum blocks on the VM and SBCL 2.6.7 and compares them (`zig build eval-check`; results in
  `compatibility/eval-status.md` and `eval-check.tsv`). Of 955 blocks, 82 matched, 0 differed in output and 511 failed only on Zilisp
  (all unimplemented features, mostly defparameter, defmacro, defstruct, cond, loop, setf and dolist).
  Error reports include a call history of VM frame function names (for errors inside functions, up to 16 entries).
  The CL constants `most-positive-fixnum`, `most-negative-fixnum`, `call-arguments-limit`, `lambda-parameters-limit`,
  `multiple-values-limit`, `char-code-limit` and `pi` have values. CL variables without a value are reported as unimplemented
- Phase 14: dynamic binding (shallow binding; a binding stack and the VM instructions `BINDING_DEPTH`, `BIND_SPECIAL`, `UNBIND_TO`,
  `PROGV_BIND`), `special` declarations (bound and free), special parameters, `defvar` and `defparameter` (names are proclaimed special
  at compile time), `progv`, `boundp`, `symbol-value`, `set`, `makunbound`. Dynamic bindings are restored when exiting with an error.
  Supported by the native backend. Tests: 23 cases compared with SBCL 2.6.7 (also under GC stress), restoration after errors,
  binding and restoring unbound variables, deep bindings and overflow, language test `tests/language/eval/special.lisp`
  (and a gc-stress version; matches natively too). Curriculum blocks matching went from 82 to 100
- Six issues from Codex's review of Phases 09–14
  - The local slot holding the `progv` depth overlapped with `let` inside the symbol and value forms
  - Native programs did not restore dynamic bindings when exiting with an error (now restored per top-level form)
  - `defvar` and `defparameter` that are never executed were also proclaimed special at compile time (only top-level forms are
    proclaimed at compile time; both cases are proclaimed when executed)
  - Zig code generated for `let` and `progv` in value-discarding positions left unused variables
  - The verifier accepted `WIDE` before instructions that have no index or count operand
  - Generated native programs were not tested under GC stress (`--gc-stress`; `native-test` now runs both ways)
- Phase 15: macro expander (in the resolver; expansions of top-level forms are top-level), `defmacro` (also defined at compile time
  when at top level), destructuring (required, `&optional`, `&rest`, `&body`, `&key`, `&allow-other-keys`, `&aux`, `&whole`,
  `&environment`, nesting) and `destructuring-bind`, backquote expansion (`,`, `,@`, `,.`, vectors, nesting), `macroexpand-1`,
  `macroexpand`, `macro-function`, `gensym`, `append`, `vector`. A standard library written in Lisp, `src/lisp/boot.lisp`
  (`when`, `unless`, `cond`, `and`, `or`, `case`, `prog1`, `prog2`, and `incf`, `decf`, `push`, `pop` on variables), loaded at startup.
  Tests: 57 cases compared with SBCL 2.6.7 (also under GC stress), language test `tests/language/eval/macros.lisp`
  (and a gc-stress version; matches natively too). Curriculum blocks matching went from 100 to 179
- Phase 16: `setf` (multiple pairs) and place expansion (written in Lisp: short and long `defsetf`, `(defun (setf name) …)`,
  `#'(setf name)`). Places: variables, `car`, `cdr`, `first`–`tenth`, `cXXr`, `nth`, `aref`, `svref`, `char`, `schar`, `gethash`, `getf`,
  `get`, `symbol-value`, `symbol-function`, `fdefinition`. `incf`, `decf`, `push` and `pop` share the expansion. `eval-when`. The VM's
  eval evaluates the forms inside top-level `progn`, macro expansions and `eval-when` one at a time. Hash tables (`make-hash-table` with
  `:test` `eq`, `eql` or `equal`, `gethash`, `remhash`, `clrhash`, `maphash`, `hash-table-count`, `hash-table-p`), one-dimensional
  arrays (`make-array`, `aref`, `svref`, `char`, `length`, `copy-seq` and others), `equal`, `rplaca`, `rplacd`, `nth`, `nthcdr`, `getf`, `get`,
  `symbol-plist`, `fdefinition`. Tests: 48 cases compared with SBCL 2.6.7 (also under GC stress), language test
  `tests/language/eval/setf.lisp` (and a gc-stress version; matches natively too). Curriculum blocks matching went from 179 to 223
- Phase 17: multiple values (`values`, `values-list`, `multiple-value-bind`, `multiple-value-list`, `multiple-value-prog1`,
  `multiple-value-call`, `nth-value`, `multiple-value-setq`; ValueMode passes the value count from the last form of a function body;
  VM instructions `VALUES`, `SINGLE`, `MV_LIST`, `MV_PUSH_N`, `MV_RESTORE`; supported by the native backend); the REPL prints all values.
  Function lambda lists with `&optional` (defaults and supplied-p variables), `&rest`, `&key` (`((:k v) …)`, `&allow-other-keys`,
  `:allow-other-keys t`) and `&aux`. `get-setf-expansion`, `define-setf-expander`. Tests: 50 cases compared with SBCL 2.6.7
  (also under GC stress), language test `tests/language/eval/values.lisp` (and a gc-stress version; matches natively too).
  Curriculum blocks matching went from 223 to 244
- Phase 18: `block`, `return-from`, `return`, `catch`, `throw`, `unwind-protect` (detailed design §6.4). A control stack and a stack of
  in-progress exits; `return-from` within the same function is a jump (undoing crossed dynamic bindings and entries), otherwise a
  run-time exit. Exits carry multiple values. Cleanup forms of unwind-protect run in the dynamic environment at entry, both for exits and
  errors. Exits inside cleanup forms (only exits that leave the cleanup cancel the exit in progress). Implicit blocks around the bodies of
  `defun`, `flet`, `labels` and `defmacro`. VM instructions `BLOCK_ENTER`, `CATCH_ENTER`, `UWP_ENTER`, `CONTROL_POP`, `UWP_SAVE`,
  `UWP_END`, `RETURN_FROM_NL`, `THROW`, `SLIDE`. Supported by the native backend. Tests: 63 cases compared with SBCL 2.6.7 (also under
  GC stress), language tests `exits.lisp` (and a gc-stress version), `exit-cases.lisp` and `error-cleanup.lisp`. A prototype of a
  second non-local exit method (saving and restoring registers with inline assembly) and a comparative benchmark
  (`zig build bench -- nonlocal`); the first method is kept (detailed design §6.4)

### Changed
- VM instruction dispatch was rewritten with a labeled `switch` and `continue` (detailed design §7.1).
  fib(25) went from 5.08 ms to 2.97 ms (about 41% faster), and speed no longer fluctuated with changes unrelated to the dispatch loop

### Fixed
- Ten issues from Codex's review of Phase 07
  - `readAll` accumulated read values in a Zig array that the GC does not scan (now returns a Lisp list registered as an explicit root while reading)
  - Building a vector copied the elements into a Zig array (the vector is allocated first and filled directly from the list)
  - Saving registers was left to the compiler (the values of callee-saved registers are read directly and the scan starts at the current stack pointer).
    Added a test where a reference exists only in a register
  - Registering a symbol and creating a package corrupted the tables when an allocation failed (allocations are done first).
    Added a test that fails every allocation site
  - The size of large objects was a u32, so interior pointers beyond 4 GiB were not recognized
  - Reusing large objects kept adding the same pages to the free page list
  - `1||` read as an integer and `:||` was an error (an empty escape `||` counts as an escape, as in SBCL 2.6.7)
  - `#n=` while skipping did not skip the following object
  - The GC benchmark used `@frameAddress()` of the function holding the values as the top of the scan
- Six issues from Codex's review of Phase 08
  - Calls between Zig functions (such as apply calling apply) were not subject to the nesting depth limit (primitive calls are also counted in Thread.call)
  - Values left in unused VM value-stack slots were treated as GC roots (only [0, sp) is scanned)
  - The REPL ended with exit code 0 without any report when input ended in the middle of a form (reports END-OF-FILE with exit code 1)
  - `notinline` declarations were ignored and fast-path instructions were used
  - Any number of documentation strings at the start of a body were skipped (only one; a declare after a second string is an error)
  - The verifier missed jump targets in unreachable instructions that point into the middle of an instruction
- Codex and agy review (Phase 18): the implicit block also enclosed lambda-list init forms (now only the body);
  the compile-time definition of `defmacro` had no implicit block; nested error cleanups overflowed the record of in-progress exits
  (the limit is now checked against the sum with the control stack, signaling `storage-condition`); an error caught inside a cleanup
  overwrote the details of the original error (the details and call history are saved); the verifier accepted invalid control-stack
  operations (the sequence of entries is checked per position, and also at run time). Method-2 prototype: the floating-point control
  state was not saved, and the method-1 comparison did not use the tag search result (fixed and re-measured; the break-even point is
  about 25 frames, not about 12)
- Unit tests panicked on Linux and macOS (the top of the stack for conservative GC scanning now comes from /proc/self/maps on Linux and
  pthread_get_stackaddr_np on macOS). In Linux debug builds, heap chunks were not zero-filled (`Allocator.alignedAlloc` fills memory with
  an undefined marker, so `rawAlloc` is used to keep the OS-provided memory). The method-2 prototype is skipped with Zig's own code
  generator, which does not emit global assembly
- Issues found by the GitHub Actions tests: in a GC test, an object that should have been collected was kept conservatively by a stale
  value left on the stack (Linux with AVX2 builds; the test helper that clears the stack now works in two levels and garbage is created
  in a deeper frame). The Windows runner checked files out with CRLF and `zig fmt --check` failed (`.gitattributes` fixes LF, CRLF for
  `.ps1` and `.iss`)
