# Architecture

`cl-parser-kit` is organized as a small stack of layers. Each layer stays
intentionally narrow so the behavior remains easy to reason about and test.

## Layering

1. `spans` model source locations.
2. `tokens` attach lexical meaning and source metadata to text.
3. `tokenizer` turns raw text into token vectors.
4. `diagnostics` capture structured failures and fix-it data.
5. `combinators` provide small parser primitives over token vectors.
6. `pratt` builds expression parsers on top of token streams.
7. `parser` ties tokenization and parser execution together.
8. `ast` and `cst` provide tree-shaped outputs for downstream consumers.
9. `testing` supplies the local assertion helpers used by the suite.

## Dependency Direction

Dependencies flow downward. Higher layers may use lower layers, but lower
layers do not depend on higher ones.

- tokenizers depend on spans and tokens
- diagnostics depend on spans and tokens
- combinators depend on tokens and diagnostics
- parser entry points depend on tokenizer and combinator layers
- tree helpers depend on spans and tokens

This keeps the public surface modular without introducing multiple
packages for every concept.

## Invariants

- parse failures preserve the furthest known position when possible
- parser entry points consume the full token stream when `parse-all` is
  used
- token spans remain attached end-to-end so diagnostics and trees can
  share the same location data
- examples are expected to stay REPL-friendly and dependency-light

## Public Shape

The repository intentionally exports one package, `:cl-parser-kit`, so the
common path stays simple for consumers. See [API Reference](api-reference.md) for
the full exported surface grouped by concern.
