# P29 Claude Code review (2026-11-12)

Read-only CLI with Read/Grep/Glob; no code execution or changes by the reviewer. Original report follows.
Disposition: `clos-phase29-claude-review.ja.md`.

Four actionable findings, none in the GC or rack-swap paths. Everything below is static and unverified: nothing was run, per your constraints.

## Findings

### 1. Medium: `defclass` on an alias name redefines and renames the aliased class
`src/lisp/clos-update.lisp:160-165`, `:172`, `:182`

`%define-standard-class` reuses whatever `find-class name` returns, then overwrites `d[0]` with `name`. CLHS `defclass` only redefines when a class with the same *proper name* exists, that is `(class-name C)` = name and `(find-class name)` = C. SBCL's `ensure-class` applies the same test and otherwise creates a fresh class.

```lisp
(defclass a () ((x :initform 1)))
(defvar *i* (make-instance 'a))
(setf (find-class 'b) (find-class 'a))
(defclass b () ((y :initform 2)))
(list (eq (find-class 'a) (find-class 'b)) (class-name (find-class 'a))
      (slot-exists-p *i* 'x))
;; expected (NIL A T); Zilisp by reading: (T B NIL)
```

The same path fires for the `p29-cache-a` → `p29-other` rebinding in your unit test if `p29-cache-a` is later `defclass`ed.

Fix: in `%define-standard-class`, reuse the existing class only when `(eq (class-name old) name)`. Otherwise create a new class object and rebind the name.

### 2. Medium: `typep` through a non-standard alias recurses by name, giving unbounded native recursion or a wrong error
`src/primitives/types.zig:515`

`if (desc[0] != spec) return typep(th, v, desc[0]);` re-resolves the class through its name instead of using the descriptor already in hand.

- **Crash:** swapping two structure (or condition) names loops forever in Zig.
  ```lisp
  (defstruct sx) (defstruct sy)
  (let ((cx (find-class 'sx)) (cy (find-class 'sy)))
    (setf (find-class 'sx) cy (find-class 'sy) cx))
  (typep 1 'sx)   ; SX→SY→SX→… native stack overflow
  ```
- **Wrong result:** an alias stops working once the original name is unbound.
  ```lisp
  (define-condition my-c (error) ())
  (defvar *c* (make-condition 'my-c))
  (setf (find-class 'my-alias) (find-class 'my-c))
  (setf (find-class 'my-c) nil)
  (typep *c* 'my-alias)   ; expected T; I expect an unknown-type error for MY-C
  ```

Fix: `return recordTypep(v, desc[0]);`. The same pattern at `types.zig:512` is safe because `STANDARD-OBJECT` cannot be rebound.

### 3. Medium-low: a failed `defclass` leaves forward classes registered
`src/lisp/clos-update.lisp:163-167` (creation at `:72-78`); interacts with `src/lisp/boot.lisp:1426-1430` and `:2291-2294`

`%forward-class` registers `name` and every parent (property list plus `*standard-classes*`) before the "Unsupported superclass", cycle and CPL-consistency checks run. A failed definition of a new name is therefore not transactional.

```lisp
(handler-case (eval '(defclass oops (integer) ())) (error () nil))
(find-class 'oops nil)               ; expected NIL; returns a :forward class
(define-condition oops (error) ())   ; expected OK; "Cannot change the kind of class OOPS"
```

`(defstruct oops)` fails the same way, and so does the self-cycle case from your unit test when the name is new. Your `p29-transaction` test only covers a class that already existed.

Fix: validate before creating anything, or record the forward classes created in this call and unregister them on non-local exit.

### 4. Low: an alias to a structure/condition class reverts the class object after the original is redefined
`src/lisp/clos-update.lisp:36-37` with P27 `find-class` at `src/lisp/clos.lisp:15-16`

For non-standard classes the alias stores a snapshot descriptor in `%class`. After the original name is redefined, `(find-class 'alias)` sees a descriptor mismatch and refreshes the shared class object back to the obsolete descriptor with a new stamp. `(find-class 'orig)` then flips it forward again.

```lisp
(define-condition c1 (error) ())
(setf (find-class 'c1-alias) (find-class 'c1))
(define-condition c1 (warning) ())
(find-class 'c1-alias)
(zl-sys::%class-cpl-objects (find-class 'c1))  ; old CPL (ERROR…) until (find-class 'c1) runs again
```

The effect is stale CPL ranking in `%gf-rank` and stamp churn in the dispatch caches. This is alias behaviour (#535), not the excluded redefinition redesign.

Fix: skip the refresh in the P27 lookup when the cached public class's `d[0]` differs from the name being looked up.

## Checked and found sound

- **Your two SBCL-difference interpretations:** I agree with both.
  - CLHS 4.3.6.1 says a local slot in both old and new that was unbound stays unbound, and 4.3.6.2 defines added slots as those absent from the old class.
  - CLHS 4.3.6 removes methods "created by" the old `defclass` accessor options; a user replacement with the same specializers is not such a method.
- **Method combination:** around/before/primary/after order, the `:core` chaining, changed arguments through `call-next-method`, and `multiple-value-prog1` for after methods all read correctly.
- **Migration and `change-class`:** the rack is swapped before the hook runs, so the hook cannot re-enter migration. Shared↔local transitions, the discarded plist and the previous-instance snapshot follow CLHS.
- **Zig side:** `%replace-instance` rejects record instances and does not allocate. `standardClassTypep` cannot misread condition or structure descriptors, since those are 7 long and the check is `len < 16`.
- **Cache invalidation:** stamps are unique and monotonic, so a stale entry can never hit; selective invalidation is hygiene only.
- **Castle adapter:** the `defcommand` change adds only the named `block` and keeps declarations in place.

One non-correctness note: `make-instance` (`clos-update.lisp:264-271`) now allocates a probe instance and runs four uncached `compute-applicable-methods` per call, which may show up in GC-stress and native suite times.


## Focused follow-up (verbatim)

Three actionable findings remain, all on alias paths the four fixes did not reach. Everything below is static and unverified: nothing was run. The four original fixes themselves read correctly.

## Findings

### 1. Medium: `define-condition` / `defstruct` on an alias name leaves the name bound to the aliased class
`src/lisp/clos-update.lisp:17-21` (fix 4) with the wrappers at `:37-42`

This is the legacy-class counterpart of original finding 1, and fix 4 changes how it shows up. The boot definer stores a new descriptor in `%class` but leaves `%public-class` pointing at the aliased class. `%class-description` then treats that cached object as authoritative because its `class-name` differs from the name, so `find-class` never sees the new descriptor.

```lisp
(define-condition c1 (warning) ())
(setf (find-class 'al) (find-class 'c1))
(define-condition al (error) ())
(list (eq (find-class 'al) (find-class 'c1)) (class-name (find-class 'al))
      (typep (make-condition 'c1) 'al) (typep (make-condition 'al) 'error))
;; expected (NIL AL NIL T); by reading (T C1 T NIL)
```

Dispatch on instances of `al` would use C1's CPL for the same reason. `defstruct` on an alias of a structure class takes the same path.

Fix: in both wrappers, before calling the original definer, clear `%class` and `%public-class` when the bound class's `class-name` is not `name`. That also removes the spurious "Cannot change the kind of class" when the alias pointed at a class of another kind.

### 2. Low-medium: frozen legacy CPLs are still built by name lookup
`src/lisp/clos-update.lisp:29-31`

`%remember-legacy-class` maps `find-class` over the proper names in `d[1]`. The boot definer resolved the direct parent through `%class`, which works for an alias, but the freeze then looks up the parent's proper name, which may be unbound or rebound.

```lisp
(define-condition p (error) ())
(setf (find-class 'p-alias) (find-class 'p))
(setf (find-class 'p) nil)
(define-condition child (p-alias) ())   ; expected OK; "No class named P" from the wrapper
```

The descriptor is already installed when the error is signalled, so later `typep`, `class-of` ranking and handler matching on `child` instances retry the freeze and signal again. If `p` was redefined rather than removed, the freeze silently records the wrong parent identity instead.

Fix: build the list from the direct superclass objects, as `(cons class (frozen CPL of (find-class direct-super)))` merged in `d[1]` order, rather than from names.

### 3. Low: cleanup can orphan a class that a nested definition attached to a placeholder
`src/lisp/clos-update.lisp:211-218`

The placeholder for the class being defined stays `:forward` until publication. A shared-slot initform that defines a subclass of it and then fails leaves that subclass published with `d[11]` pointing at a placeholder that cleanup then unregisters.

```lisp
(handler-case
    (eval '(defclass outer ()
             ((s :allocation :class
                 :initform (progn (eval '(defclass inner (outer) ())) (error "x"))))))
  (error () nil))
(defclass outer () ())
(make-instance 'inner)   ; expected an instance; "Class is not a finalized standard class."
```

`inner` stays unfinalizable until it is itself redefined, because the new `outer` is a different class object and `%affected-classes` never reaches it.

Fix: skip removal of a placeholder that any class in `*standard-classes*` lists in its `d[11]`.

## Test coverage

`clos-lifecycle-review.lisp` and the P29 units cover all four original reproducers and the related legacy-parent fix. They do not cover the three cases above.
