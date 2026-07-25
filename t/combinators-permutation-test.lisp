(in-package :cl-parser-kit/test)

;;; PERMUTE -------------------------------------------------------------------

(it-sequential "combinator-permute-accepts-any-order-test"
  ;; Elements arrive as b c a but the values come back in argument order a b c.
  (with-combinator-tokens (tokens '((:type :b :text "b")
                                    (:type :c :text "c")
                                    (:type :a :text "a")))
    (let ((parser (permute (type-token :a) (type-token :b) (type-token :c))))
      (assert-combinator-success (parse-tokens parser tokens)
          (value next failure)
        (expect next :to-equal 3)
        (expect (mapcar #'token-type value) :to-equal '(:a :b :c))))))

(it-sequential "combinator-permute-accepts-original-order-test"
  (with-combinator-tokens (tokens '((:type :a :text "a")
                                    (:type :b :text "b")
                                    (:type :c :text "c")))
    (let ((parser (permute (type-token :a) (type-token :b) (type-token :c))))
      (assert-combinator-success (parse-tokens parser tokens)
          (value next failure)
        (expect (mapcar #'token-type value) :to-equal '(:a :b :c))))))

(it-sequential "combinator-permute-fails-on-missing-element-test"
  (with-combinator-tokens (tokens '((:type :a :text "a") (:type :b :text "b")))
    (let ((parser (permute (type-token :a) (type-token :b) (type-token :c))))
      (assert-combinator-failure (parse-tokens parser tokens)
          (value next failure)
        (expect failure :to-be-truthy)))))

(it-sequential "combinator-permute-propagates-committed-failure-test"
  ;; The first element consumes :a then fails hard requiring :b; that committed
  ;; failure must propagate rather than letting another ordering be tried.
  (with-combinator-tokens (tokens '((:type :a :text "a") (:type :c :text "c")))
    (let ((parser (permute (seq (type-token :a) (type-token :b))
                           (type-token :c))))
      (assert-combinator-failure (parse-tokens parser tokens)
          (value next failure)
        (expect (parse-failure-committed-p failure) :to-be-truthy)))))

(it-sequential "combinator-permute-rejects-excessive-parser-list-test"
  (let ((*maximum-parser-repetition-count* 2))
    (expect (lambda ()
              (permute (type-token :a) (type-token :b) (type-token :c)))
            :to-throw 'error)))

(it-sequential "combinator-permute-of-no-parsers-succeeds-empty-test"
  (with-combinator-tokens (tokens '((:type :a :text "a")))
    (assert-combinator-success (parse-tokens (permute) tokens)
        (value next failure)
      (expect value :to-be-falsy)
      (expect next :to-equal 0))))
