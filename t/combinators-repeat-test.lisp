(in-package :cl-parser-kit/test)

(defun %number-tokens (&rest values)
  (coerce (mapcar (lambda (value)
                    (make-token :type :number
                                :text (princ-to-string value)
                                :value value))
                  values)
          'vector))

(defparameter *number-value* (type-token-value :number))

(defparameter *minus-operator*
  (operator-parser (type-token :minus)
                   (lambda (left right) (- left right))))

;;; TIMES ---------------------------------------------------------------------

(it-sequential "combinator-times-parses-exactly-n-test"
  (let ((tokens (%number-tokens 1 2 3))
        (parser (times 2 (type-token-value :number))))
    (assert-combinator-success (parse-tokens parser tokens)
        (value next failure)
      (expect next :to-equal 2)
      (expect value :to-equal '(1 2)))))

(it-sequential "combinator-times-fails-when-short-test"
  (let ((tokens (%number-tokens 1))
        (parser (times 2 (type-token-value :number))))
    (assert-combinator-failure (parse-tokens parser tokens)
        (value next failure)
      (expect (parse-failure-expected failure) :to-equal :number))))

(it-sequential "combinator-times-zero-succeeds-empty-test"
  (let ((parser (times 0 (type-token-value :number))))
    (assert-combinator-success (parse-tokens parser #())
        (value next failure)
      (expect next :to-equal 0)
      (expect value :to-be-falsy))))

(it-sequential "combinator-times-rejects-non-advancing-parser-test"
  (let ((parser (times 2 (return-parser :ok))))
    (assert-combinator-values (parse-tokens parser #())
        (ok value next failure)
      (expect ok :to-be-falsy)
      (expect value :to-be-falsy)
      (expect next :to-equal 0)
      (expect (parse-failure-expected failure) :to-equal :progressing-parser)
      (expect (parser-name (parse-failure-actual failure)) :to-equal :return))))

(it-sequential "combinator-times-rejects-excessive-count-test"
  (let ((*maximum-parser-repetition-count* 2))
    (expect (lambda () (times 3 (type-token-value :number))) :to-throw 'error)))

(it-sequential "combinator-times-handles-large-fixed-count-iteratively-test"
  (let* ((count 2048)
         (tokens (make-array count :initial-element (make-token :type :number
                                                                :text "1"
                                                                :value 1)))
         (parser (times count (type-token-value :number))))
    (assert-combinator-success (parse-tokens parser tokens)
        (value next failure)
      (expect next :to-equal count)
      (expect (length value) :to-equal count))))

;;; SKIP-MANY / SKIP-MANY1 ----------------------------------------------------

(it-sequential "combinator-skip-many-discards-and-returns-t-test"
  (with-combinator-tokens (tokens '((:type :identifier :text "a")
                                    (:type :identifier :text "b")))
    (let ((parser (skip-many (type-token :identifier))))
      (assert-combinator-success (parse-tokens parser tokens)
          (value next failure)
        (expect value :to-be-truthy)
        (expect next :to-equal 2)))))

(it-sequential "combinator-skip-many-succeeds-on-empty-test"
  (with-combinator-tokens (tokens '((:type :comma :text ",")))
    (let ((parser (skip-many (type-token :identifier))))
      (assert-combinator-success (parse-tokens parser tokens)
          (value next failure)
        (expect value :to-be-truthy)
        (expect next :to-equal 0)))))

(it-sequential "combinator-skip-many-propagates-committed-failure-test"
  ;; Mirrors the OPT commit test: once the inner SEQ consumes :PLUS, the
  ;; trailing :NUMBER failure must stay committed instead of being swallowed.
  (let* ((tokens (vector (make-token :type :plus :text "+")))
         (parser (skip-many (seq (type-token :plus) (type-token :number)))))
    (assert-combinator-failure (parse-tokens parser tokens)
        (value next failure)
      (expect (parse-failure-position failure) :to-equal 1)
      (expect (parse-failure-expected failure) :to-equal :number))))

(it-sequential "combinator-skip-many-rejects-non-advancing-parser-test"
  ;; Mirrors MANY's own guard test (combinators-core-test.lisp):
  ;; RETURN-PARSER always succeeds without consuming input, so an unguarded
  ;; loop would never terminate.
  (let ((parser (skip-many (return-parser :ok))))
    (assert-combinator-failure (parse-tokens parser #())
        (value next failure)
      (expect (parse-failure-expected failure) :to-equal :progressing-parser))))

(it-sequential "combinator-skip-many1-requires-one-match-test"
  (with-combinator-tokens (tokens '((:type :comma :text ",")))
    (let ((parser (skip-many1 (type-token :identifier))))
      (assert-combinator-failure (parse-tokens parser tokens)
          (value next failure)
        (expect (parse-failure-expected failure) :to-equal :identifier))))
  (with-combinator-tokens (tokens '((:type :identifier :text "a")
                                    (:type :identifier :text "b")))
    (let ((parser (skip-many1 (type-token :identifier))))
      (assert-combinator-success (parse-tokens parser tokens)
          (value next failure)
        (expect value :to-be-truthy)
        (expect next :to-equal 2)))))

;;; FOLD-MANY -----------------------------------------------------------------

(it-sequential "combinator-fold-many-folds-results-test"
  (let ((tokens (%number-tokens 1 2 3))
        (parser (fold-many #'+ 0 (type-token-value :number))))
    (assert-combinator-success (parse-tokens parser tokens)
        (value next failure)
      (expect next :to-equal 3)
      (expect value :to-equal 6))))

(it-sequential "combinator-fold-many-empty-yields-initial-test"
  (with-combinator-tokens (tokens '((:type :comma :text ",")))
    (let ((parser (fold-many #'+ 41 (type-token-value :number))))
      (assert-combinator-success (parse-tokens parser tokens)
          (value next failure)
        (expect next :to-equal 0)
        (expect value :to-equal 41)))))

(it-sequential "combinator-fold-many-rejects-non-advancing-parser-test"
  ;; Mirrors MANY's own guard test (combinators-core-test.lisp): RETURN-PARSER
  ;; always succeeds without consuming input.
  (let ((parser (fold-many #'+ 0 (return-parser 1))))
    (assert-combinator-failure (parse-tokens parser #())
        (value next failure)
      (expect (parse-failure-expected failure) :to-equal :progressing-parser))))

;;; FOLD-MANY1 ----------------------------------------------------------------

(it-sequential "combinator-fold-many1-folds-nonempty-test"
  (let ((tokens (%number-tokens 1 2 3))
        (parser (fold-many1 #'+ 0 (type-token-value :number))))
    (assert-combinator-success (parse-tokens parser tokens)
        (value next failure)
      (expect next :to-equal 3)
      (expect value :to-equal 6))))

(it-sequential "combinator-fold-many1-requires-one-match-test"
  (with-combinator-tokens (tokens '((:type :comma :text ",")))
    (let ((parser (fold-many1 #'+ 0 (type-token-value :number))))
      (assert-combinator-failure (parse-tokens parser tokens)
          (value next failure)
        (expect (parse-failure-expected failure) :to-equal :number)))))

;;; SOME-TILL ------------------------------------------------------------------

(it-sequential "combinator-some-till-collects-until-end-test"
  ;; numbers until a semicolon; requires at least one number.
  (let ((tokens (vector (make-token :type :number :text "1" :value 1)
                        (make-token :type :number :text "2" :value 2)
                        (make-token :type :semicolon :text ";"))))
    (let ((parser (some-till (type-token-value :number) (type-token :semicolon))))
      (assert-combinator-success (parse-tokens parser tokens)
          (value next failure)
        (expect next :to-equal 3)
        (expect value :to-equal '(1 2))))))

(it-sequential "combinator-some-till-requires-one-match-test"
  ;; end matches immediately with no preceding item -> failure.
  (let ((tokens (vector (make-token :type :semicolon :text ";"))))
    (let ((parser (some-till (type-token-value :number) (type-token :semicolon))))
      (assert-combinator-failure (parse-tokens parser tokens)
          (value next failure)
        (expect failure :to-be-truthy)))))

;;; LENGTH-COUNT ---------------------------------------------------------------

(it-sequential "combinator-length-count-parses-n-items-test"
  ;; count 2, then two identifiers.
  (let ((tokens (vector (make-token :type :number :text "2" :value 2)
                        (make-token :type :identifier :text "a")
                        (make-token :type :identifier :text "b"))))
    (let ((parser (length-count (type-token-value :number)
                                (type-token-text :identifier))))
      (assert-combinator-success (parse-tokens parser tokens)
          (value next failure)
        (expect next :to-equal 3)
        (expect value :to-equal '("a" "b"))))))

(it-sequential "combinator-length-count-zero-yields-empty-test"
  (let ((tokens (vector (make-token :type :number :text "0" :value 0))))
    (let ((parser (length-count (type-token-value :number)
                                (type-token-text :identifier))))
      (assert-combinator-success (parse-tokens parser tokens)
          (value next failure)
        (expect next :to-equal 1)
        (expect value :to-be-falsy)))))

(it-sequential "combinator-length-count-fails-when-items-run-out-test"
  ;; count says 3 but only one identifier follows.
  (let ((tokens (vector (make-token :type :number :text "3" :value 3)
                        (make-token :type :identifier :text "a"))))
    (let ((parser (length-count (type-token-value :number)
                                (type-token-text :identifier))))
      (assert-combinator-failure (parse-tokens parser tokens)
          (value next failure)
        (expect failure :to-be-truthy)))))

(it-sequential "combinator-length-count-fails-when-count-is-not-a-non-negative-integer-test"
  ;; A count-parser value that is not an integer, or a negative integer, must
  ;; fail the parse instead of signalling -- distinct from the count exceeding
  ;; *MAXIMUM-PARSER-REPETITION-COUNT* tested below.
  (let ((tokens (vector (make-token :type :string :text "oops" :value "oops"))))
    (let ((parser (length-count (type-token-value :string)
                                (type-token-text :identifier))))
      (assert-combinator-failure (parse-tokens parser tokens)
          (value next failure)
        (expect (parse-failure-expected failure) :to-equal :length-count))))
  (let ((tokens (vector (make-token :type :number :text "-1" :value -1))))
    (let ((parser (length-count (type-token-value :number)
                                (type-token-text :identifier))))
      (assert-combinator-failure (parse-tokens parser tokens)
          (value next failure)
        (expect (parse-failure-expected failure) :to-equal :length-count)))))

(it-sequential "combinator-length-count-fails-when-count-exceeds-limit-test"
  (let ((*maximum-parser-repetition-count* 2)
        (tokens (vector (make-token :type :number :text "3" :value 3))))
    (let ((parser (length-count (type-token-value :number)
                                (type-token-text :identifier))))
      (assert-combinator-failure (parse-tokens parser tokens)
          (value next failure)
        (expect next :to-equal 1)
        (expect (parse-failure-expected failure) :to-equal :length-count)))))

(it-sequential "combinator-length-count-handles-large-count-iteratively-test"
  (let* ((count 2048)
         (tokens (make-array (1+ count))))
    (setf (aref tokens 0) (make-token :type :number
                                      :text (princ-to-string count)
                                      :value count))
    (loop for index from 1 to count
          do (setf (aref tokens index)
                   (make-token :type :identifier
                               :text "a"
                               :value "a")))
    (let ((parser (length-count (type-token-value :number)
                                (type-token-text :identifier))))
      (assert-combinator-success (parse-tokens parser tokens)
          (value next failure)
        (expect next :to-equal (1+ count))
        (expect (length value) :to-equal count)))))

;;; END-BY / END-BY1 ----------------------------------------------------------

(it-sequential "combinator-end-by-requires-terminator-after-each-test"
  ;; a ; b ; -> ("a" "b"); every item is terminated by ';'.
  (with-combinator-tokens (tokens '((:type :identifier :text "a")
                                    (:type :semicolon :text ";")
                                    (:type :identifier :text "b")
                                    (:type :semicolon :text ";")))
    (let ((parser (end-by (type-token-text :identifier) (type-token :semicolon))))
      (assert-combinator-success (parse-tokens parser tokens)
          (value next failure)
        (expect next :to-equal 4)
        (expect value :to-equal '("a" "b"))))))

(it-sequential "combinator-end-by-empty-input-succeeds-test"
  (with-combinator-tokens (tokens '((:type :comma :text ",")))
    (let ((parser (end-by (type-token-text :identifier) (type-token :semicolon))))
      (assert-combinator-success (parse-tokens parser tokens)
          (value next failure)
        (expect next :to-equal 0)
        (expect value :to-be-falsy)))))

(it-sequential "combinator-end-by-missing-final-terminator-fails-test"
  ;; a ; b  (no trailing ';') -> the second item is unterminated, a hard failure.
  (with-combinator-tokens (tokens '((:type :identifier :text "a")
                                    (:type :semicolon :text ";")
                                    (:type :identifier :text "b")))
    (let ((parser (end-by (type-token-text :identifier) (type-token :semicolon))))
      (assert-combinator-failure (parse-tokens parser tokens)
          (value next failure)
        (expect (parse-failure-committed-p failure) :to-be-truthy)
        (expect (parse-failure-expected failure) :to-equal :semicolon)))))

(it-sequential "combinator-end-by1-requires-at-least-one-test"
  (with-combinator-tokens (tokens '((:type :comma :text ",")))
    (let ((parser (end-by1 (type-token-text :identifier) (type-token :semicolon))))
      (assert-combinator-failure (parse-tokens parser tokens)
          (value next failure)
        (expect (parse-failure-expected failure) :to-equal :identifier)))))

;;; MANY-TILL -----------------------------------------------------------------

;;; AT-LEAST / AT-MOST --------------------------------------------------------

(it-sequential "combinator-at-least-requires-minimum-test"
  (with-combinator-tokens (tokens '((:type :identifier :text "a")
                                    (:type :identifier :text "b")
                                    (:type :identifier :text "c")))
    (let ((parser (at-least 2 (type-token-text :identifier))))
      (assert-combinator-success (parse-tokens parser tokens)
          (value next failure)
        (expect next :to-equal 3)
        (expect value :to-equal '("a" "b" "c")))))
  (with-combinator-tokens (tokens '((:type :identifier :text "a")))
    (let ((parser (at-least 2 (type-token :identifier))))
      (assert-combinator-failure (parse-tokens parser tokens)
          (value next failure)
        (expect (parse-failure-expected failure) :to-equal :identifier)))))

(it-sequential "combinator-at-least-zero-is-many-test"
  (with-combinator-tokens (tokens '((:type :comma :text ",")))
    (let ((parser (at-least 0 (type-token :identifier))))
      (assert-combinator-success (parse-tokens parser tokens)
          (value next failure)
        (expect next :to-equal 0)
        (expect value :to-be-falsy)))))

(it-sequential "combinator-at-most-caps-repetitions-test"
  (with-combinator-tokens (tokens '((:type :identifier :text "a")
                                    (:type :identifier :text "b")
                                    (:type :identifier :text "c")))
    (let ((parser (at-most 2 (type-token-text :identifier))))
      (assert-combinator-success (parse-tokens parser tokens)
          (value next failure)
        (expect next :to-equal 2)
        (expect value :to-equal '("a" "b"))))))

(it-sequential "combinator-many-till-collects-until-end-test"
  (with-combinator-tokens (tokens '((:type :identifier :text "a")
                                    (:type :identifier :text "b")
                                    (:type :semicolon :text ";")))
    (let ((parser (many-till (type-token-text :identifier)
                             (type-token :semicolon))))
      (assert-combinator-success (parse-tokens parser tokens)
          (value next failure)
        (expect next :to-equal 3)
        (expect value :to-equal '("a" "b"))))))

(it-sequential "combinator-many-till-empty-before-end-test"
  (with-combinator-tokens (tokens '((:type :semicolon :text ";")))
    (let ((parser (many-till (type-token-text :identifier)
                             (type-token :semicolon))))
      (assert-combinator-success (parse-tokens parser tokens)
          (value next failure)
        (expect next :to-equal 1)
        (expect value :to-be-falsy)))))

(it-sequential "combinator-many-till-recoverable-failure-at-start-test"
  ;; Neither END nor an item matches at the very first position (no input
  ;; consumed), so MANY-TILL fails recoverably -- an enclosing OPT backtracks.
  (with-combinator-tokens (tokens '((:type :plus :text "+")))
    (let ((parser (opt (many-till (type-token-text :identifier)
                                  (type-token :semicolon)))))
      (assert-combinator-success (parse-tokens parser tokens)
          (value next failure)
        (expect next :to-equal 0)
        (expect value :to-be-falsy)))))

(it-sequential "combinator-many-till-commits-after-progress-test"
  ;; Consume one item, then neither END nor another item matches: because input
  ;; was consumed the failure must be committed (an enclosing OPT must not
  ;; silently backtrack past the partially-parsed run).
  (with-combinator-tokens (tokens '((:type :identifier :text "a")
                                    (:type :plus :text "+")))
    (let ((parser (opt (many-till (type-token-text :identifier)
                                  (type-token :semicolon)))))
      (assert-combinator-failure (parse-tokens parser tokens)
          (value next failure)
        (expect (parse-failure-committed-p failure) :to-be-truthy)))))

;;; CHAINL / CHAINR -----------------------------------------------------------

(it-sequential "combinator-chainl-left-associates-test"
  (let ((tokens (vector (make-token :type :number :text "10" :value 10)
                        (make-token :type :minus :text "-")
                        (make-token :type :number :text "3" :value 3)
                        (make-token :type :minus :text "-")
                        (make-token :type :number :text "2" :value 2)))
        (parser (chainl *number-value* *minus-operator* 0)))
    (assert-combinator-success (parse-tokens parser tokens)
        (value next failure)
      (expect next :to-equal 5)
      (expect value :to-equal 5))))          ; (10 - 3) - 2

(it-sequential "combinator-chainr-right-associates-test"
  (let ((tokens (vector (make-token :type :number :text "10" :value 10)
                        (make-token :type :minus :text "-")
                        (make-token :type :number :text "3" :value 3)
                        (make-token :type :minus :text "-")
                        (make-token :type :number :text "2" :value 2)))
        (parser (chainr *number-value* *minus-operator* 0)))
    (assert-combinator-success (parse-tokens parser tokens)
        (value next failure)
      (expect next :to-equal 5)
      (expect value :to-equal 9))))          ; 10 - (3 - 2)

(it-sequential "combinator-chainl-empty-yields-default-test"
  (let ((parser (chainl *number-value* *minus-operator* :default)))
    (assert-combinator-success (parse-tokens parser #())
        (value next failure)
      (expect next :to-equal 0)
      (expect value :to-equal :default))))

(it-sequential "combinator-chainr-empty-yields-default-test"
  (let ((parser (chainr *number-value* *minus-operator* :default)))
    (assert-combinator-success (parse-tokens parser #())
        (value next failure)
      (expect next :to-equal 0)
      (expect value :to-equal :default))))

;;; TIMES-BETWEEN -------------------------------------------------------------

(it-sequential "combinator-times-between-is-greedy-up-to-max-test"
  (with-combinator-tokens (tokens '((:type :identifier :text "a")
                                    (:type :identifier :text "b")
                                    (:type :identifier :text "c")
                                    (:type :identifier :text "d")))
    (let ((parser (times-between 1 3 (type-token-text :identifier))))
      (assert-combinator-success (parse-tokens parser tokens)
          (value next failure)
        (expect next :to-equal 3)
        (expect value :to-equal '("a" "b" "c"))))))

(it-sequential "combinator-times-between-stops-below-max-on-non-match-test"
  (with-combinator-tokens (tokens '((:type :identifier :text "a")
                                    (:type :identifier :text "b")
                                    (:type :comma :text ",")))
    (let ((parser (times-between 1 5 (type-token-text :identifier))))
      (assert-combinator-success (parse-tokens parser tokens)
          (value next failure)
        (expect next :to-equal 2)
        (expect value :to-equal '("a" "b"))))))

(it-sequential "combinator-times-between-fails-below-min-test"
  (with-combinator-tokens (tokens '((:type :identifier :text "a")
                                    (:type :comma :text ",")))
    (let ((parser (times-between 2 4 (type-token :identifier))))
      (assert-combinator-failure (parse-tokens parser tokens)
          (value next failure)
        (expect (parse-failure-committed-p failure) :to-be-truthy)
        (expect (parse-failure-expected failure) :to-equal :identifier)))))

(it-sequential "combinator-times-between-rejects-excessive-max-test"
  (let ((*maximum-parser-repetition-count* 2))
    (expect (lambda () (times-between 0 3 (type-token :identifier)))
            :to-throw 'error)))

(it-sequential "combinator-times-between-rejects-min-greater-than-max-test"
  (expect (lambda () (times-between 3 1 (type-token :identifier)))
          :to-throw 'error))

(it-sequential "combinator-times-between-below-min-without-progress-is-recoverable-test"
  ;; Zero matches when MIN is 1: the failure did not consume input, so it stays
  ;; non-committed and an enclosing OPT recovers.
  (with-combinator-tokens (tokens '((:type :comma :text ",")))
    (let ((parser (opt (times-between 1 3 (type-token :identifier)))))
      (assert-combinator-success (parse-tokens parser tokens)
          (value next failure)
        (expect next :to-equal 0)
        (expect value :to-be-falsy)))))

(it-sequential "combinator-many-till-propagates-committed-end-failure-test"
  ;; The END parser consumes input (matches :SEMICOLON) then fails (no :COLON),
  ;; so its committed failure must propagate rather than trigger another item.
  (let ((tokens (vector (make-token :type :identifier :text "a")
                        (make-token :type :semicolon :text ";")
                        (make-token :type :plus :text "+")))
        (parser (many-till (type-token-text :identifier)
                           (seq (type-token :semicolon) (type-token :colon)))))
    (assert-combinator-failure (parse-tokens parser tokens)
        (value next failure)
      (expect (parse-failure-committed-p failure) :to-be-truthy)
      (expect (parse-failure-expected failure) :to-equal :colon))))
