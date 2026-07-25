(in-package :cl-parser-kit)

(defun %recoverable-success (value position diagnostics failure)
  (if (or (%progress-failure-p failure)
          (parse-failure-committed-p failure))
      (%failure-from failure)
      (%success value
                position
                (%merge-diagnostics diagnostics
                                    (parse-failure-diagnostics failure)))))

(defun %collect-many/cps (parser input current values diagnostics)
  "Same match-until-failure loop %RUN-PROGRESSING-PARSER/CPS's CPS callers
elsewhere in this library express as self-recursion through two fresh
closures per iteration; written as a plain LOOP instead specifically because
this is MANY's hot inner loop -- one iteration per matched token -- so
avoiding a per-iteration closure allocation here is worth the departure from
the CPS house style everywhere else in this file."
  (loop
    (multiple-value-bind (ok value next result)
        (%run-parser-on-token-vector parser input current)
      (cond
        ((not ok)
         (return (%recoverable-success (nreverse values) current diagnostics result)))
        ((= next current)
         (return (%recoverable-success (nreverse values) current diagnostics
                                       (%progress-failure-object current parser))))
        (t
         (setf values (cons value values)
               diagnostics (%merge-diagnostics diagnostics result)
               current next))))))

(defun %run-parser-or-recoverable (parser input position fallback-value)
  (%run-parser/if-success
   parser input position
   (lambda (value next result) (%success value next result))
   (lambda (result failed-next)
     (declare (ignore failed-next))
     (%recoverable-success fallback-value position nil result))))

;;; As with DEFINE-TREE-NODE-FAMILY (see TREE-MACROS.LISP) and
;;; DEFINE-PRATT-REGISTER-OPERATOR (see PRATT.LISP), SB-COVER attributes each
;;; DEFINE-SEPARATED-PARSER / DEFINE-CHAIN-PARSER expansion's body to its call
;;; site below, not to the macro definitions here -- SEP-BY/SEP-BY1/
;;; SEP-END-BY/SEP-END-BY1/CHAINL1/CHAINR1 are exercised extensively
;;; (t/combinators-separator-test.lisp, t/combinators-chain-test.lisp), so
;;; these two macro bodies showing as uncovered is a reporting artifact.

(defmacro define-separated-parser (name &rest options)
  (let ((parser-name (intern (symbol-name name) :keyword)))
    `(defun ,name (parser separator)
       (%make-separated-parser ,parser-name parser separator
                               ,@options))))

(define-parser-function many (parser) :many
  (%collect-many/cps parser input position '() '()))

(defun many1 (parser)
  (bind-parser parser
               (lambda (first)
                 (map-parser (many parser)
                             (lambda (rest)
                               (cons first rest))))))

(defmacro define-chain-parser (name recursion-style)
  (let ((parser-name (intern (symbol-name name) :keyword)))
    (ecase recursion-style
      (:left
       `(defun ,name (parser operator)
          (make-parser
           :name ,parser-name
           :fn (lambda (input position)
                 (labels ((continue-chain (accumulator current diagnostics)
                            (%run-progressing-parser/cps
                             operator input current
                             (lambda (operator-value operator-next operator-result)
                               (%run-progressing-parser/cps
                                parser input operator-next
                                (lambda (item-value item-next item-result)
                                  (continue-chain
                                   (funcall operator-value accumulator item-value)
                                   item-next
                                   (%merge-diagnostics diagnostics
                                                       operator-result
                                                       item-result)))
                                (lambda (item-failure)
                                  (%committed-failure-from item-failure))))
                             (lambda (operator-failure)
                               (%recoverable-success accumulator
                                                     current
                                                     diagnostics
                                                     operator-failure)))))
                   (%run-progressing-parser/cps
                    parser input position
                    (lambda (value next result)
                      (continue-chain value next result))
                    #'%failure-from))))))
      (:right
       `(defun ,name (parser operator)
          (make-parser
           :name ,parser-name
           :fn (lambda (input position)
                 ;; CHAINR1's right-recursion calls PARSE-CHAIN directly
                 ;; instead of routing back through RUN-PARSER (its result is
                 ;; consumed by the enclosing MULTIPLE-VALUE-BIND, so it is
                 ;; not a tail call and the RUN-PARSER depth guard never
                 ;; sees it), so it needs its own explicit check against the
                 ;; same *PARSER-RECURSION-DEPTH* counter.
                 (labels ((parse-chain (current-position)
                            (if (>= *parser-recursion-depth* *maximum-parser-recursion-depth*)
                                (values nil nil current-position
                                        (%recursion-depth-exceeded-failure current-position))
                                (let ((*parser-recursion-depth* (1+ *parser-recursion-depth*)))
                                  (%run-progressing-parser/cps
                                   parser input current-position
                                   (lambda (value next result)
                                     (%run-progressing-parser/cps
                                      operator input next
                                      (lambda (operator-value operator-next operator-result)
                                        (multiple-value-bind (right-ok right-value right-next right-result)
                                            (parse-chain operator-next)
                                          (if right-ok
                                              (%success (funcall operator-value value right-value)
                                                        right-next
                                                        (%merge-diagnostics result
                                                                            operator-result
                                                                            right-result))
                                              (%committed-failure-from right-result))))
                                      (lambda (operator-failure)
                                        (%recoverable-success value
                                                              next
                                                              result
                                                              operator-failure))))
                                   #'%failure-from)))))
                   (parse-chain position)))))))))

(define-chain-parser chainl1 :left)
(define-chain-parser chainr1 :right)

(defun %collect-separated-items/cps (parser separator input current values diagnostics
                                    on-item-failure)
  (%run-progressing-parser/cps
   separator input current
   (lambda (_separator-value separator-next separator-result)
     (declare (ignore _separator-value))
     (%run-progressing-parser/cps
      parser input separator-next
      (lambda (item-value item-next item-result)
        (%collect-separated-items/cps parser separator input item-next
                                      (cons item-value values)
                                      (%merge-diagnostics diagnostics
                                                          separator-result
                                                          item-result)
                                      on-item-failure))
      (lambda (item-failure)
        (funcall on-item-failure values
                 current
                 diagnostics
                 separator-next
                 separator-result
                 item-failure))))
   (lambda (separator-failure)
     (%recoverable-success (nreverse values)
                           current
                           diagnostics
                           separator-failure))))

(defun %make-separated-parser (name parser separator
                               &key allow-empty-p final-item-failure-recoverable-p)
  (make-parser
   :name name
   :fn (lambda (input position)
         (%run-progressing-parser/cps
          parser input position
          (lambda (value next result)
            (%collect-separated-items/cps
             parser separator input next (list value) result
             (lambda (values current diagnostics separator-next separator-result item-failure)
               (declare (ignore current))
               (if final-item-failure-recoverable-p
                   (%recoverable-success (nreverse values)
                                         separator-next
                                         (%merge-diagnostics diagnostics
                                                             separator-result)
                                         item-failure)
                   (%committed-failure-from item-failure)))))
          (if allow-empty-p
              (lambda (failure)
                (%recoverable-success '() position nil failure))
              #'%failure-from)))))

(define-separated-parser sep-by1
  :final-item-failure-recoverable-p nil)

(define-separated-parser sep-by
  :allow-empty-p t
  :final-item-failure-recoverable-p nil)

(define-separated-parser sep-end-by1
  :final-item-failure-recoverable-p t)

(define-separated-parser sep-end-by
  :allow-empty-p t
  :final-item-failure-recoverable-p t)

(define-parser-function opt (parser) :opt
  (%run-parser-or-recoverable parser input position nil))
