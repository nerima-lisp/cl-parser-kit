(in-package :cl-parser-kit/test)

;;; Property-based checks for parser invariants.

(defun %identifier-token (name)
  (make-token :type :identifier :text name))

(defun %comma-token ()
  (make-token :type :comma :text ","))

(defun %identifier-vector (count)
  "A token vector of COUNT identifier tokens named i0, i1, ..."
  (coerce (loop for index below count
                collect (%identifier-token (format nil "i~D" index)))
          'vector))

(defun %comma-separated-vector (count &key trailing)
  "COUNT identifiers separated by commas, optionally with a trailing comma."
  (coerce (loop for index below count
                collect (%identifier-token (format nil "i~D" index))
                when (or (< index (1- count)) trailing)
                  collect (%comma-token))
          'vector))

(defun %plus-chain-vector (operand-count)
  "OPERAND-COUNT number tokens joined by :plus, e.g. 1 + 1 + 1."
  (coerce (loop for index below operand-count
                collect (make-token :type :number :text "1" :value 1)
                when (< index (1- operand-count))
                  collect (make-token :type :plus :text "+"))
          'vector))

(defun %left-fold-plus-table ()
  (let ((table (make-pratt-table)))
    (register-prefix-operator
     table :number 0
     (lambda (token stream next current-table)
       (declare (ignore stream current-table))
       (values t (token-value token) next nil)))
    (register-infix-operator
     table :plus 10 11
     (lambda (left op right next current-table)
       (declare (ignore op current-table))
       (values t (list :add left right) next nil)))
    table))

(defun %add-node-count (tree)
  (if (and (consp tree) (eq (first tree) :add))
      (+ 1 (%add-node-count (second tree)) (%add-node-count (third tree)))
      0))

(defun %leftmost-leaf (tree)
  (if (and (consp tree) (eq (first tree) :add))
      (%leftmost-leaf (second tree))
      tree))

(it-property "property-many-consumes-every-matching-token"
    ((count (gen-integer :min 0 :max 40)))
  (let ((tokens (%identifier-vector count)))
    (assert-combinator-success (parse-tokens (many (type-token :identifier)) tokens)
        (value next failure)
      (expect next :to-equal count)
      (expect (length value) :to-equal count))))

(it-property "property-sep-by1-yields-one-item-per-operand"
    ((count (gen-integer :min 1 :max 25)))
  (let ((tokens (%comma-separated-vector count)))
    (assert-combinator-success
        (parse-all (sep-by1 (type-token :identifier) (type-token :comma)) tokens)
        (value next failure)
      (expect (length value) :to-equal count)
      (expect next :to-equal (max 0 (1- (* 2 count)))))))

(it-property "property-sep-end-by1-accepts-optional-trailing-separator"
    ((count (gen-integer :min 1 :max 25))
     (trailing (gen-member '(t nil))))
  (let ((tokens (%comma-separated-vector count :trailing trailing)))
    (assert-combinator-success
        (parse-all (sep-end-by1 (type-token :identifier) (type-token :comma)) tokens)
        (value next failure)
      (expect (length value) :to-equal count)
      (expect next :to-equal (length tokens)))))

(defun %token-kind-text (kind index)
  (ecase kind
    (:id (format nil "id~D" index))
    (:num "42")
    (:plus "+")))

(defun %build-spaced-source (kinds)
  "Join one lexeme per KIND with single spaces; returns the source string."
  (with-output-to-string (out)
    (loop for kind in kinds
          for index from 0
          unless (zerop index) do (write-char #\Space out)
          do (write-string (%token-kind-text kind index) out))))

(defun %spanned-tokenizer ()
  (make-tokenizer :rules (list (make-whitespace-rule :skip-p t)
                               (make-identifier-rule)
                               (make-number-rule)
                               (make-literal-rule :plus "+"))))

(it-property "property-tokenizer-spans-cover-source-exactly"
    ((kinds (gen-list (gen-member '(:id :num :plus)) :min-length 1 :max-length 20)))
  (let* ((source (%build-spaced-source kinds))
         (tokens (tokenize source (%spanned-tokenizer))))
    ;; One emitted token per lexeme (whitespace is skipped).
    (expect (length tokens) :to-equal (length kinds))
    (loop for index below (length tokens)
          for token = (aref tokens index)
          for span = (token-span token)
          do (progn
               ;; The recorded span/text must exactly reference the source slice.
               (expect (token-text token)
                       :to-equal (subseq source (token-start token) (token-end token)))
               (expect (token-start token) :to-equal (span-start span))
               (expect (token-end token) :to-equal (span-end span))
               (expect (< (token-start token) (token-end token)) :to-be-truthy)
               ;; Single-line input: 1-based column is offset + 1, line stays 1.
               (expect (span-start-line span) :to-equal 1)
               (expect (span-start-column span) :to-equal (1+ (token-start token)))
               ;; Tokens are ordered and non-overlapping.
               (when (plusp index)
                 (expect (<= (token-end (aref tokens (1- index)))
                             (token-start token))
                         :to-be-truthy))))))

(defun %deep-prefix-table ()
  "A Pratt table whose :neg prefix recursively parses its operand, so a run of
:neg tokens drives recursion depth linearly."
  (let ((table (make-pratt-table)))
    (register-prefix-operator
     table :number 0
     (lambda (token stream next current-table)
       (declare (ignore stream current-table))
       (values t (token-value token) next nil)))
    (register-prefix-operator
     table :neg 100
     (lambda (token stream next current-table)
       (declare (ignore token))
       (multiple-value-bind (ok value new-next failure)
           (parse-pratt stream current-table :position next :min-binding-power 100)
         (if ok
             (values t (list :neg value) new-next nil)
             (values nil nil new-next failure)))))
    table))

(defun %deep-prefix-vector (depth)
  (coerce (append (loop repeat depth collect (make-token :type :neg :text "-"))
                  (list (make-token :type :number :text "1" :value 1)))
          'vector))

(it-sequential "pratt-depth-guard-rejects-pathologically-deep-input"
  ;; A hostile run of prefix operators must fail gracefully instead of
  ;; exhausting the control stack (security hardening).
  (let ((*maximum-pratt-recursion-depth* 100))
    (assert-combinator-failure
        (parse-pratt-all (%deep-prefix-vector 500) (%deep-prefix-table))
        (value next failure)
      (expect (parse-failure-expected failure) :to-equal :maximum-recursion-depth))))

(it-sequential "pratt-depth-guard-allows-input-within-limit"
  (let ((*maximum-pratt-recursion-depth* 100))
    (assert-combinator-success
        (parse-pratt-all (%deep-prefix-vector 20) (%deep-prefix-table))
        (value next failure)
      (expect (%leftmost-leaf-neg value) :to-equal 1))))

(defun %leftmost-leaf-neg (tree)
  (if (and (consp tree) (eq (first tree) :neg))
      (%leftmost-leaf-neg (second tree))
      tree))

(it-property "property-pratt-left-associative-chain-folds-left"
    ((operands (gen-integer :min 1 :max 20)))
  (let ((tokens (%plus-chain-vector operands))
        (table (%left-fold-plus-table)))
    (assert-combinator-success (parse-pratt-all tokens table)
        (value next failure)
      (expect (%add-node-count value) :to-equal (1- operands))
      (expect (%leftmost-leaf value) :to-equal 1))))

;;; CHAINR1 recurses outside RUN-PARSER, so it needs its own recursion guard;
;;; nested delimiters exercise the guard in RUN-PARSER.

(defun %nested-paren-tokens (depth)
  (coerce (append (loop repeat depth collect (make-token :type :lparen :text "("))
                  (list (make-token :type :number :text "1" :value 1))
                  (loop repeat depth collect (make-token :type :rparen :text ")")))
          'vector))

(defun %nested-expr-parser ()
  "A hand-written recursive-descent grammar: expr := NUMBER | '(' expr ')'.
The lazy inner parser re-derives EXPR on every run so recursion happens at
parse time, one RUN-PARSER call per nesting level, exactly like a real
consumer's grammar would."
  (labels ((expr ()
             (alt (type-token :number)
                  (between (type-token :lparen)
                          (make-parser :name :lazy-expr
                                       :fn (lambda (input position)
                                             (run-parser (expr) input position)))
                          (type-token :rparen)))))
    (expr)))

(it-sequential "combinator-depth-guard-rejects-pathologically-nested-input"
  ;; A hostile run of nested delimiters must fail gracefully instead of
  ;; exhausting the control stack.
  (let ((*maximum-parser-recursion-depth* 1000))
    (assert-combinator-failure
        (parse-tokens (%nested-expr-parser) (%nested-paren-tokens 5000))
        (value next failure)
      (expect (parse-failure-expected failure) :to-equal :maximum-recursion-depth))))

(it-sequential "combinator-depth-guard-allows-input-within-limit"
  (let ((*maximum-parser-recursion-depth* 1000))
    (assert-combinator-success
        (parse-tokens (%nested-expr-parser) (%nested-paren-tokens 5))
        (value next failure)
      (expect (token-value value) :to-equal 1))))

(defun %operator-chain-tokens (operand-count)
  (coerce (loop for index below operand-count
                collect (make-token :type :number :text "1" :value 1)
                when (< index (1- operand-count))
                  collect (make-token :type :caret :text "^"))
          'vector))

(defun %chainr1-parser ()
  (chainr1 (map-parser (type-token :number) #'token-value)
          (operator-parser (type-token :caret) (lambda (left right) (list :expt left right)))))

(it-sequential "chainr1-depth-guard-rejects-pathologically-long-chain"
  ;; CHAINR1's right-recursion is a direct Lisp call, not a tail call (its
  ;; result feeds MULTIPLE-VALUE-BIND), so it needs its own explicit guard
  ;; distinct from the general RUN-PARSER check above.
  (let ((*maximum-parser-recursion-depth* 1000))
    (assert-combinator-failure
        (parse-tokens (%chainr1-parser) (%operator-chain-tokens 5000))
        (value next failure)
      (expect (parse-failure-expected failure) :to-equal :maximum-recursion-depth))))

(it-sequential "chainr1-depth-guard-allows-input-within-limit"
  (let ((*maximum-parser-recursion-depth* 1000))
    (assert-combinator-success
        (parse-tokens (%chainr1-parser) (%operator-chain-tokens 5))
        (value next failure)
      (expect value :to-equal '(:expt 1 (:expt 1 (:expt 1 (:expt 1 1))))))))
