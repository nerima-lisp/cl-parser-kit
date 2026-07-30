(in-package :cl-parser-kit)

;;;; Backtracking control.
;;;;
;;;; COMMIT (in combinators-boundary.lisp) promotes any failure to a committed
;;;; one so a surrounding OPT/MANY/SEP-BY can no longer recover past it. ATTEMPT
;;;; is its exact inverse: it demotes a committed failure back to a recoverable
;;;; one, so an enclosing recovery combinator may backtrack even after PARSER
;;;; consumed input. This is Parsec/Megaparsec's `try`.
;;;;
;;;; Note that ALT in this library already backtracks unconditionally (it tries
;;;; every alternative at the same position regardless of commitment), so ATTEMPT
;;;; is not needed to make ALT branches recoverable. It matters for the
;;;; commitment-respecting combinators -- OPT, OPTION, MANY, SKIP-MANY, SEP-BY,
;;;; TIMES-BETWEEN, CHAINL/CHAINR -- which stop (rather than recover) once a
;;;; sub-parser fails with a committed failure.

(define-parser-function attempt (parser) :attempt
  "Run PARSER, but demote any failure to a non-committed (recoverable) one.

On success ATTEMPT behaves exactly like PARSER. On failure it resets the
failure's commitment so a surrounding OPT/MANY/SEP-BY/OPTION treats it as a
clean miss and backtracks to the position ATTEMPT started at, instead of
propagating a committed failure. Use it to make a multi-token construct
all-or-nothing inside an optional context, e.g.
  (opt (attempt (seq (literal \"else\") (literal \"if\"))))
recovers cleanly when only `else` (but not `else if`) is present."
  (%run-parser/if-success
   parser input position
   #'%success
   (lambda (failure next)
     (declare (ignore next))
     ;; Backtrack the consumption: return NEXT = POSITION (where ATTEMPT began)
     ;; and reset commitment so a surrounding OPT/MANY/SEP-BY treats it as a
     ;; clean miss and resumes here. The failure object keeps its own (deeper)
     ;; position and expected form, so MERGE-PARSE-FAILURES / ALT can still
     ;; report the precise point PARSER actually stalled at.
     (values nil nil
             position
             (%copy-parse-failure failure :committed-p nil)))))
