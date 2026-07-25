(in-package :cl-parser-kit/test)

(defparameter *single-foo-token-vector* (vector (make-token :type :identifier :text "foo")
                         (make-token :type :comma :text ",")
                         (make-token :type :identifier :text "bar")
                         (make-token :type :comma :text ",")
                         (make-token :type :identifier :text "baz")))

(it-sequential "combinator-sep-by1-test"
  (let* ((tokens *single-foo-token-vector*)
         (parser (sep-by1 (type-token :identifier)
                          (type-token :comma))))
    (assert-combinator-projected-values (parse-tokens parser tokens)
        (value next failure)
        5
        '("foo" "bar" "baz")
        #'token-text)))

(it-sequential "combinator-sep-by-test"
  (let* ((tokens (vector (make-token :type :identifier :text "foo")
                         (make-token :type :comma :text ",")
                         (make-token :type :identifier :text "bar")
                         (make-token :type :plus :text "+")))
         (parser (sep-by (type-token :identifier)
                         (type-token :comma))))
    (assert-combinator-projected-values (parse-tokens parser tokens)
        (value next failure)
        3
        '("foo" "bar")
        #'token-text))
  (let ((parser (sep-by (type-token :identifier)
                        (type-token :comma))))
    (assert-combinator-success (parse-tokens parser #())
        (value next failure)
      (expect value :to-equal '())
      (expect next :to-equal 0))))

(it-sequential "combinator-sep-by-trailing-separator-fails-test"
  (let* ((tokens (vector (make-token :type :identifier :text "foo")
                         (make-token :type :comma :text ",")))
         (parser (sep-by1 (type-token :identifier)
                          (type-token :comma))))
    (assert-separator-combinator-failure (parse-tokens parser tokens)
                                         2
                                         :identifier
                                         :eof)))

(it-sequential "combinator-sep-by1-rejects-non-advancing-separator-test"
  (let* ((tokens (vector (make-token :type :identifier :text "foo")))
         (separator-parser (return-parser :separator))
         (parser (sep-by1 (type-token :identifier) separator-parser)))
    (assert-separator-combinator-failure (parse-tokens parser tokens)
                                         1
                                         :progressing-parser
                                         :return)))

(it-sequential "combinator-sep-by-propagates-committed-failure-test"
  (let* ((tokens (vector (make-token :type :identifier :text "foo")
                         (make-token :type :comma :text ",")))
         (parser (sep-by (type-token :identifier)
                          (type-token :comma))))
    (assert-separator-combinator-failure (parse-tokens parser tokens)
                                         2
                                         :identifier
                                         :eof)))

(it-sequential "combinator-sep-end-by1-allows-trailing-separator-test"
  (let* ((tokens (vector (make-token :type :identifier :text "foo")
                         (make-token :type :comma :text ",")
                         (make-token :type :identifier :text "bar")
                         (make-token :type :comma :text ",")))
         (parser (sep-end-by1 (type-token :identifier)
                              (type-token :comma))))
    (assert-combinator-projected-values (parse-tokens parser tokens)
        (value next failure)
        4
        '("foo" "bar")
        #'token-text)))

(it-sequential "combinator-sep-end-by1-rejects-non-advancing-separator-test"
  (let* ((tokens (vector (make-token :type :identifier :text "foo")))
         (separator-parser (return-parser :separator))
         (parser (sep-end-by1 (type-token :identifier) separator-parser)))
    (assert-separator-combinator-failure (parse-tokens parser tokens)
                                         1
                                         :progressing-parser
                                         :return)))

(it-sequential "combinator-sep-end-by1-rejects-non-advancing-item-after-separator-test"
  (let* ((tokens (vector (make-token :type :identifier :text "foo")
                         (make-token :type :comma :text ",")))
         (parser (sep-end-by1 (return-parser :item)
                              (type-token :comma))))
    (assert-separator-combinator-failure (run-parser parser tokens 0)
                                         0
                                         :progressing-parser
                                         :return)))

(it-sequential "combinator-sep-end-by-allows-empty-input-test"
  (let ((parser (sep-end-by (type-token :identifier)
                            (type-token :comma))))
    (assert-combinator-success (parse-tokens parser #()) (value next failure)
      (expect value :to-equal '())
      (expect next :to-equal 0))))

(it-sequential "combinator-sep-end-by1-propagates-committed-failure-test"
  (let* ((tokens (vector (make-token :type :identifier :text "foo")
                         (make-token :type :number :text "1" :value 1)
                         (make-token :type :comma :text ",")
                         (make-token :type :identifier :text "bar")))
         (parser (sep-end-by1 (seq (type-token :identifier)
                                    (type-token :number))
                                 (type-token :comma))))
    (assert-separator-combinator-failure (parse-tokens parser tokens)
                                         4
                                         :number
                                         :eof)))

(it-sequential "combinator-sep-end-by-preserves-recoverable-diagnostics-test"
  (with-combinator-tokens (tokens *positioned-identifier-comma-token-specs*)
    (let ((parser (sep-end-by (lookahead (seq (type-token :identifier)
                                              (end-of-input)))
                              (type-token :comma))))
      (assert-combinator-success (run-parser parser tokens 0)
          (value next diagnostics)
        (expect value :to-equal '())
        (expect next :to-equal 0)
        (%assert-rendered-diagnostic-contains (first diagnostics)
                                              "Unexpected trailing token"
                                              "1:4-1:5")))))

(it-sequential "combinator-sep-by-allows-non-consuming-lookahead-failure-test"
  (with-combinator-tokens (tokens *identifier-comma-token-specs*)
    (let ((parser (sep-by (lookahead (seq (type-token :identifier)
                                          (type-token :plus)))
                          (type-token :comma))))
      (assert-combinator-success (parse-tokens parser tokens)
          (value next failure)
        (expect value :to-equal '())
        (expect next :to-equal 0)))))

(it-sequential "combinator-sep-by-preserves-recoverable-diagnostics-test"
  (with-combinator-tokens (tokens *positioned-identifier-comma-token-specs*)
    (let ((parser (sep-by (lookahead (seq (type-token :identifier)
                                          (end-of-input)))
                          (type-token :comma))))
      (assert-combinator-success (run-parser parser tokens 0)
          (value next diagnostics)
        (expect value :to-equal '())
        (expect next :to-equal 0)
        (%assert-single-diagnostic diagnostics
                                   "Unexpected trailing token"
                                   "1:4-1:5")))))

;;; SEP-BY-BETWEEN / SEP-BY-AT-LEAST / SEP-BY-AT-MOST -------------------------

(it-sequential "combinator-sep-by-between-is-greedy-up-to-max-test"
  (let ((tokens *single-foo-token-vector*))
    (let ((parser (sep-by-between 1 2 (type-token-text :identifier)
                                  (type-token :comma))))
      (assert-combinator-success (parse-tokens parser tokens)
          (value next failure)
        (expect next :to-equal 3)
        (expect value :to-equal '("foo" "bar"))))))

(it-sequential "combinator-sep-by-between-fails-below-min-test"
  ;; *SINGLE-FOO-TOKEN-VECTOR* has exactly 3 items ("foo" "bar" "baz"); with
  ;; MIN 4 the shortfall is discovered where a 4th SEPARATOR would have to
  ;; start, not where a 4th item would -- SEP-BY-BETWEEN always needs a
  ;; SEPARATOR before it tries another item.
  (let ((tokens *single-foo-token-vector*))
    (let ((parser (sep-by-between 4 5 (type-token :identifier)
                                  (type-token :comma))))
      (assert-combinator-failure (parse-tokens parser tokens)
          (value next failure)
        (expect (parse-failure-committed-p failure) :to-be-truthy)
        (expect (parse-failure-expected failure) :to-equal :comma)))))

(it-sequential "combinator-sep-by-between-allows-zero-when-min-is-zero-test"
  (let ((parser (sep-by-between 0 3 (type-token :identifier)
                                (type-token :comma))))
    (assert-combinator-success (parse-tokens parser #())
        (value next failure)
      (expect next :to-equal 0)
      (expect value :to-be-falsy))))

(it-sequential "combinator-sep-by-between-zero-max-succeeds-without-running-parser-test"
  (with-combinator-tokens (tokens '((:type :identifier :text "a")))
    (let ((parser (sep-by-between 0 0 (type-token :identifier)
                                  (type-token :comma))))
      (assert-combinator-success (parse-tokens parser tokens)
          (value next failure)
        (expect next :to-equal 0)
        (expect value :to-be-falsy)))))

(it-sequential "combinator-sep-by-between-item-failure-after-separator-is-committed-test"
  (with-combinator-tokens (tokens '((:type :identifier :text "a")
                                    (:type :comma :text ",")
                                    (:type :comma :text ",")))
    (let ((parser (sep-by-between 1 3 (type-token :identifier)
                                  (type-token :comma))))
      (assert-combinator-failure (parse-tokens parser tokens)
          (value next failure)
        (expect (parse-failure-committed-p failure) :to-be-truthy)
        (expect (parse-failure-expected failure) :to-equal :identifier)))))

(it-sequential "combinator-sep-by-between-rejects-excessive-max-test"
  (let ((*maximum-parser-repetition-count* 2))
    (expect (lambda () (sep-by-between 0 3 (type-token :identifier) (type-token :comma)))
            :to-throw 'error)))

(it-sequential "combinator-sep-by-between-rejects-min-greater-than-max-test"
  (expect (lambda () (sep-by-between 3 1 (type-token :identifier) (type-token :comma)))
          :to-throw 'error))

(it-sequential "combinator-sep-by-between-fails-when-first-item-is-entirely-missing-test"
  ;; With no tokens at all and MIN > 0, the very first PARSER call inside
  ;; %RUN-PROGRESSING-PARSER/CPS fails outright, before any SEPARATOR is ever
  ;; tried -- SEP-BY-BETWEEN's own failure branch, distinct from (and reached
  ;; before) %RUN-BOUNDED-SEPARATED-ITEMS's separate MIN check exercised by
  ;; combinator-sep-by-between-fails-below-min-test above.
  (let ((parser (sep-by-between 1 3 (type-token :identifier) (type-token :comma))))
    (assert-combinator-failure (parse-tokens parser #())
        (value next failure)
      (expect (parse-failure-expected failure) :to-equal :identifier))))

(it-sequential "combinator-sep-by-at-least-zero-is-sep-by-test"
  (let ((parser (sep-by-at-least 0 (type-token :identifier) (type-token :comma))))
    (assert-combinator-success (parse-tokens parser #())
        (value next failure)
      (expect next :to-equal 0)
      (expect value :to-be-falsy))))

(it-sequential "combinator-sep-by-at-least-requires-minimum-with-no-upper-bound-test"
  (let ((tokens *single-foo-token-vector*))
    (let ((parser (sep-by-at-least 2 (type-token-text :identifier) (type-token :comma))))
      (assert-combinator-success (parse-tokens parser tokens)
          (value next failure)
        (expect next :to-equal 5)
        (expect value :to-equal '("foo" "bar" "baz")))))
  (let ((tokens *single-foo-token-vector*))
    (let ((parser (sep-by-at-least 4 (type-token :identifier) (type-token :comma))))
      (assert-combinator-failure (parse-tokens parser tokens)
          (value next failure)
        (expect (parse-failure-committed-p failure) :to-be-truthy)))))

(it-sequential "combinator-sep-by-at-least-rejects-excessive-min-test"
  ;; Unlike SEP-BY-BETWEEN (whose MAX check also bounds MIN via MIN <= MAX),
  ;; SEP-BY-AT-LEAST has no MAX at all, so it must validate MIN itself against
  ;; *MAXIMUM-PARSER-REPETITION-COUNT* directly, matching every other bounded
  ;; repetition combinator's resource-limit contract.
  (let ((*maximum-parser-repetition-count* 2))
    (expect (lambda () (sep-by-at-least 3 (type-token :identifier) (type-token :comma)))
            :to-throw 'error)))

(it-sequential "combinator-sep-by-at-most-caps-repetitions-test"
  (let ((tokens *single-foo-token-vector*))
    (let ((parser (sep-by-at-most 2 (type-token-text :identifier) (type-token :comma))))
      (assert-combinator-success (parse-tokens parser tokens)
          (value next failure)
        (expect next :to-equal 3)
        (expect value :to-equal '("foo" "bar"))))))
