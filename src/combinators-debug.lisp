(in-package :cl-parser-kit)

;;;; Debugging aid.
;;;;
;;;; TRACE-PARSER is the one combinator in this library whose entire purpose is
;;;; a side effect: it never changes what PARSER parses, only prints what it did.

(define-parser-function trace-parser (parser &key (label (parser-name parser))
                                                    (stream nil stream-supplied-p))
    :trace
  "Run PARSER unchanged, printing one line to STREAM reporting its outcome, then
return exactly what PARSER returned.

LABEL identifies the traced parser in the printed line, defaulting to PARSER's
own NAME. When STREAM is not supplied, each parse looks up *TRACE-OUTPUT*
afresh -- rather than capturing it once when TRACE-PARSER builds the parser
object -- so redirecting that one special still turns tracing on or off for
every already-built TRACE-PARSER in a grammar, including one constructed long
before the parse it now traces. Pass STREAM explicitly to pin tracing to a
fixed destination instead. A pure debugging aid megaparsec calls `dbg` -- wrap
the one sub-parser under suspicion, not the whole grammar, since every traced
call pays for the FORMAT."
  (let ((stream (if stream-supplied-p stream *trace-output*)))
    (multiple-value-bind (ok value next result) (%run-parser-on-token-vector parser input position)
      (if ok
          (format stream "~&TRACE ~A: ~D -> ~D, value ~S~%" label position next value)
          (format stream "~&TRACE ~A: ~D failed, expected ~S actual ~S~%"
                  label position (parse-failure-expected result) (parse-failure-actual result)))
      (values ok value next result))))
