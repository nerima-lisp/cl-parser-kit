# API Reference

This document groups the public `:cl-parser-kit` exports by concern and
shows the normal entry points for each layer.

For the exact symbol list, see [`src/package.lisp`][package-lisp].
For parser-construction guidance organized by grammar shape, see
[Parsing Patterns](parsing-patterns.md).

## Spans

Use spans when you need source positions that survive tokenization,
parsing, and diagnostics.

- type: `span`
- constructors: `make-span`
- accessors: `span-source`, `span-start`, `span-end`, `span-start-line`,
  `span-start-column`, `span-end-line`, `span-end-column`
- helpers: `span-length`, `span-empty-p`, `span-merge`,
  `span-contains-position-p` (is a character offset inside the half-open
  span), `span-text` (the source substring the span covers, defaulting to
  the span's own `span-source`)

## Tokens

Tokens carry lexical meaning and source metadata.

- type: `token`
- constructor: `make-token`
- accessors: `token-type`, `token-text`, `token-value`, `token-metadata`,
  `token-span`, `token-start`, `token-end`
- stream helper: `filter-tokens` returns a fresh vector of the tokens
  satisfying a predicate, for pruning a stream before parsing (e.g.
  dropping non-skipped `:comment` tokens)
- when tokens come from an external pipeline, `token-metadata` may carry
  plist-style `(:source <string>)`; diagnostics use it together with
  `token-start` / `token-end` to recover line/column data when
  `token-span` is absent

Typical usage starts with a tokenizer and ends with a vector of tokens.

- [`examples/tokenizer-example.lisp`][tokenizer-example]
- [`examples/token-stream-example.lisp`][token-stream-example]
- [`examples/external-token-diagnostic-example.lisp`][external-token-diagnostic-example]

## Tokenizers

Tokenizer helpers keep the lexical layer independent and REPL-friendly.

- tokenizer type: `tokenizer`
- constructor: `make-tokenizer`
- tokenizer accessors: `tokenizer-rules`
- rule type: `token-rule`
- rule constructor: `make-token-rule`
- rule accessors: `token-rule-type`, `token-rule-matcher`, `token-rule-skip-p`
- built-in rules: `make-literal-rule`, `make-keyword-rule`,
  `make-whitespace-rule`,
  `make-identifier-rule`, `make-number-rule`, `make-string-rule`,
  `make-predicate-rule`, `make-char-rule`, `make-line-comment-rule`,
  `make-block-comment-rule`, `make-nested-block-comment-rule`
- numeric and operator rules: `make-radix-integer-rule`, `make-float-rule`,
  `make-operator-rule`
- entry points: `tokenize`, `tokenize-string`

`make-char-rule` matches exactly one character described by a `character`,
a string/list of characters (any member), or a predicate function, with an
optional `:value-function`; it is the single-character counterpart to
`make-predicate-rule` (which scans a run) and suits punctuation and
one-character operators.

`make-literal-rule` performs raw prefix matching and is a good fit for
punctuation and operators. Use `make-keyword-rule` when a reserved word
should match only at identifier boundaries, such as `let`.

`make-identifier-rule` accepts `:start-predicate` and `:continue-predicate`
for languages whose identifiers allow sigils or suffix markers. When
reserved words should respect that same custom alphabet, pass the matching
`identifier-char-predicate` to `make-keyword-rule`. Pass `:case-sensitive nil`
to `make-keyword-rule` for case-insensitive keywords (`SELECT`, `select` and
`Select` all match `select`, while the token text and value stay the
canonical literal).

`make-radix-integer-rule` reads integers in base 2..36 introduced by an
optional `:prefix` (matched case-insensitively, e.g. `0x`, `0b`, `0o`),
producing the integer value via `parse-integer` -- never the reader.
`make-float-rule` reads a floating literal with an optional fractional
part and an optional decimal exponent (`3.14`, `1e10`, `2.5e-3`), yielding
a `double-float` (or the `:float-type` requested); it matches only lexemes
carrying a fractional part or exponent unless `:require-fractional nil`,
and leaves a leading sign to the parser unless `:allow-sign t`.
`make-operator-rule` matches the longest of a set of operator strings, so
`==` wins over `=` without hand-ordering separate literal rules.

`make-nested-block-comment-rule` matches block comments that nest (Rust
`/* .. /* .. */ .. */`, Common Lisp `#| .. |#`), unlike
`make-block-comment-rule` which stops at the first close. `make-string-rule`
accepts `:escapes`, an alist of `(escaped-char . replacement-char)`, to
decode escape sequences such as `\n` into their control characters; a
character absent from the alist is taken literally.

- `tokenize` rejects a source longer than `*maximum-tokenizer-source-length*`,
  stops once it has emitted `*maximum-tokenizer-tokens*` tokens, and rejects
  a tokenizer with more than `*maximum-tokenizer-rules*` rules, all by
  signaling `tokenizer-resource-limit-exceeded` (accessors
  `tokenizer-resource-limit-exceeded-kind`,
  `tokenizer-resource-limit-exceeded-value`,
  `tokenizer-resource-limit-exceeded-limit`) instead of exhausting memory;
  rebind tokenizer limits for intentionally large inputs
- tokenizer rule constructors that accept computed alternative sets,
  currently `make-operator-rule`, reject more than
  `*maximum-tokenizer-rule-alternatives*` alternatives with
  `tokenizer-resource-limit-exceeded`
- `make-number-rule` caps a single numeric lexeme at
  `*maximum-number-lexeme-length*` characters so an adversarially long
  digit run cannot force multi-megabyte bignum arithmetic; the scanner
  simply stops there and the remaining digits start a new number token,
  the same graceful split already used for a stray interior `.`
- `make-float-rule` clamps the exponent magnitude at
  `*maximum-number-exponent*` and saturates on overflow (a huge positive
  exponent yields the largest representable float, a huge negative one
  yields zero), so a literal like `1e999999` neither builds a gigantic
  bignum nor traps

## Diagnostics

Diagnostics and parse failures preserve structured error data.

- diagnostic type: `diagnostic`
- constructor: `make-diagnostic`
- accessors: `diagnostic-kind`, `diagnostic-message`, `diagnostic-span`,
  `diagnostic-notes`, `diagnostic-fixes`, `diagnostic-data`
- render helper: `diagnostic->string` renders the main message, opt
  source excerpt, notes, and fix-it hints in a readable multiline form;
  `diagnostics->string` renders a whole list of diagnostics (blank-line
  separated), for a recovery parse's collected diagnostics
- `diagnostic->string` caps rendered notes and fix-it hints at
  `*maximum-diagnostic-related-count*`, signaling
  `diagnostic-resource-limit-exceeded` for externally constructed
  diagnostics with adversarially large or improper related-item lists;
  accessors: `diagnostic-resource-limit-exceeded-kind`,
  `diagnostic-resource-limit-exceeded-value`,
  `diagnostic-resource-limit-exceeded-limit`
- convenience constructors: `warning-diagnostic`, `error-diagnostic`,
  `note-diagnostic`, `fix-it`, `make-fix-it`
- fix-it accessors: `fix-it-span`, `fix-it-replacement`
- fix-it application: `apply-fix-it` returns source with one fix-it's span
  region replaced by its replacement; `apply-fixes` applies a list of
  fix-its while preserving source-relative spans. Non-overlapping fixes are
  emitted in source order, overlapping fixes keep last-to-first sequential
  semantics, and same-position zero-width insertions preserve input order.
  `apply-fixes` consumes at most `*maximum-diagnostic-fix-count*` input
  entries; `nil` entries are skipped for application but still counted.
  Excess data signals `diagnostic-resource-limit-exceeded` with kind
  `:fix-count`; circular or improper fix lists are rejected through the
  same condition. This turns suggestion data into corrected text -- e.g.
  `(apply-fixes source (diagnostic-fixes diagnostic))`
- parse failure helpers: `make-parse-failure`, `parse-failure-position`,
  `parse-failure-expected`, `parse-failure-actual`,
  `parse-failure-committed-p`,
  `parse-failure-diagnostics`, `parse-failure->string`,
  `merge-parse-failures`
- `parse-failure-span` returns the source span of the failure's actual
  token (or `nil` at end of input), a convenience for rendering a caret or
  slicing the offending source region without building a full diagnostic
- `parse-failure->diagnostics` returns the structured `diagnostic` objects
  for a failure (its attached diagnostics, or a synthesized default) -- the
  structured counterpart of `parse-failure->string`, for rendering or
  aggregating failures with your own tooling
- `parse-failure->string` is the stable top-level renderer for parse
  failures; it joins attached diagnostics when present and synthesizes a
  readable fallback message when only `expected` / `actual` data is
  available
- parse failure expected-item and attached-diagnostic lists are capped by
  `*maximum-parse-failure-expected-count*` and
  `*maximum-parse-failure-diagnostic-count*` during merge and rendering;
  excess data, circular lists, and improper list tails signal
  `parse-failure-resource-limit-exceeded` (accessors
  `parse-failure-resource-limit-exceeded-kind`,
  `parse-failure-resource-limit-exceeded-value`,
  `parse-failure-resource-limit-exceeded-limit`)
- `diagnostics->string` skips `nil` entries while streaming and caps the
  number of input list entries with `*maximum-diagnostic-count*`; excess
  data signals `diagnostic-resource-limit-exceeded`; circular or improper
  diagnostic lists are rejected through the same condition
- `parse-all` trailing-token failures preserve the actual trailing token
  and attach a diagnostic from the token span, falling back to
  `token-start` / `token-end` offsets or the current parser position when
  full span data is unavailable
- if that fallback path also has plist-style `(:source <string>)` in
  `token-metadata`, the synthesized diagnostic span includes reconstructed
  line/column positions and a renderable source excerpt
- `diagnostic->string` caps the rendered source excerpt and caret
  padding/width at `*maximum-diagnostic-line-length*` characters (appending
  an ellipsis when truncated), so a single pathological line -- a minified
  file with no line breaks, or a span far into an adversarially long line
  -- can't make one diagnostic allocate output proportional to that line's
  full length

- [`examples/diagnostic-example.lisp`][diagnostic-example]
- [`examples/external-token-diagnostic-example.lisp`][external-token-diagnostic-example]

## Parser Primitives

The parser combinators operate on token vectors and return parse results
with a failure object on error.

- parser object: `parser`, `make-parser`, `parser-name`, `parser-fn`
- execution: `run-parser`, `parse-tokens`, `parse-all`, `parse-source`,
  `parse`
- matching: `literal`, `type-token`, `satisfies-token`
- token projection helpers: `literal-text`, `literal-value`,
  `type-token-text`, `type-token-value`
- composition: `seq`, `alt`, `many`, `many1`, `chainl1`, `chainr1`, `opt`,
  `label`, `sep-by`, `sep-by1`, `sep-end-by`, `sep-end-by1`, `preceded-by`,
  `terminated-by`, `between`, `delimited-sep-by`, `delimited-sep-by1`,
  `delimited-sep-end-by`, `delimited-sep-end-by1`, `operator-parser`,
  `lookahead`, `not-followed-by`
- functional combinators: `map-parser`, `bind-parser`, `return-parser`
- failure context: `context` (append an explanatory `note-diagnostic` to a
  failure while leaving its expected form, actual token, and commitment
  intact -- unlike `label`, which replaces the expected form)
- termination: `end-of-input`
- token navigation: `peek-token`, `next-token`, `eof-token-p`
- tree helpers reject malformed child lists with `tree-child-list-invalid`;
  use `tree-child-list-invalid-kind` to distinguish `:circular` from
  `:improper`
- `end-of-input` and `not-followed-by` attach diagnostics from the failing
  token span, falling back to `token-start` / `token-end` offsets when
  span data is unavailable, or to the current parser position as a last
  resort
- the same fallback path reconstructs multiline locations when the failing
  token carries `(:source <string>)` in `token-metadata`
- `alt` propagates the farthest branch failure; when multiple
  branches fail at that same farthest position, their expected forms are
  merged
- `lookahead` keeps the input position unchanged on success, while
  preserving the nested farthest failure position on error
- `opt`, `many`, and `sep-by` only recover from non-consuming failures;
  once a nested parser has committed input, the original failure is
  propagated
- `sep-end-by` and `sep-end-by1` mirror that recovery model, but treat a
  final separator plus a non-committing item failure as a successful
  trailing separator
- when that recovery carries diagnostics, observe them through
  `run-parser`; terminal entry points (`parse-tokens`, `parse-all`,
  `parse-source`, `parse-pratt-all`) only surface terminal parse failures
- `preceded-by` and `terminated-by` are thin value-projection wrappers over
  `bind-parser` / `map-parser`; they remove delimiter boilerplate without
  changing failure positions or commitment behavior
- `delimited-sep-by` and `delimited-sep-by1` are thin wrappers over
  `between` plus `sep-by` / `sep-by1`, so they inherit the same commitment
  and failure-position behavior
- `delimited-sep-end-by` and `delimited-sep-end-by1` are the corresponding
  wrappers over `between` plus `sep-end-by` / `sep-end-by1`
- `literal-text`, `literal-value`, `type-token-text`, and `type-token-value`
  are thin wrappers over `literal` / `type-token` plus `map-parser`, so
  they keep the underlying matcher failure behavior intact
- `operator-parser` is the same kind of thin wrapper over `map-parser`; it
  is intended for `chainl1` / `chainr1` operator parsers that should ignore
  the matched token and return a binary combiner function
- `(alt)` is defined and fails cleanly with `:alternative` instead of
  signaling
- large or deeply nested input is bounded by
  `*maximum-parser-recursion-depth*`: every combinator invokes its
  sub-parsers through `run-parser`, so once recursion (grammar nesting
  depth, or the length of a `chainr1` chain) exceeds it, parsing returns a
  `:maximum-recursion-depth` failure instead of exhausting the control
  stack; rebind it for intentionally large or deep grammars
- bounded repetition created with `times`, `times-between`, `at-most`, or
  `length-count` is capped by `*maximum-parser-repetition-count*`; hostile
  construction-time bounds signal before allocating unbounded parser
  state, and hostile length-prefixed counts fail the parse instead of
  looping; rebind it for intentionally large bounded repetitions
- public token-stream boundaries are capped by `*maximum-parser-tokens*`;
  `run-parser`, `parse-tokens`, `parse-all`, `parse-pratt`, and
  `parse-pratt-all` return a `:maximum-parser-tokens` parse failure before
  walking oversized proper token lists or vectors; `filter-tokens` signals
  an error at the same limit; circular or improper token lists are
  rejected before traversal; source-oriented entry points also inherit
  this check after tokenization

### Extended Combinators

The following combinators build on the primitives above and inherit their
commitment model unchanged (a recoverable failure backtracks; a committed
failure propagates).

- token matching:
    - `any-token` — match any single token, failing only at end of input
    - `token-type-in` — match a token whose type is one of the given
      types; the failure's expected form is the list of types
    - `token-text-in` — match a token whose `token-text` is one of the
      given lexemes (the text counterpart to `token-type-in`)
    - `token-type-not-in` / `token-text-not-in` — the complements: match a
      token whose type / text is *none* of the given set (e.g. any token
      except a closing bracket), with an expected form of `(:not ...)`
    - `token-value-in` / `token-value-not-in` — match (or reject) a token
      whose `token-value` is one of a set of decoded payloads, completing
      the type/text/value matching family
    - token set combinators cap their argument count at
      `*maximum-parser-repetition-count*`, so caller-constructed sets
      cannot create unbounded construction or membership work
    - `take-while` / `take-while1` — match a run of consecutive tokens
      satisfying a predicate, returning the list (`take-while1` requires
      at least one); Megaparsec's `takeWhileP` / `takeWhile1P`.
      `skip-while` skips such a run, discarding it
    - `satisfies-value` — match a token whose `token-value` satisfies a
      predicate, branching on a decoded payload rather than only the
      token type
- choice and value shaping:
    - `choice` — ordered choice over a *list* of parsers; the list form of
      `alt` (`(choice (list a b))` is `(alt a b)`), for alternatives
      computed at runtime
    - `sequence-of` — run a *list* of parsers in order, returning the list
      of values; the list form of `seq` (`(sequence-of (list a b))` is
      `(seq a b)`), the counterpart to `choice`
    - `option` — like `opt` but yields an explicit default value instead
      of `nil` when the parser does not match; a committed failure still
      propagates
    - `fail-parser` — always fails at the current position with a message
      (non-committed), turning a semantic guard into a parse error;
      accepts an `:expected` keyword to shape the failure's expected form
    - `as-value` — run a parser, discard its result, and yield a constant
      value, preserving the parser's consumption and commitment
    - `pure` — alias of `return-parser`, named for the Applicative
      operation
- backtracking control:
    - `attempt` — the inverse of `commit`: demote a parser's failure to a
      non-committed one so a surrounding `opt`/`many`/`sep-by` backtracks
      to the start position even after input was consumed
      (Parsec/Megaparsec's `try`). `alt` already backtracks
      unconditionally, so `attempt` matters for the commitment-respecting
      combinators, e.g.
      `(opt (attempt (seq (literal "else") (literal "if"))))`
- packrat memoization:
    - `memoize` — wrap a parser so that, inside a `with-parse-memoization`
      extent, its result at each position is computed once and reused on
      any later visit (turning an ambiguous / heavily backtracking
      grammar's exponential re-parsing into linear-time packrat parsing);
      a no-op outside the extent
    - `with-parse-memoization` — a macro establishing a fresh per-parse
      cache for the `memoize` parsers run inside it; wrap a top-level
      parse call
    - `left-recursion-detected` — signalled by `memoize`, instead of
      computing forever, if a memoized parser (directly or through other
      memoized parsers) calls itself again at the same position before its
      first call there has returned; `left-recursion-detected-parser` /
      `left-recursion-detected-position` read the offending parser and
      position. `memoize` is plain packrat memoization, not a
      left-recursion algorithm -- rewrite the rule (e.g. via `sep-by` /
      `chainl1` / `chainl`) or use the Pratt layer's
      `register-infix-left`, which does support left-recursive grammars
- debugging:
    - `trace-parser` — run a parser unchanged, printing one line per call
      to `*trace-output*` (or an explicit `:stream`) reporting its
      position and outcome; `:label` overrides the printed name,
      defaulting to the wrapped parser's own `parser-name` (megaparsec's
      `dbg`)
- permutation:
    - `permute` — parse a fixed set of parsers in any order, each exactly
      once, returning their values in the original argument order
      (attribute lists, keyword blocks); a committed sub-failure
      propagates, a recoverable one lets the other elements be tried, and
      a missing element fails; the parser count is capped by
      `*maximum-parser-repetition-count*`
- repetition:
    - `times` — parse a parser exactly N times, returning the N results; N
      is capped by `*maximum-parser-repetition-count*`
    - `skip-many` / `skip-many1` — parse zero-or-more / one-or-more and
      discard the results (yielding `t`) without allocating the
      intermediate list
    - `fold-many` / `fold-many1` — parse zero-or-more / one-or-more,
      folding each result into an accumulator
      (`(fold-many function initial parser)`) without building a list;
      `fold-many1` requires at least one match
    - `many-till` / `some-till` — parse repeatedly until an `end` parser
      matches, returning the collected results (`end`'s value is
      discarded and its input consumed); `some-till` requires at least
      one match before `end`
    - `length-count` — parse a count parser for a non-negative integer N,
      then parse an item parser exactly N times (length-prefixed
      sequences like `3 a b c`); N is capped by
      `*maximum-parser-repetition-count*`, and each item must consume
      input, so a hostile count cannot loop
    - `not-empty` — run a parser but fail if it succeeded without
      consuming input, to guarantee forward progress before repeating an
      optional-matching parser
    - `chain-postfix` — parse a base, then apply zero or more suffix
      parsers left-to-right, each yielding a function that transforms the
      accumulated value; the left-associative suffix chain for member
      access, calls, and indexing (`primary .field (args) [i] ...`)
    - `chainl` / `chainr` — like `chainl1` / `chainr1` but yield a
      supplied default (consuming nothing) when the operand does not
      match even once
    - `times-between` — parse greedily between a minimum and maximum
      number of times; fewer than the minimum is a failure, a further
      recoverable failure past the minimum simply stops
    - `at-least` / `at-most` — the open-ended variants: `at-least` parses
      a minimum or more (`(at-least 0 p)` is `many`, `(at-least 1 p)` is
      `many1`), `at-most` parses zero up to a cap
      (`(times-between 0 max p)`)
    - `end-by` / `end-by1` — like `sep-by` but every item must be
      *followed* by the separator (a required terminator, e.g. `item ;`
      runs), as opposed to `sep-end-by`'s optional trailing separator
    - `sep-by-between` — like `times-between` but for `sep-by`: parse a
      separated list at least a minimum and at most a maximum number of
      times (`(sep-by-between 0 max p s)` allows zero items, unlike
      `times-between`'s unseparated items); a separator failure past the
      minimum simply stops, an item failure after a matched separator is
      always committed
    - `sep-by-at-least` / `sep-by-at-most` — the open-ended variants:
      `sep-by-at-least` parses a minimum or more (`(sep-by-at-least 0 p
      s)` is `(sep-by p s)`, `(sep-by-at-least 1 p s)` is `(sep-by1 p
      s)`), `sep-by-at-most` parses zero up to a cap
      (`(sep-by-between 0 max p s)`)
    - `surrounded-by` — parse a body wrapped in a matching delimiter on
      both sides, `(surrounded-by d p)` is `(between d p d)`, for quotes
      or symmetric brackets
- error recovery (panic-mode resynchronisation):
    - `skip-until` — consume tokens until one satisfies a predicate
      (optionally `:including` the match), always succeeding with the
      list of skipped tokens
    - `recover` — run a parser and, on failure, run a recovery parser from
      the failure position, keeping the failure's diagnostics on the
      recovered success so a single parse can report several errors;
      drive the surrounding loop with `(many-till statement (end-of-input))`
      so it halts on end of input
- applicative shaping and source spans:
    - `seq-map` — run parsers in sequence (`seq`) and apply a function to
      their results as separate positional arguments, e.g.
      `(seq-map #'make-node a b c)`; parser-list construction is capped by
      `*maximum-parser-repetition-count*` and the final function-call
      arity is capped by `*maximum-parser-apply-arity*`
    - `pick` — run parsers in sequence and keep only the N-th (0-based)
      result, e.g. `(pick 1 open body close)` keeps `body`; parser-list
      construction is capped by `*maximum-parser-repetition-count*`
    - `pair` — run two parsers in sequence and return both results as a
      two-element list (nom's `pair`)
    - `separated-pair` — run `first separator second`, drop the separator,
      and return `(first-value second-value)` (nom's `separated_pair`)
    - `spanning` — run a parser and call `(function value span)` where
      `span` covers the tokens the parser consumed (or `nil` if none),
      for building located AST/CST nodes
    - `recognize` — run a parser, discard its value, and return the
      merged source span of the tokens it consumed (the span-only form of
      `spanning`)
- value constraints and cut:
    - `verify` — run a parser then require its value to satisfy a
      predicate, failing (non-committed, at the original position) when
      it does not; for semantic constraints a grammar cannot express
      structurally
    - `commit` — promote any failure of a parser to a committed one, a
      PEG-style cut so a surrounding `opt`/`many`/`sep-by` will not
      backtrack past it
    - `current-position` — succeed without consuming, yielding the
      current token index, to capture positions inside `parse-let*` /
      `seq-map`
- ergonomic macros:
    - `parse-let*` — sequential monadic binding (do-notation) that expands
      to nested `bind-parser` calls; each `(var parser-form)` binds `var`
      for the rest of the bindings and the body, whose value becomes the
      result (a `_` binding is ignored)
    - `parser-lazy` — defer building a parser expression until first use
      (memoized), enabling forward references and directly recursive
      grammars
    - `defparser` — define a function returning a `parser-lazy`-wrapped
      parser, so self- and mutually-recursive grammars can be written in
      natural order

Example:

```lisp
(let ((parser (cl-parser-kit:seq
               (cl-parser-kit:type-token :identifier)
               (cl-parser-kit:opt (cl-parser-kit:type-token :number))
               (cl-parser-kit:end-of-input))))
  parser)
```

```lisp
(cl-parser-kit:label
 (cl-parser-kit:type-token :identifier)
 :binding-name)
```

- [`examples/combinator-example.lisp`][combinator-example]
- [`examples/token-stream-example.lisp`][token-stream-example]
- [`examples/mini-language-parser.lisp`][mini-language-parser]

### Operator-Precedence Expression Builder

`make-expression-parser` builds an ordinary combinator parser from an
operator table — the combinator-layer counterpart to the token-keyed
Pratt parser below. Reach for it when the operands and operators are
themselves arbitrary parsers (rather than single tokens dispatched by
type).

- `(make-expression-parser term table)` — `term` parses an operand; `table`
  is a list of precedence levels, **highest precedence first**. Each level
  is a list of operator specifications, each a `(keyword op-parser)` pair
  where `op-parser` yields the combining function:
    - `(:prefix op)` / `(:postfix op)` — unary, `op` yields a one-argument
      function (both may repeat within a level)
    - `(:infix-left op)` / `(:infix-right op)` — binary, `op` yields a
      two-argument function; associativity is handled internally via
      `chainl1` / `chainr1`
    - `(:infix-non-assoc op)` — binary with no chaining (`a op b` but not
      `a op b op c`)
- a level may combine any prefix/postfix operators with at most one infix
  associativity; mixing left- and right-associative infix operators in one
  level is ambiguous and signals an error at build time
- operator tables and operator sets are bounded by
  `*maximum-parser-repetition-count*`, so computed or adversarially
  circular grammar tables fail at construction time instead of walking
  indefinitely
- built entirely on the verified primitives (`chainl1` / `chainr1`, `many`,
  `parse-let*`, `opt`, `alt`), so it inherits their commitment model

- [`examples/operator-precedence-example.lisp`][operator-precedence-example]

## Pratt Parsing

Pratt parsing is the best fit when you need expression precedence without
a large grammar framework.

- table: `pratt-table`, `make-pratt-table`
- entry types: `pratt-prefix-entry`, `pratt-infix-entry`, `pratt-postfix-entry`
- entry constructors: `make-pratt-prefix-entry`, `make-pratt-infix-entry`,
  `make-pratt-postfix-entry`
- accessors: `pratt-table-prefixes`, `pratt-table-infixes`,
  `pratt-table-postfixes`
- registration (low level, raw nud/led closures): `register-prefix-operator`,
  `register-infix-operator`, `register-postfix-operator`
- registration (high level, plain value builders — hide the nud/led
  protocol and binding-power arithmetic):
    - `register-atom` — a leaf token (`(builder token)`, consumes nothing
      further)
    - `register-prefix` — a unary prefix operator parsing one operand at a
      binding power (`(builder operand)`)
    - `register-infix-left` / `register-infix-right` — a binary operator
      of a given binding power, left- or right-associative
      (`(builder left right)`); the right-binding-power offset needed for
      associativity is handled internally
    - `register-postfix` — a unary postfix operator (`(builder operand)`)
    - `register-grouping` — a matched `open expr close` delimiter pair
      yielding the inner value, reporting a failure that expects the
      close key when it is missing
    - `register-ternary` — a right-associative ternary conditional
      `cond ? then : else` (`(builder cond then else)`), reporting a
      failure that expects the colon key when it is missing
    - `register-infix-non-assoc` — a non-associative binary operator:
      `a op b` is accepted but a chain `a op b op c` is a parse error
      (`:non-associative-operator`), as with many comparison operators
- parse entry points: `parse-pratt`, `parse-pratt-all`, `parse-pratt-source`
- `parse-pratt` and `parse-pratt-all` accept `:position` to start from a
  later token and `:min-binding-power` to parse only operators at or above
  a precedence floor
- `parse-pratt-source` passes the same `:position` and `:min-binding-power`
  keywords through after tokenization
- EOF and missing-prefix failures return `parse-failure` values instead of
  signaling internal errors
- large or deeply nested input is bounded by
  `*maximum-pratt-recursion-depth*`: once recursion (nesting depth, or the
  number of operators in a flat chain) exceeds it, parsing returns a
  `:maximum-recursion-depth` failure instead of exhausting the control
  stack; rebind it for intentionally large or deep grammars
- `parse-pratt-all` matches `parse-all`: it rejects trailing tokens while
  preserving the actual trailing token in the returned failure
- Pratt handlers use the same parser contract as other combinators:
  prefix/postfix/infix handlers return `(values t value next nil)` on
  success and may return `(values nil nil next failure)` for
  domain-specific failures

- [`examples/expression-parser.lisp`][expression-parser]
- [`examples/diagnostic-example.lisp`][diagnostic-example]

## Trees

AST and CST helpers keep tree-shaped output simple and explicit.

- AST: `ast-node`, `make-ast-node`, `ast-node-type`, `ast-node-value`,
  `ast-node-children`, `ast-node-span`, `ast-node-data`, `ast-node->sexp`
- CST: `cst-node`, `make-cst-node`, `cst-node-type`, `cst-node-value`,
  `cst-node-children`, `cst-node-span`, `cst-node-data`, `cst-node->sexp`
- construction (for both families): `token->ast-node` / `token->cst-node`
  build a leaf node from a token (its `value` from `:value-function`,
  `token-text` by default, and its `span` from the token); `ast-node-of` /
  `cst-node-of` run a parser and wrap the result into a node whose `span`
  covers the consumed tokens (the value goes in `value`, or in `children`
  with `:as-children t`)
- serialization (for both families): `ast-node->sexp` / `cst-node->sexp`
  render a node as a plist (optionally with `:include-span` /
  `:include-data`), and `sexp->ast-node` / `sexp->cst-node` reconstruct the
  node from that plist, rebuilding an embedded span — a round trip
  (`(ast-node-equal n (sexp->ast-node (ast-node->sexp n)))` is true)
- rendering (for both families): `ast-node->string` / `cst-node->string`
  render a human-readable indented tree (one node per line, `type` then
  `value`), for debugging and REPL inspection; `ast-node->dot` /
  `cst-node->dot` render a Graphviz DOT digraph (`:graph-name` names the
  graph) for visualizing a tree with `dot` — the machine-readable
  counterparts of the `->sexp` plist
- traversal (generated for both families): `ast-node-walk` / `cst-node-walk`
  visit every node for side effects (returning the root), in pre-order by
  default or post-order with `:order :post`; `ast-node-find` / `cst-node-find`
  return the first node satisfying a predicate (pre-order), or `nil`;
  `ast-node-map` / `cst-node-map` rebuild the tree bottom-up, replacing
  each node with the result of a function applied to a copy whose
  children have already been mapped (the original tree is left untouched)
- queries (also generated for both families): `ast-node-collect` /
  `cst-node-collect` return every node satisfying a predicate (pre-order
  list); `ast-node-count` / `cst-node-count` count nodes (matching an
  optional predicate, every node by default); `ast-node-depth` /
  `cst-node-depth` return the maximum depth (a leaf has depth 1)
- folding and comparison (for both families): `ast-node-reduce` /
  `cst-node-reduce` fold a function over every node from an initial
  accumulator (`(reduce-fn accumulator node)`, in `:order :pre` or
  `:post`); `ast-node-equal` / `cst-node-equal` test two trees for
  structural equality (equal type, value, and children), optionally
  including span (`:include-span t`) and data (`:include-data t`)
- resource limits: tree traversal, conversion, comparison, and rendering
  helpers enforce `*maximum-tree-depth*` and `*maximum-tree-nodes*`,
  signaling `tree-depth-limit-exceeded` with `tree-depth-limit-depth` /
  `tree-depth-limit-limit` for excessively deep inputs and
  `tree-node-limit-exceeded` with `tree-node-limit-count` /
  `tree-node-limit-limit` for excessively wide inputs; rebind them for
  intentionally large generated trees

## Testing

The repository test system runs on `cl-weave`, with `cl-prolog/weave`
providing declarative contract checks for parser behavior.

- primary entry point: `asdf:test-system "cl-parser-kit-test"`
- raw checkout script: `sbcl --script scripts/run-tests.lisp`
- coverage script: `sbcl --script scripts/run-coverage.lisp`

`cl-parser-kit-test.asd` executes the full suite through `cl-weave:run-all`
with the `:spec` reporter and treats an empty suite as a failure.

## Recommended Entry Points

If you are new to the library, start here:

1. tokenize source with `make-tokenizer` and `tokenize-string`
2. build token parsers with `seq`, `alt`, `many`, and `opt`.
   For comma-separated or bracketed forms, start with `sep-by`, `sep-by1`,
   `sep-end-by`, `sep-end-by1`, `preceded-by`, `terminated-by`, `between`,
   `delimited-sep-by{,1}`, and `delimited-sep-end-by{,1}` instead of
   hand-rolling the control flow.
   For left- or right-associative operator chains outside Pratt parsing,
   start with `chainl1` or `chainr1`; pair them with `operator-parser` when
   the operator token itself does not carry semantic payload. `chainr1`
   recurses in step with the right-associative nesting depth; like the
   rest of the combinator engine, that depth is bounded by
   `*maximum-parser-recursion-depth*`, so adversarially deep input fails
   gracefully instead of exhausting the control stack. Bounded repetition
   is also capped by `*maximum-parser-repetition-count*`, so hostile
   construction-time bounds fail before allocating unbounded parser state
   and hostile length-prefixed counts fail instead of looping.
3. use `parse-tokens`, `parse-all`, or `parse-source` for end-to-end
   parsing
4. move to `parse-pratt`, `parse-pratt-all`, or `parse-pratt-source` when
   expression precedence matters
5. use `make-ast-node` or `make-cst-node` to shape downstream data
6. use `ast-node->sexp` or `cst-node->sexp` when you need stable,
   printable tree output for tests, examples, or REPL inspection
7. read [Parsing Patterns](parsing-patterns.md) when you need to choose
   between seq helpers, projected token payloads, operator-chain helpers,
   and Pratt parsing

## Quick Start Surface

`README.md` mirrors this exact bullet list in its public API section so
the onboarding surface stays stable across both entry-point documents.

- `make-span`
- `make-token`
- `make-tokenizer`
- `tokenize`
- `tokenize-string`
- `make-diagnostic`
- `parse-tokens`
- `parse-all`
- `parse-source`
- `parse-pratt`
- `parse-pratt-all`
- `parse-pratt-source`
- `seq`
- `alt`
- `many`
- `many1`
- `opt`
- `delimited-sep-by`
- `delimited-sep-by1`
- `delimited-sep-end-by`
- `delimited-sep-end-by1`
- `make-ast-node`
- `make-cst-node`
- `ast-node->sexp`
- `cst-node->sexp`

## Parser Entry Points

End-to-end entry points intentionally stay small so combinator logic,
Pratt logic, and tokenizer construction remain separable:

- `run-parser` executes a parser at a position and returns four values:
  `ok`, `value`, `next-position`, and either diagnostics (success) or a
  parse failure (failure). Recursive parser execution is capped by
  `*maximum-parser-recursion-depth*`; token stream length is capped by
  `*maximum-parser-tokens*`
- `parse-tokens` accepts a parser and a token stream, and does not require
  the parse to consume every token; token stream length is capped by
  `*maximum-parser-tokens*`
- `parse-all` accepts a parser and a token vector, and enforces full
  consumption; token stream length is capped by `*maximum-parser-tokens*`
- `parse-source` tokenizes a source string with a tokenizer, then
  delegates to `parse-all`
- `parse-pratt` parses a precedence expression from a token vector; token
  stream length is capped by `*maximum-parser-tokens*`
- `parse-pratt-all` parses a precedence expression and enforces full
  consumption; token stream length is capped by `*maximum-parser-tokens*`
- `parse-pratt-source` tokenizes a source string, then delegates to
  `parse-pratt-all`

[package-lisp]: https://github.com/nerima-lisp/cl-parser-kit/blob/main/src/package.lisp
[tokenizer-example]: https://github.com/nerima-lisp/cl-parser-kit/blob/main/examples/tokenizer-example.lisp
[token-stream-example]: https://github.com/nerima-lisp/cl-parser-kit/blob/main/examples/token-stream-example.lisp
[external-token-diagnostic-example]: https://github.com/nerima-lisp/cl-parser-kit/blob/main/examples/external-token-diagnostic-example.lisp
[diagnostic-example]: https://github.com/nerima-lisp/cl-parser-kit/blob/main/examples/diagnostic-example.lisp
[combinator-example]: https://github.com/nerima-lisp/cl-parser-kit/blob/main/examples/combinator-example.lisp
[mini-language-parser]: https://github.com/nerima-lisp/cl-parser-kit/blob/main/examples/mini-language-parser.lisp
[operator-precedence-example]: https://github.com/nerima-lisp/cl-parser-kit/blob/main/examples/operator-precedence-example.lisp
[expression-parser]: https://github.com/nerima-lisp/cl-parser-kit/blob/main/examples/expression-parser.lisp
