(in-package :cl-parser-kit)

;;;; Applicative combinators and source-span capture.

(defparameter *maximum-parser-apply-arity* 256
  "Maximum number of positional values SEQ-MAP expands into one function call.
Use SEQUENCE-OF for large computed parser lists that should return one list
instead of being passed as implementation-level call arguments.")

(defun %check-parser-apply-arity (name count)
  (when (> count *maximum-parser-apply-arity*)
    (error "~A arity ~D exceeds *MAXIMUM-PARSER-APPLY-ARITY* (~D)"
           name count *maximum-parser-apply-arity*)))

(defun seq-map (function &rest parsers)
  "Run PARSERS in sequence (SEQ) and apply FUNCTION to their results as separate
positional arguments.

(SEQ-MAP #'MAKE-NODE A B C) parses A, B, C in order and returns
(MAKE-NODE VA VB VC). This is the applicative lift over SEQ and the idiomatic
way to combine a fixed number of sub-parsers into one value without manually
pulling the pieces out of SEQ's list."
  (%check-parser-apply-arity "SEQ-MAP" (length parsers))
  (map-parser (sequence-of parsers)
              (lambda (values)
                (apply function values))))

(defun pick (index &rest parsers)
  "Run PARSERS in sequence (SEQ) and keep only the INDEX-th result (0-based).

A concise way to parse surrounding syntax while retaining a single meaningful
value, e.g. (PICK 1 OPEN BODY CLOSE) keeps BODY. INDEX must be within range of
PARSERS."
  (map-parser (sequence-of parsers)
              (lambda (values)
                (nth index values))))

(defun pair (first second)
  "Run FIRST then SECOND in sequence (SEQ) and return the two-element list of
their results.

The two-parser specialisation of SEQ, named after nom's `pair`. Commit behaviour
is SEQ's: once FIRST consumes input a later SECOND failure stays committed."
  (seq-map (lambda (a b) (list a b)) first second))

(defun separated-pair (first separator second)
  "Run FIRST, SEPARATOR, then SECOND, discarding SEPARATOR's value and returning
the two-element list (FIRST-VALUE SECOND-VALUE).

nom's `separated_pair`: the idiomatic way to parse a `key = value` or `a , b`
pair while dropping the delimiter between them."
  (seq-map (lambda (a _separator b)
             (declare (ignore _separator))
             (list a b))
           first separator second))

(defun %span-between (input start-position end-position)
  "Merged source span covering tokens [START-POSITION, END-POSITION) of INPUT.

Returns NIL when the range is empty (a parser that consumed no tokens). Spans
are derived through %TOKEN-EFFECTIVE-SPAN, so tokens carrying either a stored
span or raw start/end offsets both contribute a meaningful location."
  (let ((tokens (ensure-vector input)))
    (when (< start-position end-position)
      (let ((limit (min end-position (length tokens)))
            (span nil))
        (loop for index from start-position below limit
              for token = (aref tokens index)
              for token-span = (%token-effective-span token :position index)
              do (setf span (if span
                                (span-merge span token-span)
                                token-span)))
        span))))

(define-parser-function spanning (function parser) :spanning
  "Run PARSER and call (FUNCTION VALUE SPAN), where SPAN covers the tokens PARSER
consumed (or NIL if it consumed none).

Designed for constructing located AST/CST nodes, e.g.
  (SPANNING (LAMBDA (V S) (MAKE-AST-NODE :TYPE :EXPR :VALUE V :SPAN S)) INNER)
attaches the exact source region of INNER to the node. PARSER's consumption and
commit behaviour are unchanged; only its value is transformed."
  (%run-parser/if-success
   parser input position
   (lambda (value next result)
     (%success (funcall function value (%span-between input position next))
               next
               result))))

(defun recognize (parser)
  "Run PARSER, discard its value, and yield the merged source span of the tokens
it consumed (NIL when it consumed none).

The span-only form of SPANNING, useful when only the matched source region
matters (for slicing text via SPAN-TEXT or reporting a location)."
  (spanning (lambda (value span)
              (declare (ignore value))
              span)
            parser))
