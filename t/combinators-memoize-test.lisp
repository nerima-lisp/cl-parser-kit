(in-package :cl-parser-kit/test)

(defun %counting-parser (counter-box inner)
  "A parser that bumps COUNTER-BOX (a one-element list) each time it is run, then
delegates to INNER -- to observe how often a position is (re)parsed."
  (make-parser
   :name :counting
   :fn (lambda (input position)
         (incf (first counter-box))
         (run-parser inner input position))))

;;; A directly left-recursive grammar, written the same way PARSER-LAZY's own
;;; docstring example builds a recursive grammar -- a DEFPARAMETER referencing
;;; itself through (PARSER-LAZY variable) -- except the self-reference comes
;;; first in the SEQ instead of after a token is consumed. Every visit to this
;;; single, stable MEMOIZE-wrapped parser object immediately revisits itself at
;;; the very same position, before ever reaching the TYPE-TOKEN :NUM that would
;;; consume input.
(defparameter %memoize-left-recursive-number
  (memoize (seq (parser-lazy %memoize-left-recursive-number) (type-token :num))))

;;; An ordinary right-recursive grammar re-entering the SAME memoized NUMBERS
;;; parser at successive (later) positions -- MEMOIZE must not mistake this for
;;; left recursion.
(defparameter %memoize-right-recursive-numbers (memoize (type-token-value :num)))

(defparser %memoize-right-recursive-list ()
  (alt (seq-map (lambda (first rest) (cons first rest))
                %memoize-right-recursive-numbers
                (parser-lazy (%memoize-right-recursive-list)))
       (map-parser %memoize-right-recursive-numbers #'list)))

;;; MEMOIZE / WITH-PARSE-MEMOIZATION -------------------------------------------

(it-sequential "memoize-caches-repeated-position-within-extent-test"
  ;; The grammar visits position 0 twice (branch 1 fails at :b, branch 2 retries
  ;; the same sub-parser). With memoization active the sub-parser runs once.
  (let* ((counter (list 0))
         (counted (memoize (%counting-parser counter (type-token :a))))
         (grammar (alt (seq counted (type-token :b)) counted))
         (tokens (vector (make-token :type :a :text "a"))))
    (assert-combinator-success
        (with-parse-memoization (parse-tokens grammar tokens))
        (value next failure)
      (expect next :to-equal 1)
      (expect (token-type value) :to-equal :a))
    (expect (first counter) :to-equal 1)))

(it-sequential "memoize-is-a-noop-without-extent-test"
  ;; Outside WITH-PARSE-MEMOIZATION the same grammar reparses position 0 twice.
  (let* ((counter (list 0))
         (counted (memoize (%counting-parser counter (type-token :a))))
         (grammar (alt (seq counted (type-token :b)) counted))
         (tokens (vector (make-token :type :a :text "a"))))
    (assert-combinator-success (parse-tokens grammar tokens)
        (value next failure)
      (expect (token-type value) :to-equal :a))
    (expect (first counter) :to-equal 2)))

(it-sequential "memoize-preserves-parse-result-test"
  ;; Memoization must not change the parse outcome, only avoid recomputation.
  (let* ((grammar (memoize (seq (type-token :a) (type-token :b))))
         (tokens (vector (make-token :type :a :text "a")
                         (make-token :type :b :text "b"))))
    (assert-combinator-success
        (with-parse-memoization (parse-tokens grammar tokens))
        (value next failure)
      (expect next :to-equal 2)
      (expect (mapcar #'token-type value) :to-equal '(:a :b)))))

(it-sequential "memoize-caches-failure-too-test"
  (let* ((counter (list 0))
         (counted (memoize (%counting-parser counter (type-token :x))))
         ;; Both branches try COUNTED at position 0 and fail; the second is cached.
         (grammar (alt (seq counted (type-token :b)) counted))
         (tokens (vector (make-token :type :a :text "a"))))
    (assert-combinator-failure (with-parse-memoization (parse-tokens grammar tokens))
        (value next failure)
      (expect (first counter) :to-equal 1))))

;;; MEMOIZE left-recursion detection -------------------------------------------

(it-sequential "memoize-detects-direct-left-recursion-test"
  (let ((tokens (vector (make-token :type :num :text "1" :value 1))))
    (expect (lambda ()
              (with-parse-memoization
                (run-parser %memoize-left-recursive-number tokens 0)))
            :to-throw 'left-recursion-detected)))

(it-sequential "memoize-left-recursion-error-reports-parser-and-position-test"
  (let ((tokens (vector (make-token :type :num :text "1" :value 1)))
        (signalled nil))
    (handler-case
        (with-parse-memoization
          (run-parser %memoize-left-recursive-number tokens 0))
      (left-recursion-detected (condition)
        (setf signalled t)
        (expect (left-recursion-detected-position condition) :to-equal 0)
        ;; The reported PARSER is MEMOIZE's own argument -- the inner SEQ, not
        ;; the outer memoized wrapper -- so only its type is checked here.
        (expect (cl-parser-kit::parser-p (left-recursion-detected-parser condition))
                :to-be-truthy)))
    ;; Guards against the assertions above being silently skipped if the
    ;; condition is never signalled at all.
    (expect signalled :to-be-truthy)))

(it-sequential "memoize-does-not-flag-ordinary-non-left-recursion-test"
  ;; MEMOIZE re-entering the SAME parser at a DIFFERENT (later) position, as an
  ;; ordinary right-recursive or iterative grammar does, must not be mistaken
  ;; for left recursion.
  (let* ((tokens (vector (make-token :type :num :text "1" :value 1)
                         (make-token :type :num :text "2" :value 2)))
         (numbers (memoize (type-token-value :num))))
    (defparser %right ()
      (alt (seq-map (lambda (first rest) (cons first rest))
                    numbers (parser-lazy (%right)))
           (map-parser numbers #'list)))
    (assert-combinator-success
        (with-parse-memoization (parse-tokens (%right) tokens))
        (value next failure)
      (expect next :to-equal 2)
      (expect value :to-equal '(1 2)))))
