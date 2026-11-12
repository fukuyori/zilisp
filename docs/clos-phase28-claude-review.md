# P28 Claude Code review (2026-11-12)

Read-only CLI review with Read/Grep/Glob only; no code execution or edits by the reviewer.
Original report follows verbatim. Disposition and validation are in `clos-phase28-claude-review.ja.md`.

**Review of P28 (read-only, nothing executed): no memory-safety or GC defects found; two medium and three low correctness findings.** Every finding below comes from reading the code, so the reproducers are untested.

## Findings

### 1. Medium — an implicit generic function created by `defmethod` inherits the first method's keyword names
`src/lisp/generic.lisp:58-65` (`%gf-normalize-ll`), used at `generic.lisp:260`.

```lisp
(defmethod k1 ((x integer) &key a) a)
(defmethod k1 ((x string) &key b) b)   ; zilisp: "Method omits a generic keyword."  SBCL: OK
```

- **Cause:** the implicit lambda list becomes `(x &key a)`, so `%gf-congruent` (line 85-87) requires every later method to accept `:a`. CLHS 7.6.4 and SBCL give the implicit generic function a bare `&key`.
- **Second symptom:** `:a` is permanently in the allowed union in `%gf-keywords` (line 221), so a call is accepted even when no applicable method takes `:a`:
  ```lisp
  (defmethod k2 ((x integer) &key a) a)
  (defmethod k2 ((x string) &rest r) r)
  (k2 "s" :a 1)   ; accepted here; SBCL signals an unknown-keyword error
  ```
- **Fix:** have `%gf-normalize-ll` emit `&key` and drop the key parameters.

### 2. Medium — recursive generic calls hit the native-depth limit at a few hundred levels
`src/runtime/function.zig:43-45` (`genericEntry`), `generic.lisp:235` (`apply` in `%gf-invoke`), `src/vm/vm.zig:125`, `src/runtime/thread.zig:24` (`max_native_depth = 1000`).

```lisp
(defmethod g-deep ((n integer)) (if (= n 0) 0 (1+ (g-deep (1- n)))))
(g-deep 600)   ; expected: stack-exhausted error; the same defun works
```

- **Cause:** each generic call nests at least two `vm.run` activations (dispatcher, then the method via `apply`), plus one more per `call-next-method`. Ordinary closure calls stay inside one run loop.
- **Printing regression:** every record, structure or instance now prints through `%print-record` → `print-object` → dispatcher → method. That is about three nested runs per nesting level where there was one, so the printable nesting depth of structures and conditions drops to roughly a third.
- **Assumption:** this relies on `apply` being the native primitive (`primitives.zig:131`) rather than a VM opcode. The failure is a Lisp error, not a crash.
- **Fix:** invoke the method closure without a second native re-entry, or count generic dispatch separately from the native-depth budget.

### 3. Low — the default `print-object` method is wrong for anything that is not an instance, record or structure
`generic.lisp:301-307`.

```lisp
(print-object 42 *standard-output*)                         ; prints #<FIXNUM {0}>, SBCL prints 42
(defmethod print-object ((x integer) s) (call-next-method)) ; same result when called directly
```

- **Cause:** the else branch always writes `#<class {address}>`, and signals `print-not-readable` under `*print-readably*` even for readable objects.
- **Fix:** fall back to the built-in printer (for example `write` through the Zig path) for objects that are not instances.

### 4. Low — a failing accessor definition leaves the class half-defined and the form cannot be re-evaluated
`src/lisp/clos.lisp:167-168`.

```lisp
(defun area (x) x)
(defclass sq () ((a :accessor area)))   ; type-error from %generic-data, after the class is registered
(defclass sq () ((a :accessor area2)))  ; "Class redefinition (P29)"
```

- **Cause:** `%define-standard-class` runs before the accessor `defmethod`s, and redefinition is blocked until P29.
- **Fix:** check accessor names for an ordinary-function binding before registering the class. The error should also be the program-error from `%ensure-generic`; `%install-method` (line 260) skips that check when the name is already fbound.

### 5. Low — re-evaluating `defgeneric` keeps methods from earlier `(:method ...)` options
`generic.lisp:104-111, 133`.

```lisp
(defgeneric h (x) (:method ((x integer)) :int))
(defgeneric h (x) (:method ((x string)) :str))
(h 1)   ; :INT here; SBCL removes the old method and signals no-applicable-method
```

CLHS says methods defined by a previous `defgeneric` form are removed. Fixing it means recording which methods came from `:method` options.

## Checked and found clean
- **GC:** `GenericFunction` and `Method` fields are all marked. Arguments stay rooted across `makeGeneric`/`makeMethod` allocation. `Class.stamp` is a raw integer and correctly unmarked.
- **Entry ABI:** the entry offset is asserted. The VM, `Thread.call` and `native/rt.zig` only go through `entry`. Every `closurePtr`/`nativePtr` use is guarded by a kind check.
- **Stamps and cache keys:** `class-of` is total and stamps are unique. Within one stamp, `typep` gives the same answer for every class specializer, so cached method lists cannot be applied to the wrong object. EQL specializers are keyed by boolean, not by value.
- **Dispatch:** changed `call-next-method` arguments are diagnosed, and a rejected `defgeneric` redeclaration leaves the old order intact.
- **Printer:** defstruct printers are registered as class-specific methods, and condition and structure printing still reaches the legacy printer through the default method.


## Focused follow-up (verbatim)

**One remaining actionable defect, in the area of fix 1; fixes 3, 4 and 5 read clean.** Everything below is unverified static reading — nothing was executed.

## Remaining defect

### Low/Medium — unknown keywords are still accepted when the generic function has `&rest` but no `&key` (unverified)
`src/lisp/generic.lisp:241` (`%gf-keywords`), together with `generic.lisp:70-76` (`%gf-method-ll`).

This is the original finding 1 second symptom with the definition order reversed:

```lisp
(defmethod kr ((x integer) &rest r) r)   ; implicit GF lambda list: (x &rest r)
(defmethod kr ((x string) &key a) a)
(kr "s" :zz 1)   ; expected here: NIL (accepted). SBCL: unknown &KEY argument error
```

The explicit form has the same hole:

```lisp
(defgeneric kr2 (x &rest r))
(defmethod kr2 ((x integer) &key a) a)
(kr2 1 :zz 1)    ; accepted
```

- **Cause:** the keyword check only runs when the generic function's own signature has `&key` (`(fourth sig)`). Meanwhile `%gf-method-ll` adds `&allow-other-keys` to every `&key` method, so the method closure no longer checks either.
- **Spec:** CLHS 7.6.5 requires the check when the generic function or any applicable method mentions `&key`.
- **Fix:** enter the check at line 241 when `(fourth sig)` is true or any applicable method's signature has key-p set. The rest of the function (union of keys, `any`, `:allow-other-keys`) already works for that case.
- **Test gap:** `tests/language/eval/generic-review.lisp:5-7` only covers the order where the `&key` method comes first, which gives the generic function a bare `&key` and hides this path.

This was not introduced by the fixes; it predates them.

## Fixes that read clean (unverified)

- **Fix 1** (`generic.lisp:58-65`): the implicit lambda list keeps a bare `&key` and drops key variables and `&allow-other-keys`.
- **Fix 3** (`generic.lisp:323-331`, `streams.zig:568-601, 646-658`, `pprint.zig:221-233`): every kind that `scanLispPrinted` and `outputUgly` route to `%print-record` ends in a non-dispatching leaf in the default method, so I see no recursive dispatch.
- **Fix 4** (`clos.lisp:146-171`, `generic.lisp:89-103, 283`): the preflight runs before `%define-standard-class` and covers ordinary-function bindings, generic arity and reader/writer arity conflicts, including `(setf name)`.
- **Fix 5** (`generic.lisp:120-130, 163`): a rejected redeclaration leaves the old state intact, and an externally replaced inline method survives because `remove-method` ignores the stale entry.
