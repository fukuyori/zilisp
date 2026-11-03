# Zilisp

[![test](https://github.com/fukuyori/zilisp/actions/workflows/test.yml/badge.svg)](https://github.com/fukuyori/zilisp/actions/workflows/test.yml)

[日本語](README.ja.md)

Zilisp is a practical Common Lisp–compatible implementation written in [Zig](https://ziglang.org/).
It aims at a well-defined, useful subset of Common Lisp rather than full ANSI conformance,
but every feature that is implemented behaves as the standard specifies.
Execution speed is the top design priority; standard semantics are never traded for speed.

- **Execution model**: the REPL, `eval` and `load` run on a bytecode VM; a native backend compiles
  Lisp to Zig source and builds it together with the runtime. Producing stand-alone executables is
  a goal for a later release.
- **Platforms**: Windows, Linux and macOS (x86-64 and AArch64).
- **Reference curriculum**: [CommonLispBasicMaster](https://github.com/fukuyori/CommonLispBasicMaster).
  Its code blocks are run against SBCL 2.6.7 to measure compatibility (`compatibility/eval-status.md`).

## Status

Zilisp is at **0.2.0**, the first public release. It is still early: many common operators are not
implemented yet. Unimplemented features are reported as errors before or during evaluation; Zilisp
never silently returns a different value.

Implemented in 0.2.0:

- Reader (numbers, symbols, package-qualified names, strings, characters, `#` syntax, backquote,
  `#+`/`#-`) and printer (`prin1` style, matching SBCL)
- Page-based heap and a mark-and-sweep GC (precise roots plus conservative scanning of the native
  stack and registers)
- Compiler (resolver, Core IR, bytecode) and a stack-based bytecode VM; a minimal native backend
- Special forms and macros: `quote` `if` `progn` `let` `let*` `setq` `function` `lambda` `flet`
  `labels` `progv` `eval-when` `block` `return-from` `return` `catch` `throw` `unwind-protect`,
  `when` `unless` `cond` `and` `or` `case` `prog1` `prog2`
- `defun`, `defmacro` (with destructuring), backquote, `macroexpand`, `destructuring-bind`
- Lambda lists: `&optional`, `&rest`, `&key`, `&aux`
- Dynamic binding: `defvar`, `defparameter`, `special` declarations
- Multiple values: `values`, `multiple-value-bind`, `multiple-value-list`, `multiple-value-call`,
  `multiple-value-prog1`, `nth-value`, `multiple-value-setq`
- `setf` and places (`defsetf`, `define-setf-expander`, `(defun (setf name) ...)`), `incf` `decf`
  `push` `pop`
- Hash tables (`eq`, `eql`, `equal`) and one-dimensional arrays (simple vectors and strings)

Implemented after 0.2.0 (in `main`, not yet released):

- `tagbody`/`go`, `do`, `do*`, `dolist`, `dotimes`, `psetq`, and `loop` (main clauses)
- `mapcar`, `mapc`, `mapcan`, `nconc`, `reduce`, `reverse`, `nreverse`, `copy-list`, `last`, `max`, `min`,
  `evenp`, `oddp`, `mod`, `rem`, `string=`, `string-upcase`, `princ`, and a minimal `format`
  (`~A ~S ~D ~% ~& ~~` to `T` or `NIL`)
- Bignums and ratios, exact comparisons with floats, `floor`/`ceiling`/`truncate`/`round`, `gcd`, `lcm`,
  `expt`, `sqrt`, `isqrt`, `exp`, `log`, trigonometric functions and bit operations (`logand`, `ash`, ...)
- Multidimensional arrays, fill pointers and adjustable arrays (`vector-push-extend`, `adjust-array`),
  `equalp` and `equalp` hash tables; `maphash` visits entries in the same order as SBCL 2.6.7
- Sequence functions (`find`, `position`, `remove-if`, `substitute`, `sort`, `subseq`, `search`,
  `concatenate`, `map`, `coerce`, ...), list and set functions (`member`, `assoc`, `union`, `pushnew`, ...),
  and character and string functions (`char-upcase`, `string<`, `string-trim`, `parse-integer`, ...); character classes
  and case follow Unicode 15.0.0, as in SBCL 2.6.7

- Packages: `defpackage`, `in-package`, `export`, `use-package`, `intern`, `find-symbol` and the other package
  functions, name-conflict detection, and `load` for files named by strings

Not yet implemented (planned for later releases): the full `format`, complex numbers, streams and files (pathnames,
`with-open-file`), `defstruct`, CLOS, and the condition system (`handler-case`, restarts).

Error messages are currently written in Japanese.

## Installation

Download a package from the [Releases](https://github.com/fukuyori/zilisp/releases) page.

| Platform | File |
|---|---|
| Windows (x86-64) | `zilisp-<version>-x86_64-windows-setup.exe` (installer) or `zilisp-<version>-x86_64-windows.zip` |
| Linux (x86-64, AArch64) | `zilisp-<version>-x86_64-linux.tar.gz`, `zilisp-<version>-aarch64-linux.tar.gz` (static, musl) |
| macOS (Apple Silicon, Intel) | `zilisp-<version>-aarch64-macos.tar.gz`, `zilisp-<version>-x86_64-macos.tar.gz` |

The release packages are **not code-signed**. Windows SmartScreen and macOS Gatekeeper may warn
about them. SHA-256 checksums are in `SHA256SUMS.txt`. The Windows installer installs for the
current user by default (no administrator rights needed) and can optionally add Zilisp to `PATH`.

## Usage

```
zilisp                  start the REPL (ends at end of input)
zilisp FILE             evaluate the forms in FILE (same as --script FILE)
zilisp --script FILE    evaluate FILE; stop at the first error with exit code 1
zilisp --eval TEXT      evaluate the forms in TEXT (values are not printed)
zilisp --load FILE      evaluate FILE, then start the REPL
zilisp --version        show the version
zilisp --help           show help
```

Global options (before the command): `--gc-stress` (collect on every allocation, for testing) and
`--gc-stats` (print GC statistics at exit).

```
$ zilisp
* (defun fact (n) (if (< n 2) 1 (* n (fact (- n 1)))))
FACT
* (fact 10)
3628800
* (catch 'done (throw 'done (values 1 2)))
1
2
```

## Building from source

Requires **Zig 0.17.0**.

```
zig build                      # build zig-out/bin/zilisp
zig build test                 # unit tests
zig build lang-test            # language tests (tests/language)
zig build native-test          # run the language tests with the native backend and compare
zig build bench                # benchmarks (ReleaseFast)
zig build -Doptimize=ReleaseFast
```

Comparing the curriculum with SBCL needs SBCL and the extracted code blocks:

```
zig build extract-samples -- <CommonLispBasicMaster directory> .work/samples
zig build eval-check -Dsbcl=<path to sbcl>
```

Release scripts (PowerShell): `scripts/build-release.ps1` builds the release binaries, and
`scripts/build-installer.ps1 [-Sign]` builds the Windows installer and ZIP packages (`-Sign` signs
the executable, the uninstaller and the installer with the certificate named by `CODESIGN_CERT`).
Pushing a tag `v<version>` runs `.github/workflows/release.yml`, which tests, builds and publishes a
GitHub release.

## Documentation

- [`docs/Zilisp_Detailed_Design_v0.2.md`](docs/Zilisp_Detailed_Design_v0.2.md) — detailed design ([日本語](docs/Zilisp_詳細設計書_v0.2.md))
- [`docs/zig-std-usage.md`](docs/zig-std-usage.md) — notes on Zig 0.17.0 standard library and language features ([日本語](docs/zig-std-usage.ja.md))
- `docs/Zilisp_企画・基本設計書_v0.3.md` — project plan and basic design (Japanese only)
- `docs/version-update-checklist.md` — files to update when the version changes, and release steps (Japanese only)

Changes are listed in [CHANGELOG.md](CHANGELOG.md) ([日本語](CHANGELOG.ja.md)).

## Roadmap

| Version | Contents |
|---|---|
| 0.3 | `tagbody`/`go` and `loop`, numeric tower (bignums, ratios), sequences, packages, streams and files, `format` |
| 0.4 | Conditions and restarts, `defstruct`, CLOS |
| 0.5 | Standard library integration for the curriculum, FFI and OS layer |
| 0.6 | Compatibility layers for HTTP, Web and GUI used by the curriculum |
| 0.7 | Compiled modules and stand-alone executables through native compilation |
| 1.0 | Distribution on three OSes, test reports and a defined compatibility scope |

## License

[MIT](LICENSE) — Copyright (c) 2026 fukuyori

The character tables are generated from the Unicode Character Database (`data/unicode/`), which is distributed under the
[Unicode License v3](data/unicode/LICENSE.txt). The distribution packages include it as `LICENSE-UNICODE.txt`.
