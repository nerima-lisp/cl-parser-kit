(in-package :cl-parser-kit/test)

(it-sequential "parse-failure-string-joins-three-or-more-expected-items-test"
  ;; Exercises the comma-joined branch of the expected-item formatter (2-item
  ;; "X or Y" is covered elsewhere; 3+ items use a distinct code path).
  (let ((failure (make-parse-failure :position 0
                                     :expected '(:identifier :number :string)
                                     :actual :plus)))
    (assert-rendered-contains-all
     (parse-failure->string failure)
     '("one of IDENTIFIER, NUMBER, STRING" "got PLUS"))))

(it-sequential "parse-failure-diagnostics-synthesizes-default-test"
  ;; A failure with no attached diagnostics yields one synthesized error
  ;; diagnostic carrying the failure's data.
  (let* ((failure (make-parse-failure :position 0 :expected :identifier :actual :plus))
         (diagnostics (parse-failure->diagnostics failure)))
    (expect (length diagnostics) :to-equal 1)
    (expect (diagnostic-kind (first diagnostics)) :to-equal :error)
    (expect (search "Expected IDENTIFIER" (diagnostic-message (first diagnostics)))
            :to-be-truthy)))

(it-sequential "parse-failure-diagnostics-synthesizes-default-when-diagnostics-are-all-nil-test"
  ;; A failure whose DIAGNOSTICS field is a non-empty list of nothing but NIL
  ;; entries (a legitimate input elsewhere -- NIL entries are always tolerated
  ;; and skipped, per DIAGNOSTICS->STRING's contract) still synthesizes a
  ;; default diagnostic instead of crashing when %PARSE-FAILURE-DEFAULT-SPAN
  ;; looks for a span to borrow from the (filtered-to-empty) list.
  (let* ((failure (make-parse-failure :position 0 :expected :identifier :actual :plus
                                      :diagnostics (list nil nil)))
         (diagnostics (parse-failure->diagnostics failure)))
    (expect (length diagnostics) :to-equal 1)
    (expect (diagnostic-kind (first diagnostics)) :to-equal :error)
    (expect (diagnostic-span (first diagnostics)) :to-be-falsy)))

(it-sequential "parse-failure-diagnostics-returns-attached-diagnostics-test"
  ;; When the failure already carries diagnostics, those are returned verbatim.
  (let* ((note (error-diagnostic "custom problem"))
         (failure (make-parse-failure :position 0 :expected :identifier :actual :plus
                                      :diagnostics (list note)))
         (diagnostics (parse-failure->diagnostics failure)))
    (expect diagnostics :to-equal (list note))))

(it-sequential "parse-failure-expected-count-limit-caps-rendering-test"
  (let ((*maximum-parse-failure-expected-count* 2)
        (failure (make-parse-failure :position 0
                                     :expected '(:one :two :three)
                                     :actual :plus)))
    (expect (lambda () (parse-failure->string failure))
            :to-throw 'parse-failure-resource-limit-exceeded)))

(it-sequential "parse-failure-expected-count-limit-caps-circular-rendering-test"
  (let ((*maximum-parse-failure-expected-count* 2)
        (failure (make-parse-failure :position 0
                                     :expected (%circular-list :one :two)
                                     :actual :plus)))
    (expect (lambda () (parse-failure->string failure))
            :to-throw 'parse-failure-resource-limit-exceeded)))

(it-sequential "parse-failure-expected-list-rejects-improper-rendering-test"
  (let ((failure (make-parse-failure :position 0
                                     :expected (cons :one :two)
                                     :actual :plus)))
    (expect (lambda () (parse-failure->string failure))
            :to-throw 'parse-failure-resource-limit-exceeded)))

(it-sequential "parse-failure-diagnostic-count-limit-caps-rendering-test"
  (let* ((*maximum-parse-failure-diagnostic-count* 2)
         (failure (make-parse-failure
                   :position 0
                   :expected :identifier
                   :actual :plus
                   :diagnostics (list (error-diagnostic "one")
                                      (error-diagnostic "two")
                                      (error-diagnostic "three")))))
    (expect (lambda () (parse-failure->diagnostics failure))
            :to-throw 'parse-failure-resource-limit-exceeded)))

(it-sequential "parse-failure-diagnostic-count-limit-caps-circular-rendering-test"
  (let* ((*maximum-parse-failure-diagnostic-count* 2)
         (failure (make-parse-failure
                   :position 0
                   :expected :identifier
                   :actual :plus
                   :diagnostics (%circular-list (error-diagnostic "one")
                                               (error-diagnostic "two")))))
    (expect (lambda () (parse-failure->diagnostics failure))
            :to-throw 'parse-failure-resource-limit-exceeded)))

(it-sequential "parse-failure-diagnostic-list-rejects-improper-rendering-test"
  (let ((failure (make-parse-failure
                  :position 0
                  :expected :identifier
                  :actual :plus
                  :diagnostics (cons (error-diagnostic "one")
                                     (error-diagnostic "two")))))
    (expect (lambda () (parse-failure->diagnostics failure))
            :to-throw 'parse-failure-resource-limit-exceeded)))

(it-sequential "diagnostics-string-renders-list-test"
  (let* ((first-diagnostic (error-diagnostic "first problem"))
         (second-diagnostic (warning-diagnostic "second problem"))
         (rendered (diagnostics->string (list first-diagnostic nil second-diagnostic))))
    (expect (search "first problem" rendered) :to-be-truthy)
    (expect (search "second problem" rendered) :to-be-truthy)))

(it-sequential "diagnostics-string-renders-nothing-for-an-empty-list-test"
  ;; %WRITE-DIAGNOSTICS's own CONSP check takes its non-list branch for an
  ;; empty (NIL) diagnostics list -- distinct from a list of NIL entries,
  ;; which is still a CONS -- and must render an empty string, not error.
  (expect (diagnostics->string nil) :to-equal ""))

(it-each ((:mixed) (:all-nil) (:circular-nil) (:improper))
    "diagnostics-string-count-limit-~(~A~)-diagnostic-list-test"
    (variant)
  ;; Every variant below is a different malformed shape hitting the same
  ;; *MAXIMUM-DIAGNOSTIC-COUNT* resource-limit assertion.
  (let ((*maximum-diagnostic-count* 2)
        (diagnostics (ecase variant
                       (:mixed (list (error-diagnostic "one") nil
                                     (warning-diagnostic "two") (note-diagnostic "three")))
                       (:all-nil (list nil nil nil))
                       (:circular-nil (%circular-list nil nil))
                       (:improper (cons (error-diagnostic "one") :tail)))))
    (expect (lambda () (diagnostics->string diagnostics))
            :to-throw 'diagnostic-resource-limit-exceeded)))

(it-sequential "parse-failure-string-renders-token-and-string-expectations-test"
  ;; A type-less token falls back to its printed text, and a raw string
  ;; expectation passes through unchanged.
  (let ((failure (make-parse-failure
                  :position 0
                  :expected "a binding name"
                  :actual (make-token :type nil :text "foo" :start 0 :end 3))))
    (assert-rendered-contains-all
     (parse-failure->string failure)
     '("Expected a binding name" "\"foo\""))))

(it-sequential "parse-failure-string-test"
  (let* ((diagnostic (error-diagnostic "bad token"
                                       :span (make-span :source "foo + bar"
                                                        :start 0 :end 3 :start-line 1 :start-column 1
                                                        :end-line 1 :end-column 2)))
         (failure (make-parse-failure :position 0
                                      :expected :identifier
                                      :actual :plus
                                      :diagnostics (list diagnostic))))
    (assert-rendered-contains-all
     (parse-failure->string failure)
     '("bad token" "foo + bar"))))

(it-sequential "parse-failure-string-fallback-test"
  (dolist (case
           (list
            (list (make-parse-failure :position 1
                                      :expected '(:identifier :number)
                                      :actual (make-token :type :plus
                                                          :text "+"
                                                          :start 7
                                                          :end 8
                                                          :metadata (list :source "answer
+")))
                  '("Expected one of IDENTIFIER or NUMBER, got PLUS"
                    "2:1-2:2"
                    "+"
                    "^"))
            (list (make-parse-failure :position 1
                                      :expected '(:identifier :number)
                                      :actual (make-token :type :plus
                                                          :text "+"
                                                          :start 8
                                                          :end 9
                                                          :metadata (list :source (format nil "answer~C~C+"
                                                                                           #\Return
                                                                                           #\Newline))))
                  '("Expected one of IDENTIFIER or NUMBER, got PLUS"
                    "2:1-2:2"
                    "+"
                    "^"))))
    (destructuring-bind (failure snippets) case
      (assert-rendered-contains-all (parse-failure->string failure) snippets))))

(it-sequential "parse-failure-string-fallback-eof-test"
  (let ((failure (make-parse-failure :position 4
                                     :expected :identifier
                                     :actual nil)))
    (let ((text (parse-failure->string failure)))
      (expect (search "Expected IDENTIFIER, got EOF" text) :to-be-truthy)
      (expect (search "[" text) :to-be-falsy))))

(it-sequential "parse-failure-string-renders-unknown-input-for-an-empty-expected-list-test"
  ;; %PARSE-FAILURE-EXPECTED-STRING falls back to "unknown input" when EXPECTED
  ;; renders to no items at all.
  (let ((failure (make-parse-failure :position 0 :expected nil :actual :plus)))
    (expect (search "Expected unknown input" (parse-failure->string failure))
            :to-be-truthy)))

(it-sequential "parse-failure-string-renders-a-non-standard-actual-item-test"
  ;; %PARSE-FAILURE-ITEM->STRING's TYPECASE falls back to PRIN1-TO-STRING for an
  ;; ACTUAL that is neither NULL, a TOKEN, a SYMBOL, nor a STRING.
  (let ((failure (make-parse-failure :position 0 :expected :number :actual 42)))
    (expect (search "got 42" (parse-failure->string failure)) :to-be-truthy)))

(it-sequential "parse-failure-string-renders-a-typeless-token-by-its-text-test"
  ;; %PARSE-FAILURE-TOKEN-STRING falls back to the token's (PRIN1-TO-STRING TEXT)
  ;; when it has text but no TOKEN-TYPE.
  (let ((failure (make-parse-failure
                  :position 0 :expected :number
                  :actual (make-token :type nil :text "??"))))
    (expect (search "got \"??\"" (parse-failure->string failure)) :to-be-truthy)))

(it-sequential "parse-failure-string-renders-a-typeless-textless-token-as-token-fallback-test"
  ;; %PARSE-FAILURE-TOKEN-STRING falls all the way back to the literal "TOKEN"
  ;; when the token has neither a TOKEN-TYPE nor TEXT to fall back on.
  (let ((failure (make-parse-failure
                  :position 0 :expected :number
                  :actual (make-token :type nil :text nil))))
    (expect (search "got TOKEN" (parse-failure->string failure)) :to-be-truthy)))

(it-sequential "parse-failure-string-ignores-nil-diagnostics-test"
  (let* ((diagnostic (error-diagnostic "bad token"
                                       :span (make-span :source "foo"
                                                        :start 0 :end 3
                                                        :start-line 1 :start-column 1
                                                        :end-line 1 :end-column 4)))
         (failure (make-parse-failure :position 0
                                     :expected :identifier
                                     :actual :plus
                                     :diagnostics (list nil diagnostic))))
    (assert-rendered-contains-all
     (parse-failure->string failure)
     '("bad token" "foo"))))
