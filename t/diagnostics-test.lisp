(in-package :cl-parser-kit/test)

(it-sequential "parse-failure-merge-test"
  (let ((left (make-parse-failure :position 1 :expected '(:number) :actual :plus))
        (right (make-parse-failure :position 1 :expected '(:identifier) :actual :plus)))
    (let ((merged (merge-parse-failures left right)))
      (expect (parse-failure-position merged) :to-equal 1)
      (expect (sort (copy-list (parse-failure-expected merged)) #'string< :key #'symbol-name) :to-equal '(:identifier :number))
      (expect (parse-failure-actual merged) :to-equal :plus))))

(it-sequential "parse-failure-merge-with-no-expected-items-skips-dedup-hash-test"
  ;; Both failures' EXPECTED lists are NIL here, exercising
  ;; %MERGE-PARSE-FAILURE-LISTS-UNIQUE's fast path that skips building a
  ;; dedup hash table entirely when there is nothing to deduplicate.
  (let ((left (make-parse-failure :position 1 :actual :plus))
        (right (make-parse-failure :position 1 :actual :plus)))
    (let ((merged (merge-parse-failures left right)))
      (expect (parse-failure-position merged) :to-equal 1)
      (expect (parse-failure-expected merged) :to-be-falsy))))

(it-sequential "parse-failure-merge-deduplicates-overlapping-expected-items-test"
  ;; %MERGE-PARSE-FAILURE-LISTS-UNIQUE's dedup hash must actually skip an item
  ;; it has already seen -- :IDENTIFIER appears in both failures' EXPECTED
  ;; lists here, so the merged result must list it only once.
  (let ((left (make-parse-failure :position 1 :expected '(:number :identifier) :actual :plus))
        (right (make-parse-failure :position 1 :expected '(:identifier :string) :actual :plus)))
    (let ((merged (merge-parse-failures left right)))
      (expect (sort (copy-list (parse-failure-expected merged)) #'string< :key #'symbol-name)
              :to-equal '(:identifier :number :string)))))

(it-sequential "parse-failure-merge-prefers-farthest-position-test"
  (let ((near (make-parse-failure :position 2 :expected :identifier :actual :plus))
        (far (make-parse-failure :position 5 :expected :number :actual :minus)))
    (let ((merged (merge-parse-failures near far)))
      (expect (parse-failure-position merged) :to-equal 5)
      (expect (parse-failure-expected merged) :to-equal :number)
      (expect (parse-failure-actual merged) :to-equal :minus))))

(it-sequential "parse-failure-merge-preserves-commit-and-diagnostics-test"
  (let* ((left-diagnostic (error-diagnostic "expected number"))
         (right-diagnostic (note-diagnostic "after prefix operator"))
         (left (make-parse-failure :position 3
                                   :expected :number
                                   :actual :plus
                                   :diagnostics (list left-diagnostic)))
         (right (make-parse-failure :position 3
                                    :expected :identifier
                                    :actual :plus
                                    :diagnostics (list right-diagnostic)
                                    :committed-p t)))
    (let ((merged (merge-parse-failures left right)))
      (expect (parse-failure-committed-p merged) :to-be-truthy)
      (expect (parse-failure-diagnostics merged) :to-equal (list left-diagnostic right-diagnostic)))))

(it-sequential "parse-failure-merge-rejects-excessive-expected-list-test"
  (let ((*maximum-parse-failure-expected-count* 2)
        (left (make-parse-failure :position 1 :expected '(:one :two) :actual :plus))
        (right (make-parse-failure :position 1 :expected :three :actual :plus)))
    (expect (lambda () (merge-parse-failures left right))
            :to-throw 'parse-failure-resource-limit-exceeded)))

(it-sequential "parse-failure-merge-rejects-improper-expected-list-test"
  (let ((left (make-parse-failure :position 1 :expected (cons :one :two) :actual :plus))
        (right (make-parse-failure :position 1 :expected :three :actual :plus)))
    (expect (lambda () (merge-parse-failures left right))
            :to-throw 'parse-failure-resource-limit-exceeded)))

(it-sequential "parse-failure-merge-rejects-excessive-diagnostic-list-test"
  (let* ((*maximum-parse-failure-diagnostic-count* 2)
         (left (make-parse-failure :position 1
                                   :expected :identifier
                                   :actual :plus
                                   :diagnostics (list (error-diagnostic "one")
                                                      (error-diagnostic "two"))))
         (right (make-parse-failure :position 1
                                    :expected :number
                                    :actual :plus
                                    :diagnostics (list (error-diagnostic "three")))))
    (expect (lambda () (merge-parse-failures left right))
            :to-throw 'parse-failure-resource-limit-exceeded)))

(it-sequential "parse-failure-merge-rejects-improper-diagnostic-list-test"
  (let ((left (make-parse-failure :position 1
                                  :expected :identifier
                                  :actual :plus
                                  :diagnostics (cons (error-diagnostic "one")
                                                     (error-diagnostic "two"))))
        (right (make-parse-failure :position 1
                                   :expected :number
                                   :actual :plus)))
    (expect (lambda () (merge-parse-failures left right))
            :to-throw 'parse-failure-resource-limit-exceeded)))

(it-sequential "parse-failure-public-accessor-contract-test"
  (let* ((diagnostic (warning-diagnostic "recoverable"))
         (failure (make-parse-failure :position 4
                                      :expected '(:identifier :number)
                                      :actual :plus
                                      :diagnostics (list diagnostic)
                                      :committed-p t)))
    (expect (typep failure 'parse-failure) :to-be-truthy)
    (expect (parse-failure-position failure) :to-equal 4)
    (expect (parse-failure-expected failure) :to-equal '(:identifier :number))
    (expect (parse-failure-actual failure) :to-equal :plus)
    (expect (parse-failure-diagnostics failure) :to-equal (list diagnostic))
    (expect (parse-failure-committed-p failure) :to-be-truthy)))

(it-sequential "diagnostic-public-accessor-contract-test"
  (let* ((span (make-span :source "abc"
                          :start 1 :end 2
                          :start-line 1 :start-column 2
                          :end-line 1 :end-column 3))
         (note (note-diagnostic "context" :span span))
         (fix (make-fix-it :span span :replacement "z"))
         (diagnostic (make-diagnostic :kind :warning
                                      :message "problem"
                                      :span span
                                      :notes (list note)
                                      :fixes (list fix)
                                      :data '(:origin :test)))
         (warning (warning-diagnostic "warn" :span span)))
    (expect (diagnostic-kind diagnostic) :to-equal :warning)
    (expect (diagnostic-message diagnostic) :to-equal "problem")
    (expect (diagnostic-span diagnostic) :to-equal span)
    (expect (diagnostic-notes diagnostic) :to-equal (list note))
    (expect (diagnostic-fixes diagnostic) :to-equal (list fix))
    (expect (diagnostic-data diagnostic) :to-equal '(:origin :test))
    (expect (fix-it-span fix) :to-equal span)
    (expect (fix-it-replacement fix) :to-equal "z")
    (expect (diagnostic-kind warning) :to-equal :warning)
    (expect (diagnostic-message warning) :to-equal "warn")))
