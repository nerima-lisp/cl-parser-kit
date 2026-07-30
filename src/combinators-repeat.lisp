(in-package :cl-parser-kit)

;;;; Repetition combinators.
;;;;
;;;; TIMES / CHAINL / CHAINR delegate to already-verified primitives (SEQ,
;;;; CHAINL1/CHAINR1, OPTION). SKIP-MANY / FOLD-MANY / MANY-TILL use dedicated
;;;; CPS loops that mirror %COLLECT-MANY/CPS exactly -- same progress guard
;;;; (%RUN-PROGRESSING-PARSER/CPS rejects a non-advancing repetition) and same
;;;; recovery rule (%RECOVERABLE-SUCCESS: stop on recoverable failure, propagate
;;;; a committed one) -- but without consing an intermediate result list.

(defun %check-parser-repetition-count (name count)
  (when (> count *maximum-parser-repetition-count*)
    (error "~A count ~D exceeds *MAXIMUM-PARSER-REPETITION-COUNT* (~D)"
           name count *maximum-parser-repetition-count*)))

(defun %run-fixed-repetition (parser input position count)
  "Run PARSER exactly COUNT times from POSITION, threading the position through
and collecting each result. Returns RUN-PARSER's (values ok value next result)
contract: on success VALUE is the list of the COUNT results; on failure, the
result is committed iff any repetition already consumed input (SEQ's
semantics). Shared by TIMES and LENGTH-COUNT's %LENGTH-COUNTED, which differ
only in where COUNT comes from -- a literal argument versus one parsed at run
time."
  (let ((current position)
        (results '())
        (diagnostics '()))
    (block done
      (loop repeat count
            do (%run-progressing-parser/cps
                parser input current
                (lambda (value next result)
                  (push value results)
                  (setf current next
                        diagnostics (%merge-diagnostics diagnostics result)))
                (lambda (failure)
                  (return-from done
                    (%failure-committed-if-consumed failure current position)))))
      (%success (nreverse results) current diagnostics))))

(defun times (count parser)
  "Parse PARSER exactly COUNT times, returning a list of the COUNT results.

COUNT must be a non-negative integer. As soon as one repetition fails the whole
parser fails, committed iff any input was already consumed (SEQ's semantics).
Each successful repetition must consume input, matching MANY's progress guard.
COUNT of 0 succeeds immediately consuming nothing and yielding NIL."
  (check-type count (integer 0))
  (%check-parser-repetition-count "TIMES" count)
  (make-parser
   :name :times
   :fn (lambda (input position)
         (%run-fixed-repetition parser input position count))))

(define-parser-function skip-many (parser) :skip-many
  "Parse PARSER zero or more times, discarding every result, yielding T.

Semantically MANY followed by discarding the list, but never allocates that
list. Like MANY it rejects a sub-parser that succeeds without consuming input
(guards against an infinite loop) and propagates a committed sub-failure.

Written as a plain LOOP rather than the self-recursive-through-two-closures
CPS shape used elsewhere in this file, for the same reason as
%COLLECT-MANY/CPS (combinators-sequence.lisp): this is a hot per-token loop,
and a closure per iteration is allocation this loop can avoid entirely."
  (loop with current = position
        with diagnostics = '()
        do (multiple-value-bind (ok value next result)
               (%run-parser-on-token-vector parser input current)
             (declare (ignore value))
             (cond
               ((not ok)
                (return (%recoverable-success t current diagnostics result)))
               ((= next current)
                (return (%recoverable-success t current diagnostics
                                              (%progress-failure-object current parser))))
               (t
                (setf diagnostics (%merge-diagnostics diagnostics result)
                      current next))))))

(defun skip-many1 (parser)
  "Parse PARSER one or more times, discarding every result, yielding T.

Fails (committed once the first item is consumed) if PARSER does not match at
least once."
  (bind-parser parser
               (lambda (_first)
                 (declare (ignore _first))
                 (skip-many parser))))

(defun fold-many (function initial parser)
  "Parse PARSER zero or more times, folding each result into an accumulator.

Starting from INITIAL, each successful match V updates the accumulator to
(FUNCALL FUNCTION ACC V); the final accumulator is the parser's value. Unlike
(MAP-PARSER (MANY P) ...) this never builds the intermediate list. Shares
MANY's progress guard and committed-failure propagation."
  (make-parser
   :name :fold-many
   :fn (lambda (input position)
         (loop with current = position
               with accumulator = initial
               with diagnostics = '()
               do (multiple-value-bind (ok value next result)
                      (%run-parser-on-token-vector parser input current)
                    (cond
                      ((not ok)
                       (return (%recoverable-success accumulator current diagnostics result)))
                      ((= next current)
                       (return (%recoverable-success accumulator current diagnostics
                                                     (%progress-failure-object current parser))))
                      (t
                       (setf accumulator (funcall function accumulator value)
                             diagnostics (%merge-diagnostics diagnostics result)
                             current next))))))))

(define-parser-function many-till (parser end) :many-till
  "Parse PARSER repeatedly until END succeeds; return the list of PARSER values.

Each iteration first tries END: on success the collected PARSER results are
returned (END's own value is discarded and its input consumed). Otherwise, if
END failed without committing, one PARSER is required. The parser fails when
PARSER fails before END matches, or when END commits input and then fails; such
a failure is committed iff any input was consumed, so an enclosing OPT/MANY does
not silently backtrack past a partially-parsed run."
  ;; A plain LOOP rather than the self-recursive-through-closures CPS shape
  ;; used elsewhere in this file, for the same reason as %COLLECT-MANY/CPS
  ;; (combinators-sequence.lisp): this is a hot per-token loop, and a closure
  ;; per iteration is allocation it can avoid entirely. Two levels of the
  ;; original CPS dispatch collapse into the COND below: try END first (the
  ;; outer %RUN-PARSER/IF-SUCCESS), and only on END's uncommitted failure try
  ;; PARSER (the inner %RUN-PROGRESSING-PARSER/CPS, whose own "succeeded but
  ;; did not progress" failure is reproduced explicitly via
  ;; %PROGRESS-FAILURE-OBJECT below).
  (loop with current = position
        with values = '()
        with diagnostics = '()
        do (multiple-value-bind (end-ok end-value end-next end-result)
               (%run-parser-on-token-vector end input current)
             (declare (ignore end-value))
             (cond
               (end-ok
                (return (%success (nreverse values) end-next
                                  (%merge-diagnostics diagnostics end-result))))
               ((parse-failure-committed-p end-result)
                (return (%committed-failure-from end-result)))
               (t
                (multiple-value-bind (item-ok value next item-result)
                    (%run-parser-on-token-vector parser input current)
                  (cond
                    ((and item-ok (/= next current))
                     (setf values (cons value values)
                           diagnostics (%merge-diagnostics diagnostics item-result)
                           current next))
                    (t
                     (let ((merged (merge-parse-failures
                                    end-result
                                    (if item-ok
                                        (%progress-failure-object current parser)
                                        item-result))))
                       (return (%failure-committed-if-consumed merged current position)))))))))))

(defun fold-many1 (function initial parser)
  "Like FOLD-MANY but requires PARSER to match at least once.

Folds each result into the accumulator starting from INITIAL, exactly as
FOLD-MANY, but fails (committed once the first item is consumed) when PARSER does
not match even once. Equivalent in shape to (FOLD-MANY ...) guarded by MANY1."
  (bind-parser parser
               (lambda (first)
                 (fold-many function (funcall function initial first) parser))))

(defun chain-postfix (base suffix)
  "Parse BASE, then apply zero or more SUFFIX parsers left-to-right, each of which
yields a function transforming the accumulated value; return the final value.

The left-associative suffix-chain combinator, for member access, calls and
indexing: with SUFFIX an ALT of parsers each producing a one-argument function,
  (chain-postfix primary
                 (alt (map-parser field   (lambda (f) (lambda (v) (list :get v f))))
                      (map-parser args     (lambda (a) (lambda (v) (list :call v a))))))
parses `primary .field (args) .field2 ...` folding each suffix onto the value.
Built on FOLD-MANY, so it shares MANY's progress guard and committed-failure
propagation."
  (bind-parser base
               (lambda (initial)
                 (fold-many (lambda (accumulator function) (funcall function accumulator))
                            initial
                            suffix))))

(defun some-till (parser end)
  "Like MANY-TILL but requires PARSER to match at least once before END.

Parses PARSER one or more times until END succeeds, returning the collected
PARSER values; fails if END matches (or the input ends) before PARSER matched at
least once. Megaparsec's `someTill`, the non-empty companion of MANY-TILL."
  (bind-parser parser
               (lambda (first)
                 (map-parser (many-till parser end)
                             (lambda (rest)
                               (cons first rest))))))

(defun %length-counted (count item-parser)
  (make-parser
   :name :length-count
   :fn (lambda (input position)
         (%run-fixed-repetition item-parser input position count))))

(defun length-count (count-parser item-parser)
  "Parse COUNT-PARSER for a non-negative integer N, then parse ITEM-PARSER exactly
N times, returning the list of N item values.

For length-prefixed sequences such as `3 a b c`. nom's `length_count`. A count
that is not a non-negative integer fails the parse (rather than signalling); each
item must consume input, and counts above *MAXIMUM-PARSER-REPETITION-COUNT* fail
the parse, so a hostile count cannot force an unbounded loop."
  (bind-parser count-parser
               (lambda (count)
                 (cond
                   ((not (and (integerp count) (>= count 0)))
                    (fail-parser "length-count expected a non-negative integer count"
                                 :expected :length-count))
                   ((> count *maximum-parser-repetition-count*)
                    (fail-parser "length-count count exceeds maximum parser repetition count"
                                 :expected :length-count))
                   (t
                    (%length-counted count item-parser))))))

(defun chainl (parser operator default)
  "Like CHAINL1 but succeeds with DEFAULT (consuming nothing) when PARSER does
not match even once. Left-associative folding of PARSER separated by OPERATOR."
  (option default (chainl1 parser operator)))

(defun chainr (parser operator default)
  "Like CHAINR1 but succeeds with DEFAULT (consuming nothing) when PARSER does
not match even once. Right-associative folding of PARSER separated by OPERATOR."
  (option default (chainr1 parser operator)))

(defun times-between (min max parser)
  "Parse PARSER at least MIN and at most MAX times, returning the list of results.

Matching is greedy: it keeps parsing until PARSER fails or MAX is reached. Fewer
than MIN matches is a failure (committed iff any input was consumed); once MIN is
reached a further recoverable failure simply stops. A committed sub-parser
failure always propagates. MIN and MAX are non-negative integers with MIN <= MAX."
  (check-type min (integer 0))
  (check-type max (integer 0))
  (assert (<= min max) (min max)
          "TIMES-BETWEEN requires MIN (~D) <= MAX (~D)" min max)
  (%check-parser-repetition-count "TIMES-BETWEEN" max)
  (make-parser
   :name :times-between
   :fn (lambda (input position)
         (loop with current = position
               with count = 0
               with values = '()
               with diagnostics = '()
               do (when (>= count max)
                    (return (%success (nreverse values) current diagnostics)))
                  (multiple-value-bind (ok value next result)
                      (%run-parser-on-token-vector parser input current)
                    (cond
                      ((and ok (/= next current))
                       (setf count (1+ count)
                             values (cons value values)
                             diagnostics (%merge-diagnostics diagnostics result)
                             current next))
                      (t
                       (let ((failure (if ok (%progress-failure-object current parser) result)))
                         (return
                           (if (>= count min)
                               (%recoverable-success (nreverse values)
                                                     current diagnostics failure)
                               (%failure-committed-if-consumed
                                failure current position)))))))))))

(defun at-least (min parser)
  "Parse PARSER at least MIN times with no upper bound, returning the list of
results. (AT-LEAST 0 P) is (MANY P); (AT-LEAST 1 P) is (MANY1 P)."
  (check-type min (integer 0))
  (if (zerop min)
      (many parser)
      (map-parser (seq (times min parser) (many parser))
                  (lambda (parts)
                    (append (first parts) (second parts))))))

(defun at-most (max parser)
  "Parse PARSER at most MAX times (zero to MAX), returning the list of results.
Equivalent to (TIMES-BETWEEN 0 MAX PARSER)."
  (times-between 0 max parser))

(defun end-by (parser separator)
  "Parse zero or more PARSER, each of which MUST be followed by SEPARATOR,
returning the list of PARSER results. Unlike SEP-END-BY (trailing separator
optional), every item's separator is required, so (END-BY item semicolon) parses
a run of `item ;` groups."
  (many (terminated-by parser separator)))

(defun end-by1 (parser separator)
  "Like END-BY but requires at least one terminated PARSER."
  (many1 (terminated-by parser separator)))
