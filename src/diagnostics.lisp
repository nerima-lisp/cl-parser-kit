(in-package :cl-parser-kit)

;;; Data

(defstruct (fix-it (:constructor %make-fix-it (span replacement))
                   (:copier nil))
  span
  replacement)

(defstruct (diagnostic (:constructor %make-diagnostic
                                     (kind
                                      message
                                      span
                                      notes
                                      fixes
                                      data))
                       (:copier nil))
  kind
  message
  span
  notes
  fixes
  data)

(defstruct (parse-failure (:constructor %make-parse-failure
                                        (position
                                         expected
                                         actual
                                         diagnostics
                                         committed-p))
                          (:copier nil))
  position
  expected
  actual
  diagnostics
  committed-p)

(defparameter *maximum-diagnostic-fix-count* 1000
  "Maximum number of input FIXES entries APPLY-FIXES consumes. NIL entries are
ignored for application but still counted so nil-only or circular batches
terminate.")

(defparameter *maximum-parse-failure-expected-count* 1000
  "Maximum EXPECTED item count accepted when merging or rendering parse
failures. Rebind or SETF to raise it for intentionally broad grammars.")

(defparameter *maximum-parse-failure-diagnostic-count* 1000
  "Maximum attached diagnostic count accepted when merging or rendering parse
failures. Rebind or SETF to raise it for intentionally broad recovery reports.")

(define-resource-limit-condition parse-failure-resource-limit-exceeded
    "Parse failure resource limit exceeded for ~A: ~D > ~D")

(defun %parse-failure-resource-limit (kind value limit)
  (error 'parse-failure-resource-limit-exceeded
         :kind kind
         :value value
         :limit limit))

(defun %ensure-parse-failure-list-count (kind values limit)
  (if (consp values)
      (let ((items '()))
        (%walk-bounded-list values limit
                            (lambda (count) (%parse-failure-resource-limit kind count limit))
                            (lambda (item) (push item items)))
        (nreverse items))
      (ensure-list values)))

(defun %merge-parse-failure-lists (kind left right limit)
  (loop with count = 0
        for values in (list left right)
        append (loop for item in (%ensure-parse-failure-list-count kind
                                                                  values
                                                                  limit)
                     collect item
                     do (incf count)
                        (when (> count limit)
                          (%parse-failure-resource-limit kind count limit)))))

(defun %merge-parse-failure-lists-unique (kind left right limit)
  ;; LEFT and RIGHT are both frequently NIL -- most parse failures at a given
  ;; position carry only a handful of expected tokens, and %ALT/%CHOICE merge
  ;; failures from every tried branch -- so skip the hash table entirely
  ;; rather than allocate one just to discover there is nothing to
  ;; deduplicate. See %DO-PROPER-LIST (core.lisp) for the same pattern.
  (when (or left right)
    (loop with count = 0
          with seen = (make-hash-table :test 'equal)
          with merged = '()
          for values in (list left right)
          do (dolist (item (%ensure-parse-failure-list-count kind values limit))
               (incf count)
               (when (> count limit)
                 (%parse-failure-resource-limit kind count limit))
               (unless (gethash item seen)
                 (setf (gethash item seen) t)
                 (push item merged)))
          finally (return (nreverse merged)))))

(defun %append-parse-failure-diagnostic (diagnostics diagnostic)
  (%merge-parse-failure-lists :diagnostic-count
                              diagnostics
                              (list diagnostic)
                              *maximum-parse-failure-diagnostic-count*))

(defun make-fix-it (&key span replacement)
  (%make-fix-it span replacement))

(defun make-diagnostic (&key (kind :error) message span notes fixes data)
  (%make-diagnostic kind message span notes fixes data))

(defun make-parse-failure (&key position expected actual diagnostics committed-p)
  (%make-parse-failure position expected actual diagnostics committed-p))

(defun %copy-parse-failure (failure &key (expected :unspecified expected-supplied-p)
                                      (actual :unspecified actual-supplied-p)
                                      (diagnostics :unspecified diagnostics-supplied-p)
                                      (committed-p (parse-failure-committed-p failure)
                                                   committed-p-supplied-p))
  (%make-parse-failure (parse-failure-position failure)
                       (if expected-supplied-p
                           expected
                           (parse-failure-expected failure))
                       (if actual-supplied-p
                           actual
                           (parse-failure-actual failure))
                       (if diagnostics-supplied-p
                           diagnostics
                           (parse-failure-diagnostics failure))
                       (if committed-p-supplied-p
                           committed-p
                           (parse-failure-committed-p failure))))

(defmacro define-diagnostic-constructor (name kind)
  `(defun ,name (message &key span notes fixes data)
     (make-diagnostic :kind ,kind
                      :message message
                      :span span
                      :notes notes
                      :fixes fixes
                      :data data)))

(define-diagnostic-constructor warning-diagnostic :warning)
(define-diagnostic-constructor error-diagnostic :error)
(define-diagnostic-constructor note-diagnostic :note)

(defun %merge-parse-failure-pair (left right)
  (let ((left-position (parse-failure-position left))
        (right-position (parse-failure-position right)))
    (cond
      ((> right-position left-position) right)
      ((< right-position left-position) left)
      (t
         (%make-parse-failure
         left-position
         (%merge-parse-failure-lists-unique :expected-count
                                            (parse-failure-expected left)
                                            (parse-failure-expected right)
                                            *maximum-parse-failure-expected-count*)
         (or (parse-failure-actual right)
             (parse-failure-actual left))
         (%merge-parse-failure-lists :diagnostic-count
                                     (parse-failure-diagnostics left)
                                     (parse-failure-diagnostics right)
                                     *maximum-parse-failure-diagnostic-count*)
         (or (parse-failure-committed-p left)
             (parse-failure-committed-p right)))))))

(defun merge-parse-failures (&rest failures)
  (loop with merged-failure = nil
        for failure in failures
        when failure
          do (setf merged-failure
                   (if merged-failure
                       (%merge-parse-failure-pair merged-failure failure)
                       failure))
        finally (return merged-failure)))
