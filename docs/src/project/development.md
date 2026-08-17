# Development

Everything below assumes a checkout and a working Nix with flakes enabled.

## The Gate

```sh
nix flake check --print-build-logs
```

This is the whole gate, and it is exactly what CI runs. It realises five
checks in parallel:

| Check | What it proves |
|---|---|
| `default` | The test suite passes (`run-tests.lisp` under cl-weave). |
| `package` | `src/` still compiles from a raw checkout, not just interpreted. |
| `coverage` | Coverage stays at or above 90% expression / 80% branch. |
| `paredit-lint` | The Lisp sources pass `paredit lint`. |
| `formatting` | Every Nix file is nixfmt-clean. |
| `docs` | `mkdocs build --strict` succeeds — no broken links, no unlisted pages. |

Run one on its own while iterating:

```sh
nix build .#checks.x86_64-linux.coverage --print-build-logs
```

## Day-to-day

```sh
nix develop          # SBCL, perl, and paredit-cli, with the dependency roots exported
nix run .#test       # the test suite, against the working tree
nix fmt              # format Nix sources (treefmt / nixfmt)
nix build .#docs     # render the documentation site
```

Tests live in `t/` and run under
[cl-weave](https://github.com/nerima-lisp/cl-weave), the org's test framework.
`t/` mirrors `src/`: a source file `src/combinators-repeat.lisp` is tested by
`t/combinators-repeat-test.lisp`.

## Running Without Nix

`scripts/bootstrap.lisp` loads the project and its two test dependencies by
reading the `.asd` forms directly, so the suite runs from a raw checkout
without an ASDF source registry. Point it at the dependencies either by placing
`cl-weave` and `cl-prolog-kit` next to this checkout, or by setting:

```sh
export CL_PARSER_KIT_CL_WEAVE_ROOT=/path/to/cl-weave
export CL_PARSER_KIT_CL_PROLOG_KIT_ROOT=/path/to/cl-prolog-kit

sbcl --script run-tests.lisp
```

The other entry points follow the same convention:

| Script | Purpose |
|---|---|
| `run-tests.lisp` | The full suite. The root-level entry point CI uses. |
| `scripts/run-compile-check.lisp` | Compile every component; catches warnings the interpreter hides. |
| `scripts/run-coverage.lisp` | Coverage run, writing `cl-parser-kit-coverage-report/`. |
| `scripts/run-examples.lisp` | Loads every file under `examples/` and checks the documented shapes. |
| `scripts/run-benchmarks.lisp` | Timing harness; not part of the gate. |
| `scripts/run-implementation-smoke.sh` | Best-effort compile/test/example pass on ccl, ecl, clisp, abcl. |

## Property-based Tests

Parsers, serializers and round-trips are required to carry property-based
coverage. Those tests use cl-weave's `it-property` with its `gen-*` generators
— see `t/parser-properties-test.lisp`, `t/fuzz-test.lisp`, and the round-trip
properties in `t/trees-traversal-test.lisp`. Keep `*property-seed*` fixed;
never call `(make-random-state t)` in a test.

## Releasing

The release process is org-wide and lives in
[RELEASE_STANDARD.md](https://github.com/nerima-lisp/.github/blob/main/RELEASE_STANDARD.md).
The short version: `.asd` `:version` is the only place a version is edited,
`.github/workflows/release.yml` refuses a tag that disagrees with it, and the
workflow then opens an empty DRAFT release for the maintainer to write the
notes into. That description is the only canonical release history.

## Contributing

See the org-wide
[contributing guide](https://github.com/nerima-lisp/.github/blob/main/CONTRIBUTING.md)
and the
[package standard](https://github.com/nerima-lisp/.github/blob/main/PACKAGE_STANDARD.md).
