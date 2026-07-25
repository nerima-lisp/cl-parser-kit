(in-package :cl-parser-kit)

;;;; Debugging aid.
;;;;
;;;; TRACE-PARSER is the one combinator in this library whose entire purpose is
;;;; a side effect: it never changes what PARSER parses, only prints what it did.

(define-parser-function trace-parser (parser &key (label (parser-name parser))
                                                    (stream *trace-output*))
    :trace
  "Run PARSER unchanged, printing one line to STREAM reporting its outcome, then
return exactly what PARSER returned.

LABEL identifies the traced parser in the printed line, defaulting to PARSER's
own NAME; STREAM defaults to *TRACE-OUTPUT*, so redirecting that one special
turns tracing on or off for every TRACE-PARSER in a grammar without touching
the combinators themselves. A pure debugging aid megaparsec calls `dbg` --
wrap the one sub-parser under suspicion, not the whole grammar, since every
traced call pays for the FORMAT."
  (multiple-value-bind (ok value next result) (%run-parser-on-token-vector parser input position)
    (if ok
        (format stream "~&TRACE ~A: ~D -> ~D, value ~S~%" label position next value)
        (format stream "~&TRACE ~A: ~D failed, expected ~S actual ~S~%"
                label position (parse-failure-expected result) (parse-failure-actual result)))
    (values ok value next result)))
