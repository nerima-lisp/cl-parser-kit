# Maintainers

This repository is currently maintained as a small, direct-maintenance project.

## Current Maintainer Responsibilities

Maintainers are expected to:

- review changes for API and behavior regressions
- keep `README.md`, `API.md`, `EXAMPLES.md`, and `SUPPORT.md` aligned with the
  shipped behavior
- keep the published documentation site (`docs/src/`, built by
  `nix build .#docs` and deployed via `.github/workflows/docs.yml`) aligned
  with the root docs it restructures
- preserve the reproducible verification path through `nix flake check` and
  the focused `sbcl --script scripts/run-tests.lisp` entry point inside the
  Nix development shell
- keep issue triage, security routing, and conduct handling actionable

## Availability Expectations

There is no guaranteed response-time SLA. Urgent security-sensitive reports
should use the private reporting path in `SECURITY.md`.

## Updating This File

If additional maintainers take long-term responsibility for reviews and release
readiness, list them here together with their maintenance scope.
