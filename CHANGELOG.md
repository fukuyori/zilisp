# Changelog

[日本語](CHANGELOG.ja.md)

## Unreleased

### Added
- Fixed six P27 Claude Code review findings: duplicate/LIST slot names, non-simple vector/string class lookup,
  accepting `:type` declarations, cross-kind class guards and cache refresh, `slot-exists-p` for arbitrary objects
  and structures, and restart's metaclass. Guards preserve repeated initialization of the same Runtime.
  Regression coverage and reports are recorded in `docs/clos-phase27-claude-review.ja.md`.
- Phase 27: rack-based standard instances, `defclass`, `find-class`, `class-name`, `class-of`, `make-instance`,
  CLHS CPL computation, slot access/unbinding/existence checks, shared slots, and default initargs.
  Conditions and restarts now use racks; structures participate in public class lookup.
  Generic accessors follow in P28, redefinition and initialization hooks in P29.
  Measurements and scope are in `docs/clos-phase27-plan.md`. New language-test expectations use SBCL 2.6.10.168.
- Phase 26: `defstruct` (CLHS defstruct). The options `:conc-name`, `:constructor` (the keyword one and the ones with an
  argument list (BOA); several allowed), `:copier`, `:predicate`, `:include` (overriding the default, type and read-only of
  slots), `:print-function` and `:print-object`; the slot options `:type` (checked by constructors and `setf`, a type-error on
  a mismatch) and `:read-only`; `copy-structure`; printing and reading `#S(...)`; `typep` (structure names and
  `structure-object`); `equalp` and `equalp` hash tables. Printing has the same form as SBCL 2.6.7 (including the pretty
  printer's line breaks, `*print-level*`, `*print-length*` and `*print-circle*`). `(:type list)`, `(:type vector)`, `:named`
  and `:initial-offset` are not implemented (`zilisp:unimplemented`). A structure literal can be used only when it is read
  after the definition has run (it cannot be written in a file compiled natively)
- Time: `get-universal-time`, `get-decoded-time`, `decode-universal-time` and `encode-universal-time` (the argument types and
  the handling of years outside the range are the same as SBCL 2.6.7; the offset of local time comes from the OS rules on
  Windows and from `/etc/localtime` elsewhere)
- `fboundp` accepts `(setf name)`
- Tests: the language tests `defstruct.lisp`, `defstruct-read.lisp`, `defstruct-review.lisp` and `time.lisp` (the same output as SBCL 2.6.7; also gc-stress versions and
  native) and unit tests. The curriculum blocks that use `defstruct` (31 blocks in Levels 7, 19, 23, 24 and 26) and one that
  uses `get-universal-time` now give the same output as SBCL; curriculum blocks matching went from 513 to 545
- Fixed 5 issues from the Codex review of Phase 26 (all checked against SBCL 2.6.7): a structure that refers to itself
  through `#n#`, as in `#1=#S(node :next #1#)`, can be read (the placeholder stayed in the slot; typed slots are checked
  after the replacement), a slot named like the supplied-p variable of a BOA constructor, the original type of a slot is
  still checked when `:include` overrides its type, `decode-universal-time` signals a type-error when the time-zone is not a
  whole number of seconds, and extra arguments and repeated options of `defstruct` are errors
- Fixed 6 issues from the second Codex review of Phase 26 (all checked against SBCL 2.6.7): when `#n#` is inside a list or
  vector in a `#S` slot value, the type is checked with the value after the replacement (correct values were rejected and
  wrong ones let through), `(x)` in `:include` keeps the original default, `*print-level*` and `*print-circle*` reach lists
  inside structures and conditions when printing without the pretty printer, `(:conc-name "")` makes symbols in the current
  package, `(:print-function nil)` and `(:print-object nil)` give the `#S(...)` form, and overriding the same slot twice in
  `:include` is an error
- Fixed 2 issues from the third Codex review of Phase 26 (both checked against SBCL 2.6.7): while a circular `#S` is being
  read, the types of other structures made by initforms, of `setf` and of nested reads are still checked (only values that
  contain a `#n=` placeholder are skipped), and a multi-dimensional character array inside a structure or list was printed
  one level too deep without the pretty printer
- Fixed 1 issue from the fourth Codex review of Phase 26 (checked against SBCL 2.6.7): while a circular `#S` was being read,
  a `#n#` placeholder that a reader macro took out and an initform passed to another constructor or `setf` escaped the type
  check. Only the slots of the structure the reader is making go unchecked now (through a reader constructor that does not
  check types)
- Fixed 1 issue from the fifth Codex review of Phase 26 (checked against SBCL 2.6.7): when a reader macro returned a copy or
  another value instead of the `#S` structure it read, the original structure kept the `#n#` placeholder and its types were
  never checked. Placeholders inside the structures waiting to be checked are replaced too
- Fixed 2 issues from the sixth Codex review of Phase 26 (both checked against SBCL 2.6.7): after `#n#` is replaced, the types
  of all structures inside what was read are checked (when a reader macro returned a copy and changed only the original, the
  copy escaped the check), and the rest of the same stream can be read after a type-error in `#S` (the position did not
  advance, so the next `read` signaled the same error again)
- Fixed 3 issues from the seventh Codex review of Phase 26 (caused by the sixth-round fix): when an initform of a `#S` reads
  from the same stream, the outer read continues after it (the same input was read twice), existing structures unrelated to
  `#n#` are not checked again and rejected, and reading many structures while an enclosing label is pending no longer takes
  quadratic time
- Fixed 3 issues from the eighth Codex review of Phase 26: a recursive `read` from an initform of a `#S` can refer to the
  labels of the enclosing `#n=`; the reader checks the types only of the structures it makes itself for `#S` (the types of
  structures a reader macro makes or changes are the reader macro's responsibility; the wider check kept rejecting unrelated
  structures and slowing down); and reading an input where many `#S` refer to the same label no longer takes quadratic
  time (5.1 seconds became 24 ms with ReleaseFast for 6,400 of them)
- Fixed 2 issues from the ninth Codex review of Phase 26 (both checked against SBCL 2.6.7): when a recursive `read` in an
  initform of a `#S` takes in `#n#`, the slot types are checked with the value after the replacement (the placeholder was
  checked as it was, rejecting correct values and letting wrong ones through), and a recursive `read` in an initform can
  read a comma inside the enclosing backquote
- The issue from the fifteenth Codex review of Phase 26 is left as a limitation: a comma is represented by an ordinary
  list (`(zl-sys:unquote-splicing x)` and so on), so a list that writes this internal symbol directly, placed right after
  a dot inside a backquote, is a reader-error just like `,@x` (SBCL represents a comma by a dedicated object). It is
  recorded in the list of implementation-dependent behaviour.
- Fixed 2 issues from the fourteenth Codex review of Phase 26: the check of `,@` / `,.` right after a dot inside a
  backquote looks at the object that was read (`#-no-such-feature ,@b`, `#1=,@b` and a `,@b` read and returned by a
  reader macro are reader-errors too). The error is signaled after reading up to the close parenthesis (the position for
  reading on after the error; end-of-file when there is no close parenthesis). The same as SBCL 2.6.7.
- Fixed 2 issues from the thirteenth Codex review of Phase 26: while skipping (`*read-suppress*`, `#+` / `#-`), a lone dot
  is read as an ordinary token (`#+no-such-feature (a . b c)`, `(a . .)` and `#(. )` can be skipped). Inside a backquote,
  `,@` or `,.` right after a dot is a reader-error (`` `(a . ,@b) ``). Also, a `#+` / `#-` whose feature expression holds
  reads the one following object on the spot (`(1 #-no-such-feature . 2)` is a reader-error). The same as SBCL 2.6.7.
- Fixed 2 issues from the twelfth Codex review of Phase 26: a list, a vector and the body of a `#S` are closed by the
  character `)` itself (a reader macro set on `)` is not called; another character that copies the syntax of `)`, such as
  `]`, does not close and is a reader-error; `read-delimited-list` checks its end character in the same way after a
  comment). A character other than `(` after `#S` is consumed before the error (the position for reading on after the
  error). The same as SBCL 2.6.7.
- Fixed the issue from the eleventh Codex review of Phase 26: `#S` must be followed directly by `(` (`#S#.(…)`, `#S (…)`
  and `#S name` are reader-errors, and the `#.` is not evaluated). The body is read without going through the macro
  function of `(`, so `#S(…)` can be read even in a readtable that sets a reader macro on `(`. The same as SBCL 2.6.7.
- Fixed 2 issues from the tenth Codex review of Phase 26: an alias made inside an unresolved label (`#2` in `#1=(#2=#1#)`)
  gives the resolved value when referred to later (a placeholder was left in the result), and a comma inside the body of a
  `#S` is a reader-error even inside a backquote (the same as SBCL 2.6.7). Limitations left as decided: the types when a
  reader macro later puts `#n#` into a structure, the delayed type-error of a large `#S` inside a label, and a recursive
  `read` in an error handler not seeing the enclosing labels
- Phase 25: conditions, handlers and restarts (CLHS chapter 9). `define-condition` (`:initarg`, `:initform`, `:reader`,
  `:writer`, `:accessor`, `:report`, `:default-initargs`) and `make-condition`, the hierarchy of the standard condition types,
  `signal`, `error`, `cerror`, `warn`, `invoke-debugger` and `*debugger-hook*`, `handler-bind`, `handler-case` (with
  `:no-error`) and `ignore-errors`, `restart-bind`, `restart-case` (`:report`, `:interactive`, `:test`, association with the
  signaled condition), `with-simple-restart`, `with-condition-restarts`, `compute-restarts`, `find-restart`, `invoke-restart`,
  `invoke-restart-interactively`, `restart-name`, `abort`, `continue`, `muffle-warning`, `store-value` and `use-value`, and the
  condition accessors (`type-error-datum` and the others). Errors found in Zig (the type-error of `car`, division by zero,
  unbound variables, ...) can be handled too, and restarts work with them. The report texts and printing of the standard
  conditions are the same as SBCL 2.6.7. Reports of errors that no handler takes now list the available restarts (choosing
  one by number comes in a later phase)
- `typep` (numeric ranges, `mod`, `member`, `and`, `or`, `not`, `satisfies`, `cons`, element types and sizes of vectors and
  arrays, condition types), `typecase`, `etypecase`, `ctypecase`, `ecase`, `ccase`, `check-type` and `assert` (with SBCL's
  texts), and `eval` as a function
- Tests: the language test `conditions.lisp` (the same output as SBCL 2.6.7; also a gc-stress version and native) and unit tests.
  Level 13 of the curriculum gives the same output as SBCL except one file-error text (implementation-dependent) and one block
  that calls `get-universal-time` (not implemented yet). Curriculum
  blocks matching went from 478 to 513. Startup time is 13.55 ms
- Fixed six issues found in the Codex review of P25 (each checked against SBCL 2.6.7): the evaluation order of `cerror`'s
  arguments inside `restart-case`; associating restarts with forms that macroexpand to `signal` or `error`; control-error when
  an `abort` or `muffle-warning` restart returns; `typep` of `(vector t n)` and `(string n)` compares the dimension, not the
  fill pointer; the stream position seen by reader-error and end-of-file handlers that read from the stream; and
  `stream-error-stream` of reader-error. `*break-on-signals*` is left to the debugger phase
- Fixed the four issues of the second Codex review of P25: the stream position on wrong `#A` contents, the stream of
  reader-error and end-of-file from `read-from-string`, evaluating the subforms of the place of `ccase` and `ctypecase` once,
  and calling `*debugger-hook*` for errors found in Zig even with no handler or restart
- Fixed the three issues of the third Codex review of P25: `ccase` and `ctypecase` read the place only once; places with
  several store variables; a failed allocation of the stream for a `read-from-string` error is no longer overwritten by the
  original error
- Fixed the five issues of the fourth Codex review of P25: funcall of a macro or special operator is undefined-function, not
  unimplemented; `typep` of a CL symbol that is not a type, a wrong `pprint-logical-block` specification and an unknown `loop`
  clause are errors, not unimplemented; `otherwise` in `etypecase` and `ctypecase` is a type specifier; added
  `(setf (values ...))` (setf of places with several store variables)
- Fixed the six issues of the fifth Codex review of P25: `setf`, `incf`, `decf`, `push` and `pop` of places with zero or
  several store variables (`(values)`, `(values a b)`) bind every store variable; `typep` checks the form of a type specifier,
  so a malformed one (`(random-state 3)`, `(mod 0)`, `(integer 1 2 3)`, an element type that is not a type) is an error, and
  `(base-string n)`, `(simple-base-string n)` and `(complex type)` are false; a `loop` `named` that is not first and an unknown
  `being` kind are program-error (only the symbol kinds of `being` and SBCL's `elements` are unimplemented)
- Fixed the five issues of the sixth Codex review of P25: `getf` and nested `values` places bind every store variable (a place
  with no store variables takes no value and gives NIL); `typep` always checks the outer form of `and`, `or`, `not` and `cons`
  (the parts are still checked only when used); the bounds of a numeric range are checked per type (`(integer 1.5 3)` and
  `(single-float 1 3)` are errors); the argument of `(complex type)` must be `*` or a subtype of `real`
- Fixed the three issues of the seventh Codex review of P25: `incf` and `decf` evaluate the delta before reading the place;
  `(complex (and ...))` is accepted (an intersection can be empty or real); the element type `base-char` does not match
  strings (Zilisp strings always have element type `character`)
- Fixed the two issues of the eighth Codex review of P25: the argument of `complex` is now classified three ways. It is
  accepted when it is surely a subtype of `real` (including `(not (not real))`), rejected when it surely contains a
  non-real (including `(and string)` and `(and t string)`), and signals `zilisp:unimplemented` otherwise (empty
  intersections such as `(and string symbol)`; SBCL returns NIL)
- Fixed the issue of the ninth Codex review of P25: a `cons` type with a `nil` part (such as `(cons nil t)`) is empty
  and so is accepted as the argument of `complex`; `cons` and compound `complex` types that may or may not be empty
  (such as `(complex nil)`) signal `zilisp:unimplemented` (SBCL returns NIL)
- Fixed the issue of the tenth Codex review of P25: when `invoke-restart` or `invoke-restart-interactively` is given a
  restart object, it only checks that the restart is active (it no longer calls `:test` again without the condition).
  A restart found for a condition (also through `continue`, `store-value` and `use-value`) was rejected with a
  control-error
- Fixed the issue of the eleventh Codex review of P25: `assert` no longer evaluates the arguments first when the test
  form is a special operator such as `if` or `let` (it evaluated the branch not taken, and evaluated the bindings of
  `let` as forms). `special-operator-p` is implemented for this (it agrees with SBCL 2.6.7 on the 25 special operators
  of CL)
- Fixed the issue of the twelfth Codex review of P25: a symbol given to the `:report` option of `define-condition`
  now names the function in the lexical environment of the form (`(function name)`, CLHS), so it can be a local
  function of `flet` or `labels`. It used to be quoted, so the global function was always called
- Fixed the issue of the thirteenth Codex review of P25: the values of a function called while printing (the report of
  a condition or restart, `~/name/` of `format`, a `set-pprint-dispatch` function) no longer leak into the values of
  `princ-to-string`, `write-to-string` or `format`. A report returning `(values)` made `princ-to-string` return NIL
- Fixed the issues of the fourteenth Codex review of P25, all of the same kind: the values of a `(satisfies …)`
  predicate (seen through `set-pprint-dispatch`), the values left before an empty `progn` or `eval-when` given to
  `eval`, and the values of a reader macro just before the end of input no longer leak into the result. `reduce` on
  an empty sequence without `:initial-value` now returns only the primary value of the function

### Changed
- Releases no longer include `SHA256SUMS.txt`, and the release notes no longer say whether the packages are signed
- Malformed `do`, `do*` and `psetq` forms signal simple-error as in SBCL 2.6.7 (they were program-error)
- Unimplemented features (`zilisp:unimplemented`) are not a subtype of `error` (they are `serious-condition`s), so
  `ignore-errors` and `(handler-case ... (error ...))` do not take them and they reach the top level. Unimplemented CL functions
  and variables are also signaled to handlers as `zilisp:unimplemented`
- The storage-condition of a stack overflow (the VM and native stacks, the dynamic binding and control stacks) is not
  signaled to handlers (there is no reserve area to run them in)
- With `*print-pretty*` NIL, conditions and restarts inside lists and vectors print in the same form as SBCL 2.6.7
  (they printed as `#<type {address}>`)
- Top-level error reports write structure values in the `#S(...)` form
- `zig build native-test` runs the tests in parallel (the number of jobs comes from the environment variable
  `ZILISP_NATIVE_TEST_JOBS`, by default half the logical processors, 1 to 8; results are printed in name order; Debug for
  38 files went from about 37 minutes to about 7)
- `zig build lang-test` and `zig build eval-check` run in parallel too (environment variables `ZILISP_LANG_TEST_JOBS` and
  `ZILISP_EVAL_CHECK_JOBS`; lang-test runs tests of the same name (eval and gc-stress) in turn as one group and the groups
  in parallel). The large-data cases of the language test `defstruct-read.lisp` are smaller. lang-test went from about
  280 seconds to 49, and eval-check from about 160 seconds to 28

## 0.3.0 - 2026-11-04

Data processing, files and programs in several files (Phases 19–24): iteration and `loop`, the numeric tower
(bignums and ratios), general arrays and the sequence functions, Unicode 15.0.0 characters, hash tables with SBCL's
layout, packages and `load`, streams and pathnames, the full `format`, reader extensions and the pretty printer.
Conditions (`handler-case`, restarts), `defstruct` and CLOS are not implemented yet (`compatibility/eval-status.md`).

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

- Phase 22: packages. `*package*` is a real special variable; the package functions (`find-package`, `make-package`,
  `rename-package`, `delete-package`, `intern`, `find-symbol`, `unintern`, `export`, `unexport`, `import`, `shadow`,
  `shadowing-import`, `use-package`, `unuse-package`, `find-all-symbols`, `symbol-package`, `keywordp`, `make-symbol`, ...),
  `defpackage` (including SBCL's `:local-nicknames`), `in-package`, `do-symbols`, `do-external-symbols`, `do-all-symbols`,
  name-conflict detection (package-error), and `load` for files named by strings (binding `*package*`). Symbols are printed
  with package prefixes relative to `*package*`; native programs write constants as "package::name". Curriculum blocks
  went from 421 to 429 matches. Startup time 9.08 ms

- Phase 23: streams and pathnames. Standard streams (`*standard-output*`, `*standard-input*`, `*error-output*`,
  `*terminal-io*`, ...), file streams (`open`, `close`, `with-open-file`, character and `(unsigned-byte 8)` elements,
  UTF-8 and Latin-1), string streams (`with-output-to-string`, `with-input-from-string`, `read-from-string`,
  `prin1-to-string`, ...), broadcast, two-way and synonym streams, the reading and writing functions (`read-line`,
  `read-char`, `read`, `read-byte`, `read-sequence`, `write-string`, `write-line`, `write-byte`, `fresh-line`, ...), and
  output functions and `format` that take a stream. Pathnames (`#P`, `make-pathname`, `merge-pathnames`, `namestring`,
  `probe-file`, `truename`, `directory`, `ensure-directories-exist`, `delete-file`, `rename-file`, `file-write-date`,
  `*default-pathname-defaults*`) parsed as SBCL 2.6.7 does. The GC closes streams that are collected. Scripts end
  quietly on end-of-file on standard input, as SBCL's `--script` does. Curriculum blocks went from 429 to 467
  matches. Startup time 9.47 ms
- Phase 24 (P24a): printer variables. `*print-base*`, `*print-radix*`, `*print-case*`, `*print-level*`, `*print-length*`,
  `*print-circle*` (`#n=` and `#n#`), `*print-readably*` (`print-not-readable` for objects that cannot be read back),
  `*print-array*`, `*print-gensym*`, `*print-escape*` and `*read-default-float-format*` take effect in `prin1`, `princ`,
  `print`, the `-to-string` functions, `~A` and `~S` of `format`, and the values printed by the REPL. `write` and
  `write-to-string` take all their keywords. The printer and reader variables have SBCL 2.6.7's initial values
  (`*print-pretty*` became T with the pretty printer in P24d). Language test `printer.lisp` (same output as SBCL 2.6.7)
- Phase 24 (P24b): `format` with all directives except the pretty printer ones, following SBCL 2.6.7: `~A ~S ~W ~C`,
  `~D ~B ~O ~X ~R ~P`, `~F ~E ~G ~$` (SBCL's `flonum-to-string` ported, so rounding is the same), `~% ~& ~| ~~ ~T`,
  `~* ~? ~( ~) ~[ ~; ~] ~{ ~} ~^`, `~< ~>` justification and `~/name/`, with parameters (`v`, `#`, `'c`) and modifiers.
  `formatter` and function controls. Curriculum blocks went from 467 to 478 matches. Language test `format.lisp`
- Phase 24 (P24c): reader extensions. Readtables (`*readtable*`, `copy-readtable`, `readtablep`, `readtable-case` and its
  `setf`), user reader macros (`set-macro-character`, `get-macro-character`, `make-dispatch-macro-character`,
  `set-dispatch-macro-character`, `get-dispatch-macro-character`, `set-syntax-from-char`, `read-delimited-list`), `#.`
  with `*read-eval*`, `#n=` and `#n#` (also circular), `readtable-case` for reading and printing, `*read-base*`,
  `*read-default-float-format*` and `*read-suppress*` in every read, and `with-standard-io-syntax`. Native programs keep
  circular constants. Language test `readtable.lisp`
- Phase 24 (P24d): the pretty printer, following SBCL 2.6.7's `pprint.lisp`. `pprint`, `pprint-logical-block`,
  `pprint-pop`, `pprint-exit-if-list-exhausted`, `pprint-newline`, `pprint-indent`, `pprint-tab`, `pprint-fill`,
  `pprint-linear`, `pprint-tabular`, `*print-pprint-dispatch*` with `pprint-dispatch`, `set-pprint-dispatch` and
  `copy-pprint-dispatch`, SBCL's standard layouts for special forms, macros, function calls, quote and backquote, and
  arrays, `*print-right-margin*`, `*print-miser-width*` and `*print-lines*`, and the `format` directives `~<...~:>`,
  `~_`, `~I` and `~:T`. `*print-pretty*` is T at startup, as in SBCL. Language tests `pretty.lisp` and
  `pretty-default.lisp` (same output as SBCL 2.6.7)
- Phase 24 acceptance: the reader reads `#nA` and `#A(dimensions element-type . contents)`, and `*print-readably*`
  writes arrays that `#nA` cannot represent (such as `(make-array '(0 3))`) in the `#A` form, as SBCL does. Objects
  printed readably read back as `equalp` objects with and without the pretty printer. Language test `round-trip.lisp`

### Fixed
- Bignums printed in bases 8 and 32 had wrong digits (Zig 0.17.0's `toStringAlloc`; now built from the base-2 digits)
- Review of the 0.3 changes (agy and Codex, Phases 19 to 24), 41 issues reproduced and fixed:
  - Crashes: negative lengths in sequence type specifiers (`(make-sequence '(vector t -1) 0)`), lengths beyond the
    object header (`(make-string 4294967296)` is now a storage-condition) and `~0,0<...~>` in `format` (now
    division-by-zero) panicked.
  - `loop`: destructuring and `and` in `with`, subclauses of `for ... from` evaluated in the written order, conflicting
    directions and a non-positive `by` signal errors, `by` of `in`/`on` evaluated once, `it` only in the first clause
    after a test, mixed kinds of accumulation and wrong `using` clauses signal program-error. `do` rejects malformed
    variable specs. `reduce` checks `:start`/`:end`; `mapcan` works on lists longer than `call-arguments-limit`.
    `(expt -2 2.0)` is 4.0.
  - Sequences and arrays: `sxhash` of symbols is computed from the name; `remove-duplicates :from-end t` passes the
    arguments to `:test` in SBCL's order; `coerce` returns objects that already have a compound array type and makes
    functions from lambda expressions; `butlast`/`nbutlast` with 0 keep a dotted tail and reject negative counts;
    `adjust-array` and `make-string` check their keyword arguments; `:initial-contents` rejects dotted lists and is
    no longer quadratic for lists; memory exhaustion while copying a string is reported.
  - Streams: `fresh-line`, `~&` and `clear-output` on closed or input streams signal errors; `file-position` and
    `file-length` on closed streams signal stream-error; `unread-char` after `peek-char` with skipping returns the
    skipped character; `make-synonym-stream` accepts NIL; `make-broadcast-stream` and `make-two-way-stream` check
    stream directions; `write-sequence` writes bytes to broadcast streams; `:probe` streams have no direction; reading
    more of standard input no longer re-reads the form (side effects of `#.` and reader macros happened twice).
  - `load` binds `*readtable*`; `equal` compares pathnames in the cdr of lists; symbols that leave or enter the
    KEYWORD package get or lose the keyword flags; pathname functions accept non-simple strings, resolve `:back`,
    match `**/` against names without a directory, return `:start` from `parse-namestring` and follow synonym
    streams; `make-pathname` checks its components; package nicknames drop duplicates and the package's own name,
    and `:local-nicknames` rejects CL, COMMON-LISP, KEYWORD and the package's names.
  - Reader and printer: reader macros called while `#+`/`#-` skip, or with `*read-suppress*`, read as NIL with
    `*read-suppress*` bound; a recursive `read` inside a reader macro keeps the backquote depth; `NIL` is escaped
    by the readtable; `read-delimited-list` rejects a different closing parenthesis; changing a copy of the initial
    pprint dispatch table keeps the standard layouts (SBCL's priorities); `#nA` reading of lists is no longer
    quadratic.
  - Native programs: the constants of each toplevel form are read just before the form runs (symbols of later forms
    were interned too early, so `shadow` in an earlier form conflicted), and all constants share one set of
    `#n=` labels (an uninterned symbol used by two constants stays the same symbol).
  - Language test `review-cases.lisp` (same output as SBCL 2.6.7; also a gc-stress version) and unit tests for 31
    error cases compared with SBCL.
  - A Codex review of these fixes found 8 more issues, now fixed: removing duplicate package nicknames read freed
    strings; strings copied by `make-pathname` were held where the GC could not see them; importing a symbol into
    KEYWORD replaced its value; `with` destructuring without an initial value used the wrong defaults; `it` in the
    test of a nested condition; a pathname without a directory against `(:absolute :wild-inferiors)`; malformed
    directories in `make-pathname` (simple-error, as in SBCL); the second value of `parse-namestring` for streams.
  - A further Codex review found 5 more, now fixed: `for ... from` bound the loop variable before evaluating `to`/`by`
    (they saw the new variable); the outer `it` leaked into `and`/`else` of a nested condition; `:back` did not remove a
    preceding `:wild`/`:wild-inferiors`; `make-string` rejected `:element-type nil`; `format` to a closed stream
    signalled an error even when nothing was written (as in SBCL, only writing and `~&` signal).
  - And 3 more: reading more of standard input inside `#.` (for example with `read-line`) moved the input buffer while
    the outer reader still used it (a crash; the reader now resynchronizes after `#.` as after reader macros);
    `(format t "")` with a closed `*standard-output*`; empty strings in `make-pathname` directories are dropped before
    `:back` is processed, as in SBCL.
- Standard output and standard error were written at file positions from 0, so redirecting both to one file, or
  appending with `>>`, overwrote earlier output (they are now written as streams)
- Codex review (Phase 24), 8 issues: `format` copied list arguments where the GC could not see them, so a `~/name/`
  function that cut the list could free later arguments; with the pretty printer, array elements printed by the
  fallback lost `*print-circle*` labels (a circular vector overflowed the stack); `~:<...~:>` with a circular list did
  not end; native constants were not written readably (`#A((0 3) T)` came back as `(0 0)`, constants that cannot be
  read back now fail at `--emit-zig`); the `#A` form wrote `NIL`, `T` and `CHARACTER` without package prefixes; `~:*`,
  `~@*` and `~@[` did not move back inside logical blocks; `~&` inside logical blocks used a stale line state (on a
  pretty stream `fresh-line` and `~&` now always start a new line, as in SBCL); `with-standard-io-syntax` did not bind
  `*print-pprint-dispatch*`
- Codex review (Phase 23), 16 issues: `:if-exists :rename` and `:rename-and-delete` truncated the file instead of moving it
  to `name.bak`; the REPL and `*standard-input*` read standard input through different buffers, so input could be lost;
  CR LF was read as one newline on Windows (SBCL 2.6.7 does not translate it) and `read` on a Latin-1 stream decoded the
  bytes as UTF-8; `write-string`, `format` and other character output to a binary stream did not signal an error;
  `write-byte`, `finish-output` and `force-output` on a broadcast stream did not reach its streams; reading or writing
  through a closed synonym or two-way stream worked; `read-char-no-hang` waited for terminal input; `file-length` of an
  `:overwrite` stream ignored the existing length; `pathname-match-p` compared only the name and type, byte by byte;
  `merge-pathnames` kept `:back` and did not fall back to the default version; `directory` left out matching
  directories and returned duplicates for patterns such as `**/**/`; `equalp` did not compare pathnames;
  `input-stream-p`, `stream-element-type`, `file-position` and `file-length` did not follow synonym streams; characters
  that Latin-1 cannot encode were written as `?` (now a stream-error). Also `make-pathname` without `:defaults` gave the
  version `:newest` (SBCL gives NIL), and `equal` on pathnames no longer compares the version (as SBCL)
- Codex review (Phase 22), 6 issues: native programs registered packages while reading their constants at startup, so
  `find-package` saw them before `defpackage` and a `make-package` run both at compile time and at run time failed;
  `import` did not set the home package of a home-less symbol already present; `shadowing-import` changed the home package;
  KEYWORD could be made to use other packages; `NIL` was printed unqualified even when it was not visible from
  `*package*`; `defpackage` did not check the arguments of `:size` and `:documentation`
- `concatenate` and other functions that collect several vectors could run out of reserved capacity (an assertion
  failure in Debug builds, possible memory corruption in ReleaseFast builds); a failed standard-library load in
  `Thread.create` leaked the VM buffers
- Codex review (Phase 21.6), 4 issues: growing a very large hash table could overflow the u32 bucket count (now a
  `storage-condition` above 2^28 slots); a failed growth left a flat table marked as non-flat; `:rehash-size` was ignored,
  so the `maphash` order differed from SBCL (it is now used, and `:rehash-size` and `:rehash-threshold` are type-checked);
  `clrhash` cleared the whole table instead of the used part
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
