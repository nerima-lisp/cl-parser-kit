# Versioning

`cl-parser-kit` publishes tagged releases starting with `v0.1.0`, using
semantic versioning.

## Consumption Model

- consume a tagged release, or pin the exact commit on `main` if you need
  unreleased fixes
- rerun `nix flake check` from that checkout before treating it as a
  supported baseline

## Release Model

- patch releases fix incorrect behavior without reshaping the documented
  public contract
- minor releases may add new APIs, examples, and docs
- major releases may remove or redefine public behavior with explicit
  migration notes

## Stability From v1.0.0

`v1.0.0` freezes the public contract. Before it, a `0.x` minor bump could still
make breaking changes while the surface settled; from `v1.0.0` on, that is a
major release and nothing else.

What is frozen is every symbol exported from the `cl-parser-kit` package: its
name, its documented arguments, and its documented behavior. As of `v1.0.0`
that is 290 symbols, each documented in `API.md` and, since `v1.0.0`, from the
running image as well — `t/api-surface-test.lisp` enforces both, so an
undocumented export fails CI rather than shipping.

What is not frozen:

- anything named with a leading `%`, and anything not exported: internal by
  construction, changeable in any release
- the resource-limit defaults (`*maximum-parser-tokens*` and the rest). The
  specials themselves are public and rebindable; the specific numbers may be
  retuned in a minor release
- the exact text of a diagnostic or parse-failure message. Its structure
  (`diagnostic-kind`, `diagnostic-span`, `parse-failure-expected`, and the
  other readers) is the contract; the prose is not, so parse structure rather
  than rendered strings
- performance characteristics, which may improve in any release

See `CHANGELOG.md` for what changed in each release.
