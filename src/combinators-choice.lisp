(in-package :cl-parser-kit)

;;;; Choice and value-shaping combinators.
;;;;
;;;; Computed parser lists avoid APPLY and reject circular lists at construction.

(defun %ensure-parser-list-vector (name parsers)
  (multiple-value-bind (stream parser-count too-many-p)
      (ensure-vector-up-to parsers *maximum-parser-repetition-count*)
    (when too-many-p
      (error "~A parser count ~D exceeds *MAXIMUM-PARSER-REPETITION-COUNT* (~D)"
             name parser-count *maximum-parser-repetition-count*))
    stream))

(defun choice (parsers)
  "Ordered choice over a LIST of parsers -- the list form of ALT.

Tries each parser in PARSERS in order at the same position, returning the first
success. On total failure the farthest (best) failure is reported, exactly as
ALT does. (CHOICE (LIST A B C)) is equivalent to (ALT A B C); prefer CHOICE
when the alternatives are computed at runtime."
  (let ((branches (%ensure-parser-list-vector "CHOICE" parsers)))
    (make-parser
     :name :alt
     :fn (lambda (input position)
           (if (zerop (length branches))
               (%failure position :alternative nil)
               (%run-ordered-choice branches input position))))))

(defun sequence-of (parsers)
  "Run PARSERS (a LIST) in sequence, returning the list of their values.

The list form of SEQ, exactly as CHOICE is the list form of ALT: prefer it when
the sequence of sub-parsers is computed at runtime. (SEQUENCE-OF (LIST A B C)) is
equivalent to (SEQ A B C), inheriting SEQ's commitment semantics."
  (let ((items (%ensure-parser-list-vector "SEQUENCE-OF" parsers)))
    (make-parser
     :name :seq
     :fn (lambda (input position)
           (%run-parser-sequence items input position)))))

(define-parser-function option (default parser) :option
  "Run PARSER, falling back to DEFAULT and consuming nothing when it fails
recoverably -- OPT with a caller-chosen absent value instead of NIL, so an
omitted clause can default to 0, an empty list, or any sentinel that is not
confusable with a parsed NIL.

A committed failure still propagates, so a half-consumed construct is never
silently swallowed."
  ;; Reuse OPT's exact recoverable machinery, only substituting DEFAULT for
  ;; NIL as the fallback value. A recoverable (non-committed, progressing-safe)
  ;; failure yields DEFAULT and consumes nothing; a committed failure still
  ;; propagates, so OPTION never silently swallows a half-consumed construct.
  (%run-parser-or-recoverable parser input position default))

(define-parser-function fail-parser (message &key (expected :failure)) :fail
  "A parser that always fails at the current position with MESSAGE.

Useful for turning a semantic guard into a parse error, e.g. inside an ALT
branch reached only when the input is structurally valid but disallowed. The
failure is non-committed, so an enclosing OPT/ALT may still recover from it."
  (declare (ignore input))
  (%failure position expected nil (list (error-diagnostic message))))

(defun as-value (value parser)
  "Run PARSER, discard its result, and yield the constant VALUE on success.

PARSER's input consumption and commit behaviour are preserved unchanged; only
the produced value is replaced. The applicative \"$>\" / \"replace\" operator."
  (map-parser parser
              (lambda (_result)
                (declare (ignore _result))
                value)))

(defun pure (value)
  "Alias for RETURN-PARSER: a parser that consumes no input and yields VALUE.

Named after the Applicative PURE so monadic/applicative code reads naturally
alongside SEQ-MAP and PARSE-LET*."
  (return-parser value))
