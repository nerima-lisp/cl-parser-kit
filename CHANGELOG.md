# Changelog

## Unreleased

- bumped the `cl-weave` test dependency 0.11.0 -> 1.0.0 (cl-weave's first
  stable, SemVer-committed release; audit-driven correctness fixes only in
  reporters/matchers/CLI/runner internals, no change to any macro or API this
  project uses)
- extended mutation testing (`t/mutation-testing-test.lisp`) to a second
  dense boundary-comparison predicate, `%fix-it-region-conflicts-p`
  (previously only `%merge-parse-failure-pair` was mutation-tested);
  confirms every mutant of its 4-comparison or/and overlap guard is killed
- documented `sep-by-between`/`sep-by-at-least`/`sep-by-at-most`,
  `memoize`/`left-recursion-detected`, and `trace-parser` in
  `PARSING_PATTERNS.md` (the "recommended patterns" guide) -- present in
  `API.md`'s reference since they were added, but absent from the patterns
  guide entirely until now; mirrored the same additions into
  `docs/src/parsing-patterns.md` (the published MkDocs site's copy, manually
  kept in sync with the root guide)
- closed a pre-existing (not introduced this release) gap in
  `docs/src/api.md`, the published MkDocs site's copy of `API.md`: it was
  missing `left-recursion-detected`, the entire "debugging: `trace-parser`"
  category, and `sep-by-between`/`sep-by-at-least`/`sep-by-at-most` --
  likely never synced when those landed. Verified with a systematic
  symbol-set diff against the root file, not spot-checking, that every
  other documented symbol matches between the two

## 0.4.0 - 2026-07-25

- added `left-recursion-detected` — `memoize` now signals it instead of
  looping until the generic recursion-depth guard trips, giving a precise
  diagnostic for a packrat-memoization misuse; `left-recursion-detected-parser`
  / `left-recursion-detected-position` read the offending parser and position
- added `sep-by-between` / `sep-by-at-least` / `sep-by-at-most` for
  separated-list parsing with explicit min/max repetition bounds
- added `:case-sensitive` to `make-literal-rule` for case-insensitive
  keyword/literal tokenizing
- added `trace-parser`, a pass-through debugging combinator that logs each
  wrapped parser's outcome to `*trace-output*` (megaparsec's `dbg`)
- fixed `trace-parser`'s `:stream` default, which was evaluated once and
  closed over permanently instead of re-reading `*trace-output*` on every
  parse, contradicting its own documented rebinding behavior
- fixed `sep-by-at-least` not validating `min` against
  `*maximum-parser-repetition-count*`, unlike every sibling
  bounded-repetition combinator
- fixed a latent bug in the doc-support tooling (`t/examples-doc-support.lisp`)
  where `merge-pathnames` silently inherited README.md's `.md` type onto
  extension-less link targets like `LICENSE`, resolving to a nonexistent
  `LICENSE.md`
- broad internal performance pass: rewrote six self-recursive CPS combinator
  loops (`many`, `skip-many`, `fold-many`, `many-till`, `times-between`,
  `sep-by`/`chainl1`) as plain iteration, removed wasted hash-table
  allocations on empty-list fast paths, added an early return for
  `apply-fixes` with no fixes to apply, stack-allocated the `&rest` argument
  lists of `%merge-diagnostics` and `merge-parse-failures`, deduplicated
  tokenizer text/value computation for same-range token rules, and declared
  a global `(speed 3) (safety 1)` optimize policy; no public behavior change,
  measured throughput/consing improvements are in the individual commits
- bumped `cl-weave` 0.10.0 -> 0.11.0 and `cl-prolog` 0.7.0 -> 0.8.0 (both
  additive releases)
- added a full MkDocs (Material) documentation site under `docs/`, published
  to GitHub Pages at <https://nerima-lisp.github.io/cl-parser-kit/> via
  `.github/workflows/docs.yml` and buildable offline with `nix build .#docs`;
  `docs/src/` restructures `README.md`, `API.md`, `ARCHITECTURE.md`,
  `EXAMPLES.md`, `PARSING_PATTERNS.md`, `ROADMAP.md`, and every governance
  and policy document into a navigable site, with `examples/*.lisp` and
  `src/package.lisp` references rewritten to GitHub blob links so the
  rendered site does not depend on the surrounding source tree

## 0.3.0 - 2026-07-24

- rewrote `%pratt-start-expression/cps` (`pratt-parse.lisp`) to reuse the
  existing `%pratt-led-step/cps` macro instead of hand-duplicating its exact
  `multiple-value-bind`/`if-ok`/`funcall-failure` expansion shape -- the
  macro already existed specifically to remove this repetition for its two
  other call sites, this was the one place still duplicating it by hand
- converted `many-till` (`combinators-repeat.lisp`) from a direct
  `run-parser` call (which re-validates the whole token vector against
  `*maximum-parser-tokens*` on every iteration) to `%run-parser/if-success`
  over the pre-validated vector, matching every sibling repetition
  combinator in this file and removing a redundant per-iteration
  revalidation cost
- added a round-trip test exercising every one of a SPAN's seven fields
  individually through `ast-node->sexp`/`sexp->ast-node` with distinct
  values (`trees-traversal-test.lisp`): `%span->plist`/`%plist->span`
  (`tree.lisp`) each independently list the same seven span keys with no
  shared schema definition, and `ast-node-equal`'s own `:include-span`
  comparison only checks START/END per its documented contract, so no
  existing test could have caught the two functions silently drifting out
  of sync on SOURCE/*-LINE/*-COLUMN

- merged `ensure-vector-up-to`'s `string` and `vector` `etypecase` clauses
  (`core.lisp`) into one `(or string vector)` clause, matching `eof-token-p`'s
  existing style in `parser.lisp`: the `string` clause's `(coerce thing
  'vector)` was a verified no-op (a string already satisfies `vector`, so
  `coerce` returns the same object unchanged), making the two clauses
  identical
- extracted `children-equal-p` out of `%tree-equal`'s (`tree.lisp`) dense
  `and`-chain: the pairwise child-list-walking loop is now a separately
  named local function, so the chain reads as a checklist -- type, value,
  span?, data?, children -- without the walk's mechanics interrupting it

- added two `it-property` tests (`trees-traversal-test.lisp`) generalizing
  the existing fixed-example `sexp->ast-node-round-trips-test` to a
  randomized range of tree shapes: `AST-NODE->SEXP`/`SEXP->AST-NODE` must
  round-trip for any linear depth (using the existing `%deep-ast` generator)
  and any child count (`%wide-ast`), not just the one hand-picked sample tree

- removed `%scan-plain-digits` (`tokenizer-rules-extra.lisp`): it was
  `%scan-radix-digits` called at radix 10 in every branch but written as an
  independent copy of the same loop; its three call sites now pass radix 10
  explicitly instead
- extracted `%ensure-vector-within-tokenizer-limit` (`tokenizer.lisp`),
  shared by `%ensure-tokenizer-rule-vector` and
  `%ensure-tokenizer-rule-alternatives-vector`, which repeated the identical
  resource-limit-check-then-signal shape differing only in which limit/kind
  applies
- extracted `%tree-node-label` (`tree.lisp`), shared by `%tree->string` and
  `%tree->dot`'s `label-of`, which independently rendered the identical
  "TYPE VALUE" / "TYPE" string, one writing straight to a stream and the
  other returning a string for DOT-escaping

- rewrote three clusters of near-duplicate `it-sequential` tests as
  `cl-weave`'s table-driven `it-each` (advanced `cl-weave` usage: a literal
  cases list destructured per-case, with the case values also driving each
  generated test's own name): `diagnostics-test.lisp`'s six
  `diagnostic-related-count-limit-*` tests (a 2x3 slot x malformed-shape
  table), its four `diagnostics-string-count-limit-*` tests (a
  malformed-shape table), and `parser-contract-test.lisp`'s four
  `*-enforces-token-count-limit-*` tests (an entry-point x input-shape
  table) -- each cluster differed only in a couple of concrete values behind
  an identical assertion, not in distinct documented scenarios

- extracted `define-token-set-predicate` (`combinators-token.lisp`),
  collapsing `token-type-in`/`-not-in`, `token-text-in`/`-not-in`, and
  `token-value-in`/`-not-in` -- six near-identical single-token
  set-membership predicates differing only in their accessor, equality test,
  and whether a `NIL` accessor value needs special handling -- into one
  macro plus three short invocations, each keeping its own full docstring

- updated every project-metadata reference from the old `github.com/takeokunn/*`
  locations to `github.com/nerima-lisp/*`, matching the repositories' actual
  move to the `nerima-lisp` GitHub organization: `cl-parser-kit.asd` and
  `cl-parser-kit-test.asd`'s `:homepage`/`:bug-tracker`/`:source-control`,
  `flake.nix`'s `cl-weave`/`cl-prolog`/`paredit-cli` input URLs and package
  homepage (regenerating `flake.lock` to match), and `README.md`'s
  dependency links; left `:author "takeokunn"` and `LICENSE`'s copyright
  holder untouched since those name a person, not a repository location
- consolidated the `:type type :skip-p skip-p :matcher ...` boilerplate that
  every tokenizer rule constructor repeated (11 call sites across
  `tokenizer-rules.lisp`, `tokenizer-rules-text.lisp`, and
  `tokenizer-rules-extra.lisp`) into one small macro, `%token-rule`,
  composable enough to fit both bare-lambda matchers and matchers built up
  inside a `let`/`let*` of precomputed bindings

- closed several more genuine branch-coverage gaps found by systematically
  walking every remaining uncovered line in `src/`, distinguishing real gaps
  from `sb-cover` artifacts (macro-attribution, `&key`/`&optional` defaults,
  and macro-internal control flow -- documented as a generalized pattern in
  CONTRIBUTING.md): `%line-comment-end` never had a test for an unterminated
  line comment reaching end-of-source; `%write-diagnostic-related-items`
  never had a test for a bare single note/fix-it (not wrapped in a list);
  `%merge-parse-failure-pair`'s fallback-to-LEFT's-actual (when positions tie
  and RIGHT's actual is `NIL`) was never one of the mutation-testing suite's
  cases; `times-between` never had a test for `MIN > MAX`; `ast-node-equal`
  never had a test with `:include-data t` or for `ast-node->dot`'s newline
  escape case
- removed two more provably-unreachable branches, using the same
  call-graph-tracing method as `%trailing-token-failure` earlier: `permute`'s
  "no remaining element matched, and no failure was ever recorded" fallback
  (impossible given `NEXT-ROUND`'s own `REMAINING-COUNT > 0` guard), and
  `%source-line-starts`'s direct/uncached branch (impossible given its sole
  caller, `%source-line-at`, only invokes it inside a
  `*diagnostic-source-line-start-cache*` truthiness check)
- documented `%resource-limit-reader-symbol` (`core.lisp`) as another
  instance of the macro-internal-control-flow coverage artifact: it is called
  only from `define-resource-limit-condition`'s own macro body, so every
  invocation happens at the macroexpansion time of whichever file defines a
  resource-limit condition, never at program-execution time
- removed an unused `on-failure` continuation parameter from
  `%parse-pratt-then` (`pratt-builders.lisp`, introduced earlier in this same
  round of changes): every one of its four call sites relied on the default
  propagate-as-is behavior, so the explicit-override branch was dead code
  from the moment it was written
- generalized `scripts/check-coverage.pl`'s macro-attribution exclusion list
  to also cover `pratt.lisp` (whose only non-trivial content, beyond three
  `defstruct`s, is `define-pratt-register-operator`'s macro body); added a
  guard against a zero adjusted-coverage denominator after briefly
  over-extending the exclusion list to ~20 files and hitting exactly that
  crash (reverted; see CONTRIBUTING.md for why whole-file exclusion doesn't
  scale to files where the artifact is a small fraction of real, tested
  content)
- removed dead code in `%parse-failure-default-span` (`parse-failure-format.lisp`):
  its diagnostics-borrowing branch was live but unreachable in practice --
  its one caller (`%parse-failure-default-diagnostic`) only ever runs after
  `parse-failure->diagnostics` has already proven the same failure's filtered
  diagnostics list is empty, so recomputing that list here could never
  return anything to borrow a span from
- removed dead code in `%trailing-token-failure` (`parse-failure.lisp`): its
  "no token at POSITION" branch was unreachable -- traced its one call site
  (`%parse-with-full-consumption`) and proved both of *its* two callers
  (`parse-all`, `parse-pratt-all`) always pair `ok=nil` with a real `FAILURE`
  object, so `%trailing-token-failure` only ever runs with `ok=t` and
  `position` still short of the stream length
- fixed a crash in `%parse-failure-default-span` (`parse-failure-format.lisp`):
  when a `parse-failure`'s `diagnostics` field held a non-empty list of
  nothing but `NIL` entries -- a legitimate input the rest of this file
  (`%write-diagnostics`, `%parse-failure-diagnostics-list`) already tolerates
  and skips -- the fallback span lookup called `diagnostic-span` on the raw
  list's untested-for-nil first element instead of the already-nil-filtered
  list, signalling an uncontrolled `TYPE-ERROR` instead of falling through to
  `NIL`; `parse-failure->diagnostics`/`parse-failure->string` now synthesize
  the intended default diagnostic in this case instead of crashing

- rewrote `%tree-children-list` and `%validate-tree-child-list` (in
  `tree.lisp`) in terms of `%do-tree-children`, the macro they and every
  `%tree-walk`/`%tree-depth`/`%tree->string`/`%tree->dot` call site already
  shared -- the same circular/improper-list cycle-detecting walk had three
  independent hand-rolled copies (one collecting, one validating-only, one
  macro-generated), now one
- extracted `%parse-pratt-then` (in `pratt-builders.lisp`), a CPS helper
  mirroring `combinators.lisp`'s `%run-parser/if-success` for the Pratt side:
  `register-prefix`, `register-ternary`, `register-infix-non-assoc`, and
  `register-grouping` each repeated the same
  `multiple-value-bind (ok value next failure) (parse-pratt ...) (if ok ...)`
  shape: now each supplies only its own success continuation, with failure
  propagation defaulted the same way `%run-parser/if-success` already does
- upgraded the `cl-weave` test dependency from v0.9.0 to v0.10.0 and the
  `cl-prolog` test dependency from v0.6.0 to v0.7.0 (`flake.nix`/`flake.lock`);
  both releases are additive/perf/refactor only for the surface this project
  uses, confirmed by a full compile-and-test run against the new pins
- closed several genuine (non-artifact) coverage gaps found by reading
  `sb-cover`'s per-line branch report directly: `bind-parser` never had a test
  where the first sub-parser consumed no input before the second one failed
  (the uncommitted-failure branch, now verified via `opt`'s recovery
  semantics); `ensure-vector-up-to`'s LIST clause never had a test that ran to
  completion successfully (every existing LIST-based test hit either an
  error or the token-count limit); `%coerce-bounded-float` never had a test
  for negative-mantissa overflow saturation, only positive; `make-radix-integer-rule`
  never had a test for a matched-but-empty digit run distinct from a
  prefix mismatch; `make-operator-rule`'s matcher never had a test invoking
  it directly at an out-of-bounds index (`token-rule-matcher` is public API,
  so this is reachable independent of `tokenize`'s own bounds-safe loop)
- extracted `%walk-bounded-list` (in `core.lisp`), the bounded
  cycle-detecting cons-walk (a `seen` hash-table plus a count-against-limit
  guard) that `%ensure-parse-failure-list-count`, `%present-fixes`,
  `%write-diagnostic-related-items`, and `%write-diagnostics` each
  re-implemented by hand across four files; every one of them now supplies
  only its own limit-exceeded condition and per-item action
- inlined and removed `%delimited-boundary`, a private one-line alias for
  `between` with no independent meaning
- documented why `tokenize-string` (a public alias for `tokenize`) exists,
  rather than leaving a reader to chase an undocumented one-line
  indirection
- taught `scripts/check-coverage.pl` to additionally report expression/branch
  coverage with known macro-attribution-artifact files excluded from the
  denominator (currently `tree-macros.lisp`, whose 0/150 is confirmed
  artifact, not untested code -- every function `define-tree-node-family`
  generates has dedicated tests reached through `ast.lisp`/`cst.lisp`).  This
  does not change the gate's pass/fail threshold, only adds a second,
  more accurate figure alongside the raw one: 96.10% adjusted expression
  coverage versus 93.74% raw
- documented, in `CONTRIBUTING.md`, the coverage-gate policy (90%/80% is the
  real bar; 100% is not reachable with `sb-cover` regardless of test effort,
  for the two proven reasons above) and the test-abstraction convention
  (`assert-combinator-success`/`-failure` by default, with the three
  narrow exceptions where it does not fit), so both are durable project
  policy rather than one-off decisions
- removed dead code: `%join-expected-items`'s 0- and 1-item `case` clauses
  were unreachable -- its sole caller (`%parse-failure-expected-string`)
  only ever invokes it with 2+ items, handling 0 and 1 itself first
- proved, with a controlled before/after test, that `sb-cover` cannot mark
  `&key`/`&optional` default-value forms as covered even when a test calls
  the function with zero arguments so every default fires: `make-span`'s
  six default forms stayed 0/6 in the coverage report after adding
  `make-span-defaults-every-keyword-to-a-zero-width-origin-test`, which
  passes and does exercise them at runtime. This is a second, independent
  `sb-cover` reporting gap alongside the macro-attribution one already
  documented, confirmed empirically rather than inferred
- closed three more real coverage gaps in `parse-failure-format.lisp`:
  the empty-`:expected`-list "unknown input" fallback, a non-token/
  non-symbol/non-string `:actual` value's `PRIN1-TO-STRING` fallback, and a
  typeless token's text-based fallback; expression coverage rose to 93.74%
  and branch coverage to 93.60%
- re-audited the 5 test-suite occurrences previously classified as
  deliberate exceptions to the `assert-combinator-success`/`-failure`
  convention; 2 of them (in `examples-advanced-snippets-test.lisp`) turned
  out to have a single deterministic outcome once traced through their
  fixed input, not a genuine either-outcome case, and are now converted.
  Exactly 3 verified exceptions remain in the whole suite: a fuzz test
  (outcome depends on generated input), a macro definition, and a
  parser-fixture builder closure (production grammar code, not a test
  assertion)
- closed five more real coverage gaps: `verify`'s default `:expected-name`,
  `length-count`'s non-integer/negative count rejection, `make-span`'s
  all-defaults construction, expression coverage rose to 93.66% and branch
  coverage to 93.19%
- converted the remaining 12 hand-written `multiple-value-bind` assertion
  blocks that used a `diagnostics`-named fourth value (across
  `combinators-core-test.lisp`, `combinators-delimited-test.lisp`,
  `combinators-recover-test.lisp`, `combinators-separator-test.lisp`, and
  `combinators-transform-test.lisp`) to `assert-combinator-success`; a
  systematic final sweep confirmed exactly 5 hand-written occurrences remain
  in the whole test suite, each independently verified as a deliberate
  exception (an either-outcome-is-valid test, one macro definition, and one
  parser-fixture builder closure) rather than an oversight
- closed six more real coverage gaps: `eof-token-p`'s LIST-argument clause,
  `parse-all`'s own token-count-limit check (distinct from `parse-tokens`'s),
  `make-keyword-rule`'s non-string-keyword rejection and its
  case-sensitive-by-default matching, `make-predicate-rule`'s `:skip-p`
  branch, and `%source-line-at`'s *uncached* fallback CRLF/lone-CR handling
  (a second, independent implementation from the cached path fixed earlier);
  expression coverage rose from 93.1% to 93.6% and branch coverage from
  90.5% to 92.6%
- raised the abstraction level of ~20 hand-written
  (across `combinators-chain-test.lisp`, `combinators-core-test.lisp`,
  `combinators-expression-test.lisp`, `combinators-memoize-test.lisp`,
  `combinators-separator-test.lisp`, `combinators-transform-test.lisp`,
  `examples-snippets-runtime-test.lisp`, and `parser-diagnostic-test.lisp`)
  to `assert-combinator-success`/`assert-combinator-failure`; only 3 of the
  original 35 remain, each a deliberate exception (two tests where either
  outcome is valid so no single fixed assertion applies, one macro
  definition) rather than an oversight
- documented, with exact numbers, why 100% `sb-cover` coverage is not
  reachable while also maximizing macro use: of the 424 currently-uncovered
  `src/` expressions, roughly 220 are inside macro *definitions*
  (`tree-macros.lisp`, `pratt.lisp`, `combinators-sequence.lisp`'s
  `define-separated-parser`/`define-chain-parser`, `pratt-parse.lisp`'s
  `%pratt-led-step/cps`, `core.lisp`'s `define-resource-limit-condition`) —
  `sb-cover` attributes a macro's generated code to its call site, never to
  the definition, so these bodies read as 0% regardless of how thoroughly
  the generated functions are tested; added matching explanatory comments
  next to each one
- raised the abstraction level of ~20 hand-written
  `(multiple-value-bind (ok value next failure) ...)` test assertion blocks
  in `pratt-builders-test.lisp`, `parser-properties-test.lisp`,
  `combinators-control-test.lisp`, and `parser-contract-test.lisp` to the
  existing `assert-combinator-success` / `assert-combinator-failure` macros,
  which already encode the "OK must be true/false, VALUE must be
  false-on-failure" invariant once instead of at every call site
- closed real coverage gaps found by walking `sb-cover`'s per-branch report
  (not the aggregate percentage): `%coerce-bounded-float`'s
  `single-float`/`short-float`/`long-float` saturation arms, the float
  scanner's digit-less `e`/`.` decline paths and `:allow-sign`, every
  `make-*-rule` constructor's `:skip-p` branch, the diagnostic source-line
  cache's CRLF/lone-CR and line-truncation paths, `ensure-vector`'s plain
  (non-circular) too-long and successful-string-coercion paths, and the five
  downstream-parse-failure propagation branches across
  `register-prefix`/`register-ternary`/`register-infix-non-assoc`/
  `register-grouping` in `pratt-builders.lisp`; expression coverage rose from
  91.5% to 93.1% and branch coverage from 87.4% to 90.5%
- extracted `%scan-float-fractional-part`, `%scan-float-exponent-part`, and
  `%float-lexeme-value` out of `make-float-rule`'s matcher, which was the
  most deeply nested function in the library (three sequential scanning
  phases and a value computation all inlined in one lambda); behavior is
  unchanged, verified against the existing float tests plus targeted manual
  checks of the "digit-less e/." decline paths
- consolidated `ast.lisp` and `cst.lisp` into a single `define-tree-node-family`
  macro invocation each; the macro (now in `src/tree-macros.lisp`, split out
  of `src/tree.lisp`) generates the full per-family API (`->sexp`, `sexp->`,
  `token->`, `-of`, `-walk`, `-reduce`, `-map`, `-equal`, `-find`, `-collect`,
  `-count`, `-depth`, `->string`, `->dot`) from the generic `%tree-*` engine,
  removing ~200 lines of duplication between the two families
- removed the unused internal helper `%parser-token-limit-failure-if-needed`
- upgraded the test-only dependency to its latest release (cl-weave `v0.9.0`)
  and added `t/fuzz-test.lisp`, which uses cl-weave's new `it-fuzz` driver to
  fuzz `tokenize-string` and `parse-tokens` against adversarial generated
  inputs
- introduced `define-resource-limit-condition` and rebuilt
  `tokenizer-resource-limit-exceeded`, `diagnostic-resource-limit-exceeded`,
  and `parse-failure-resource-limit-exceeded` on it, removing their identical
  hand-written `kind`/`value`/`limit` condition bodies without changing any
  exported name
- extracted `%run-parser-sequence` / `%run-ordered-choice` (shared by
  `seq`/`sequence-of` and `alt`/`choice`) and `%run-fixed-repetition` (shared
  by `times` and `length-count`'s internal counted-repetition helper), so each
  pair's previously duplicated loop body has one implementation
- rewrote `%run-parser-sequence`, `%run-ordered-choice`, `recover`, and
  `permute` on the existing `%run-parser/if-success` continuation-passing
  helper instead of a direct `multiple-value-bind` over `run-parser`, for
  consistency with the CPS style already used throughout
  `combinators-sequence.lisp`
- split `apply-fix-it` / `apply-fixes` and their piece-list text-splicing
  helpers out of `diagnostics.lisp` into `src/diagnostics-fixes.lisp` (a
  self-contained subsystem with no dependency on diagnostic/parse-failure
  merging)
- added direct tests for `ensure-list`'s circular- and improper-list rejection
- extracted `%recursion-depth-failure`, shared by combinator and Pratt
  recursion-depth guards, which previously built an identically-shaped
  `parse-failure` by hand in both `combinators.lisp` and `pratt-parse.lisp`
- rewrote `%run-parser-or-recoverable` (backing `opt`) on
  `%run-parser/if-success` for the same reason; the remaining hand-written
  `multiple-value-bind (ok value next result)` call sites (`memoize`,
  `%parse-with-full-consumption`, `parse-tokens`) each got a comment
  explaining why they stay direct-style -- caching all four return channels,
  post-processing an arbitrary caller-supplied form, and terminating the CPS
  chain at the public API boundary, respectively, none of which fit a
  success/failure continuation split

## 0.2.0 - 2026-07-20

- capped caller-supplied token streams with `*maximum-parser-tokens*`, which
  bounds `run-parser`, `parse-tokens` / `parse-all`, and `parse-pratt` /
  `parse-pratt-all`, returning a parse failure before walking oversized
  caller-controlled token vectors or proper lists; `filter-tokens` signals at
  the same limit, circular or improper token lists are rejected before
  traversal, and `skip-until` now skips long recovery runs iteratively instead
  of consuming control stack
- added tree resource limits `*maximum-tree-depth*` and `*maximum-tree-nodes*`
  with the `tree-depth-limit-exceeded`, `tree-node-limit-exceeded`, and
  `tree-child-list-invalid` conditions, so AST/CST traversal, conversion,
  comparison, and rendering helpers fail explicitly on adversarially deep, wide,
  or malformed external trees instead of exhausting the control stack or memory
- added `*maximum-parser-repetition-count*`, which caps `length-count`'s N,
  `permute`'s parser list, the token-set combinators' caller-supplied sets, and
  the computed parser lists built by `choice`, `sequence-of`, `seq-map`,
  `pick`, and `make-expression-parser`, and removed diagnostic merging through
  `apply`/`append`, so attacker-influenced inputs cannot expand into unbounded
  argument lists
- added `*maximum-parser-apply-arity*`, bounding `seq-map`'s function-call arity
  and removing an attacker-sized `apply` path
- extended the tokenizer limits with rule-count and operator alternative-count
  caps that signal the existing `tokenizer-resource-limit-exceeded` condition
- added diagnostic and parse-failure collection limits:
  `*maximum-diagnostic-related-count*` bounds rendered notes and fix-it hints,
  `*maximum-diagnostic-fix-count*` bounds `apply-fixes` input entries (nil
  entries included), `*maximum-diagnostic-count*` bounds batched diagnostic
  rendering, and `*maximum-parse-failure-expected-count*` /
  `*maximum-parse-failure-diagnostic-count*` bound parse-failure payloads — each
  rejecting circular or improper lists through the matching
  `diagnostic-resource-limit-exceeded` /
  `parse-failure-resource-limit-exceeded` condition
- refined `apply-fixes` so same-position zero-width insertions preserve input
  order
- hardened the release bootstrap dependency scan to statically inspect ASD
  metadata instead of loading dependency ASD files, and to reject component
  paths that resolve outside their system source root
- reduced avoidable allocation in `permute`, removed duplicate child-list
  traversal from tree equality, and bucketed operator matching by leading
  character

## 0.1.0 - 2026-07-20

- added predicate token-run scanners: `take-while` / `take-while1` match a run of
  consecutive tokens satisfying a predicate (returning the list; `take-while1`
  requires at least one), and `skip-while` skips such a run discarding it —
  Megaparsec's `takeWhileP` / `takeWhile1P` over a token stream
- added a CSV parser example (`examples/csv-parser-example.lisp`), a
  line-oriented counterpoint keeping the newline as a real token: rows via
  `sep-end-by`, fields via `sep-by1`, and quoted fields that may contain commas
- added an error-recovery example (`examples/error-recovery-example.lisp`)
  demonstrating panic-mode recovery with `recover` + `skip-until` driven by
  `many-till`, so one parse reports every malformed statement (and collects the
  recovery diagnostics, read from `run-parser`'s fourth value) instead of
  aborting at the first error
- added a complete recursive JSON parser example
  (`examples/json-parser-example.lisp`), an end-to-end demonstration of the
  tokenizer (escaped strings, signed/exponent numbers, keyword and literal
  rules), a self-referential grammar via `defparser`, and the
  sequence/choice/separator combinators, decoding objects to alists and arrays
  to lists
- completed the fix-it feature with applicators (previously fix-its were
  suggestion data with no way to apply them):
  - `apply-fix-it` — return source with one fix-it's span region replaced by its
    replacement (a `nil` replacement deletes it); offsets are clamped to source
  - `apply-fixes` — apply a list of fix-its last-to-first, so each edit leaves
    the not-yet-applied earlier offsets valid; pair with `diagnostic-fixes` to
    auto-apply a diagnostic's suggestions
- rounded out the repetition/control combinators against Parsec/Megaparsec/nom/
  FParsec:
  - `some-till` — `many-till` requiring at least one match before the end parser
    (Megaparsec's `someTill`)
  - `length-count` — parse a count for N, then parse an item parser exactly N
    times (nom's `length_count`); each item must consume input, so a hostile
    count cannot force an unbounded loop
  - `not-empty` — fail if a parser succeeds without consuming input, to guarantee
    forward progress (FParsec's `notEmpty`)
- added opt-in packrat memoization and completed the token-matching family:
  - `memoize` / `with-parse-memoization` — wrap a parser so that, inside the
    dynamic extent, its result at each position is computed once and reused,
    turning an ambiguous or heavily backtracking grammar's exponential
    re-parsing into linear-time packrat parsing (a no-op outside the extent, so
    grammars that do not need it are unaffected)
  - `token-value-in` / `token-value-not-in` — match (or reject) a token whose
    `token-value` is one of a set, completing the type/text/value matching family
    alongside `token-type-in` / `token-text-in`
- added structured-diagnostic accessors, the counterparts of the string
  renderers:
  - `parse-failure->diagnostics` — the structured `diagnostic` objects for a
    failure (its attached diagnostics, or a synthesized default), for rendering
    or aggregating failures with your own tooling
  - `diagnostics->string` — render a whole list of diagnostics (blank-line
    separated), the multi-diagnostic form of `diagnostic->string`
- added two stream/error-handling conveniences:
  - `filter-tokens` — return a fresh vector of the tokens satisfying a predicate,
    for pruning a stream (e.g. dropping non-skipped `:comment` tokens) before
    parsing
  - `parse-failure-span` — the source span of a failure's actual token (or `nil`
    at end of input), for rendering a caret or slicing the offending region
    without building a full diagnostic
- added tree construction and serialization-round-trip helpers for both node
  families, removing the boilerplate of building located nodes by hand:
  - `token->ast-node` / `token->cst-node` — build a leaf node from a token (its
    value from a `:value-function`, `token-text` by default, and its span from
    the token)
  - `ast-node-of` / `cst-node-of` — run a parser and wrap the result into a node
    whose span covers the consumed tokens (value in `value`, or in `children`
    with `:as-children t`)
  - `sexp->ast-node` / `sexp->cst-node` — reconstruct a node from the plist that
    `ast-node->sexp` / `cst-node->sexp` produce, rebuilding an embedded span, so
    the `->sexp` form round-trips
- added tree-rendering helpers for both node families, completing the tree
  lifecycle (build, traverse, query, fold, compare, and now render):
  - `ast-node->string` / `cst-node->string` — a human-readable indented tree
    (one node per line, `type` then `value`) for debugging and REPL inspection
  - `ast-node->dot` / `cst-node->dot` — a Graphviz DOT digraph (`:graph-name`
    names the graph) for visualizing a parse tree with `dot`
- added an operator-precedence expression builder and two combinator gaps:
  - `make-expression-parser` — the combinator-layer counterpart to the Pratt
    parser: build a parser from an operator table (precedence levels highest
    first, with `:prefix` / `:postfix` / `:infix-left` / `:infix-right` /
    `:infix-non-assoc` operator specs whose parsers yield the combining
    function), for when operands and operators are arbitrary parsers rather than
    single tokens; see `examples/operator-precedence-example.lisp`
  - `sequence-of` — the list form of `seq` (`(sequence-of (list a b))` is
    `(seq a b)`), the counterpart to `choice`
  - `chain-postfix` — a left-associative suffix chain (member access, calls,
    indexing): parse a base, then fold zero or more suffix parsers, each yielding
    a function that transforms the accumulated value
- broadened the surface again with a further batch of commit-preserving
  additions, each built on the existing primitives and covered by tests:
  - backtracking control: `attempt` — the inverse of `commit`, demoting a
    parser's committed failure to a recoverable one so a surrounding
    `opt`/`many`/`sep-by` backtracks to the start position (Parsec's `try`)
  - permutation parsing: `permute` — parse a fixed set of parsers in any order,
    each exactly once, returning their values in argument order
  - value shaping: `pair` and `separated-pair` (nom-style two-parser sequences),
    plus `fold-many1` (the one-or-more form of `fold-many`)
  - negative token sets: `token-type-not-in` / `token-text-not-in`, the
    complements of `token-type-in` / `token-text-in`
  - tokenizer rules: `make-radix-integer-rule` (base 2..36 with an optional
    case-insensitive prefix such as `0x`/`0b`/`0o`), `make-float-rule` (decimal
    exponents, e.g. `6.022e23`, with a clamped `*maximum-number-exponent*` guard),
    `make-operator-rule` (longest-match over an operator set), and
    `make-nested-block-comment-rule` (comments that nest); plus `:case-sensitive`
    on `make-keyword-rule` and `:escapes` decoding on `make-string-rule`
  - Pratt registrars: `register-ternary` (`cond ? then : else`, right
    associative) and `register-infix-non-assoc` (chaining is a parse error)
  - tree utilities for both node families: `ast-node-reduce` / `cst-node-reduce`
    (fold over nodes), `ast-node-equal` / `cst-node-equal` (structural equality),
    and an `:order :post` option on `ast-node-walk` / `cst-node-walk`
- expanded the combinator surface with commit-preserving additions built on the
  existing primitives:
  - choice/value: `choice` (list form of `alt`), `option` (`opt` with an
    explicit default), `fail-parser`, `as-value`, `pure`
  - repetition: `times`, `skip-many`, `skip-many1`, `fold-many`, `many-till`,
    and `chainl` / `chainr` (defaulting variants of `chainl1` / `chainr1`)
  - applicative and source spans: `seq-map` (lift a function over `seq`), `pick`
    (keep the N-th result of a sequence), `spanning` (attach the merged source
    span of the consumed tokens, for building located AST/CST nodes)
  - token matching: `any-token`, `token-type-in`, `satisfies-value`
  - failure context: `context` (append an explanatory `note-diagnostic` to a
    failure without changing its expected form or commitment)
  - tokenizer rule: `make-char-rule` (single character by character, set, or
    predicate)
  - tree queries generated for both node families: `ast-node-collect` /
    `cst-node-collect` (all matches), `ast-node-count` / `cst-node-count`,
    `ast-node-depth` / `cst-node-depth`
  - range repetition: `times-between` (greedy min..max), `at-least` and
    `at-most` (open-ended variants), plus `surrounded-by` for symmetric
    delimiters
  - high-level Pratt registrars that hide the raw nud/led protocol and
    binding-power arithmetic: `register-atom`, `register-prefix`,
    `register-infix-left`, `register-infix-right`, `register-postfix`, and
    `register-grouping` (matched `open expr close` pairs)
  - error recovery: `skip-until` and `recover` for panic-mode
    resynchronisation, so a single parse can report several errors (drive the
    loop with `(many-till statement (end-of-input))`)
  - tree traversal generated for both node families: `ast-node-walk` /
    `cst-node-walk` (pre-order visit), `ast-node-find` / `cst-node-find` (first
    match), `ast-node-map` / `cst-node-map` (bottom-up rebuild)
  - ergonomic macros: `parse-let*` (do-notation over `bind-parser`),
    `parser-lazy` and `defparser` (forward references and recursive grammars)
  - comprehensive gap closure against Parsec/Megaparsec/nom/FParsec:
    `end-by` / `end-by1` (required terminator), `verify` (assert a predicate on a
    parsed value), `commit` (PEG cut), `current-position` (capture the token
    index), `token-text-in` (match a lexeme set), `recognize` (span of consumed
    tokens), and the span helpers `span-contains-position-p` and `span-text`
- fixed a silent error-swallowing bug in `bind-parser` (the foundation of
  `preceded-by`, `terminated-by`, `between`, and the `delimited-sep-by*`
  wrappers): once the leading parser consumed input, a failing trailing parser
  was reported as a non-committed failure, so a surrounding
  `opt`/`many`/`sep-by`/`alt` backtracked past the half-consumed construct and
  dropped the grammar error. It now promotes the failure to committed, matching
  `seq`
- hardened the combinator engine against untrusted input with
  `*maximum-parser-recursion-depth*` (default 4000, checked in `run-parser` and
  in `chainr1`'s own right-recursion), so deeply nested grammars return a
  `:maximum-recursion-depth` failure instead of exhausting the control stack
- added tokenizer resource limits `*maximum-tokenizer-source-length*` and
  `*maximum-tokenizer-tokens*`, which signal the exported
  `tokenizer-resource-limit-exceeded` condition instead of exhausting memory on
  an adversarially large or token-dense source
- bounded numeric scanning with `*maximum-number-lexeme-length*` (default 1024)
  so a multi-million-digit run cannot force superlinear bignum work; excess
  digits gracefully start a new token
- bounded diagnostic rendering with `*maximum-diagnostic-line-length*` (default
  400) so a single pathological source line (e.g. a minified file) cannot make
  one `diagnostic->string` call allocate proportional to that line's full length
- fixed `span-merge` to derive start/end line and column from whichever argument
  actually has the smallest start / largest end offset, so merging two spans out
  of source order no longer produces an internally inconsistent span
- fixed `%make-offset-span` normalization so a token whose raw start/end are both
  negative no longer normalizes to an inverted span
- upgraded the test-only dependencies to their latest releases (cl-weave
  `v0.8.0`, cl-prolog `v0.6.0`) and migrated to cl-weave's string-named test
  registration API
- fixed `between` (and therefore `delimited-sep-by`/`delimited-sep-end-by`)
  to return the inner value instead of the opening delimiter
- fixed `lookahead` to preserve the farthest inner-failure position instead of
  resetting to the starting position on failure
- fixed a crash on an unterminated block comment: `make-block-comment-rule` now
  consumes to end-of-source (like line comments) instead of raising a type error
  on untrusted input that opens `/*` without closing it
- fixed diagnostic caret rendering, which was drawn two columns too far right
- fixed source-line context under carets for CR-only (classic-Mac) sources so
  line splitting agrees with position tracking
- hardened `make-number-rule` against untrusted input: numbers are parsed with
  `parse-integer` instead of the Lisp reader (which permanently interned
  malformed runs as symbols), and the scanner accepts at most one decimal point
- bounded Pratt recursion with `*maximum-pratt-recursion-depth*` so
  pathologically deep input returns a `:maximum-recursion-depth` failure
  instead of exhausting the control stack
- eliminated the O(n^2) parse cost for list token streams by coercing to a
  vector once at the `parse-tokens` / `parse-all` boundary
- sped up tokenization (roughly 2x) by returning step state through multiple
  values instead of a per-token plist, plus tighter numeric declarations
- added property-based tests (parser invariants, tokenizer span coverage) and a
  cl-prolog relational contract proving the Pratt precedence graph is acyclic
- fixed `scripts/run-coverage.lisp` to compile the project (sb-cover instruments
  at compile time) so the coverage report captures data instead of failing with
  "did not capture any coverage data"; the src coverage gate now passes at
  ~91% expression / ~87% branch
- added `scripts/run-compile-check.lisp` as a raw-checkout compile-verification
  entry point for the library and test ASD systems
- added `scripts/run-examples.lisp` as a raw-checkout example verification
  entry point so shipped sample files are executable outside the test package
- documented a canonical quick-start API surface in `API.md` and pinned
  `README.md` to the same curated bullet list with a regression test
- expanded `scripts/run-release-audit.sh` so release-readiness checks now
  enforce community, security, versioning, governance, maintainer, roadmap,
  and license artifacts in addition to the verification entry points
- made `scripts/run-implementation-smoke.sh` print each implementation's exact
  command, reported runtime version, and failing exit status for more
  audit-friendly portability triage
- added `scripts/run-release-audit.sh` as a single-command release-readiness
  entry point that checks required docs before running the baseline and smoke
  verification commands
- added `scripts/run-implementation-smoke.sh` as a checked-in multi-
  implementation smoke entry point for raw-checkout portability checks
- added `scripts/run-tests.lisp` as a raw-checkout verification entry point
  that loads repository source and test files directly before running the
  checked-in test runner
- published repository metadata in both ASD files for homepage, issue tracker,
  and source-control discovery
- added `SUPPORT.md` to document the verified support boundary and release
  expectations
- expanded `SECURITY.md` so private reports include runtime context and match
  the repository's verified support boundary
- fixed ASDF test-system wiring so raw-checkout verification no longer depends
  on a circular system lookup
- rewired raw-checkout verification scripts to register ASD metadata but load
  repository source and test files directly, avoiding ASDF system-resolution
  hangs on fresh checkouts
- removed duplicate `asdf:test-op` method definitions to keep test runs
  warning-free
- added executable regression tests for the representative README and
  `EXAMPLES.md` workflows
- added `sep-end-by`, `sep-end-by1`, `delimited-sep-end-by`, and
  `delimited-sep-end-by1` for grammars that allow trailing separators
- documented the current public surface in the README
- added contributor and security guidance
- added explicit versioning and release-policy documents for pre-release
  commit consumers
- expanded parser combinator coverage
- fixed parser combinator progress handling so `many` fails fast on
  non-advancing parsers instead of looping
- preserved nested parse failure positions through `map-parser` and
  `bind-parser`
- added `sep-by`, `sep-by1`, and `between` combinators for practical
  delimited-list and bracketed grammar construction
- added `chainl1` and `chainr1` combinators for left- and right-associative
  parser chains without a full Pratt table
- made `diagnostic->string` render source excerpts, notes, and fix-it hints
- fixed Pratt parser EOF failures to return structured diagnostics instead of
  signaling on a missing token span
- added a public Pratt diagnostic example and executable regression coverage
- made `parse-all` preserve trailing tokens in parse failures and attach
  source-backed diagnostics when available
- added a direct token-stream example for `parse-all`
- documented and regression-tested the external-token diagnostic fallback
  contract based on `token-start` / `token-end` plus `(:source <string>)` in
  `token-metadata`
- made `end-of-input` and `not-followed-by` attach source-backed diagnostics
  when the failing token carries span data
- added `preceded-by` and `terminated-by` combinators for delimiter-heavy
  grammars without manual value projection
- updated contributor guidance to treat README, `EXAMPLES.md`, and `examples/`
  workflows as executable public contract
- added roadmap and release-note placeholders for the public OSS surface
- add `ast-node->sexp` and `cst-node->sexp` for stable tree inspection output
- add CST-focused example coverage and regression tests for tree serialization

## Notes

This project does not currently ship formal versioned releases. When releases are
introduced, this file will track user-visible changes in a conventional
`Keep a Changelog` style.
