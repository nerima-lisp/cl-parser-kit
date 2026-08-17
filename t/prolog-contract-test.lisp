(in-package :cl-parser-kit/test)

(defun %prolog-pratt-success (value next)
  (values t value next nil))

(defun %make-prolog-contract-pratt-table ()
  (let ((table (make-pratt-table)))
    (register-prefix-operator table :number 0 #'%pratt-number-nud)
    (register-infix-operator table :plus 10 11 #'%pratt-add-led)
    (register-infix-operator table :star 20 21 #'%pratt-add-led)
    (register-postfix-operator table :bang 30
                               (lambda (left operator stream next current-table)
                                 (declare (ignore operator stream current-table))
                                 (%prolog-pratt-success (list :factorial left) next)))
    table))

(defun %pratt-operator-clause (table key fixity)
  (ecase fixity
    (:prefix
     (let ((entry (gethash key (pratt-table-prefixes table))))
       (cl-prolog-kit:make-clause
        `(operator ,key :prefix
                   ,(cl-parser-kit::pratt-prefix-entry-binding-power entry)
                   ,(cl-parser-kit::pratt-prefix-entry-binding-power entry))
        nil)))
    (:infix
     (let ((entry (gethash key (pratt-table-infixes table))))
       (cl-prolog-kit:make-clause
        `(operator ,key :infix
                   ,(cl-parser-kit::pratt-infix-entry-left-binding-power entry)
                   ,(cl-parser-kit::pratt-infix-entry-right-binding-power entry))
        nil)))
    (:postfix
     (let ((entry (gethash key (pratt-table-postfixes table))))
       (cl-prolog-kit:make-clause
        `(operator ,key :postfix
                   ,(cl-parser-kit::pratt-postfix-entry-binding-power entry)
                   ,(cl-parser-kit::pratt-postfix-entry-binding-power entry))
        nil)))))

(defun %make-pratt-contract-rulebase ()
  (let* ((table (%make-prolog-contract-pratt-table))
         (operator-clauses
           (list (%pratt-operator-clause table :number :prefix)
                 (%pratt-operator-clause table :plus :infix)
                 (%pratt-operator-clause table :star :infix)
                 (%pratt-operator-clause table :bang :postfix)))
         (contract-clauses
           (list
            (cl-prolog-kit:make-clause '(associativity :plus :left) nil)
            (cl-prolog-kit:make-clause '(associativity :star :left) nil)
            (cl-prolog-kit:make-clause '(precedence-edge :bang :star) nil)
            (cl-prolog-kit:make-clause '(precedence-edge :star :plus) nil))))
    (let ((rulebase
            (cl-prolog-kit:prolog
              ((higher-priority ?higher ?lower)
               (precedence-edge ?higher ?lower))
              ((higher-priority ?higher ?lower)
               (precedence-edge ?higher ?middle)
               (higher-priority ?middle ?lower))
              ((left-associative ?operator)
               (operator ?operator :infix ?left-binding ?right-binding)
               (associativity ?operator :left)))))
      (dolist (clause (append operator-clauses contract-clauses) rulebase)
        (cl-prolog-kit:rulebase-insert-clause! rulebase clause)))))

(cl-prolog-kit/weave:deftest-queries pratt-relational-contracts
    ((%make-pratt-contract-rulebase))
  ("projects the registered Pratt table as relational data"
   (operator ?operator ?fixity ?left ?right)
   :set
   (((?operator . :number) (?fixity . :prefix) (?left . 0) (?right . 0))
    ((?operator . :plus) (?fixity . :infix) (?left . 10) (?right . 11))
    ((?operator . :star) (?fixity . :infix) (?left . 20) (?right . 21))
    ((?operator . :bang) (?fixity . :postfix) (?left . 30) (?right . 30))))
  ("derives direct and transitive precedence from adjacent edges"
   (higher-priority :bang ?lower)
   :set
   (((?lower . :star)) ((?lower . :plus))))
  ("finds all left-associative infix operators"
   (left-associative ?operator)
   :set
   (((?operator . :plus)) ((?operator . :star))))
  ("does not classify postfix operators as left-associative"
   (left-associative :bang)
   :fails)
  ("proves the precedence graph is acyclic: no operator outranks itself"
   (higher-priority ?operator ?operator)
   :fails))
