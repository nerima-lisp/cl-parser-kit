# Compatibility

This page states what `cl-parser-kit` promises about its public surface. The
org-wide rules it sits on top of — how versions are chosen, how deprecations
are staged, and how a release is cut — live in the nerima-lisp standards and
are not repeated here:

- [Versioning](https://github.com/nerima-lisp/.github/blob/main/CODING_STANDARD.md)
  — `.asd` `:version` is the single source of truth, and the major/minor/patch
  classification.
- [Release process](https://github.com/nerima-lisp/.github/blob/main/RELEASE_STANDARD.md)
  — the release gate, tagging, and CHANGELOG handling.

## Verified Baseline

The supported implementation is SBCL. `nix flake check` is the gate that
defines "supported": it runs the compile check, the test suite, the coverage
floor, and the documentation build. Other implementations are exercised on a
best-effort basis by `scripts/run-implementation-smoke.sh` and are not part of
the promise.

## What v1.0.0 Freezes

`v1.0.0` froze the public contract. Before it, a `0.x` minor bump could still
make breaking changes while the surface settled; from `v1.0.0` on, that is a
major release and nothing else.

What is frozen is every symbol exported from the `cl-parser-kit` package: its
name, its documented arguments, and its documented behavior. As of `v1.0.0`
that is 290 symbols, each documented in the [API Reference](api-reference.md)
and, since `v1.0.0`, from the running image as well — `t/api-surface-test.lisp`
enforces both, so an undocumented export fails CI rather than shipping.

## What Is Not Frozen

- Anything named with a leading `%`, and anything not exported: internal by
  construction, changeable in any release.
- The resource-limit defaults (`*maximum-parser-tokens*` and the rest). The
  specials themselves are public and rebindable; the specific numbers may be
  retuned in a minor release.
- The exact text of a diagnostic or parse-failure message. Its structure
  (`diagnostic-kind`, `diagnostic-span`, `parse-failure-expected`, and the
  other readers) is the contract; the prose is not. Parse structure rather than
  rendered strings.
- Performance characteristics, which may improve in any release.

## Removing a Public Symbol

Removal follows the org's two-stage deprecation: the symbol signals a
`style-warning` for at least one minor release, and is only removed in the
following major release. A removal that skips the warning stage is a bug in the
release, not a permitted shortcut.

## Consuming a Release

Pin a release tag rather than following the default branch:

```nix
inputs.cl-parser-kit = {
  url = "github:nerima-lisp/cl-parser-kit/v1.0.0";
  inputs.nixpkgs.follows = "nixpkgs";
};
```

If you need an unreleased fix, pin the exact commit and rerun `nix flake check`
from that checkout before treating it as a supported baseline.

See the [Changelog](changelog.md) for what changed in each release.
