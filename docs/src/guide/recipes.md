# Recipes

A worked tour of every parser construction style the library offers, from
custom lexical rules through Pratt tables to operator chains. Start with
[Getting Started](../getting-started.md) if you have not tokenized anything
yet, and see [Diagnostics](diagnostics.md) for rendering failures.

## Strings, comments, and DSL-style identifier boundaries

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

The lexical helpers are intentionally customizable. If your language allows
identifier sigils or suffix markers such as `$value` or `tail?`, use
`make-identifier-rule` with custom `:start-predicate` / `:continue-predicate`,
and pass the same boundary logic into `make-keyword-rule` so reserved words
do not match inside those identifiers.

## Pratt parsing

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

Use `:position` when the expression begins later in an existing token
stream, and `:min-binding-power` when a caller needs Pratt parsing to stop
before lower-precedence operators.

The source-oriented Pratt entry point, `parse-pratt-source`, accepts the
same keywords after tokenization.

## Seq helpers for delimited grammars

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

If you want parser results to contain raw strings and values instead of
token objects, combine `terminated-by` with the projection helpers. Swap
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

- `preceded-by` returns only the inner parser value, but any committed
  failure from the prefix or inner parser is propagated as-is.
- `terminated-by` returns only the main parser value; once that main parser
  has consumed input, a missing suffix remains a hard failure instead of
  being silently ignored.
- `between` is the same contract applied to open/body/close delimiters, so
  a missing close delimiter stays committed after the body has started.
- `sep-by` / `delimited-sep-by` stop before a separator that does not match,
  but reject a trailing separator because the following item parser has
  already become mandatory.
- `sep-end-by` / `delimited-sep-end-by` keep the same committed-item
  contract, yet recover from a final separator when the next item parser
  fails without consuming input.

Pratt handlers use the same success/failure contract as the rest of the
parser:

- prefix/postfix handlers return `(values t value next nil)` on success
- infix handlers return `(values t value next nil)` on success
- handlers may return `(values nil nil next failure)` for domain-specific
  validation failures
## Working directly with tokens

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
line/column locations and source excerpts without `token-span` as long as
each token carries `token-start`, `token-end`, and `(:source <string>)` in
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

## Lowering into a CST

When downstream tooling needs a stable tree shape, lower parsed output into
a small CST:

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

## Lookahead and negative lookahead

To assert what may or may not come next without consuming extra input,
combine `lookahead` and `not-followed-by`:

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

## Naming grammar terms with `label`

When a grammar term matters more than a raw token type, wrap the parser
with `label` so failures report that domain term instead:

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

## Operand/operator chains with `chainl1` / `chainr1`

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

`operator-parser` is the thin wrapper for the common "match a token, ignore
its payload, return a binary combiner" pattern that shows up around
`chainl1` and `chainr1`.
