# P28 generic functions and methods (2026-11-12)

Tasks: tque #320 and child #536. Build callable generic functions on P27 classes/racks, sharing the ordinary Entry ABI across VM and native execution.

## Scope and acceptance

- `defgeneric`, `defmethod`, inherited primary methods, multiple dispatch, EQL specializers and argument precedence.
- Next-method APIs, no-applicable/no-next hooks, method addition/removal/lookup and applicable-method computation.
- Generic class accessors, `print-object`, `print-unreadable-object`.
- Unique positive class stamps, including built-in, condition and structure classes.
- CommonLispBasicMaster commit `639544c8133fdc51ffe4c2184aad785345128419`: Level 21-A fences at lines 86, 122, 142, 175 and 236 run sequentially and match SBCL. The manager template references an undefined supervisor and is excluded; qualifier and initialization examples belong to P29.
- P29 covers before/after/around, initialization hooks and class redefinition/obsolete racks. P30 covers with-slots after symbol-macrolet.

## Implementation

Generic functions use the function tag and ordinary Entry ABI to call a Lisp dispatcher. Managed method objects retain specializers, closures, lambda lists and their owning generic function. GC traces both new kinds.

Dispatch caches map active argument positions' class stamps plus EQL-match boolean masks to ordered applicable method lists. Values themselves are not compared by equal: that would conflate distinct strings under EQL. Add/remove/replace and generic redeclaration clear the cache. Accessors cache slot indices or shared cells by stamp. Selective invalidation and obsolete rack migration remain P29.

Keyword validation uses the union accepted by the generic and applicable methods. Generated method lambdas accept other keys so an individual method cannot reject another applicable method's keyword. Replacement next-method arguments must preserve the ordered applicable method list; violations signal program-error. Cases SBCL does not diagnose by default are tested separately from SBCL output fixtures.

## Validation and review

Claude Code performed one read-only scoped review and a focused check of fixes. Runtime sources stayed frozen during native tests. Final results are recorded below.


## Known resource limit

The Lisp dispatcher consumes more intermediate frames than an ordinary function. Depth 40 succeeds; depth 600 produces storage-condition (SBCL 2.6.10.168 succeeds at 600). Stack safety limits were retained. Task #541 tracks reducing VM re-entry and intermediate frames; the existing policy that stack exhaustion bypasses handlers also applies. The change in deeply nested printing limits has not been measured.

Original review and disposition: `clos-phase28-claude-review.md` and `clos-phase28-claude-review.ja.md`.

Keyword checking follows [CLHS 7.6.5](https://www.lispworks.com/documentation/HyperSpec/Body/07_fe.htm), including &rest-only generics with applicable &key methods. Unknown-key cases not diagnosed by SBCL 2.6.10.168 are kept in unit tests.

## Full curriculum comparison

Extracted 1107 blocks from the canonical commit and reclassified them with SBCL 2.6.10.168; 955 are candidate A. Reader comparison: both-ok 1079, both-error 23, Zilisp-only error 5, SBCL-only error 0, matching the stored aggregate.

Evaluation: match 558, both-error 362, output-diff 1, Zilisp-only error 34, SBCL-only error 0, timeout 0. Compared with the stored SBCL 2.6.7 results, all 13 changed outcomes improve from Zilisp-only error to match; none change from match to failure. These are cumulative P27/P28 changes and also involve a reference-version change, so they cannot all be attributed solely to P28. The one output difference remains Level 13 L455.

Per-block results: `compatibility/eval-check-sbcl-2.6.10-p28.tsv`. Existing 2.6.7 results and fixtures are preserved. The tool's generated Markdown hardcodes SBCL 2.6.7; this run actually passed `/usr/local/bin/sbcl` (2.6.10.168-29d0bbc7f), so the generated heading is not version evidence.

## Final validation (Linux, Zig 0.17.1)

| Check | Result |
| --- | --- |
| Unit tests | Debug, ReleaseSafe, ReleaseFast passed |
| Language tests | 83/83 passed, including three new cases and GC stress copies |
| Native ReleaseFast | All 45/45 passed, normal and GC stress |
| Native Debug | generic, generic-review and clos-level21: 3/3 passed, normal and GC stress |
| Cross builds | x86_64 Windows GNU, x86_64/aarch64 Linux musl, x86_64/aarch64 macOS passed |
| Formatting/diff | zig fmt passed; diff check passed excluding intentional expected-output trailing whitespace and empty final TSV fields |

The full 45-case Debug native suite and Windows/macOS execution were not run. Earlier native attempts were stopped before review-driven source changes and are excluded; the results above use the final frozen source.

One initial review and one focused follow-up. Started and accepted on 2026-11-12: one working day; precise active work time was not measured. No further broad review was performed.
