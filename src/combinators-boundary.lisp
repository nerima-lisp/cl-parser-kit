(in-package :cl-parser-kit)

(defun %keep-right (left right)
  (bind-parser left
               (lambda (_left)
                 (declare (ignore _left))
                 right)))

(defun %keep-left (left right)
  (bind-parser left
               (lambda (value)
                 (map-parser right
                             (lambda (_right)
                               (declare (ignore _right))
                               value)))))

(defmacro define-delimited-separated-parser (name separator-parser)
  "Define NAME as SEPARATOR-PARSER wrapped in BETWEEN -- the bracketed form of a
separated list, which is what an argument list or an array literal actually is."
  `(defun ,name (open parser separator close)
     ,(format nil "Parse OPEN, then PARSER repeated as ~A does with SEPARATOR ~
between items, then CLOSE, returning the list of PARSER's results. ~
(BETWEEN OPEN (~A PARSER SEPARATOR) CLOSE), inheriting that combinator's ~
commitment and failure-position behavior exactly."
              separator-parser separator-parser)
     (between open (,separator-parser parser separator) close)))

(define-parser-function label (parser expected) expected
  "Run PARSER unchanged, but rewrite a failure's EXPECTED to EXPECTED.

This is how an internal grammar detail is replaced by the name a user
recognizes: a failing digit-then-dot-then-digit sequence reports \"expected
NUMBER\" rather than the innermost token it happened to stop on. Only the
expected form changes -- position, actual token, diagnostics, and commitment
all pass through. Use CONTEXT instead when the internal detail should be kept
and merely annotated."
  (%run-parser/if-success
   parser input position
   #'%success
   (lambda (result next)
     (values nil nil
             next
             (%copy-parse-failure result :expected expected)))))

(define-parser-function context (parser note) :context
  "Run PARSER unchanged, but on failure append a NOTE (a `note-diagnostic`) to the
failure's diagnostics.

Unlike `label`, which replaces the expected form, `context` leaves the expected,
actual, and commitment untouched and only adds explanatory context such as
\"while parsing an argument list\". The note is observable on the returned
failure and rendered by `parse-failure->string`."
  (%run-parser/if-success
   parser input position
   #'%success
   (lambda (failure next)
     (values nil nil
             next
             (%copy-parse-failure
              failure
              :diagnostics (%append-parse-failure-diagnostic
                            (parse-failure-diagnostics failure)
                            (note-diagnostic note)))))))

(define-parser-function verify (parser predicate &key (expected-name :verify)) expected-name
  "Run PARSER, then require its value to satisfy PREDICATE.

On success where (FUNCALL PREDICATE value) is true, VERIFY behaves exactly like
PARSER. When the predicate is false the parse fails at the original position with
EXPECTED-NAME and the offending value as the actual, a non-committed failure so an
enclosing OPT/ALT may recover. Use it for semantic constraints a grammar cannot
express structurally (a number in range, a non-reserved identifier, ...)."
  (%run-parser/if-success
   parser input position
   (lambda (value next result)
     (if (funcall predicate value)
         (%success value next result)
         (%failure position expected-name value)))))

(define-parser-function commit (parser) :commit
  "Run PARSER, but promote any failure to a committed one.

A committed failure is no longer recovered by a surrounding OPT/MANY/SEP-BY, so
COMMIT expresses a PEG-style cut: once this point is reached the parse must
succeed here or fail hard, which turns a vague backtracking miss into a precise
error. PARSER's success is unchanged."
  (%run-parser/if-success
   parser input position
   #'%success
   (lambda (failure next)
     (declare (ignore next))
     (%committed-failure-from failure))))

(define-parser-function current-position () :current-position
  "Succeed without consuming input, yielding the current token index as the value.

Pair it with PARSE-LET* or SEQ-MAP to capture positions while parsing, e.g. to
record where a construct began before consuming it."
  (declare (ignore input))
  (%success position position))

(define-parser-function not-empty (parser) :not-empty
  "Run PARSER but fail if it succeeds without consuming any input.

Guarantees forward progress: wrap a parser that can succeed while consuming
nothing (an OPT or MANY of an optional element) before repeating it, so the
repetition cannot spin in place. On a consuming success NOT-EMPTY is exactly
PARSER; the failure it raises when nothing was consumed is non-committed, so an
enclosing OPT/ALT may still recover. FParsec's `notEmpty`."
  (%run-parser/if-success
   parser input position
   (lambda (value next result)
     (if (= next position)
         (%failure position :not-empty value)
         (%success value next result)))))

(defun preceded-by (prefix parser)
  "Parse PREFIX then PARSER, returning only PARSER's value and discarding
PREFIX's. The value-projection wrapper for a leading delimiter or keyword;
failure positions and commitment behave exactly as the underlying sequence."
  (%keep-right prefix parser))

(defun terminated-by (parser suffix)
  "Parse PARSER then SUFFIX, returning only PARSER's value and discarding
SUFFIX's -- the mirror of PRECEDED-BY, for a trailing delimiter such as a
statement semicolon."
  (%keep-left parser suffix))

(define-parser-function lookahead (parser) :lookahead
  "Run PARSER for its result but consume nothing: on success return its value
with the position unmoved, so the same input can be parsed again by whatever
follows.

A failure is reported at the position PARSER reached, but with commitment
cleared -- a speculative peek must never stop an enclosing ALT from trying
other branches. NOT-FOLLOWED-BY is the negative form."
  (%run-parser/if-success
   parser input position
   (lambda (value next result)
     (declare (ignore next))
     (%success value position result))
   (lambda (result next)
     (values nil nil
             next
             (%copy-parse-failure result :committed-p nil)))))

(define-parser-function not-followed-by (parser) :not-followed-by
  "Succeed with T, consuming nothing, exactly when PARSER would fail here; fail
when PARSER would succeed.

The negative lookahead used to make a prefix match maximal -- requiring that a
keyword is NOT followed by an identifier character is what stops \"iffy\" from
lexing as IF. Never consumes input in either outcome."
  (%run-parser/if-success
   parser input position
   (lambda (value next failure)
     (declare (ignore value next failure))
     (let ((token (%token-stream-token-at input position)))
       (%failure position
                 :not-followed-by
                 token
                 (%unexpected-token-diagnostic "Unexpected token"
                                               token
                                               :not-followed-by))))
   (lambda (failure next)
     (declare (ignore next))
     (%success t position (parse-failure-diagnostics failure)))))

(defun between (open parser close)
  "Parse OPEN, PARSER, then CLOSE, returning only PARSER's value -- the bracketed
form, and the composition PRECEDED-BY and TERMINATED-BY each cover one half of.
SURROUNDED-BY is the symmetric-delimiter shorthand."
  (%keep-right open (%keep-left parser close)))

(defun surrounded-by (delimiter parser)
  "Parse PARSER wrapped in a matching DELIMITER on both sides -- DELIMITER PARSER
DELIMITER -- returning PARSER's value. (SURROUNDED-BY d p) is (BETWEEN d p d),
for quotes, pipes, or any symmetric bracket."
  (between delimiter parser delimiter))

(define-delimited-separated-parser delimited-sep-by1 sep-by1)

(define-delimited-separated-parser delimited-sep-by sep-by)

(define-delimited-separated-parser delimited-sep-end-by1 sep-end-by1)

(define-delimited-separated-parser delimited-sep-end-by sep-end-by)

(define-parser-function end-of-input () :eoi
  "Succeed with T, consuming nothing, only at the end of the token stream;
otherwise fail with an \"Unexpected trailing token\" diagnostic at the offending
token.

Compose this into a grammar when only part of it must reach the end. PARSE-ALL
already enforces full consumption for a whole-document parse, so this is the
finer-grained tool, not a replacement for it."
  (let ((tokens (ensure-vector input)))
    (if (>= position (length tokens))
        (%success t position)
        (let ((token (aref tokens position)))
          (%failure position
                    :eoi
                    token
                    (%unexpected-token-diagnostic "Unexpected trailing token"
                                                  token
                                                  :eoi))))))

