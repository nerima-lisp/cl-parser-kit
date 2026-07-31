# Roadmap

`cl-parser-kit` is intentionally small. The next steps focus on keeping
the API practical, testable, and easy to audit.

## Near Term

- keep the repository-level `nix flake check` CI green so verification
  does not depend on manual local execution, and grow the enforced
  `coverage` gate alongside the parser and diagnostic surface
- keep adding targeted regression tests for portability-sensitive parser
  and diagnostic paths

## Mid Term

- write the GitHub Release description for every tagged release; it is the
  only canonical release history
- tighten the documentation around recommended parser composition and
  upgrade patterns
- keep the public surface small and intentional. `v1.0.0` froze it under
  semantic versioning (see the [versioning policy](compatibility.md)), so an
  addition is now a commitment to keep supporting it, not just a convenience

## Non-Goals

- compiler framework features
- editor integration
- CLI/runtime scaffolding
- large opinionated abstractions over the parser core

See [Governance](https://github.com/nerima-lisp/.github/blob/main/GOVERNANCE.md) for how changes against this roadmap are
evaluated, and the
[release notes](https://github.com/nerima-lisp/cl-parser-kit/releases) for
what has already shipped.
