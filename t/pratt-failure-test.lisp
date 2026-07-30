(in-package :cl-parser-kit/test)

(it-sequential "pratt-unexpected-eof-test"
  (with-pratt-number-table (table)
    (let ((tokens #()))
      (assert-pratt-failure-values (parse-pratt tokens table)
          (value next failure)
        (expect next :to-equal 0)
        (expect (parse-failure-position failure) :to-equal 0)
        (expect (parse-failure-expected failure) :to-equal :expression)
        (expect (parse-failure-actual failure) :to-equal nil)
        (let ((diagnostic (first (parse-failure-diagnostics failure))))
        (expect diagnostic :to-be-truthy)
        (expect (span-start (diagnostic-span diagnostic)) :to-equal 0)
        (expect (span-end (diagnostic-span diagnostic)) :to-equal 0))))))

(it-sequential "pratt-infix-rhs-failure-propagates-test"
  (with-pratt-plus-table (table)
    (let ((tokens (vector (make-token :type :number :text "1" :value 1)
                          (make-token :type :plus :text "+")
                          (make-token :type :plus :text "+"))))
      (register-infix-operator table :plus 10 11
                               (lambda (left op right next current-table)
                                 (declare (ignore op right current-table))
                                 (values t left next nil)))
      (assert-pratt-failure-values (parse-pratt tokens table)
          (value next failure)
        (expect next :to-equal 2)
        (expect (parse-failure-expected failure) :to-equal :prefix)
        (expect (token-type (parse-failure-actual failure)) :to-equal :plus)))))

(it-sequential "pratt-infix-rhs-failure-recovers-line-columns-from-metadata-source-test"
  (assert-pratt-failure-values (%run-pratt-plus-rhs-metadata-failure)
      (value next failure)
    (expect next :to-equal 2)
    (let* ((diagnostic (first (parse-failure-diagnostics failure)))
           (rendered (diagnostic->string diagnostic)))
      (%assert-diagnostic-span diagnostic 3 1 3 2)
      (expect (search "EXPECTED PREFIX" (string-upcase rendered)) :to-be-truthy)
      (expect (search "3:1-3:2" rendered) :to-be-truthy)
      (expect (search "  | +" rendered) :to-be-truthy))))

(it-sequential "pratt-prefix-handler-failure-propagates-test"
  (with-pratt-number-table (table)
    (let* ((token (make-token :type :number :text "1" :value 1))
           (failure (make-parse-failure
                     :position 1
                     :expected :literal
                     :actual token
                     :diagnostics
                     (list (error-diagnostic "number literals are disabled"
                                             :span (make-span :start 0 :end 1)))))
           (tokens (vector token)))
      (register-prefix-operator table :number 0
                                (lambda (current-token stream next current-table)
                                  (declare (ignore current-token stream current-table))
                                  (values nil nil next failure)))
      (assert-pratt-failure-values (parse-pratt tokens table)
          (value next actual-failure)
        (expect next :to-equal 1)
        (%assert-pratt-failure-shape actual-failure 1 :literal :number)))))

(it-sequential "pratt-postfix-handler-failure-propagates-test"
  (with-pratt-number-table (table)
    (let* ((operator (make-token :type :bang :text "!"))
           (failure (make-parse-failure
                     :position 2
                     :expected :factorial-domain
                     :actual operator
                     :diagnostics
                     (list (error-diagnostic "factorial only accepts integers"
                                             :span (make-span :start 1 :end 2)))))
           (tokens (vector (make-token :type :number :text "2" :value 2)
                           operator)))
      (register-postfix-operator table :bang 30
                                 (lambda (left op stream next current-table)
                                   (declare (ignore left op stream current-table))
                                   (values nil nil next failure)))
      (assert-pratt-failure-values (parse-pratt tokens table)
          (value next actual-failure)
        (expect next :to-equal 2)
        (%assert-pratt-failure-shape actual-failure 2 :factorial-domain :bang)))))

(it-sequential "pratt-infix-handler-failure-propagates-test"
  (with-pratt-number-table (table)
    (let* ((operator (make-token :type :slash :text "/"))
           (failure (make-parse-failure
                     :position 3
                     :expected :non-zero-divisor
                     :actual operator
                     :diagnostics
                     (list (error-diagnostic "division by zero is not allowed"
                                             :span (make-span :start 1 :end 2)))))
           (tokens (vector (make-token :type :number :text "4" :value 4)
                           operator
                           (make-token :type :number :text "0" :value 0))))
      (register-infix-operator table :slash 20 21
                               (lambda (left op right next current-table)
                                 (declare (ignore left op current-table))
                                 (if (zerop right)
                                     (values nil nil next failure)
                                     (values t right next nil))))
      (assert-pratt-failure-values (parse-pratt tokens table)
          (value next actual-failure)
        (expect next :to-equal 3)
        (%assert-pratt-failure-shape actual-failure 3 :non-zero-divisor :slash)))))

(it-sequential "pratt-token-limit-failure-reports-the-requested-start-position-test"
  ;; PARSE-PRATT is the only entry point taking a caller-supplied :POSITION, so
  ;; it is the only one that can misreport it. It used to hand
  ;; %ENSURE-PARSER-TOKEN-VECTOR no position at all and return a literal 0,
  ;; placing a resource-limit failure at the start of the stream however far in
  ;; the caller had asked to begin.
  (with-pratt-number-table (table)
    (let ((*maximum-parser-tokens* 1)
          (tokens (vector (make-token :type :number :text "1" :value 1)
                          (make-token :type :number :text "2" :value 2)
                          (make-token :type :number :text "3" :value 3))))
      (assert-pratt-failure-values (parse-pratt tokens table :position 2)
          (value next failure)
        (expect next :to-equal 2)
        (expect (parse-failure-position failure) :to-equal 2)
        (expect (parse-failure-expected failure) :to-equal :maximum-parser-tokens)
        (expect (parse-failure-actual failure) :to-equal 3)))))

(it-sequential "pratt-infix-handler-controls-next-position-test"
  (with-pratt-number-table (table)
    (let* ((trailing (make-token :type :bang :text "!"))
           (tokens (vector (make-token :type :number :text "1" :value 1)
                           (make-token :type :plus :text "+")
                           (make-token :type :number :text "2" :value 2)
                           trailing)))
      (register-infix-operator table :plus 10 11
                               (lambda (left op right next current-table)
                                 (declare (ignore op current-table next))
                                 (values t (+ left right) 3 nil)))
      (assert-pratt-success-values (parse-pratt tokens table)
          (value next)
        (expect value :to-equal 3)
        (expect next :to-equal 3)
        (expect (aref tokens next) :to-equal trailing)))))
