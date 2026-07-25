# cl-parser-kit

[![CI](https://github.com/nerima-lisp/cl-parser-kit/actions/workflows/ci.yml/badge.svg?branch=main)](https://github.com/nerima-lisp/cl-parser-kit/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![Documentation](https://img.shields.io/badge/docs-MkDocs%20Material-283593)](https://nerima-lisp.github.io/cl-parser-kit/)

`cl-parser-kit` is a small, practical parser toolkit for Common Lisp.

Full documentation, including the API reference, parsing patterns guide,
example map, and every governance and policy document, is published at
<https://nerima-lisp.github.io/cl-parser-kit/>. The source for that site
lives in [docs/src/](docs/src/index.md).

It focuses on the pieces that recur in real text-language parsers:

- tokenization from raw source text
- source spans and line/column tracking
- parser combinators for small grammars
- Pratt parsing for expression-heavy languages
- structured diagnostics
- AST and CST helpers for downstream tooling

The library is intentionally compact. It is not a compiler framework, editor
integration layer, CLI toolkit, terminal/TTY layer, Prolog engine, or dataflow
runtime.

## Status

This repository is in active development, but the core API is already usable.
The current codebase includes:

- a rule-based tokenizer
- span, token, and diagnostic types
- parser combinators and a Pratt parser
- AST/CST constructors
- AST/CST inspection helpers
- a test system wired into `asdf:test-system`
- runnable examples under `examples/`

The implementation is designed to stay small enough that the behavior is easy
to audit from the tests.

See [`ARCHITECTURE.md`](./ARCHITECTURE.md) for the layer model and dependency
direction.

See [`API.md`](./API.md) for the grouped public surface and common entry
points.

See [`PARSING_PATTERNS.md`](./PARSING_PATTERNS.md) for the recommended parser
composition, failure-shaping, and upgrade patterns.

See [`EXAMPLES.md`](./EXAMPLES.md) for a map of the sample files and the
recommended reading order.

See [`ROADMAP.md`](./ROADMAP.md) for the remaining public-facing work and
[`CHANGELOG.md`](./CHANGELOG.md) for release-oriented notes.

See [`SUPPORT.md`](./SUPPORT.md) for the currently verified support boundary
and release-readiness expectations.

See [`SECURITY.md`](./SECURITY.md) for private reporting and the current
security scope boundary.

See [`CODE_OF_CONDUCT.md`](./CODE_OF_CONDUCT.md),
[`CONTRIBUTING.md`](./CONTRIBUTING.md),
[`GOVERNANCE.md`](./GOVERNANCE.md), and
[`MAINTAINERS.md`](./MAINTAINERS.md) for the repository's collaboration and
ownership model.

See [`VERSIONING.md`](./VERSIONING.md) and [`RELEASING.md`](./RELEASING.md)
for commit pinning, future release policy, and the current release gate.

The lexical helpers are intentionally customizable. If your language allows
identifier sigils or suffix markers such as `$value` or `tail?`, use
`make-identifier-rule` with custom `:start-predicate` /
`:continue-predicate`, and pass the same boundary logic into
`make-keyword-rule` so reserved words do not match inside those identifiers.

## Installation

The library system (`cl-parser-kit`) has **no runtime dependencies** — only the
test system (`cl-parser-kit-test`) pulls in `cl-weave` and `cl-prolog`. Loading
it into an application never drags in the test tooling.

With ASDF, place the repository in your `local-projects` directory or add the
checkout to your ASDF source registry.

```lisp
(asdf:load-system :cl-parser-kit)
```

With Quicklisp, a checkout under `~/quicklisp/local-projects/` (or
`~/common-lisp/`) is discovered automatically:

```lisp
(ql:quickload "cl-parser-kit")
```

If you use [Ultralisp](https://ultralisp.org/), you can add this repository as a
source and pull the library the same way once it is indexed.

To load the repository test system explicitly:

```lisp
(asdf:load-system :cl-parser-kit-test)
```

The test system depends on `cl-weave` and `cl-prolog`, which are not distributed
through Quicklisp/Ultralisp; the Nix dev shell (`nix develop`) and `nix flake
check` resolve the pinned versions automatically. Outside Nix, make matching
checkouts of [`cl-weave`](https://github.com/nerima-lisp/cl-weave) and
[`cl-prolog`](https://github.com/nerima-lisp/cl-prolog) discoverable by ASDF (see
`scripts/bootstrap.lisp` for the exact roots it expects). Running the library
itself never requires these.

If you keep personal projects in `~/common-lisp/`, one typical setup is:

```lisp
(push #p"/path/to/cl-parser-kit/" asdf:*central-registry*)
(asdf:load-system :cl-parser-kit)
```

The repository ships tagged releases starting with `v0.1.0`. For production or
team use, pin a tagged release (or a reviewed commit) and rerun the
verification entry point from that checkout.

## Verification

From a repository checkout on a supported system, run the full suite with:

```sh
nix flake check
```

This resolves the pinned `cl-weave` and `cl-prolog` test dependencies, runs
the full suite, generates the coverage report, and checks Lisp structure with
`paredit-cli`.

The flake exposes checks for `x86_64-linux`, `aarch64-linux`, and
`aarch64-darwin`. GitHub Actions runs the `x86_64-linux` baseline on
`ubuntu-latest`. CI optionally
pulls from the Cachix cache named by the `CACHIX_CACHE` repository variable,
and enables pushes only when the `CACHIX_AUTH_TOKEN` secret is also
configured; the checks still run without a configured cache.

To prove both ASD systems compile cleanly from the same raw checkout before
running behavior tests, run:

```sh
sbcl --script scripts/run-compile-check.lisp
```

To exercise the checked-in example files as user-facing workflows from the same
raw checkout, run:

```sh
sbcl --script scripts/run-examples.lisp
```

For a single release-readiness pass that runs the SBCL baseline, the
checked-in smoke path, and the repository-level documentation sanity checks,
run:

```sh
./scripts/run-release-audit.sh
```

To exercise the checked-in smoke path across known Common Lisp
implementations in the current environment, run:

```sh
./scripts/run-implementation-smoke.sh
```

This entry point loads both ASD files from the repository root before calling
the checked-in compile, test, and example verification scripts, so it does not
depend on prior ASDF source-registry setup. It also prints the implementation
name, each attempted command, and the reported runtime version so portability
failures are easier to audit.

`scripts/run-compile-check.lisp` gives maintainers a direct raw-checkout proof
that both the library and test systems still compile before runtime behavior
checks start.

`scripts/run-release-audit.sh` reuses both verification commands and fails if
the release-policy documents drift away from those entry points. The example
verification script gives maintainers a direct raw-checkout proof that the
sample files still load and produce the documented shapes outside the test
package.

If the checkout is already on your ASDF source registry, the equivalent REPL
entry point is:

```lisp
(asdf:test-system :cl-parser-kit)
```

## Quick Start

```lisp
(asdf:load-system :cl-parser-kit)

(let* ((tokenizer (cl-parser-kit:make-tokenizer
                   :rules (list (cl-parser-kit:make-whitespace-rule :skip-p t)
                                (cl-parser-kit:make-literal-rule :plus "+")
                                (cl-parser-kit:make-number-rule)
                                (cl-parser-kit:make-identifier-rule))))
       (tokens (cl-parser-kit:tokenize-string "sum + 42" tokenizer)))
  tokens)
```

For string literals, comments, and DSL-style identifier boundaries:

```lisp
(let* ((identifier-char-p
         (lambda (char)
           (or (alpha-char-p char)
               (digit-char-p char)
               (char= char #\_)
               (char= char #\$)
               (char= char #\?))))
       (tokenizer
         (cl-parser-kit:make-tokenizer
          :rules (list (cl-parser-kit:make-whitespace-rule :skip-p t)
                       (cl-parser-kit:make-line-comment-rule :skip-p t)
                       (cl-parser-kit:make-block-comment-rule :skip-p t)
                       (cl-parser-kit:make-string-rule :escape-char #\\)
                       (cl-parser-kit:make-keyword-rule
                        :if "if"
                        :identifier-char-predicate identifier-char-p)
                       (cl-parser-kit:make-identifier-rule
                        :start-predicate identifier-char-p
                        :continue-predicate identifier-char-p)))))
  (cl-parser-kit:tokenize-string
   "if $value /* note */ \"ok\" ; trailing comment
if?"
   tokenizer))
```

For a parser example:

```lisp
(let* ((table (cl-parser-kit:make-pratt-table))
       (tokens (vector (cl-parser-kit:make-token :type :number :text "1" :value 1)
                       (cl-parser-kit:make-token :type :plus :text "+")
                       (cl-parser-kit:make-token :type :number :text "2" :value 2)
                       (cl-parser-kit:make-token :type :bang :text "!"))))
  (cl-parser-kit:register-prefix-operator
   table :number 0
   (lambda (token stream next table)
     (declare (ignore stream table))
     (values t (cl-parser-kit:token-value token) next nil)))
  (cl-parser-kit:register-infix-operator
   table :plus 10 11
   (lambda (left op right next table)
     (declare (ignore op table))
     (values t (list :add left right) next nil)))
  (cl-parser-kit:register-postfix-operator
   table :bang 30
   (lambda (left op stream next table)
     (declare (ignore op stream table))
     (values t (list :fact left) next nil)))
  (cl-parser-kit:parse-pratt-all tokens table))
```

Use `:position` when the expression begins later in an existing token stream,
and `:min-binding-power` when a caller needs Pratt parsing to stop before
lower-precedence operators.

The source-oriented Pratt entry point, `parse-pratt-source`, accepts the same
keywords after tokenization.

For small delimited grammars, the seq helpers remove most of the parser
loop boilerplate:

```lisp
(let* ((tokenizer (cl-parser-kit:make-tokenizer
                   :rules (list (cl-parser-kit:make-whitespace-rule :skip-p t)
                                (cl-parser-kit:make-keyword-rule :let "let")
                                (cl-parser-kit:make-literal-rule :lparen "(")
                                (cl-parser-kit:make-literal-rule :rparen ")")
                                (cl-parser-kit:make-literal-rule :comma ",")
                                (cl-parser-kit:make-literal-rule :semicolon ";")
                                (cl-parser-kit:make-identifier-rule))))
       (parser (cl-parser-kit:seq
                (cl-parser-kit:preceded-by
                 (cl-parser-kit:literal "let" :type :let)
                 (cl-parser-kit:delimited-sep-by1
                  (cl-parser-kit:literal "(" :type :lparen)
                  (cl-parser-kit:type-token :identifier)
                  (cl-parser-kit:literal "," :type :comma)
                  (cl-parser-kit:literal ")" :type :rparen)))
                (cl-parser-kit:opt
                 (cl-parser-kit:literal ";" :type :semicolon))
                (cl-parser-kit:end-of-input))))
  (cl-parser-kit:parse-source parser "let (answer, result);" tokenizer))
```

If you want parser results to contain raw strings and values instead of token
objects, combine `terminated-by` with the projection helpers. Swap
`delimited-sep-by` for `delimited-sep-end-by` when a trailing separator like
`(answer, result,)` should still parse:

```lisp
(let* ((tokenizer (cl-parser-kit:make-tokenizer
                   :rules (list (cl-parser-kit:make-whitespace-rule :skip-p t)
                                (cl-parser-kit:make-literal-rule :lparen "(")
                                (cl-parser-kit:make-literal-rule :rparen ")")
                                (cl-parser-kit:make-literal-rule :comma ",")
                                (cl-parser-kit:make-literal-rule :semicolon ";")
                                (cl-parser-kit:make-identifier-rule))))
       (group-parser
         (cl-parser-kit:terminated-by
          (cl-parser-kit:delimited-sep-by
           (cl-parser-kit:literal "(" :type :lparen)
           (cl-parser-kit:type-token-text :identifier)
           (cl-parser-kit:literal "," :type :comma)
           (cl-parser-kit:literal ")" :type :rparen))
          (cl-parser-kit:literal ";" :type :semicolon)))
       (binding-parser
         (cl-parser-kit:map-parser
          (cl-parser-kit:seq
           (cl-parser-kit:type-token-text :identifier)
           (cl-parser-kit:literal-value "=" :type :equals)
           (cl-parser-kit:terminated-by
            (cl-parser-kit:type-token-value :number)
            (cl-parser-kit:literal-text ";" :type :semicolon))
           (cl-parser-kit:end-of-input))
          (lambda (parts)
            (let ((identifier (first parts))
                  (operator (second parts))
                  (value (third parts))
                  (end-of-input (fourth parts)))
              (declare (ignore end-of-input))
              (list identifier operator value))))))
  (list (cl-parser-kit:parse-source group-parser "(answer, result);" tokenizer)
        (cl-parser-kit:parse-tokens
         binding-parser
         (vector (cl-parser-kit:make-token :type :identifier :text "answer")
                 (cl-parser-kit:make-token :type :equals
                                           :text "="
                                           :value :assign)
                 (cl-parser-kit:make-token :type :number
                                           :text "42"
                                           :value 42)
                 (cl-parser-kit:make-token :type :semicolon :text ";")))))
```

The seq helpers differ in where they commit failure:

- `preceded-by` returns only the inner parser value, but any committed failure
  from the prefix or inner parser is propagated as-is.
- `terminated-by` returns only the main parser value; once that main parser has
  consumed input, a missing suffix remains a hard failure instead of being
  silently ignored.
- `between` is the same contract applied to open/body/close delimiters, so a
  missing close delimiter stays committed after the body has started.
- `sep-by` / `delimited-sep-by` stop before a separator that does not match,
  but reject a trailing separator because the following item parser has already
  become mandatory.
- `sep-end-by` / `delimited-sep-end-by` keep the same committed-item contract,
  yet recover from a final separator when the next item parser fails without
  consuming input.

Pratt handlers use the same success/failure contract as the rest of the parser:

- prefix/postfix handlers return `(values t value next nil)` on success
- infix handlers return `(values t value next nil)` on success
- handlers may return `(values nil nil next failure)` for domain-specific
  validation failures

For failure rendering with source excerpts:

```lisp
(let* ((tokenizer (cl-parser-kit:make-tokenizer
                   :rules (list (cl-parser-kit:make-whitespace-rule :skip-p t)
                                (cl-parser-kit:make-literal-rule :plus "+")
                                (cl-parser-kit:make-number-rule))))
       (table (cl-parser-kit:make-pratt-table)))
  (cl-parser-kit:register-prefix-operator
   table :number 0
   (lambda (token stream next current-table)
     (declare (ignore stream current-table))
     (values t (cl-parser-kit:token-value token) next nil)))
  (cl-parser-kit:register-infix-operator
   table :plus 10 11
   (lambda (left op right next current-table)
     (declare (ignore op current-table))
     (values t (list :add left right) next nil)))
  (multiple-value-bind (ok value next failure)
      (cl-parser-kit:parse-pratt-source "1 + +" tokenizer table)
    (declare (ignore next))
    (if ok
        value
        (cl-parser-kit:parse-failure->string failure))))
```

If your pipeline already has tokens, use `parse-tokens` or `parse-all`
directly:

```lisp
(let* ((tokens (vector (cl-parser-kit:make-token :type :identifier :text "answer")
                       (cl-parser-kit:make-token :type :equals :text "=")
                       (cl-parser-kit:make-token :type :number :text "42" :value 42)))
       (parser (cl-parser-kit:seq
                (cl-parser-kit:type-token :identifier)
                (cl-parser-kit:type-token :equals)
                (cl-parser-kit:type-token :number))))
  (cl-parser-kit:parse-tokens parser tokens))
```

For custom token contracts and manual cursor inspection, combine
`satisfies-token` with `peek-token`, `next-token`, and `eof-token-p`:

```lisp
(let* ((tokens (vector (cl-parser-kit:make-token :type :identifier :text "answer")
                       (cl-parser-kit:make-token :type :equals :text "=")
                       (cl-parser-kit:make-token :type :number :text "42" :value 42)))
       (parser
         (cl-parser-kit:map-parser
          (cl-parser-kit:seq
           (cl-parser-kit:satisfies-token
            (lambda (token)
              (and (eql (cl-parser-kit:token-type token) :identifier)
                   (> (length (cl-parser-kit:token-text token)) 3)))
            :expected-name :long-identifier)
           (cl-parser-kit:type-token :equals)
           (cl-parser-kit:type-token-value :number)
           (cl-parser-kit:end-of-input))
          (lambda (parts)
            (list (cl-parser-kit:token-text (first parts))
                  (third parts))))))
  (multiple-value-bind (first next)
      (cl-parser-kit:next-token tokens 0)
    (list :peek (cl-parser-kit:token-text (cl-parser-kit:peek-token tokens 0))
          :next (list (cl-parser-kit:token-text first) next)
          :eof-before (cl-parser-kit:eof-token-p tokens next)
          :parse (multiple-value-list
                  (cl-parser-kit:parse-tokens parser tokens))
          :eof-after (cl-parser-kit:eof-token-p tokens (length tokens)))))
```

If those tokens come from an external lexer, diagnostics can still recover
line/column locations and source excerpts without `token-span` as long as each
token carries `token-start`, `token-end`, and `(:source <string>)` in
`token-metadata`:

```lisp
(let* ((source "answer
+")
       (tokens (vector (cl-parser-kit:make-token :type :identifier
                                                 :text "answer"
                                                 :start 0
                                                 :end 6
                                                 :metadata (list :source source))
                       (cl-parser-kit:make-token :type :plus
                                                 :text "+"
                                                 :start 7
                                                 :end 8
                                                 :metadata (list :source source))))
       (parser (cl-parser-kit:type-token :identifier)))
  (multiple-value-bind (ok value next failure)
      (cl-parser-kit:parse-all parser tokens)
    (declare (ignore value next))
    (if ok
        :ok
        (cl-parser-kit:parse-failure->string failure))))
```

When downstream tooling needs a stable tree shape, lower parsed output into a
small CST:

```lisp
(let* ((span (cl-parser-kit:make-span :start 0 :end 3))
       (cst (cl-parser-kit:make-cst-node
             :type :binding
             :children (list (cl-parser-kit:make-cst-node
                              :type :identifier
                              :value "answer"
                              :span span)))))
  (cl-parser-kit:cst-node->sexp cst :include-span t))
```

To assert what may or may not come next without consuming extra input, combine
`lookahead` and `not-followed-by`:

```lisp
(let* ((tokens (vector (cl-parser-kit:make-token :type :identifier :text "foo")
                       (cl-parser-kit:make-token :type :plus :text "+")))
       (parser (cl-parser-kit:seq
                (cl-parser-kit:lookahead
                 (cl-parser-kit:seq
                  (cl-parser-kit:type-token :identifier)
                  (cl-parser-kit:type-token :plus)))
                (cl-parser-kit:type-token :identifier)
                (cl-parser-kit:not-followed-by
                 (cl-parser-kit:type-token :identifier))
                (cl-parser-kit:type-token :plus))))
  (cl-parser-kit:parse-tokens parser tokens))
```

When a grammar term matters more than a raw token type, wrap the parser with
`label` so failures report that domain term instead:

```lisp
(let ((failure
        (multiple-value-bind (ok value next failure)
            (cl-parser-kit:parse-tokens
             (cl-parser-kit:seq
              (cl-parser-kit:alt
               (cl-parser-kit:seq
                (cl-parser-kit:literal "let" :type :let)
                (cl-parser-kit:type-token :identifier))
               (cl-parser-kit:seq
                (cl-parser-kit:literal "const" :type :const)
                (cl-parser-kit:label
                 (cl-parser-kit:type-token :identifier)
                 :binding-name)
                (cl-parser-kit:literal "=" :type :equals)
                (cl-parser-kit:type-token :number)))
              (cl-parser-kit:end-of-input))
             (vector (cl-parser-kit:make-token :type :const :text "const")
                     (cl-parser-kit:make-token :type :equals :text "=")))
          (declare (ignore value next))
          (unless ok
            failure))))
  (list (cl-parser-kit:parse-failure-position failure)
        (cl-parser-kit:parse-failure-expected failure)
        (cl-parser-kit:parse-failure-committed-p failure)
        (cl-parser-kit:token-type
         (cl-parser-kit:parse-failure-actual failure))))
```

When a grammar is just a repeated operand/operator pair, `chainl1` and
`chainr1` encode associativity directly without hand-written parser loops:

```lisp
(let* ((tokenizer (cl-parser-kit:make-tokenizer
                   :rules (list (cl-parser-kit:make-whitespace-rule :skip-p t)
                                (cl-parser-kit:make-literal-rule :minus "-")
                                (cl-parser-kit:make-literal-rule :caret "^")
                                (cl-parser-kit:make-number-rule))))
       (number-parser
         (cl-parser-kit:map-parser
          (cl-parser-kit:type-token :number)
          #'cl-parser-kit:token-value))
       (subtract-parser
         (cl-parser-kit:chainl1
          number-parser
          (cl-parser-kit:operator-parser
           (cl-parser-kit:literal "-" :type :minus)
           (lambda (left right)
             (- left right)))))
       (power-parser
         (cl-parser-kit:chainr1
          number-parser
          (cl-parser-kit:operator-parser
           (cl-parser-kit:literal "^" :type :caret)
           (lambda (left right)
             (expt left right))))))
  (list (cl-parser-kit:parse-source subtract-parser "10 - 3 - 2" tokenizer)
        (cl-parser-kit:parse-source power-parser "2 ^ 3 ^ 2" tokenizer)))
```

`operator-parser` is the thin wrapper for the common "match a token, ignore its
payload, return a binary combiner" pattern that shows up around `chainl1` and
`chainr1`.

When callers need to construct a user-facing diagnostic directly, the public
API also supports notes and fix-its:

```lisp
(cl-parser-kit:diagnostic->string
 (cl-parser-kit:error-diagnostic
  "bad token"
  :span (cl-parser-kit:make-span :source "foo + bar"
                                 :start 0 :end 3
                                 :start-line 1 :start-column 1
                                 :end-line 1 :end-column 2)
  :notes (list (cl-parser-kit:note-diagnostic
                "check syntax"
                :span (cl-parser-kit:make-span :start 4 :end 5
                                               :start-line 1 :start-column 5
                                               :end-line 1 :end-column 6)))
  :fixes (list (cl-parser-kit:make-fix-it
                :span (cl-parser-kit:make-span :start 0 :end 1)
                :replacement "x"))))
```

## Core Concepts

### Token

A token represents a lexical unit and carries:

- type
- text
- value
- span
- metadata

### Span

Spans track source locations using:

- offset
- line
- column
- start and end boundaries

### Tokenizer

The tokenizer is rule-based and supports:

- literal matching
- keyword matching on identifier boundaries
- identifier and number rules
- string rules
- predicate rules
- line and block comment rules
- whitespace skipping
- end-of-input handling

### Parser

The parser layer provides:

- sequencing
- alt / alternation
- repetition
- opt parsing
- lookahead
- failure propagation

### Pratt Parser

The Pratt parser layer is intended for expression grammars with:

- prefix operators
- infix operators
- postfix operators
- precedence and associativity

### Diagnostics

Structured diagnostics carry:

- kind
- message
- span
- expected forms
- actual token or lexeme
- notes and fix-its
- multiline rendering with source excerpts when `span-source` is available
- trailing-token failures from `parse-all` / `parse-source` keep the actual
  token and build diagnostics from token spans, falling back to token offsets
  or parser position when full span data is unavailable
- when external token streams omit `token-span` but provide `token-start` /
  `token-end` plus `(:source <string>)` in `token-metadata`, diagnostics
  reconstruct line/column locations and source excerpts from that original
  source text

### AST / CST Helpers

Tree helpers are provided for both abstract and concrete syntax trees:

- node type
- children
- value
- span
- metadata
- stable `*-node->sexp` conversion for tests and REPL inspection

## Public API

The main exported package is `:cl-parser-kit`.

Most users will only need a small subset of the API:

### Quick Start Surface

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

The bullet list above mirrors the canonical onboarding surface in
[`API.md`](./API.md).

The exported symbols are intentional and stable within the scope of this
repository.

When a user-facing grammar name matters more than a low-level token type, wrap
the parser with `label` so failures report a domain-specific expected form.

### API Map

The exported surface is grouped by concern:

- spans and source locations: `make-span`, `span-*`
- tokens and token metadata: `make-token`, `token-*`
- tokenizer construction: `make-tokenizer`, `make-*rule`, `tokenize-string`
- diagnostics and failures: `make-diagnostic`, `make-parse-failure`, `merge-parse-failures`
- parser primitives: `seq`, `alt`, `many`, `many1`, `chainl1`, `chainr1`, `opt`, `lookahead`, `not-followed-by`
- failure shaping: `label`
- practical seq helpers: `sep-by`, `sep-by1`, `sep-end-by`, `sep-end-by1`, `preceded-by`, `terminated-by`, `between`, `delimited-sep-by`, `delimited-sep-by1`, `delimited-sep-end-by`, `delimited-sep-end-by1`, `chainl1`, `chainr1`, `operator-parser`
- token projection helpers: `type-token-text`, `type-token-value`, `literal-text`, `literal-value`
- extended combinators: `choice`, `option`, `fail-parser`, `as-value`, `pure`, `times`, `times-between`, `at-least`, `at-most`, `end-by`, `end-by1`, `skip-many`, `skip-many1`, `fold-many`, `many-till`, `chainl`, `chainr`, `seq-map`, `pick`, `spanning`, `recognize`, `surrounded-by`
- token matching: `any-token`, `token-type-in`, `token-text-in`, `satisfies-value`
- value constraints and cut: `verify`, `commit`, `current-position`
- failure context: `context` (append an explanatory note to a failure)
- error recovery: `skip-until`, `recover` (panic-mode resynchronisation for multi-error parsing)
- tree traversal: `ast-node-walk`, `ast-node-find`, `ast-node-map`, `ast-node-collect`, `ast-node-count`, `ast-node-depth` (and the `cst-node-*` equivalents)
- ergonomic macros: `parse-let*` (do-notation), `parser-lazy` and `defparser` (forward references and recursive grammars)
- `alt` returns the farthest branch failure, and merges expected forms
  only when branches fail at the same position
- `lookahead` never consumes input on success, but preserves the nested farthest
  failure position on error
- `opt`, `many`, and `sep-by` recover only from non-consuming failures; after
  committed input, they propagate the original parse failure
- `sep-end-by` / `sep-end-by1` behave like `sep-by` / `sep-by1`, but accept a
  final separator when the following item parser fails without committing input
- when these combinators recover, attached diagnostics remain observable via
  `run-parser`; terminal entry points such as `parse-tokens`, `parse-all`,
  `parse-source`, and `parse-pratt-all` still return only hard failures
- parser entry points: `parse-tokens`, `parse-all`, `parse-source`, `parse-pratt`, `parse-pratt-all`, `parse-pratt-source`
- direct token-stream usage is covered in [`examples/token-stream-example.lisp`](./examples/token-stream-example.lisp)
- external-token fallback diagnostics are covered in [`examples/external-token-diagnostic-example.lisp`](./examples/external-token-diagnostic-example.lisp)
- Pratt parsing: `make-pratt-table`, `register-*operator`, `parse-pratt`, `parse-pratt-all`, `parse-pratt-source`
- Pratt high-level registrars: `register-atom`, `register-prefix`, `register-infix-left`, `register-infix-right`, `register-postfix`, `register-grouping`
- tree helpers: `make-ast-node`, `make-cst-node`, `ast-node->sexp`, `cst-node->sexp`
- test execution: `asdf:test-system "cl-parser-kit-test"` or `sbcl --script scripts/run-tests.lisp`

For exact exports, see [`src/package.lisp`](./src/package.lisp).

## Repository Layout

- `src/` - library source
- `t/` - tests
- `examples/` - REPL-friendly examples
- `cl-parser-kit.asd` - library system definition
- `cl-parser-kit-test.asd` - test system definition
- `ARCHITECTURE.md` - layer model and dependency direction
- `API.md` - grouped public surface and common entry points
- `EXAMPLES.md` - example map and walkthrough order

## Examples

See [`EXAMPLES.md`](./EXAMPLES.md) for a guided tour of the sample files.

## Roadmap

The current focus is on tightening the public surface rather than expanding the
core into a broader framework:

- more parser convenience helpers where they reduce boilerplate directly, especially when they add clearer contracts than ad hoc parser loops
- richer example coverage for token streams, Pratt expressions, and CST output
- additional regression tests for combinator edge cases
- clearer release notes as the public API stabilizes

## Testing

Run the test suite with:

```lisp
(asdf:test-system :cl-parser-kit)
```

The ASDF test system is `cl-parser-kit-test`, and the test package remains
`:cl-parser-kit/test`.

If you are verifying from a raw checkout outside `local-projects`, one
reproducible SBCL command is:

```sh
sbcl --script scripts/run-tests.lisp
```

The suite is defined with `cl-weave`; parser-table invariants are additionally
checked as executable `cl-prolog/weave` queries. It also covers the
representative README and `EXAMPLES.md` workflows so public snippets stay
executable as the library evolves. Example files under `examples/` are treated
the same way and should remain loadable from a fresh image.

## Design Non-Goals

This project is deliberately not trying to be:

- a CLI framework
- terminal or TTY handling layer
- Prolog engine
- event system
- dataflow engine
- generic utility package
- large compiler infrastructure
- full language workbench
- editor integration

## Contributing

Keep changes small, explicit, and covered by tests.

When adding new public behavior:

1. add or update tests first
2. keep the exported API intentional
3. make sure the README stays in sync with the actual symbols
4. prefer simple data structures over extra abstraction
5. keep representative README / `EXAMPLES.md` snippets and `examples/` files
   runnable under the test suite

## Security

The tokenizer and parser are designed to process untrusted source text. Several
exported specials bound the work any single call can perform, so hostile input
fails gracefully instead of exhausting memory or the control stack:
`*maximum-tokenizer-source-length*`, `*maximum-tokenizer-tokens*`,
`*maximum-tokenizer-rules*`, `*maximum-tokenizer-rule-alternatives*`,
`*maximum-number-lexeme-length*`, `*maximum-parser-recursion-depth*`,
`*maximum-parser-tokens*`, `*maximum-parser-repetition-count*`,
`*maximum-parser-apply-arity*`, `*maximum-pratt-recursion-depth*`,
`*maximum-tree-depth*`, `*maximum-tree-nodes*`,
`*maximum-diagnostic-line-length*`, `*maximum-diagnostic-count*`,
`*maximum-diagnostic-related-count*`, `*maximum-diagnostic-fix-count*`,
`*maximum-parse-failure-expected-count*`, and
`*maximum-parse-failure-diagnostic-count*`.
`*maximum-parser-tokens*` applies to public boundaries that accept an external
token stream, including `run-parser`, `filter-tokens`, `parse-tokens` /
`parse-all`, and `parse-pratt` / `parse-pratt-all`; circular or improper token
lists are rejected before traversal.
`*maximum-parser-repetition-count*` applies to bounded repetition, including
construction-time bounds such as `times` / `times-between` and length-prefixed
counts read by `length-count`, plus computed parser lists such as `choice`,
`sequence-of`, `seq-map`, `pick`, `permute`, token set combinators, and
`make-expression-parser` operator tables.
`*maximum-parser-apply-arity*` separately caps `seq-map`'s final call arity.
`*maximum-tree-depth*` and `*maximum-tree-nodes*` apply to AST/CST traversal,
conversion, comparison, and rendering helpers that may receive externally
constructed trees; malformed or circular tree child lists signal
`tree-child-list-invalid`. `*maximum-diagnostic-related-count*` caps rendered
diagnostic notes and fix-it hints from externally constructed diagnostics;
circular or improper related-item lists are rejected through the same condition.
`*maximum-diagnostic-fix-count*` caps input entries consumed by `apply-fixes`,
including `nil` entries skipped during application; circular or improper fix
lists are rejected through the same condition.
`*maximum-diagnostic-count*` caps batched diagnostic input entries, including
`nil` entries skipped for output; circular or improper batched diagnostic lists
are rejected through the same condition. The parse failure limits cap externally
constructed or highly ambiguous failure payloads and reject circular or improper
payload lists.
Rebind or `setf` them for intentionally large legitimate inputs; the tokenizer
limits signal `tokenizer-resource-limit-exceeded`. See [`API.md`](./API.md) for
details.

If you discover a security issue, report it privately — see
[`SECURITY.md`](./SECURITY.md) for the reporting channel — instead of opening a
public issue.

## License

MIT
