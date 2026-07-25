(in-package :cl-user)

;; Pratt parsing example that also exposes structured failure diagnostics.
;; Try: (parse-expression-source "1 + +")

(defparameter *diagnostic-tokenizer*
  (cl-parser-kit:make-tokenizer
   :rules (list (cl-parser-kit:make-whitespace-rule :skip-p t)
                (cl-parser-kit:make-literal-rule :plus "+")
                (cl-parser-kit:make-number-rule))))

(defparameter *pratt-table*
  (let ((table (cl-parser-kit:make-pratt-table)))
    (labels ((number-nud (token stream next current-table)
               (declare (ignore stream current-table))
               (values t (cl-parser-kit:token-value token) next nil))
             (plus-led (left op right next current-table)
               (declare (ignore op current-table))
               (values t (list :add left right) next nil)))
      (cl-parser-kit:register-prefix-operator table :number 0 #'number-nud)
      (cl-parser-kit:register-infix-operator table :plus 10 11 #'plus-led))
    table))

(defun parse-expression-source (source &optional (tokenizer *diagnostic-tokenizer*) (table *pratt-table*))
  (multiple-value-bind (ok value next failure)
      (cl-parser-kit:parse-pratt-source source tokenizer table)
    (if ok
        (values t value next nil)
        (values nil
                (cl-parser-kit:parse-failure->string failure)
                next
                failure))))

;; Building a diagnostic by hand: message, primary span, an explanatory note,
;; and a fix-it suggestion. Try: (princ (render-manual-diagnostic-example))
(defun render-manual-diagnostic-example ()
  (let* ((source "foo + bar")
         (primary-span (cl-parser-kit:make-span
                        :source source :start 4 :end 5
                        :start-line 1 :start-column 5
                        :end-line 1 :end-column 6))
         (note (cl-parser-kit:note-diagnostic
                "check syntax" :span primary-span))
         (fix (cl-parser-kit:make-fix-it
               :span (cl-parser-kit:make-span
                      :source source :start 0 :end 0
                      :start-line 1 :start-column 1
                      :end-line 1 :end-column 1)
               :replacement "x"))
         (diagnostic (cl-parser-kit:error-diagnostic
                      "bad token"
                      :span primary-span
                      :notes (list note)
                      :fixes (list fix))))
    (cl-parser-kit:diagnostic->string diagnostic)))
