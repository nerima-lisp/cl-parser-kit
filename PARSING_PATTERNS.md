# Parsing Patterns Guide

This guide documents the recommended parser construction patterns for
`cl-parser-kit`.

For the exported surface grouped by symbol, see [`API.md`](./API.md).
For runnable snippets, see [`EXAMPLES.md`](./EXAMPLES.md).

## Start With The Smallest Stable Layer

Choose the first layer that matches the grammar shape you actually have:

1. Start with `make-tokenizer` and `tokenize-string` when the source format is
   still changing and you need to inspect token boundaries first.
2. Start with `seq`, `alt`, `opt`, and `end-of-input` when the grammar is a
   short token sequence with one or two branch points.
3. Start with `sep-by`, `sep-end-by`, `preceded-by`, `terminated-by`, and
   `between` when delimiter control flow is more prominent than the item
   parser itself.
4. Start with `chainl1` or `chainr1` when the grammar is only a repeated
   operand/operator pair with fixed associativity.
5. Move to Pratt parsing only when prefix, infix, or postfix precedence
   layering becomes the dominant concern.

The library stays easier to audit when the parser shape mirrors the grammar
directly instead of hiding control flow in custom loops.

## Prefer Sequence Helpers Over Manual Delimiter Loops

If a token exists only to open, close, separate, or terminate another parser,
use the dedicated helper instead of spelling out the control flow manually.

- Use `preceded-by` when the prefix is syntax-only and callers only want the
  inner result.
- Use `terminated-by` when the suffix is syntax-only and the main parser must
  stay committed once it has consumed input.
- Use `between` when open/body/close delimiters should be treated as one unit.
- Use `delimited-sep-by` or `delimited-sep-by1` for bracketed lists that must
  reject a trailing separator.
- Use `delimited-sep-end-by` or `delimited-sep-end-by1` when the grammar
  should accept a final separator before the closing delimiter.

These helpers are thin wrappers around the same primitive combinators. They
remove boilerplate, but they do not weaken the underlying commitment or error
position rules.

## Choose The Right List Contract

The sequence helpers differ in one important behavioral boundary: what happens
after a separator has already matched.

- `sep-by` / `sep-by1` stop cleanly before a separator that never matched, but
  once a separator does match, the following item becomes mandatory.
- `sep-end-by` / `sep-end-by1` keep that same committed-item rule, yet recover
  from one final separator when the next item parser fails without consuming
  input.
- `delimited-sep-by*` and `delimited-sep-end-by*` inherit those same rules and
  add explicit open/close delimiter handling around the list body.

Use the strict `sep-by` family when a trailing separator would be a grammar
bug. Use the `sep-end-by` family when a trailing separator is part of the
language contract.

Reach for the bounded variants when the grammar itself caps repetition
instead of the item parser failing naturally:

- `sep-by-between` when the grammar states both a minimum and a maximum item
  count.
- `sep-by-at-least` for an open-ended minimum with no cap.
- `sep-by-at-most` for a capped count with no required minimum.

All three still enforce the same committed-item rule as `sep-by`: once a
separator matches, the following item is mandatory.

## Project Payloads Early When Syntax Tokens Are Noise

If downstream code should not care about raw token objects, project token text
or values at the parser boundary.

- Use `type-token-text` or `type-token-value` when the token type is the real
  match contract and callers only need the payload.
- Use `literal-text` or `literal-value` when a literal token carries
  meaningful semantic data in `token-value`.
- Use `operator-parser` with `chainl1` / `chainr1` when the operator token is
  syntax-only and you want the parser to return a combiner function directly.

This keeps parse results closer to the data model and removes repetitive
`token-text` / `token-value` extraction from later phases.

## Treat Committed Failures As A Public Contract

Combinator recovery in `cl-parser-kit` is intentionally conservative.

- `alt` returns the farthest branch failure.
- Same-position branch failures merge expected forms instead of discarding one
  branch's context.
- `opt`, `many`, and `sep-by` only recover from non-consuming failures.
- Once a nested parser has committed input, the failure stays hard and is
  propagated to the caller.
- `preceded-by`, `terminated-by`, `between`, and the `delimited-*` wrappers
  preserve those same commitment rules instead of inventing new ones.

Design grammars around that behavior. If a branch must remain backtrackable,
keep the speculative portion non-consuming until the parser reaches a true
decision point.

## Shape User-Facing Errors Deliberately

When a grammar term matters more than a raw token type, name that term in the
parser itself.

- Use `label` to replace low-level token expectations with a
  grammar-facing name such as `:binding-name`.
- Use `parse-failure->string` as the top-level renderer for user-facing parse
  errors.
- Use `run-parser` when you need to inspect recoverable diagnostics that do not
  surface through `parse-source`, `parse-all`, or `parse-tokens`.

This keeps error behavior stable for both machine-readable tests and human
readers.

## Know When To Escalate To Pratt Parsing

Stay with plain combinators when the grammar can be expressed as:

- delimited lists
- optional suffixes
- left- or right-associative chains with one precedence level
- a small fixed set of keyword-led forms

Move to Pratt parsing when you need:

- multiple precedence levels
- mixed prefix, infix, and postfix operators
- expression grammars where precedence handling would otherwise dominate the
  combinator code

Pratt parsing is not a general replacement for the rest of the library. It is
the focused tool for expression-heavy regions of a grammar.

## Memoize Only The Rules That Need It

`memoize` is plain packrat memoization: it trades memory for skipping repeat
parses of the same rule at the same position, which only pays off for rules a
grammar revisits through backtracking (e.g. shared sub-expressions reachable
from more than one alternative). Wrap the whole parse in
`with-parse-memoization` once at the entry point; memoizing a rule that is
never reparsed just adds bookkeeping overhead for no benefit.

`memoize` does not implement left recursion. A memoized rule that recurses
into itself at the same position without consuming input signals
`left-recursion-detected` (read the offending parser and position via
`left-recursion-detected-parser` / `left-recursion-detected-position`) instead
of looping forever. Treat that condition as a grammar bug to fix, not an error
to catch: rewrite the recursive rule iteratively (the same technique
`chainl1` uses to express left-associative operator chains without recursion).

## Debug A Parser Before Reaching For Print Statements

Wrap any parser in `trace-parser` to log its outcome (success/failure,
position, consumed input) to `*trace-output*` on every call, without changing
the parser's own behavior. It is a pass-through combinator (megaparsec's
`dbg`), so it composes with any other combinator. Wrap the one sub-parser
under suspicion, not the whole grammar -- every traced call pays for the
format call, so tracing should stay as narrow as the investigation allows.
Prefer it over ad hoc `format` calls inside a callback: it stays outside the
parser's own logic and is easy to remove by deleting the wrapper, not by
hunting down inserted print statements.

## Upgrade Existing Parsers By Replacing Boilerplate First

When modernizing an older parser built on raw `seq` and `bind-parser` chains,
upgrade in this order:

1. Replace hand-written delimiter plumbing with `preceded-by`,
   `terminated-by`, `between`, or the `delimited-*` helpers.
2. Replace repeated operand/operator loops with `chainl1`, `chainr1`, and
   `operator-parser`.
3. Replace repeated token unwrapping with the projection helpers.
4. Move expression islands to Pratt parsing only if precedence management is
   still the main source of complexity.

That path preserves behavior while making commitment boundaries easier to read
from the parser definition itself.
