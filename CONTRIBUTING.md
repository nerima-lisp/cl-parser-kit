# Contributing

`cl-parser-kit` is intentionally small. Contributions should preserve that
shape.

## Before You Change Code

- read [`ARCHITECTURE.md`](./ARCHITECTURE.md) for the layer model and dependency direction
- check the existing tests and examples
- keep exported symbols intentional
- prefer the smallest change that solves the problem

## Expectations

- add or update tests for new behavior
- keep the README in sync with public API changes
- keep `API.md` / `EXAMPLES.md` in sync when public entry points or contracts change
- keep `SUPPORT.md` in sync when verification scope or support claims change
- keep `SECURITY.md` in sync when reporting paths or security-scoped claims change
- keep `GOVERNANCE.md` / `MAINTAINERS.md` in sync when review or ownership
  expectations change
- keep `CODE_OF_CONDUCT.md` in sync when collaboration expectations or
  enforcement guidance change
- keep `VERSIONING.md` / `RELEASING.md` in sync when release expectations or
  public API text changes
- keep `docs/src/` in sync whenever `README.md`, `API.md`, `ARCHITECTURE.md`,
  `EXAMPLES.md`, `PARSING_PATTERNS.md`, `ROADMAP.md`, or a governance/policy
  document changes -- `docs/src/` restructures that same content for the
  published MkDocs site and the two copies must not drift; verify with
  `nix build .#docs` or `mkdocs build --strict --config-file docs/mkdocs.yml`
- avoid introducing broad utility layers or hidden dependencies
- keep changes readable from the test suite
- preserve the executable example contract: representative README snippets and
  files under `examples/` are regression-tested and should keep working from a
  fresh image

## Working Style

- use `nix flake check` to run the full reproducible gate (compile check,
  tests, coverage, and lint) the same way CI does, on `x86_64-linux`,
  `aarch64-linux`, or `aarch64-darwin`
- use `nix develop --command sbcl --script scripts/run-tests.lisp` to rerun
  only the test suite with its pinned `cl-weave` and `cl-prolog` dependencies
- use `sbcl --script scripts/run-compile-check.lisp` when a change could
  affect ASDF loading, package wiring, or compile-time behavior
- use `sbcl --script scripts/run-examples.lisp` when a change touches public
  sample workflows or documented result shapes
- use `./scripts/run-implementation-smoke.sh` when a change is specifically
  about implementation portability or support-boundary claims
- if you already keep the repository on ASDF's search path, `asdf:test-system
  :cl-parser-kit` remains the equivalent REPL-level entry point
- when behavior changes affect diagnostics, examples, or public exports,
  prefer the narrowest supporting regression test in `t/` plus the full ASDF
  suite before handing work off
- prefer `assert-combinator-success` / `assert-combinator-failure` (and the
  Pratt/example-specific wrappers built on them) over a hand-written
  `(multiple-value-bind (ok value next failure) ...)` when a test asserts one
  fixed outcome. Reach for the raw `multiple-value-bind` only when neither
  fits: the outcome genuinely varies per input (a fuzz test), the code
  defines one of those assertion macros itself, or it is grammar/parser
  construction code rather than a test assertion at all
- keep parser, tokenizer, and diagnostic behavior explicit
- prefer simple data structures over extra abstraction

## Coverage Expectations

The CI gate (`scripts/check-coverage.pl`, invoked from the `coverage` flake
check) requires 90% expression / 80% branch coverage of `src/`. Treat gaps
against that gate as real and worth closing with a targeted test.

100% is not a realistic target with the current toolchain, independent of
test effort: `sb-cover` cannot mark three categories of code as covered no
matter how thoroughly the generated behavior is exercised at runtime --

- a macro's generated body is attributed to its *definition* site, never to
  its call sites, so a macro like `define-tree-node-family` or
  `define-resource-limit-condition` reads as uncovered even when every
  function it generates has dedicated tests (verified for
  `define-tree-node-family`, `define-pratt-register-operator`,
  `define-separated-parser`/`define-chain-parser`, and
  `%pratt-led-step/cps`; each has an explanatory comment at its definition).
  A `(declaim (inline ...))` function is the same phenomenon by a different
  mechanism: its body is compiled directly into each call site, so the
  out-of-line definition itself reads as uncovered (verified for
  `%pratt-token-at`; removing the `inline` declaration would "fix" the
  number at the cost of a function-call per token lookup in a hot loop, so
  it stays, with an explanatory comment at its definition)
- an `&key`/`&optional` default-value form is not marked covered even when a
  test calls the function with no arguments specifically to force every
  default to fire (verified with a controlled before/after test on
  `make-span`'s six default-value forms)
- a macro's *own* control flow -- the conditionals/loops that decide what to
  expand into, as opposed to the quasiquoted template it produces -- runs
  only at macroexpansion time (compiling whatever calls the macro), which
  `sb-cover`'s runtime instrumentation cannot observe at all; this is
  distinct from the first category, which is about the *generated* code
  being misattributed elsewhere, not about macro-internal logic that never
  runs at program-execution time in the first place (verified for
  `%assert-success-values`/`%assert-failure-values`'s leading-`declare`
  extraction loop in `t/package.lisp`: several tests do pass a leading
  `declare`, exercising both outcomes at the source level, yet the loop
  still reads as 0% covered)

When you see one of these three patterns behind a "why is this still
uncovered?" question, don't chase it with more tests -- confirm the pattern,
add the same kind of explanatory comment at the definition, and move on.

`scripts/check-coverage.pl` prints a second figure alongside the raw one:
expression/branch coverage with files *dominated* by confirmed
macro-attribution artifact excluded from the denominator (currently
`tree-macros.lisp`, `package.lisp` -- whose single `defpackage` form, one
macro call spanning the entire file, accounts for 304 of its 305 lines -- and
`pratt.lisp`). This does not change the gate's threshold or pass/fail result
-- it exists so the reported percentage isn't misread as "6% of real code is
untested" when a meaningful share of that 6% is structurally unmeasurable.

Only add a file here when its own gap has been read line-by-line and
confirmed to be (almost) entirely macro-definition body, the same way
`tree-macros.lisp` was -- **not** merely because every uncovered line in it
happens to be an artifact. Most files have both real, well-tested logic and a
handful of artifact lines (an `&key` default, an `in-package`); excluding
those whole files would throw away their genuinely-covered content along
with the one or two artifact lines, and doing this for too many files at
once can shrink the branch denominator to zero (`check-coverage.pl` will
refuse to run rather than divide by it -- this happened once, from adding
~20 files at once, each of which had 100% branch coverage on its own but
whose combined exclusion left no branch-bearing file un-excluded). For a
file with only a small artifact fraction, add an explanatory comment at the
specific definition instead (see above) and accept the file's small,
permanent, explained shortfall in the raw percentage.

## Release Checklist

Before proposing a user-visible change, verify:

- tests for the changed behavior exist or were updated
- public docs (`README.md`, `API.md`, `EXAMPLES.md`) match the shipped API
- `docs/src/` (the published MkDocs site) reflects the same changes as the
  root docs it restructures
- `SUPPORT.md` matches the verification reality of the current checkout
- collaboration docs (`CODE_OF_CONDUCT.md`, `GOVERNANCE.md`,
  `MAINTAINERS.md`) still describe the actual maintenance model
- `SECURITY.md` still points reporters at the right private contact and
  verified support boundary
- `VERSIONING.md` and `RELEASING.md` still describe the actual release policy
- example files still load and return the documented shape
- `sbcl --script scripts/run-compile-check.lisp` passes when system wiring,
  package setup, or compile-time behavior moved
- `sbcl --script scripts/run-examples.lisp` passes when examples or docs moved
- `./scripts/run-implementation-smoke.sh` was rerun when portability-facing
  behavior or documented contract changed
- `./scripts/run-release-audit.sh` still passes from the checkout you modified
- `nix flake check` passes from the checkout you modified

## Reporting Bugs

When filing a bug report, include:

- the Lisp implementation and version
- the exact input that failed
- the observed result
- the expected result
