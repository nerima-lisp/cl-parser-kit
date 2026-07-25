(in-package :cl-user)

;; Tiny statement parser example.

(defparameter *mini-language-tokenizer*
  (cl-parser-kit:make-tokenizer
   :rules (list (cl-parser-kit:make-whitespace-rule :skip-p t)
                (cl-parser-kit:make-keyword-rule :let "let")
                (cl-parser-kit:make-literal-rule :equals "=")
                (cl-parser-kit:make-literal-rule :semicolon ";")
                (cl-parser-kit:make-number-rule)
                (cl-parser-kit:make-identifier-rule))))

(defparameter *statement-parser*
  (cl-parser-kit:seq
   (cl-parser-kit:literal "let" :type :let)
   (cl-parser-kit:type-token :identifier)
   (cl-parser-kit:literal "=" :type :equals)
   (cl-parser-kit:type-token :number)
   (cl-parser-kit:opt (cl-parser-kit:literal ";" :type :semicolon))
   (cl-parser-kit:end-of-input)))

;; Evaluate this form in the REPL for an end-to-end parse.
(defun parse-let-statement-example (&optional (source "let answer = 42;"))
  (cl-parser-kit:parse-source *statement-parser* source *mini-language-tokenizer*))

;; (parse-let-statement-example)
