# Examples

This repository includes small, focused examples instead of one large
tutorial. Each file demonstrates a different layer of `cl-parser-kit`.

For the exported API grouped by concern, see [API Reference](api.md).
For the layer model and dependencies, see [Architecture](architecture.md).
For the recommended parser construction and upgrade rules, see
[Parsing Patterns](parsing-patterns.md).

To execute the shipped examples as a raw-checkout regression pass, run:

```sh
sbcl --script scripts/run-examples.lisp
```

## Example Index

- [`examples/tokenizer-example.lisp`][tokenizer-example]
    - Shows how to build a tokenizer, inspect token output from raw text,
      and customize strings, comments, and identifier boundaries for small
      DSLs.
    - Best starting point when you only need lexical analysis.
- [`examples/combinator-example.lisp`][combinator-example]
    - Shows a grouped binding parser built from combinators.
    - Best starting point when you want to parse token streams with `seq`,
      `sep-by1`, `between`, `opt`, and `end-of-input`.
- [`examples/operator-chain-example.lisp`][operator-chain-example]
    - Shows how `chainl1` and `chainr1` encode associativity for repeated
      operand/operator grammars.
    - Best starting point when operator precedence is simple enough that a
      full Pratt table would be overkill.
- [`examples/sequence-helper-example.lisp`][sequence-helper-example]
    - Shows how `terminated-by`, `delimited-sep-by`, `delimited-sep-end-by`,
      and the token projection helpers return strings and values instead of
      raw token objects.
    - Best starting point when delimiters are syntax-only and downstream
      code wants projected payloads.
- [`examples/token-stream-example.lisp`][token-stream-example]
    - Shows how to keep tokenization separate from parsing and how
      `parse-all` reports a trailing token with a rendered diagnostic.
    - Best starting point when another phase already produced the token
      vector.
- [`examples/token-navigation-example.lisp`][token-navigation-example]
    - Shows how `satisfies-token` expresses a custom token predicate and how
      `peek-token`, `next-token`, and `eof-token-p` inspect a token stream
      cursor directly.
    - Best starting point when another phase already produced tokens and
      you need a small amount of manual stream control.
- [`examples/external-token-diagnostic-example.lisp`][external-token-diagnostic-example]
    - Shows how external token streams can omit `token-span` and still
      render line/column diagnostics when each token carries `token-start`,
      `token-end`, and `(:source <string>)` in `token-metadata`.
    - Best starting point when another lexer already produced tokens and
      you need source excerpts without rebuilding spans up front.
- [`examples/failure-shaping-example.lisp`][failure-shaping-example]
    - Shows how `label` and `parse-failure-*` expose a committed failure as
      stable programmatic data.
    - Best starting point when callers need to branch on parse errors
      instead of only rendering diagnostics.
- [`examples/expression-parser.lisp`][expression-parser]
    - Shows a compact Pratt parser setup for expression precedence with
      `parse-pratt-all`, including postfix operators.
    - Best starting point when infix, prefix, and postfix precedence
      matter.
- [`examples/operator-precedence-example.lisp`][operator-precedence-example]
    - Shows the combinator-layer `make-expression-parser`: an operator
      table (highest precedence first) with prefix `-`, then `*`, then `+`.
    - Best starting point when operands and operators are arbitrary parsers
      rather than single tokens keyed by type.
- [`examples/json-parser-example.lisp`][json-parser-example]
    - A complete recursive JSON parser: escaped strings, signed/exponent
      numbers, keyword and literal rules, and a self-referential grammar
      via `defparser`, decoding objects to alists and arrays to lists.
    - Best starting point for a real-world, recursively nested grammar
      spanning the whole tokenize-then-parse stack.
- [`examples/error-recovery-example.lisp`][error-recovery-example]
    - Panic-mode error recovery with `recover` + `skip-until`, driven by
      `many-till`, so one parse reports every malformed statement instead
      of aborting at the first; reads the collected diagnostics from
      `run-parser`'s fourth value.
    - Best starting point for multi-error reporting (linters, IDEs) where
      the parse must continue past mistakes.
- [`examples/csv-parser-example.lisp`][csv-parser-example]
    - A line-oriented CSV parser keeping the newline as a real token: rows
      via `sep-end-by` (optional trailing newline), fields via `sep-by1`,
      and quoted fields that may contain commas.
    - Best starting point for a delimiter-and-line structured format where
      newlines are significant.
- [`examples/diagnostic-example.lisp`][diagnostic-example]
    - Shows how a Pratt parse failure turns into a structured, multiline
      diagnostic string with source excerpts via `parse-pratt-source`, and
      how to build a manual diagnostic with notes and fix-its.
    - Best starting point when you need user-facing parse errors instead of
      only success-path AST values.
- [`examples/mini-language-parser.lisp`][mini-language-parser]
    - Shows a slightly more complete parser shape for a toy language.
    - Best starting point when you want to combine tokenization and parsing
      in one workflow.
- [`examples/cst-example.lisp`][cst-example]
    - Shows how to lower parsed tokens into a simple CST and inspect it
      with `cst-node->sexp`.
    - Best starting point when you need explicit tree output for
      downstream tooling or tests.

## Recommended Reading Order

1. Start with [`examples/tokenizer-example.lisp`][tokenizer-example] to
   understand how tokens are produced.
2. Read [`examples/combinator-example.lisp`][combinator-example] to see
   token parsers composed from primitives and practical sequence helpers.
3. Read [`examples/sequence-helper-example.lisp`][sequence-helper-example]
   to see how delimiter-heavy grammars can project strings and values
   directly, including optional trailing separators.
4. Read [`examples/operator-chain-example.lisp`][operator-chain-example]
   to see how left- and right-associative operator chains stay
   declarative.
5. Read [`examples/token-stream-example.lisp`][token-stream-example] to see
   direct `parse-all` usage on a pre-tokenized vector.
6. Read [`examples/token-navigation-example.lisp`][token-navigation-example]
   to see custom token predicates and stream cursor inspection helpers.
7. Read [`examples/external-token-diagnostic-example.lisp`][external-token-diagnostic-example]
   to see the minimum metadata contract for external token diagnostics.
8. Read [`examples/failure-shaping-example.lisp`][failure-shaping-example]
   to see how committed failures can be shaped into stable
   machine-readable data.
9. Read [`examples/expression-parser.lisp`][expression-parser] to see how
   Pratt parsing fits expression grammars.
10. Read [`examples/diagnostic-example.lisp`][diagnostic-example] to see
    how Pratt failures become user-facing diagnostics.
11. Read [`examples/mini-language-parser.lisp`][mini-language-parser] to
    see the pieces combined into a larger parser shape.
12. Read [`examples/cst-example.lisp`][cst-example] to see a concrete
    syntax tree shape and stable inspection output.

## Minimal Workflows

### Tokenize Source

```lisp
(let ((tokenizer (cl-parser-kit:make-tokenizer
                  :rules (list (cl-parser-kit:make-whitespace-rule :skip-p t)
                               (cl-parser-kit:make-literal-rule :plus "+")
                               (cl-parser-kit:make-number-rule)
                               (cl-parser-kit:make-identifier-rule)))))
  (cl-parser-kit:tokenize-string "sum + 42" tokenizer))
```

### Tokenize DSL-Flavored Source

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

### Parse a Token Stream

```lisp
(cl-parser-kit:parse-tokens
 (cl-parser-kit:seq
  (cl-parser-kit:label
   (cl-parser-kit:type-token :identifier)
   :binding-name)
  (cl-parser-kit:literal "=" :type :equals)
  (cl-parser-kit:type-token :number)
  (cl-parser-kit:end-of-input))
 (vector (cl-parser-kit:make-token :type :identifier :text "answer")
         (cl-parser-kit:make-token :type :equals :text "=")
         (cl-parser-kit:make-token :type :number :text "42" :value 42)))
```

### Shape Failure Expectations

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
        (cl-parser-kit:token-type (cl-parser-kit:parse-failure-actual failure))))
```

### Parse Left- And Right-Associative Operator Chains

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

### Project Token Text And Values

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

### Accept An Optional Trailing Separator

```lisp
(let* ((tokenizer (cl-parser-kit:make-tokenizer
                   :rules (list (cl-parser-kit:make-whitespace-rule :skip-p t)
                                (cl-parser-kit:make-literal-rule :lparen "(")
                                (cl-parser-kit:make-literal-rule :rparen ")")
                                (cl-parser-kit:make-literal-rule :comma ",")
                                (cl-parser-kit:make-identifier-rule))))
       (parser
         (cl-parser-kit:delimited-sep-end-by
          (cl-parser-kit:literal "(" :type :lparen)
          (cl-parser-kit:type-token-text :identifier)
          (cl-parser-kit:literal "," :type :comma)
          (cl-parser-kit:literal ")" :type :rparen)))
  (list (cl-parser-kit:parse-source parser "(answer, result)" tokenizer)
        (cl-parser-kit:parse-source parser "(answer, result,)" tokenizer)))
```

Use `delimited-sep-by` when the separator must always be followed by
another item, and `delimited-sep-end-by` when a final separator is part of
the grammar.

### Render A Failure From External Tokens

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

### Parse Source End-to-End

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
                (cl-parser-kit:opt (cl-parser-kit:literal ";" :type :semicolon))
                (cl-parser-kit:end-of-input))))
  (cl-parser-kit:parse-source parser "let (answer, result, total);" tokenizer))
```

### Render A Parse Failure

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
     (values (cl-parser-kit:token-value token) next)))
  (cl-parser-kit:register-infix-operator
   table :plus 10 11
   (lambda (left op right current-table)
     (declare (ignore op current-table))
     (list :add left right)))
  (multiple-value-bind (ok value next failure)
      (cl-parser-kit:parse-pratt-source "1 + +" tokenizer table)
    (declare (ignore next))
    (if ok
        value
        (cl-parser-kit:parse-failure->string failure))))
```

### Build A Manual Diagnostic

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

### Build And Inspect A CST

```lisp
(let* ((tokenizer (cl-parser-kit:make-tokenizer
                   :rules (list (cl-parser-kit:make-whitespace-rule :skip-p t)
                                (cl-parser-kit:make-keyword-rule :let "let")
                                (cl-parser-kit:make-literal-rule :equals "=")
                                (cl-parser-kit:make-literal-rule :semicolon ";")
                                (cl-parser-kit:make-number-rule)
                                (cl-parser-kit:make-identifier-rule))))
       (parser (cl-parser-kit:seq
                (cl-parser-kit:literal "let" :type :let)
                (cl-parser-kit:type-token :identifier)
                (cl-parser-kit:literal "=" :type :equals)
                (cl-parser-kit:type-token :number)
                (cl-parser-kit:opt (cl-parser-kit:literal ";" :type :semicolon))
                (cl-parser-kit:end-of-input))))
  (multiple-value-bind (ok value)
      (cl-parser-kit:parse-source parser "let answer = 42;" tokenizer)
    (when ok
      (let ((cst (cl-parser-kit:make-cst-node
                  :type :binding
                  :children (list (cl-parser-kit:make-cst-node :type :keyword :value "let")
                                  (cl-parser-kit:make-cst-node :type :identifier :value "answer")
                                  (cl-parser-kit:make-cst-node :type :punctuation :value "=")
                                  (cl-parser-kit:make-cst-node :type :number :value "42")
                                  (cl-parser-kit:make-cst-node :type :punctuation :value ";")))))
        (cl-parser-kit:cst-node->sexp cst)))))
```

[tokenizer-example]: https://github.com/nerima-lisp/cl-parser-kit/blob/main/examples/tokenizer-example.lisp
[combinator-example]: https://github.com/nerima-lisp/cl-parser-kit/blob/main/examples/combinator-example.lisp
[operator-chain-example]: https://github.com/nerima-lisp/cl-parser-kit/blob/main/examples/operator-chain-example.lisp
[sequence-helper-example]: https://github.com/nerima-lisp/cl-parser-kit/blob/main/examples/sequence-helper-example.lisp
[token-stream-example]: https://github.com/nerima-lisp/cl-parser-kit/blob/main/examples/token-stream-example.lisp
[token-navigation-example]: https://github.com/nerima-lisp/cl-parser-kit/blob/main/examples/token-navigation-example.lisp
[external-token-diagnostic-example]: https://github.com/nerima-lisp/cl-parser-kit/blob/main/examples/external-token-diagnostic-example.lisp
[failure-shaping-example]: https://github.com/nerima-lisp/cl-parser-kit/blob/main/examples/failure-shaping-example.lisp
[expression-parser]: https://github.com/nerima-lisp/cl-parser-kit/blob/main/examples/expression-parser.lisp
[operator-precedence-example]: https://github.com/nerima-lisp/cl-parser-kit/blob/main/examples/operator-precedence-example.lisp
[json-parser-example]: https://github.com/nerima-lisp/cl-parser-kit/blob/main/examples/json-parser-example.lisp
[error-recovery-example]: https://github.com/nerima-lisp/cl-parser-kit/blob/main/examples/error-recovery-example.lisp
[csv-parser-example]: https://github.com/nerima-lisp/cl-parser-kit/blob/main/examples/csv-parser-example.lisp
[diagnostic-example]: https://github.com/nerima-lisp/cl-parser-kit/blob/main/examples/diagnostic-example.lisp
[mini-language-parser]: https://github.com/nerima-lisp/cl-parser-kit/blob/main/examples/mini-language-parser.lisp
[cst-example]: https://github.com/nerima-lisp/cl-parser-kit/blob/main/examples/cst-example.lisp
