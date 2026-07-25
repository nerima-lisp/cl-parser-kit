# Releasing

`cl-parser-kit` ships tagged releases starting with `v0.1.0`; the release gate
below applies to every release, not only the first.

## Release Gate

Before cutting a public release:

1. run `nix flake check` from a clean checkout to execute the full
   reproducible CI gate (compile check, tests, coverage, and lint); until the
   first public release is cut, this repeatable CI path remains the release
   readiness gate
2. run `./scripts/run-release-audit.sh` from the same checkout
3. rerun `sbcl --script scripts/run-compile-check.lisp` to prove both shipped
   ASD systems still compile from a raw checkout
4. rerun `nix develop --command sbcl --script scripts/run-tests.lisp` directly
   if you need a narrower baseline-only confirmation
5. run `sbcl --script scripts/run-examples.lisp` to prove the shipped example
   files still load and produce their documented shapes from a raw checkout
6. run `./scripts/run-implementation-smoke.sh` and record which
   implementations actually passed the compile, test, and example smoke path
   in that environment
7. confirm `README.md`, `API.md`, `EXAMPLES.md`, and `SUPPORT.md` match the
   observed behavior
8. confirm `CONTRIBUTING.md`, `CODE_OF_CONDUCT.md`, `SECURITY.md`,
   `GOVERNANCE.md`, and `MAINTAINERS.md` still describe the active
   contribution, incident, and ownership model
9. confirm `VERSIONING.md` and `ROADMAP.md` still describe the release policy
   and remaining public gaps honestly
10. confirm `docs/src/` still mirrors the documents above, and rerun
    `nix build .#docs` (or `mkdocs build --strict --config-file docs/mkdocs.yml`)
    to prove the published site still builds cleanly
11. summarize user-visible changes in `CHANGELOG.md`

## After a Release

Once a release is tagged:

- record every user-visible API or behavior change in `CHANGELOG.md`
- keep migration notes with any breaking change
- update `VERSIONING.md` if the release policy changes
