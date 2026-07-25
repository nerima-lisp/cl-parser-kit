# Support

`cl-parser-kit` currently defines support in terms of behavior that is verified
from this repository.

## Verified Baseline

The primary support baseline is:

```sh
nix flake check
```

That command resolves the pinned test dependencies, runs the full `cl-weave`
suite including the `cl-prolog/weave` contract checks, produces coverage
artifacts, and checks Lisp structure.

The checked flake systems are `x86_64-linux`, `aarch64-linux`, and `aarch64-darwin`. The
hosted CI baseline is Linux on `ubuntu-latest`. CI optionally pulls from the cache named by the
`CACHIX_CACHE` repository variable and pushes only when the
`CACHIX_AUTH_TOKEN` secret is configured. The project cache is not required to
run the checks.

For raw-checkout compile validation of both shipped ASD systems, this
repository also provides:

```sh
sbcl --script scripts/run-compile-check.lisp
```

For broader local portability checks, this repository also provides:

```sh
./scripts/run-implementation-smoke.sh
```

For user-facing workflow drift checks on the shipped sample files, this
repository also provides:

```sh
sbcl --script scripts/run-examples.lisp
```

The smoke entry point is useful for broader local portability checks. It runs
the raw-checkout compile check, full test suite, and example verification
before reporting the overall result.

If the checkout is already registered with ASDF, the same test suite is also
available through:

```lisp
(asdf:load-system :cl-parser-kit-test)
(asdf:test-system :cl-parser-kit)
```

## Support Boundary

- support claims should be backed by executable tests or documented examples
- the checked-in SBCL baseline is the primary regression target
- Linux and `aarch64-darwin` are the current Nix platform boundary; Linux
  (`ubuntu-latest`) is the hosted CI boundary
- `./scripts/run-implementation-smoke.sh` is available for broader portability
  checks when needed
- portability across other Common Lisp implementations remains a design goal,
  but it is not treated as a contract

## Release Readiness

This project ships tagged releases starting with `v0.1.0`.

Before treating a checkout as a release candidate:

- pin the exact commit you intend to consume
- run `./scripts/run-release-audit.sh` to execute the checked-in release
  readiness audit in one pass
- rerun `sbcl --script scripts/run-compile-check.lisp` if the checkout changed
  system definitions, package wiring, or compile-time behavior
- rerun `nix flake check` from that checkout
- rerun `sbcl --script scripts/run-examples.lisp` if the checkout will be
  consumed through the documented sample workflows
- ensure public docs and examples still match observed behavior
- ensure `docs/src/` (the published MkDocs site) still matches the root docs
  it restructures, and rebuilds cleanly with `nix build .#docs`
- ensure `SECURITY.md` still points reporters at the right support and contact
  path for that checkout
- ensure maintainer and governance docs still describe the active ownership
  model
- ensure `VERSIONING.md` and `RELEASING.md` still match the release policy you
  intend to communicate
