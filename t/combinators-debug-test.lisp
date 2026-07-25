(in-package :cl-parser-kit/test)

;;; TRACE-PARSER ----------------------------------------------------------

(it-sequential "trace-parser-preserves-success-outcome-test"
  (let* ((tokens (vector (make-token :type :identifier :text "a")))
         (parser (trace-parser (type-token-text :identifier) :stream (make-broadcast-stream))))
    (assert-combinator-success (parse-tokens parser tokens)
        (value next failure)
      (expect value :to-equal "a")
      (expect next :to-equal 1))))

(it-sequential "trace-parser-preserves-failure-outcome-test"
  (let* ((tokens (vector (make-token :type :comma :text ",")))
         (parser (trace-parser (type-token :identifier) :stream (make-broadcast-stream))))
    (assert-combinator-failure (parse-tokens parser tokens)
        (value next failure)
      (expect (parse-failure-expected failure) :to-equal :identifier))))

(it-sequential "trace-parser-logs-success-with-default-label-test"
  ;; No :LABEL is given, so it defaults to PARSER's own NAME -- here
  ;; (TYPE-TOKEN :IDENTIFIER) names itself :IDENTIFIER (its EXPECTED-NAME).
  (let* ((tokens (vector (make-token :type :identifier :text "a")))
         (log (with-output-to-string (stream)
                (parse-tokens (trace-parser (type-token :identifier) :stream stream)
                              tokens))))
    (assert-string-contains-all log '("TRACE" "IDENTIFIER" "0" "1"))))

(it-sequential "trace-parser-logs-failure-with-custom-label-test"
  (let* ((tokens (vector (make-token :type :comma :text ",")))
         (log (with-output-to-string (stream)
                (parse-tokens (trace-parser (type-token :identifier)
                                            :label "IDENT" :stream stream)
                              tokens))))
    (assert-string-contains-all log '("TRACE" "IDENT" "failed" "IDENTIFIER"))))

(it-sequential "trace-parser-with-no-explicit-stream-follows-a-later-trace-output-rebind-test"
  ;; TRACE-PARSER is built once, with no :STREAM, well before *TRACE-OUTPUT* is
  ;; ever rebound -- proving STREAM is looked up fresh on each parse rather
  ;; than captured once when the parser object itself is constructed.
  (let* ((tokens (vector (make-token :type :identifier :text "a")))
         (parser (trace-parser (type-token :identifier))))
    (let ((log (with-output-to-string (*trace-output*)
                 (parse-tokens parser tokens))))
      (assert-string-contains-all log '("TRACE" "IDENTIFIER" "0" "1")))))
