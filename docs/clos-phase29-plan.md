# P29 method combination, initialization and redefinition (2026-11-12)

Tasks #321, #534 and #535 extend P28's Lisp dispatcher and rack representation.

- Standard around/before/primary/after combination, next-method calls and multiple-value preservation.
- Allocation, make/initialize/shared-initialize/reinitialize hooks and method-declared initialization keywords.
- Standard-class redefinition and descendant CPL/layout recomputation; lazy rack migration, obsolete-instance hooks, change-class and its update hook.
- Forward superclass references and find-class registration/removal independent of class identity.
- Per-class cache users and selective removal of old stamp entries; replace generated accessor methods on redefinition.
- Custom metaclasses/method combinations are rejected. with-slots/with-accessors remain P30; recursion-resource optimization remains #541.

## Representation and acceptance

Standard descriptors extend fields 0–8 with self at 9, direct defaults 10, superclass objects 11, CPL objects 12, cache users 13, reserved 14 and generated accessor methods 15. Candidate descendant descriptions are computed and checked before publication. Old layouts retain self identity. Common local values and shared-to-local values survive migration; local-to-shared slots are discarded with their bound values available to the update hook.

Only cache entries using obsolete stamps are removed, through each class's cache-user list. Historical standard layouts are not accumulated in the legacy descriptor registry. The standard-class dependency registry uses strong references; weak reclamation is outside this phase.

Curriculum CommonLispBasicMaster commit 639544c: the full Level 21-B fence at L700 contains missing named BLOCKs inside DEFCOMMAND lambdas. SBCL reports compile errors for TAKE/DROP/USE/TALK too. The acceptance fixture adapts only that macro, keeping declarations outside its added named BLOCK; the remaining completion code is unchanged. It compares world generation, movement, input parsing and object printing. Level 21-A qualifier and initialization examples also run sequentially.

The lifecycle fixture compares combination, values, initialization, redefinition, inheritance, forward references, aliases and change-class with SBCL 2.6.10.168. Common unbound-slot preservation and removing only the old generated accessor method object follow the CLHS and are checked in unit tests: SBCL includes common unbound slots in the added hook list, and removes external accessor replacements by signature. The fixture filters that unbound name from its hook log.

## References and validation approach

[Class redefinition](https://www.lispworks.com/documentation/HyperSpec/Body/04_cf.htm), [slot preservation](https://www.lispworks.com/documentation/HyperSpec/Body/04_cfa.htm), [shared-initialize](https://www.lispworks.com/documentation/HyperSpec/Body/f_shared.htm), [change-class](https://www.lispworks.com/documentation/HyperSpec/Body/f_chg_cl.htm), [find-class](https://www.lispworks.com/documentation/HyperSpec/Body/f_find_c.htm).

Prepare implementation and acceptance tests before one read-only Claude Code review; batch reproductions and fixes. Normally one focused follow-up. Run heavy native suites only after review fixes, against frozen sources.


Review fixes restrict redefinition to proper names, roll back newly created forward placeholders on failed definitions and restore old aliases. Legacy condition/structure CPL objects are frozen at definition time so removed or rebound parent names cannot change ancestry identity. The review regression fixture covers aliases, failed definitions, swapped structure names, removed condition names and reused parent names. Reports: `clos-phase29-claude-review.md` and `clos-phase29-claude-review.ja.md`.


After the focused follow-up: standard DEFCLASS on an alias creates a new class; same-kind condition/structure definitions update the aliased object and keep its proper name, matching measured SBCL behavior. Legacy CPL snapshots derive from direct parent objects; only the legacy definition's internal name lookups use temporary resolved ancestor descriptions. SBCL 2.6.10.168 itself fails condition inheritance through an alias whose proper name was removed; that case, including inherited readers/reports, is covered by Zilisp unit tests. A placeholder referenced by a successful nested definition survives an outer failure.


## Full curriculum comparison

Of 1107 canonical blocks classified with SBCL 2.6.10.168, 955 are candidate A. Reader: both-ok 1079, both-error 23, Zilisp-only error 5, SBCL-only error 0, unchanged from P28.

Evaluation: match 566, both-error 362, output-diff 1, Zilisp-only error 26, SBCL-only error 0, timeout 0. All eight changed outcomes versus P28 with the same SBCL version improve to match: five forward-reference cases and three qualifier cases. None regress from match. The single output difference remains Level13 L455. Results: `compatibility/eval-check-sbcl-2.6.10-p29.tsv`. Earlier 2.6.7 and P28 records are preserved. The tool's generated Markdown still hardcodes 2.6.7, so that heading is not version evidence for this run.


## Final validation (Linux, Zig 0.17.1)

| Check | Result |
| --- | --- |
| Unit tests | Debug, ReleaseSafe, ReleaseFast passed |
| Language tests | 91/91 passed, including four new cases and GC stress copies |
| Native ReleaseFast | All 49/49 passed, normal and GC stress |
| Native Debug | clos-lifecycle and clos-lifecycle-review: 2/2 passed, normal and GC stress |
| Cross builds | x86_64 Windows GNU, x86_64/aarch64 Linux musl, x86_64/aarch64 macOS passed |
| Formatting/diff | zig fmt passed; diff check excludes intentional expected-output whitespace and empty final TSV fields. New-file trailing whitespace, fixture copies and TSV field counts verified |

The full 49-case native Debug suite and Windows/macOS execution were not run. Heavy final checks used frozen sources after review fixes. GC stress includes captured class guards/method closures, rack migration, cyclic shared values and condition aliases/readers/reports.

One initial review and one focused follow-up. Started and accepted on 2026-11-12, one working day; exact active time was not measured. Recursion resource optimization remains #541. Weak registries and custom metaclasses/method combinations are not implemented; with-slots/with-accessors remain P30.
