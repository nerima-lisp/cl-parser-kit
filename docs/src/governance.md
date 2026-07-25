# Governance

`cl-parser-kit` uses a maintainer-led model.

## Decision Making

- routine fixes and doc updates can be merged by a maintainer after review
- API changes should explain the user-facing impact in code, tests, and
  docs
- behavioral claims are expected to be backed by executable tests or
  runnable examples
- when tradeoffs are unclear, choose the smaller public surface until
  stronger evidence justifies expansion

## Change Criteria

Maintainers evaluate changes against the repository's explicit goals:

- keep the public surface small and intentional
- preserve runnable examples and regression coverage
- avoid hidden dependencies or framework drift
- document support and release claims conservatively

## Escalation Path

If a technical disagreement cannot be resolved in a review thread:

1. restate the disputed behavior with a concrete example
2. identify the relevant API, test, or documentation contract
3. ask maintainers for a decision in the pull request or issue

## Project Status

This repository does not currently use formal voting, committees, or a
release manager rotation. If the maintainer set grows, this document
should be updated before claiming a broader governance model. See
[Maintainers](maintainers.md) for who currently holds that
responsibility.
