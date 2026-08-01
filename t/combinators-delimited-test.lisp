(in-package :cl-parser-kit/test)

(it-sequential "combinator-between-test"
  (with-combinator-tokens
      (tokens '((:type :lparen :text "(")
                (:type :identifier :text "foo")
                (:type :rparen :text ")")))
    (let ((parser (between (type-token :lparen)
                           (type-token :identifier)
                           (type-token :rparen))))
      (assert-combinator-values (parse-tokens parser tokens)
          (ok value next failure)
        (declare (ignore failure))
        (expect ok :to-be-truthy)
        (expect next :to-equal 3)
        (expect (token-type value) :to-equal :identifier)
        (expect (token-text value) :to-equal "foo")))))

(it-sequential "combinator-type-token-projection-helpers-test"
  (with-combinator-tokens
      (tokens '((:type :identifier :text "answer")
                (:type :number :text "42" :value 42)))
    (let ((text-parser (type-token-text :identifier))
          (value-parser (type-token-value :number)))
      (assert-combinator-values (parse-tokens text-parser tokens)
          (ok value next failure)
        (declare (ignore failure))
        (expect ok :to-be-truthy)
        (expect value :to-equal "answer")
        (expect next :to-equal 1))
      (assert-combinator-values (run-parser value-parser tokens 1)
          (ok value next failure)
        (declare (ignore failure))
        (expect ok :to-be-truthy)
        (expect value :to-equal 42)
        (expect next :to-equal 2)))))

(it-sequential "combinator-literal-projection-helpers-test"
  (with-combinator-tokens
      (tokens '((:type :keyword :text "let" :value :let)
                (:type :operator :text "=" :value :assign)))
    (let ((text-parser (literal-text "let" :type :keyword))
          (value-parser (literal-value "=" :type :operator)))
      (assert-combinator-values (parse-tokens text-parser tokens)
          (ok value next failure)
        (declare (ignore failure))
        (expect ok :to-be-truthy)
        (expect value :to-equal "let")
        (expect next :to-equal 1))
      (assert-combinator-values (run-parser value-parser tokens 1)
          (ok value next failure)
        (declare (ignore failure))
        (expect ok :to-be-truthy)
        (expect value :to-equal :assign)
        (expect next :to-equal 2)))))

(it-sequential "combinator-preceded-by-test"
  (with-combinator-tokens
      (tokens '((:type :let :text "let")
                (:type :identifier :text "answer")))
    (let ((parser (preceded-by (type-token :let)
                               (type-token :identifier))))
      (assert-combinator-success (parse-tokens parser tokens)
          (value next failure)
        (expect next :to-equal 2)
        (expect (token-type value) :to-equal :identifier)
        (expect (token-text value) :to-equal "answer")))))

(it-sequential "combinator-preceded-by-propagates-inner-failure-test"
  (with-combinator-tokens (tokens '((:type :let :text "let")))
    (let ((parser (preceded-by (type-token :let)
                               (type-token :identifier))))
      (assert-combinator-failure (parse-tokens parser tokens) (value next failure)
        (expect value :to-be-falsy)
        (expect next :to-equal 1)
        (expect (parse-failure-position failure) :to-equal 1)
        (expect (parse-failure-expected failure) :to-equal :identifier)
        (expect (parse-failure-actual failure) :to-equal :eof)
        ;; PRECEDED-BY's prefix already consumed "let", so the failure must
        ;; stay committed -- otherwise a surrounding OPT/MANY/ALT silently
        ;; backtracks past a half-consumed construct (docs/src/guide/parsing-patterns.md).
        (expect (parse-failure-committed-p failure) :to-be-truthy)))))

(it-sequential "combinator-terminated-by-test"
  (with-combinator-tokens
      (tokens '((:type :identifier :text "answer")
                (:type :semicolon :text ";")))
    (let ((parser (terminated-by (type-token :identifier)
                                 (type-token :semicolon))))
      (assert-combinator-success (parse-tokens parser tokens)
          (value next failure)
        (expect next :to-equal 2)
        (expect (token-type value) :to-equal :identifier)
        (expect (token-text value) :to-equal "answer")))))

(it-sequential "combinator-terminated-by-preserves-success-diagnostics-test"
  (with-combinator-tokens (tokens *positioned-identifier-semicolon-token-specs*)
    (let ((parser (terminated-by (map-parser (seq (type-token :identifier)
                                                  (opt (lookahead (end-of-input))))
                                             #'first)
                                 (type-token :semicolon))))
      (assert-combinator-success (run-parser parser tokens 0)
          (value next diagnostics)
        (expect (token-type value) :to-equal :identifier)
        (expect next :to-equal 2)
        (%assert-rendered-diagnostic-contains (first diagnostics)
                                              "Unexpected trailing token"
                                              "1:7-1:8")))))

(it-sequential "combinator-terminated-by-propagates-suffix-failure-test"
  (with-combinator-tokens (tokens '((:type :identifier :text "answer")))
    (let ((parser (terminated-by (type-token :identifier)
                                 (type-token :semicolon))))
      (assert-combinator-failure (parse-tokens parser tokens) (value next failure)
        (expect value :to-be-falsy)
        (expect next :to-equal 1)
        (expect (parse-failure-position failure) :to-equal 1)
        (expect (parse-failure-expected failure) :to-equal :semicolon)
        (expect (parse-failure-actual failure) :to-equal :eof)
        ;; TERMINATED-BY's body already consumed "answer", so the failure
        ;; must stay committed once the suffix fails (docs/src/guide/parsing-patterns.md).
        (expect (parse-failure-committed-p failure) :to-be-truthy)))))

(it-sequential "combinator-terminated-by-committed-failure-is-not-swallowed-by-many-test"
  ;; Regression for a bug where BIND-PARSER (which TERMINATED-BY is built on)
  ;; ignored that its first sub-parser had consumed input, so a surrounding
  ;; MANY treated a genuine "identifier not followed by ';'" grammar error as
  ;; an ordinary non-consuming stop-here failure and silently returned an
  ;; empty list instead of propagating the hard failure.
  (with-combinator-tokens
      (tokens '((:type :identifier :text "a")
                (:type :identifier :text "a")))
    (let ((parser (many (terminated-by (type-token :identifier)
                                       (type-token :semicolon)))))
      (assert-combinator-failure (parse-tokens parser tokens) (value next failure)
        (expect value :to-be-falsy)
        (expect next :to-equal 1)
        (expect (parse-failure-committed-p failure) :to-be-truthy)))))

(it-sequential "combinator-between-propagates-committed-close-delimiter-failure-test"
  (with-combinator-tokens
      (tokens '((:type :lparen :text "(")
                (:type :identifier :text "foo")
                (:type :identifier :text "bar")))
    (let ((parser (between (type-token :lparen)
                           (type-token :identifier)
                           (type-token :rparen))))
      (assert-combinator-failure (parse-tokens parser tokens) (value next failure)
        (expect value :to-be-falsy)
        (expect next :to-equal 2)
        (expect (parse-failure-expected failure) :to-equal :rparen)
        ;; BETWEEN already consumed "(" and "foo", so a wrong close token
        ;; must stay a hard failure instead of letting e.g. ALT or OPT
        ;; recover past the unmatched "(".
        (expect (parse-failure-committed-p failure) :to-be-truthy)))))

(it-sequential "combinator-delimited-sep-by1-test"
  (with-combinator-tokens (tokens *paren-identifier-comma-identifier-token-specs*)
    (let ((parser (delimited-sep-by1 (type-token :lparen)
                                     (type-token :identifier)
                                     (type-token :comma)
                                     (type-token :rparen))))
      (assert-combinator-projected-values (parse-tokens parser tokens)
          (value next failure)
          5
          '("foo" "bar")
          #'token-text))))

(it-sequential "combinator-delimited-sep-by-allows-empty-body-test"
  (with-combinator-tokens
      (tokens '((:type :lparen :text "(")
                (:type :rparen :text ")")))
    (let ((parser (delimited-sep-by (type-token :lparen)
                                    (type-token :identifier)
                                    (type-token :comma)
                                    (type-token :rparen))))
      (assert-combinator-success (parse-tokens parser tokens)
          (value next failure)
        (expect value :to-equal '())
        (expect next :to-equal 2)))))

(it-sequential "combinator-delimited-sep-by1-propagates-trailing-separator-failure-test"
  (with-combinator-tokens (tokens *paren-identifier-comma-rparen-token-specs*)
    (let ((parser (delimited-sep-by1 (type-token :lparen)
                                     (type-token :identifier)
                                     (type-token :comma)
                                     (type-token :rparen))))
      (assert-combinator-failure (parse-tokens parser tokens) (value next failure)
        (expect value :to-be-falsy)
        (expect next :to-equal 3)
        (expect (parse-failure-position failure) :to-equal 3)
        (expect (parse-failure-expected failure) :to-equal :identifier)
        (expect (token-type (parse-failure-actual failure)) :to-equal :rparen)))))

(it-sequential "combinator-delimited-sep-end-by1-allows-trailing-separator-before-close-test"
  (with-combinator-tokens
      (tokens *paren-identifier-comma-identifier-comma-rparen-token-specs*)
    (let ((parser (delimited-sep-end-by1 (type-token :lparen)
                                         (type-token :identifier)
                                         (type-token :comma)
                                         (type-token :rparen))))
      (assert-combinator-projected-values (parse-tokens parser tokens)
          (value next failure)
          6
          '("foo" "bar")
          #'token-text))))

(it-sequential "combinator-delimited-sep-end-by-allows-empty-body-test"
  (with-combinator-tokens
      (tokens '((:type :lparen :text "(")
                (:type :rparen :text ")")))
    (let ((parser (delimited-sep-end-by (type-token :lparen)
                                        (type-token :identifier)
                                        (type-token :comma)
                                        (type-token :rparen))))
      (assert-combinator-success (parse-tokens parser tokens)
          (value next failure)
        (expect value :to-equal '())
        (expect next :to-equal 2)))))

(it-sequential "define-delimited-separated-parser-expansion-test"
  (let* ((name (gensym "DELIMITED-PARSER-"))
         (expansion
           (macroexpand-1
            `(cl-parser-kit::define-delimited-separated-parser
                 ,name cl-parser-kit:sep-by))))
    (expect (first expansion) :to-equal 'defun)
    (expect (second expansion) :to-equal name)
    ;; The generated DEFUN carries a docstring naming the separator combinator
    ;; it wraps, so the body it delegates to is the form after it, not the
    ;; fourth element as it was before the docstring was added.
    (expect (stringp (fourth expansion)) :to-be-truthy)
    (expect (search "SEP-BY" (fourth expansion)) :to-be-truthy)
    (expect (first (fifth expansion))
            :to-equal 'cl-parser-kit:between)
    (expect (first (third (fifth expansion)))
            :to-equal 'cl-parser-kit:sep-by)))
