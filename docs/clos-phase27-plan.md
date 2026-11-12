# Phase 27: proposed CLOS representation and acceptance scope

2026-11-12. tque #319. The user approved racks and the Phase boundaries below.

## Layout comparison

Run `zig build bench -- clos-layout`. Source: `tests/bench/clos_layout.zig`.
ReleaseFast, Zig 0.17.1, Linux x86_64, Intel Core i7-8700K. After warming each
case, measure ten million reads; take the median of five sequential runs.

| Layout | Median ns/read | Five samples |
|---|---:|---|
| Direct | 1.782 | 1.800, 1.740, 1.815, 1.782, 1.771 |
| Rack | 1.832 | 1.765, 1.832, 1.863, 1.914, 1.755 |
| Direct after forwarding | 2.683 | 2.585, 2.700, 2.818, 2.683, 2.567 |
| Rack after replacement | 1.846 | 1.754, 1.846, 1.873, 1.853, 1.814 |

This prototype reads four slots in 4,096 objects using pseudorandom indices.
The slot index is already resolved; each read checks the stamp. Direct placement
also checks a forwarding pointer. Object pointers are hidden from the compiler
to prevent read elimination. Allocation and initialization are included in the
timed interval but small relative to the iteration count.
GC, slot name lookup, redefinition itself, update hooks, and VM call overhead
are excluded. The page allocator and contiguous arrays do not model production
heap fragmentation or cache misses. Direct objects occupy 72 bytes; rack objects
use a 24-byte instance plus a 56-byte rack, before heap rounding.
These results do not establish overall runtime speed or memory usage.

Recommendation: retain the existing rack design. Direct placement's ordinary-read
advantage is about 3%, overlapping run-to-run variation. Racks fare better after
forwarding and simplify redefinition while preserving identity. Repeat the
comparison with the actual heap and VM after implementation, and reconsider if
ordinary access is clearly slower.

## P27 acceptance scope

- `defclass`, `find-class`, `class-of`, `make-instance`, and class names in `typep`.
- CLHS CPL computation, multiple and diamond inheritance, and inconsistent order errors.
- `slot-value` and its setf, `slot-boundp`, `slot-exists-p`, and `slot-makunbound`.
- `:initarg`, `:initform`, `:allocation`, and `:default-initargs`; check lexical
  initform environments, unbound slots, and inherited shared slots.
- Integrate conditions and structures with `class-of` and `find-class`, preserving
  existing type checks, printing, and GC behavior.
- A minimal sample defines a class, creates an object, reads and writes slots,
  makes a slot unbound, and checks its type.

Set the boundary with P28's generic accessors and P29's user initialization hooks
and class redefinition. Any early implementation must preserve generic function
semantics rather than overwrite ordinary functions with the same name.
`with-slots` needs `symbol-macrolet`, currently unimplemented and planned for P30.
Exclude it from P27 acceptance unless its scope is explicitly brought forward.

## Comparison baseline and validation scope

Preserve existing expected outputs derived from SBCL 2.6.7. The installed binary
is 2.6.10.168; record that version for new comparisons. Known differences are in
`handoff.ja.md` §6. The extracted curriculum `.work/samples` is absent in this
environment, so curriculum-block acceptance remains unverified.

## Implementation

Implemented in `src/primitives/clos.zig` and `src/lisp/clos.lisp`. CLOS is appended
to the embedded boot source, so VM and native startup share its definitions.
Public classes are `ObjKind.class` objects wrapping vector descriptors, retaining
the existing name and CPL fields at indices 0 and 1. Symbol properties register
class names and cache public class objects.

Standard instances, conditions, and restarts use `ObjKind.instance` and
`ObjKind.rack`. Standard racks hold a stamp, layout, and inline slots.
Condition and restart racks retain a separate slot vector for existing accessors;
those two kinds differ from the prototype's inline rack slots.
Structures retain their direct storage and are integrated
through public structure classes and `class-of`. Redefinition and obsolete-rack
updates follow in P29.
Forward-referenced superclasses are tracked in tque #534; class-name registration
and removal through `(setf find-class)` are tracked in #535.
Dispatch stamps for built-in, condition, and structure classes follow in P28 task #536.

Acceptance cases in `tests/language/eval/clos.lisp` (also under GC stress) cover
classes, diamond inheritance and inconsistent ordering, shared slots, default
initargs, lexical environments, unbound slots, class objects as type specifiers,
and condition/structure integration.
They also check that lists, strings, and vectors reachable only from the last
slot survive repeated allocation and collection.

Debug, ReleaseSafe, and ReleaseFast unit suites, 75 language cases, and five
cross builds for Windows, Linux, and macOS passed. After the final switch to
inline slots, the CLOS cases were compared on VM and native backends, and
the existing condition cases were rechecked under GC stress. CLOS passed on the VM,
native Debug and native ReleaseFast, each with and without GC stress. Curriculum comparison
remains unperformed as noted above.

The first native suite run passed 28 cases and failed to compile 13 because
sources were edited during execution. Retrying those 13 plus CLOS against fixed
sources passed all 14, both normally and with GC stress, covering all 41 cases.
The final empty-class and `standard-object` creation cases were checked by
rerunning CLOS. Runtime checks were on Linux; Windows and macOS were cross-built only.
Claude Code performed an initial review and one follow-up limited to the six fixes;
all six were confirmed addressed. See `clos-phase27-claude-review.ja.md` for the original
reports and dispositions. After the fixes, Debug unit tests, 77 language cases,
and four affected native cases (normal and GC stress) passed. A Runtime-reuse
regression introduced by the guard was corrected by allowing same-kind restart
initialization and checked with focused P27 tests. The full 42-case native suite
was not rerun. `:type` is accepted as a declaration without runtime enforcement in P27.
Started and accepted on 2026-11-12 (one calendar day); tque #319 is complete.
