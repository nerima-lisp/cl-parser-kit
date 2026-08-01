# Core Concepts

This page introduces the vocabulary behind the [Quick Start](../getting-started.md)
snippets. For the layer model and dependency direction between these
concepts, see [Architecture](../reference/architecture.md). For the exact exported
symbols behind each concept, see [API Reference](../reference/api.md).

## Token

A token represents a lexical unit and carries:

- type
- text
- value
- span
- metadata

## Span

Spans track source locations using:

- offset
- line
- column
- start and end boundaries

## Tokenizer

The tokenizer is rule-based and supports:

- literal matching
- keyword matching on identifier boundaries
- identifier and number rules
- string rules
- predicate rules
- line and block comment rules
- whitespace skipping
- end-of-input handling

## Parser

The parser layer provides:

- sequencing
- alt / alternation
- repetition
- opt parsing
- lookahead
- failure propagation

## Pratt Parser

The Pratt parser layer is intended for expression grammars with:

- prefix operators
- infix operators
- postfix operators
- precedence and associativity

## Diagnostics

Structured diagnostics carry:

- kind
- message
- span
- expected forms
- actual token or lexeme
- notes and fix-its
- multiline rendering with source excerpts when `span-source` is available
- trailing-token failures from `parse-all` / `parse-source` keep the actual
  token and build diagnostics from token spans, falling back to token
  offsets or parser position when full span data is unavailable
- when external token streams omit `token-span` but provide `token-start` /
  `token-end` plus `(:source <string>)` in `token-metadata`, diagnostics
  reconstruct line/column locations and source excerpts from that original
  source text

## AST / CST Helpers

Tree helpers are provided for both abstract and concrete syntax trees:

- node type
- children
- value
- span
- metadata
- stable `*-node->sexp` conversion for tests and REPL inspection

## Next

- [Parsing Patterns](parsing-patterns.md) — how to choose the smallest
  stable layer for a grammar, and how these layers compose.
- [API Reference](../reference/api.md) — the exported surface for each concept above,
  grouped by concern.
