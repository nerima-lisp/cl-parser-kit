(in-package :cl-user)

;; Panic-mode error recovery: parse a run of `name = number ;` statements, but
;; when one is malformed, skip to the next `;` (recording an :error marker) and
;; keep going, so a single parse reports EVERY bad statement instead of aborting
;; at the first. The diagnostics collected during recovery ride the success path,
;; so they are read from RUN-PARSER's fourth value (the terminal PARSE-* entry
;; points deliberately surface only hard failures).

(defparameter *recovery-tokenizer*
  (cl-parser-kit:make-tokenizer
   :rules (list (cl-parser-kit:make-whitespace-rule :skip-p t)
                (cl-parser-kit:make-number-rule :type :number)
                (cl-parser-kit:make-identifier-rule :type :identifier)
                (cl-parser-kit:make-literal-rule :equals "=")
                (cl-parser-kit:make-literal-rule :semicolon ";"))))

(defun %semicolon-p (token)
  (eql (cl-parser-kit:token-type token) :semicolon))

;; name = number ; -> (:stmt name value); CONTEXT attaches a note on a missing number.
(defparameter *statement*
  (cl-parser-kit:parse-let* ((name (cl-parser-kit:type-token-value :identifier))
                             (_eq (cl-parser-kit:type-token :equals))
                             (value (cl-parser-kit:context
                                     (cl-parser-kit:type-token-value :number)
                                     "expected a number on the right of ="))
                             (_semi (cl-parser-kit:type-token :semicolon)))
    (list :stmt name value)))

;; Recovery: skip through the next `;` (inclusive), yielding an :error marker.
;; RECOVER keeps the failed statement's diagnostics on this recovered success.
(defparameter *recovery*
  (cl-parser-kit:as-value :error
                          (cl-parser-kit:skip-until #'%semicolon-p :including t)))

;; Drive the loop with MANY-TILL ... END-OF-INPUT (not a bare MANY) so it stops at
;; end of input rather than tripping MANY's non-advancing guard when RECOVERY has
;; nothing left to skip.
(defparameter *program*
  (cl-parser-kit:many-till (cl-parser-kit:recover *statement* *recovery*)
                           (cl-parser-kit:end-of-input)))

(defun parse-program-with-recovery (source)
  "Parse SOURCE, recovering past malformed statements. Returns
(values ok (:results <list> :error-count N :diagnostic-count N) next
diagnostics), reading the recovery diagnostics from RUN-PARSER's fourth
value."
  (let ((tokens (cl-parser-kit:tokenize source *recovery-tokenizer*)))
    (multiple-value-bind (ok value next diagnostics)
        (cl-parser-kit:run-parser *program* tokens 0)
      (if ok
          (values t
                  (list :results value
                        ;; how many statements were recovered (each left an
                        ;; :error marker); the recovery notes are also available
                        ;; in DIAGNOSTICS (RUN-PARSER's fourth value)
                        :error-count (count :error value)
                        :diagnostic-count (length diagnostics))
                  next
                  diagnostics)
          (values nil nil next diagnostics)))))

(defun parse-error-recovery-example ()
  "Two valid statements around one malformed (missing number) statement; the
parse recovers and reports all three results plus the collected error."
  (parse-program-with-recovery "a = 1 ; b = ; c = 3 ;"))

;; (parse-error-recovery-example)
;; => T, (:results ((:stmt "a" 1) :error (:stmt "c" 3)) :error-count 1
;;         :diagnostic-count 1), 11, (...)
