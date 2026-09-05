(in-package :cl-parser-kit)

;;;; Operator-precedence expression builder for arbitrary operand and operator
;;;; parsers.

(defun %expression-ops-of-kind (level kind)
  "The op-parsers in LEVEL tagged KIND, in order."
  (loop for spec across (%ensure-parser-list-vector
                         "MAKE-EXPRESSION-PARSER precedence level"
                         level)
        when (eq (first spec) kind)
        collect (second spec)))

(defun %expression-choice (op-parsers)
  "ALT over OP-PARSERS, or NIL when the list is empty."
  (let ((ops (%ensure-parser-list-vector "MAKE-EXPRESSION-PARSER operator set"
                                         op-parsers)))
    (unless (zerop (length ops))
      (choice ops))))

(defun %expression-factor (base prefix-op postfix-op)
  "BASE wrapped in zero or more PREFIX-OP functions (applied right-to-left, so the
nearest prefix binds innermost) and zero or more POSTFIX-OP functions (applied
left-to-right). A NIL PREFIX-OP / POSTFIX-OP skips that side; when both are NIL
BASE is returned unchanged so a plain level adds no overhead."
  (if (and (null prefix-op) (null postfix-op))
      base
      (parse-let* ((prefixes (if prefix-op (many prefix-op) (pure '())))
                   (value base)
                   (postfixes (if postfix-op (many postfix-op) (pure '()))))
        (let ((pre-applied (reduce (lambda (fn accumulator) (funcall fn accumulator))
                                   prefixes
                                   :from-end t
                                   :initial-value value)))
          (reduce (lambda (accumulator fn) (funcall fn accumulator))
                  postfixes
                  :initial-value pre-applied)))))

(defun %expression-level (base level)
  "Wrap BASE (the parser built from all tighter levels) with one precedence
LEVEL's prefix/postfix/infix operators, returning the level's parser."
  (let* ((prefix-op (%expression-choice (%expression-ops-of-kind level :prefix)))
         (postfix-op (%expression-choice (%expression-ops-of-kind level :postfix)))
         (left-ops (%expression-ops-of-kind level :infix-left))
         (right-ops (%expression-ops-of-kind level :infix-right))
         (non-ops (%expression-ops-of-kind level :infix-non-assoc))
         (factor (%expression-factor base prefix-op postfix-op)))
    (when (> (+ (if left-ops 1 0) (if right-ops 1 0) (if non-ops 1 0)) 1)
      (error "MAKE-EXPRESSION-PARSER: a precedence level may not mix infix ~
associativities (found~@[ left~*~]~@[ right~*~]~@[ non-assoc~*~])"
             left-ops right-ops non-ops))
    (cond
      (left-ops (chainl1 factor (%expression-choice left-ops)))
      (right-ops (chainr1 factor (%expression-choice right-ops)))
      (non-ops
       (let ((op (%expression-choice non-ops)))
         (parse-let* ((operand factor)
                      (tail (opt (seq-map #'cons op factor))))
           (if tail
               (funcall (car tail) operand (cdr tail))
               operand))))
      (t factor))))

(defun make-expression-parser (term table)
  "Build a combinator parser for an operator-precedence expression grammar.

TERM parses an operand (a primary/atom). TABLE is a list of precedence levels,
HIGHEST precedence first; each level is a list of operator specifications, each a
two-element list of a keyword and an operator parser:
  (:prefix op)          unary prefix    -- OP yields a one-argument function
  (:postfix op)         unary postfix   -- OP yields a one-argument function
  (:infix-left op)      left-associative binary  -- OP yields a two-argument fn
  (:infix-right op)     right-associative binary
  (:infix-non-assoc op) non-associative binary (a b, but not a b c)
Each OP is itself a parser producing the combining function (see OPERATOR-PARSER,
which maps a token parser to a fixed function). Prefix and postfix operators may
repeat within a level; a level may combine any prefix/postfix operators with at
most one infix associativity (mixing left and right in one level is ambiguous and
signals an error at build time).

Example -- the usual four-function arithmetic with unary minus:

  (make-expression-parser
   (type-token-value :number)
   (list (list (list :prefix     (operator-parser (literal \"-\") (lambda (x) (- x)))))
         (list (list :infix-left  (operator-parser (literal \"*\") #'*))
               (list :infix-left  (operator-parser (literal \"/\") #'/)))
         (list (list :infix-left  (operator-parser (literal \"+\") #'+))
               (list :infix-left  (operator-parser (literal \"-\") #'-)))))

This is the combinator-layer counterpart to the Pratt parser: reach for Pratt
when dispatching on single token types, and for MAKE-EXPRESSION-PARSER when the
operands and operators are arbitrary parsers."
  (let ((levels (%ensure-parser-list-vector "MAKE-EXPRESSION-PARSER table"
                                            table))
        (parser term))
    (loop for level across levels
          do (setf parser (%expression-level parser level))
          finally (return parser))))
