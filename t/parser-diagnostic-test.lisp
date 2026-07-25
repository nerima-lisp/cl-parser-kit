(in-package :cl-parser-kit/test)

(it-sequential "parse-failure-span-returns-actual-token-span-test"
  ;; A failure whose actual is a token exposes that token's span for rendering.
  (let* ((tokens (vector (make-token :type :number :text "1" :value 1 :start 0 :end 1)))
         (parser (type-token :identifier)))
    (assert-combinator-failure (parse-tokens parser tokens)
        (value next failure)
      (let ((span (parse-failure-span failure)))
        (expect (typep span 'span) :to-be-truthy)
        (expect (span-start span) :to-equal 0)
        (expect (span-end span) :to-equal 1)))))

(it-sequential "parse-failure-span-is-nil-at-end-of-input-test"
  ;; At EOF the actual is :EOF, not a token, so there is no span.
  (let ((parser (type-token :identifier)))
    (assert-combinator-failure (parse-tokens parser #())
        (value next failure)
      (expect (parse-failure-actual failure) :to-equal :eof)
      (expect (parse-failure-span failure) :to-be-falsy))))

(it-sequential "parse-all-trailing-token-test"
  (with-parser-tokens ("answer + 1" *identifier-plus-number-rule-specs*)
      (tokenizer tokens)
    (let ((parser (type-token :identifier)))
      (assert-parser-failure (parse-all parser tokens)
          (value next failure)
        (expect next :to-equal 1)
        (expect (parse-failure-expected failure) :to-equal :eoi)
        (expect (token-type (parse-failure-actual failure)) :to-equal :plus)
        (%assert-trailing-token-diagnostic failure "answer + 1" "^" "^")))))

(it-sequential "parse-all-trailing-token-without-span-test"
  (let* ((tokens (vector (make-token :type :identifier :text "answer")
                         (make-token :type :plus :text "+")))
         (parser (type-token :identifier)))
    (assert-parser-failure (parse-all parser tokens)
        (value next failure)
      (expect next :to-equal 1)
      (expect (token-type (parse-failure-actual failure)) :to-equal :plus)
      (%assert-trailing-token-diagnostic failure nil "1:2-1:2" nil))))

(it-sequential "parse-all-trailing-token-falls-back-to-token-offsets-test"
  (let* ((tokens (vector (make-token :type :identifier :text "answer" :start 0 :end 6)
                         (make-token :type :plus :text "+" :start 7 :end 8)))
         (parser (type-token :identifier)))
    (assert-parser-failure (parse-all parser tokens)
        (value next failure)
      (expect next :to-equal 1)
      (expect (token-type (parse-failure-actual failure)) :to-equal :plus)
      (%assert-trailing-token-diagnostic failure nil "1:8-1:9" nil))))

(it-sequential "parse-all-trailing-token-recovers-line-columns-from-metadata-source-test"
  (let* ((source "answer
+")
         (tokens (vector (make-token :type :identifier
                                     :text "answer"
                                     :start 0
                                     :end 6
                                     :metadata (list :source source))
                         (make-token :type :plus
                                     :text "+"
                                     :start 7
                                     :end 8
                                     :metadata (list :source source))))
         (parser (type-token :identifier)))
    (assert-parser-failure (parse-all parser tokens)
        (value next failure)
      (expect next :to-equal 1)
      (let* ((diagnostic (first (parse-failure-diagnostics failure)))
             (rendered (diagnostic->string diagnostic)))
        (%assert-diagnostic-span diagnostic 2 1 2 2)
        (expect (search "2:1-2:2" rendered) :to-be-truthy)
        (expect (search "  | +" rendered) :to-be-truthy)))))
