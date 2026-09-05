(in-package :cl-parser-kit)

(defstruct (pratt-prefix-entry (:constructor make-pratt-prefix-entry
                                (&key binding-power nud)))
  "How a token behaves in prefix position: NUD (\"null denotation\") is called
with no left operand to parse the construct the token introduces, and
BINDING-POWER is the strength with which it binds its operand.

Registered in a PRATT-TABLE by REGISTER-PREFIX-OPERATOR; this covers unary
minus, an opening parenthesis, and any literal that starts an expression."
  binding-power
  nud)

(defstruct (pratt-infix-entry (:constructor make-pratt-infix-entry
                               (&key left-binding-power right-binding-power led)))
  "How a token behaves between two operands: LED (\"left denotation\") is called
with the already-parsed left operand, LEFT-BINDING-POWER decides whether this
operator captures that operand at all, and RIGHT-BINDING-POWER bounds what it
takes on the right.

The gap between the two powers is what encodes associativity -- equal powers
group to the right, a higher left power groups to the left -- so
REGISTER-INFIX-LEFT and REGISTER-INFIX-RIGHT differ only in how they fill these
two slots."
  left-binding-power
  right-binding-power
  led)

(defstruct (pratt-postfix-entry (:constructor make-pratt-postfix-entry
                                 (&key binding-power led)))
  "How a token behaves after an operand with nothing following: LED is called
with the parsed left operand and takes no right operand, and BINDING-POWER
decides how tightly it captures that left operand.

Registered by REGISTER-POSTFIX-OPERATOR; this covers factorial, an index
suffix, and similar trailing forms."
  binding-power
  led)

(defstruct (pratt-table (:constructor make-pratt-table
                         (&key (prefixes (make-hash-table :test #'equal))
                               (infixes (make-hash-table :test #'equal))
                               (postfixes (make-hash-table :test #'equal)))))
  "An operator-precedence grammar: three token-type-keyed tables of
PRATT-PREFIX-ENTRY, PRATT-INFIX-ENTRY, and PRATT-POSTFIX-ENTRY.

One token type may appear in more than one table -- that is how \"-\" is both
unary negation and binary subtraction without ambiguity, since position alone
selects the entry. Populate with the REGISTER-* functions and run with
PARSE-PRATT, PARSE-PRATT-ALL, or PARSE-PRATT-SOURCE."
  prefixes
  infixes
  postfixes)

(defmacro define-pratt-register-operator (name table-accessor constructor &rest slots)
  "Define NAME as the registrar storing a CONSTRUCTOR entry, built from SLOTS,
under a token type in TABLE-ACCESSOR's table.

The three registrars differ only in which table they write and which slots the
entry carries, so the store-and-return-TABLE shape is written once here."
  `(defun ,name (table key ,@slots)
     ,(format nil "Register the token type KEY in TABLE with ~{~A~^, ~}, ~
replacing any existing entry for KEY, and return TABLE so registrations chain.~
~2%Builds a ~A; see that structure for what the slots mean."
              (mapcar #'symbol-name slots)
              (subseq (symbol-name constructor) (length "MAKE-")))
     (setf (gethash key (,table-accessor table))
           (,constructor ,@(loop for slot in slots
                                 append (list (intern (string-upcase (symbol-name slot)) :keyword)
                                              slot))))
     table))

(define-pratt-register-operator register-prefix-operator
  pratt-table-prefixes
  make-pratt-prefix-entry
  binding-power
  nud)

(define-pratt-register-operator register-infix-operator
  pratt-table-infixes
  make-pratt-infix-entry
  left-binding-power
  right-binding-power
  led)

(define-pratt-register-operator register-postfix-operator
  pratt-table-postfixes
  make-pratt-postfix-entry
  binding-power
  led)
