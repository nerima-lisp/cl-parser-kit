(in-package :cl-parser-kit/test)

(defun %tokenize-with (rules source)
  (tokenize source (make-tokenizer :rules rules)))

;;; MAKE-RADIX-INTEGER-RULE ---------------------------------------------------

(it-sequential "tokenizer-radix-integer-parses-hex-test"
  (let ((tokens (%tokenize-with (list (make-radix-integer-rule :type :hex :radix 16 :prefix "0x"))
                                "0xFF")))
    (expect (length tokens) :to-equal 1)
    (expect (token-type (elt tokens 0)) :to-equal :hex)
    (expect (token-value (elt tokens 0)) :to-equal 255)
    (expect (token-text (elt tokens 0)) :to-equal "0xFF")))

(it-sequential "tokenizer-radix-integer-prefix-is-case-insensitive-test"
  (let ((tokens (%tokenize-with (list (make-radix-integer-rule :type :hex :radix 16 :prefix "0x"))
                                "0X1a")))
    (expect (token-value (elt tokens 0)) :to-equal 26)))

(it-sequential "tokenizer-radix-integer-parses-binary-test"
  (let ((tokens (%tokenize-with (list (make-radix-integer-rule :type :bin :radix 2 :prefix "0b"))
                                "0b1010")))
    (expect (token-value (elt tokens 0)) :to-equal 10)))

(it-sequential "tokenizer-radix-integer-declines-without-digits-test"
  ;; "0x" with no hex digit declines, so the fallback number rule sees the 0.
  (let ((tokens (%tokenize-with (list (make-radix-integer-rule :type :hex :radix 16 :prefix "0x")
                                      (make-number-rule :type :dec))
                                "0")))
    (expect (token-type (elt tokens 0)) :to-equal :dec)
    (expect (token-value (elt tokens 0)) :to-equal 0)))

(it-sequential "tokenizer-radix-integer-declines-when-no-digit-follows-a-matched-prefix-test"
  ;; The (empty) prefix matches, but the very next character is not a valid
  ;; radix digit, so the rule declines a zero-length digit run instead of
  ;; matching one -- distinct from declining because the prefix itself failed.
  (let ((tokens (%tokenize-with (list (make-radix-integer-rule :type :hex :radix 16 :prefix "")
                                      (make-identifier-rule))
                                "g1")))
    (expect (token-type (elt tokens 0)) :to-equal :identifier)))

(it-sequential "tokenizer-radix-integer-skip-p-emits-no-token-test"
  (let ((tokens (%tokenize-with
                 (list (make-radix-integer-rule :type :hex :radix 16 :prefix "0x" :skip-p t))
                 "0xFF")))
    (expect (length tokens) :to-equal 0)))

;;; MAKE-FLOAT-RULE -----------------------------------------------------------

(it-sequential "tokenizer-float-parses-fractional-test"
  (let ((tokens (%tokenize-with (list (make-float-rule)) "1.5")))
    (expect (token-type (elt tokens 0)) :to-equal :float)
    (expect (token-value (elt tokens 0)) :to-equal 1.5d0)))

(it-sequential "tokenizer-float-parses-exponent-test"
  (let ((tokens (%tokenize-with (list (make-float-rule)) "1e3")))
    (expect (token-value (elt tokens 0)) :to-equal 1000.0d0))
  (let ((tokens (%tokenize-with (list (make-float-rule)) "1.5e2")))
    (expect (token-value (elt tokens 0)) :to-equal 150.0d0))
  (let ((tokens (%tokenize-with (list (make-float-rule)) "5e-1")))
    (expect (token-value (elt tokens 0)) :to-equal 0.5d0)))

(it-sequential "tokenizer-float-requires-marker-by-default-test"
  ;; A bare integer run is left to the following integer rule.
  (let ((tokens (%tokenize-with (list (make-float-rule) (make-number-rule :type :int)) "42")))
    (expect (token-type (elt tokens 0)) :to-equal :int)
    (expect (token-value (elt tokens 0)) :to-equal 42)))

(it-sequential "tokenizer-float-saturates-huge-exponent-test"
  ;; Clamped exponent + overflow saturation instead of an unbounded bignum/trap.
  (let ((tokens (%tokenize-with (list (make-float-rule)) "1e999999")))
    (expect (token-value (elt tokens 0)) :to-equal most-positive-double-float)))

(it-sequential "tokenizer-float-saturates-huge-exponent-for-every-float-type-test"
  ;; %COERCE-BOUNDED-FLOAT's ECASE covers all four standard float types, not
  ;; just the DOUBLE-FLOAT default; each must saturate to its own maximum
  ;; rather than trap.
  (dolist (case (list (cons 'single-float most-positive-single-float)
                      (cons 'short-float most-positive-short-float)
                      (cons 'long-float most-positive-long-float)))
    (let ((tokens (%tokenize-with (list (make-float-rule :float-type (car case))) "1e999999")))
      (expect (token-value (elt tokens 0)) :to-equal (cdr case))))
  ;; A huge negative exponent underflows to zero instead of saturating.
  (let ((tokens (%tokenize-with (list (make-float-rule)) "1e-999999")))
    (expect (token-value (elt tokens 0)) :to-equal 0.0d0)))

(it-sequential "tokenizer-float-saturates-huge-negative-mantissa-test"
  ;; %COERCE-BOUNDED-FLOAT saturates a negative overflow to the most-negative
  ;; representable float, not just a positive one.
  (let ((tokens (%tokenize-with (list (make-float-rule :allow-sign t)) "-1e999999")))
    (expect (token-value (elt tokens 0)) :to-equal (- most-positive-double-float))))

(it-sequential "tokenizer-float-allow-sign-consumes-a-leading-minus-test"
  (let ((tokens (%tokenize-with (list (make-float-rule :allow-sign t)) "-2.5e-3")))
    (expect (token-value (elt tokens 0)) :to-equal -2.5d-3))
  (let ((tokens (%tokenize-with (list (make-float-rule :allow-sign t)) "+1.5")))
    (expect (token-value (elt tokens 0)) :to-equal 1.5d0)))

(it-sequential "tokenizer-float-declines-a-marker-with-no-following-digit-test"
  ;; 'e'/'.' with nothing (or no digit) after it is not an exponent/fractional
  ;; marker: the rule must fall back to the bare integer digits already
  ;; scanned instead of misreading a lone letter or dot as part of the number.
  (let ((tokens (%tokenize-with
                 (list (make-float-rule :require-fractional nil)
                       (make-predicate-rule :identifier #'alpha-char-p))
                 "1e")))
    (expect (map 'list #'token-text tokens) :to-equal '("1" "e")))
  (let ((tokens (%tokenize-with
                 (list (make-float-rule :require-fractional nil)
                       (make-char-rule :dot #\.))
                 "1.")))
    (expect (map 'list #'token-text tokens) :to-equal '("1" "."))))

(it-sequential "tokenizer-float-declines-a-sign-with-no-following-exponent-digit-test"
  ;; 'e' followed by a sign but no digit (e.g. "1e+") is also not a valid
  ;; exponent -- the sign must not be mistaken for one.
  (let ((tokens (%tokenize-with
                 (list (make-float-rule :require-fractional nil)
                       (make-predicate-rule :identifier #'alpha-char-p)
                       (make-char-rule :plus #\+))
                 "1e+")))
    (expect (map 'list #'token-text tokens) :to-equal '("1" "e" "+"))))

(it-sequential "tokenizer-float-skip-p-emits-no-token-text-or-value-test"
  (let ((tokens (%tokenize-with (list (make-float-rule :skip-p t)) "1.5")))
    (expect (length tokens) :to-equal 0)))

;;; MAKE-OPERATOR-RULE --------------------------------------------------------

(it-sequential "tokenizer-operator-rule-prefers-longest-test"
  (let ((tokens (%tokenize-with (list (make-operator-rule :op '("==" "=" "<=" "<"))) "==")))
    (expect (length tokens) :to-equal 1)
    (expect (token-text (elt tokens 0)) :to-equal "==")
    (expect (token-value (elt tokens 0)) :to-equal "=="))
  (let ((tokens (%tokenize-with (list (make-operator-rule :op '("==" "=" "<=" "<"))) "===")))
    (expect (map 'list #'token-text tokens) :to-equal '("==" "="))))

(it-sequential "tokenizer-operator-rule-matcher-declines-at-end-of-source-test"
  ;; TOKENIZE's own loop never calls a matcher past the end of SOURCE, but
  ;; TOKEN-RULE-MATCHER is public API, so the matcher itself must still decline
  ;; gracefully when invoked directly at an out-of-bounds index.
  (let ((rule (make-operator-rule :op '("+" "-"))))
    (expect (funcall (token-rule-matcher rule) "+" 1) :to-be-falsy)))

(it-sequential "tokenizer-operator-rule-skip-p-emits-no-token-test"
  (let ((tokens (%tokenize-with (list (make-operator-rule :op '("+" "-") :skip-p t)) "+")))
    (expect (length tokens) :to-equal 0)))

(it-sequential "tokenizer-operator-rule-rejects-empty-operator-test"
  (expect (lambda () (make-operator-rule :op '("+" "")))
          :to-throw 'error))

(it-sequential "tokenizer-operator-rule-rejects-excessive-operator-set-test"
  (let ((*maximum-tokenizer-rule-alternatives* 1))
    (expect (lambda () (make-operator-rule :op '("+" "-")))
            :to-throw 'tokenizer-resource-limit-exceeded)))

(it-sequential "tokenizer-operator-rule-rejects-improper-operator-set-test"
  (expect (lambda () (make-operator-rule :op (cons "+" :tail)))
          :to-throw 'error))

;;; MAKE-NESTED-BLOCK-COMMENT-RULE --------------------------------------------

(it-sequential "tokenizer-nested-block-comment-spans-nested-delimiters-test"
  (let* ((source "/* a /* b */ c */")
         (tokens (%tokenize-with (list (make-nested-block-comment-rule
                                        :type :comment :skip-p nil))
                                 source)))
    (expect (length tokens) :to-equal 1)
    (expect (token-text (elt tokens 0)) :to-equal source)))

(it-sequential "tokenizer-nested-block-comment-skips-by-default-test"
  (let ((tokens (%tokenize-with (list (make-nested-block-comment-rule))
                                "/* a /* b */ c */")))
    (expect (length tokens) :to-equal 0)))

;;; MAKE-KEYWORD-RULE :case-sensitive -----------------------------------------

(it-sequential "tokenizer-keyword-case-insensitive-matches-any-case-test"
  (let ((rules (list (make-keyword-rule :kw "select" :case-sensitive nil)
                     (make-identifier-rule))))
    (dolist (source '("select" "SELECT" "Select"))
      (let ((tokens (%tokenize-with rules source)))
        (expect (token-type (elt tokens 0)) :to-equal :kw)
        (expect (token-value (elt tokens 0)) :to-equal "select")))))

(it-sequential "tokenizer-keyword-case-insensitive-still-respects-boundary-test"
  (let* ((rules (list (make-keyword-rule :kw "select" :case-sensitive nil)
                      (make-identifier-rule)))
         (tokens (%tokenize-with rules "SELECTED")))
    (expect (token-type (elt tokens 0)) :to-equal :identifier)))

;;; MAKE-LITERAL-RULE :case-sensitive ------------------------------------------

(it-sequential "tokenizer-literal-rule-is-case-sensitive-by-default-test"
  ;; CASE-SENSITIVE defaults to T: "Select" must not match the :KW literal and
  ;; falls through to the identifier rule instead.
  (let* ((rules (list (make-literal-rule :kw "select") (make-identifier-rule)))
         (tokens (%tokenize-with rules "Select")))
    (expect (token-type (elt tokens 0)) :to-equal :identifier)))

(it-sequential "tokenizer-literal-case-insensitive-matches-any-case-test"
  (let ((rules (list (make-literal-rule :kw "select" :case-sensitive nil))))
    (dolist (source '("select" "SELECT" "Select"))
      (let ((tokens (%tokenize-with rules source)))
        (expect (token-type (elt tokens 0)) :to-equal :kw)
        (expect (token-text (elt tokens 0)) :to-equal "select")
        (expect (token-value (elt tokens 0)) :to-equal "select")))))

;;; MAKE-STRING-RULE :escapes -------------------------------------------------

(it-sequential "tokenizer-string-rule-decodes-escapes-test"
  (let* ((source (coerce (list #\" #\a #\\ #\n #\b #\") 'string))
         (tokens (%tokenize-with (list (make-string-rule
                                        :type :str :escape-char #\\
                                        :escapes (list (cons #\n #\Newline)
                                                       (cons #\t #\Tab))))
                                 source)))
    (expect (token-value (elt tokens 0))
            :to-equal (coerce (list #\a #\Newline #\b) 'string))))

(it-sequential "tokenizer-string-rule-without-escape-map-is-literal-test"
  (let* ((source (coerce (list #\" #\a #\\ #\n #\b #\") 'string))
         (tokens (%tokenize-with (list (make-string-rule :type :str :escape-char #\\))
                                 source)))
    (expect (token-value (elt tokens 0)) :to-equal "anb")))

;;; COMMENT RULE CONSTRUCTOR VALIDATION ---------------------------------------

(it-sequential "tokenizer-comment-rule-constructors-reject-zero-width-delimiters-test"
  (expect (lambda () (make-line-comment-rule :prefix ""))
          :to-throw 'error)
  (expect (lambda () (make-block-comment-rule :start ""))
          :to-throw 'error)
  (expect (lambda () (make-block-comment-rule :end ""))
          :to-throw 'error)
  (expect (lambda () (make-nested-block-comment-rule :start ""))
          :to-throw 'error)
  (expect (lambda () (make-nested-block-comment-rule :end ""))
          :to-throw 'error)
  (expect (lambda () (make-nested-block-comment-rule :start "/*" :end "/*"))
          :to-throw 'error))
