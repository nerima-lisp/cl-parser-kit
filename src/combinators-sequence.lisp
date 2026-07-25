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
       ;; A plain LOOP rather than the self-recursive-through-closures CPS
       ;; shape used elsewhere in this file, for the same reason as
       ;; %COLLECT-MANY/CPS (combinators-sequence.lisp): this is a hot
       ;; per-operator loop, and a closure per iteration is allocation it can
       ;; avoid entirely. %RUN-PROGRESSING-PARSER/CPS's own "succeeded but did
       ;; not progress" failure case is reproduced explicitly via
       ;; %PROGRESS-FAILURE-OBJECT below, for both PARSER's initial call and
       ;; every OPERATOR/PARSER pair inside the loop, since the loop no longer
       ;; delegates to that shared function.
       `(defun ,name (parser operator)
          (make-parser
           :name ,parser-name
           :fn (lambda (input position)
                 (multiple-value-bind (ok value next result)
                     (%run-parser-on-token-vector parser input position)
                   (if (or (not ok) (= next position))
                       (%failure-from (if ok
                                          (%progress-failure-object position parser)
                                          result))
                       (loop with accumulator = value
                             with current = next
                             with diagnostics = result
                             do (multiple-value-bind (op-ok op-value op-next op-result)
                                    (%run-parser-on-token-vector operator input current)
                                  (when (or (not op-ok) (= op-next current))
                                    (return (%recoverable-success
                                             accumulator current diagnostics
                                             (if op-ok
                                                 (%progress-failure-object current operator)
                                                 op-result))))
                                  (multiple-value-bind (item-ok item-value item-next item-result)
                                      (%run-parser-on-token-vector parser input op-next)
                                    (cond
                                      ((or (not item-ok) (= item-next op-next))
                                       (return (%committed-failure-from
                                                (if item-ok
                                                    (%progress-failure-object op-next parser)
                                                    item-result))))
                                      (t
                                       (setf accumulator (funcall op-value accumulator item-value)
                                             diagnostics (%merge-diagnostics diagnostics
                                                                             op-result item-result)
                                             current item-next))))))))))))
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
  "A plain LOOP rather than the self-recursive-through-closures CPS shape used
elsewhere in this file, for the same reason as %COLLECT-MANY/CPS
(combinators-sequence.lisp): this is a hot per-item loop, and a closure per
iteration is allocation it can avoid entirely. %RUN-PROGRESSING-PARSER/CPS's
own \"succeeded but did not progress\" failure case (both for SEPARATOR and
for PARSER) is reproduced explicitly via %PROGRESS-FAILURE-OBJECT below,
since the loop no longer delegates to that shared function."
  (loop
    (multiple-value-bind (separator-ok separator-value separator-next separator-result)
        (%run-parser-on-token-vector separator input current)
      (declare (ignore separator-value))
      (when (or (not separator-ok) (= separator-next current))
        (return (%recoverable-success
                 (nreverse values) current diagnostics
                 (if separator-ok
                     (%progress-failure-object current separator)
                     separator-result))))
      (multiple-value-bind (item-ok item-value item-next item-result)
          (%run-parser-on-token-vector parser input separator-next)
        (cond
          ((or (not item-ok) (= item-next separator-next))
           (return (funcall on-item-failure values current diagnostics
                            separator-next separator-result
                            (if item-ok
                                (%progress-failure-object separator-next parser)
                                item-result))))
          (t
           (setf values (cons item-value values)
                 diagnostics (%merge-diagnostics diagnostics separator-result item-result)
                 current item-next)))))))

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
