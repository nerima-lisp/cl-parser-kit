# Versioning Policy

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

`0.x` releases may still make breaking changes in a minor bump while the
public contract stabilizes; see the
[release notes](https://github.com/nerima-lisp/cl-parser-kit/releases)
for what changed in each release.
