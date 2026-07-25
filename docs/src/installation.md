# Installation

The library system (`cl-parser-kit`) has **no runtime dependencies** — only
the test system (`cl-parser-kit-test`) pulls in `cl-weave` and `cl-prolog`.
Loading it into an application never drags in the test tooling.

## ASDF

Place the repository in your `local-projects` directory or add the checkout
to your ASDF source registry:

```lisp
(asdf:load-system :cl-parser-kit)
```

## Quicklisp

A checkout under `~/quicklisp/local-projects/` (or `~/common-lisp/`) is
discovered automatically:

```lisp
(ql:quickload "cl-parser-kit")
```

## Ultralisp

If you use [Ultralisp](https://ultralisp.org/), you can add this repository
as a source and pull the library the same way once it is indexed.

## Manual registry entry

If you keep personal projects in `~/common-lisp/`, one typical setup is:

```lisp
(push #p"/path/to/cl-parser-kit/" asdf:*central-registry*)
(asdf:load-system :cl-parser-kit)
```

## Pinning a release

The repository ships tagged releases starting with `v0.1.0`. For production
or team use, pin a tagged release (or a reviewed commit) and rerun the
verification entry point from that checkout. See [Versioning Policy](versioning.md)
for the release model.

## Test system

To load the repository test system explicitly:

```lisp
(asdf:load-system :cl-parser-kit-test)
```

The test system depends on `cl-weave` and `cl-prolog`, which are not
distributed through Quicklisp/Ultralisp; the Nix dev shell (`nix develop`)
and `nix flake check` resolve the pinned versions automatically. Outside
Nix, make matching checkouts of [`cl-weave`](https://github.com/nerima-lisp/cl-weave)
and [`cl-prolog`](https://github.com/nerima-lisp/cl-prolog) discoverable by
ASDF (see [`scripts/bootstrap.lisp`](https://github.com/nerima-lisp/cl-parser-kit/blob/main/scripts/bootstrap.lisp)
for the exact roots it expects). Running the library itself never requires
these.

## Verification

From a repository checkout on a supported system, run the full suite with:

```sh
nix flake check
```

This resolves the pinned `cl-weave` and `cl-prolog` test dependencies, runs
the full suite, generates the coverage report, and checks Lisp structure
with `paredit-cli`.

The flake exposes checks for `x86_64-linux`, `aarch64-linux`, and
`aarch64-darwin`. GitHub Actions runs the `x86_64-linux` baseline on
`ubuntu-latest`. CI optionally
pulls from the Cachix cache named by the `CACHIX_CACHE` repository variable,
and enables pushes only when the `CACHIX_AUTH_TOKEN` secret is also
configured; the checks still run without a configured cache.

To prove both ASD systems compile cleanly from the same raw checkout before
running behavior tests, run:

```sh
sbcl --script scripts/run-compile-check.lisp
```

To exercise the checked-in example files as user-facing workflows from the
same raw checkout, run:

```sh
sbcl --script scripts/run-examples.lisp
```

For a single release-readiness pass that runs the SBCL baseline, the
checked-in smoke path, and the repository-level documentation sanity
checks, run:

```sh
./scripts/run-release-audit.sh
```

To exercise the checked-in smoke path across known Common Lisp
implementations in the current environment, run:

```sh
./scripts/run-implementation-smoke.sh
```

This entry point loads both ASD files from the repository root before
calling the checked-in compile, test, and example verification scripts, so
it does not depend on prior ASDF source-registry setup. It also prints the
implementation name, each attempted command, and the reported runtime
version so portability failures are easier to audit.

`scripts/run-compile-check.lisp` gives maintainers a direct raw-checkout
proof that both the library and test systems still compile before runtime
behavior checks start.

`scripts/run-release-audit.sh` reuses both verification commands and fails
if the release-policy documents drift away from those entry points. The
example verification script gives maintainers a direct raw-checkout proof
that the sample files still load and produce the documented shapes outside
the test package.

If the checkout is already on your ASDF source registry, the equivalent
REPL entry point is:

```lisp
(asdf:test-system :cl-parser-kit)
```

The ASDF test system is `cl-parser-kit-test`, and the test package remains
`:cl-parser-kit/test`. If you are verifying from a raw checkout outside
`local-projects`, one reproducible SBCL command is:

```sh
sbcl --script scripts/run-tests.lisp
```

Continue with [Quick Start](quick-start.md) for the first runnable
tokenizer and parser snippets.
