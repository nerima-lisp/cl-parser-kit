(in-package :cl-user)

;; Tiny CST-oriented example.

(defparameter *cst-tokenizer*
  (cl-parser-kit:make-tokenizer
   :rules (list (cl-parser-kit:make-whitespace-rule :skip-p t)
                (cl-parser-kit:make-keyword-rule :let "let")
                (cl-parser-kit:make-literal-rule :equals "=")
                (cl-parser-kit:make-literal-rule :semicolon ";")
                (cl-parser-kit:make-number-rule)
                (cl-parser-kit:make-identifier-rule))))

(defparameter *binding-parser*
  (cl-parser-kit:seq
   (cl-parser-kit:literal "let" :type :let)
   (cl-parser-kit:type-token :identifier)
   (cl-parser-kit:literal "=" :type :equals)
   (cl-parser-kit:type-token :number)
   (cl-parser-kit:opt (cl-parser-kit:literal ";" :type :semicolon))
   (cl-parser-kit:end-of-input)))

(defun build-binding-cst (parsed)
  (destructuring-bind (let-token identifier-token equals-token number-token semicolon-token eof-token) parsed
    (declare (ignore eof-token))
    (cl-parser-kit:make-cst-node
     :type :binding
     :span (cl-parser-kit:span-merge (cl-parser-kit:token-span let-token)
                                     (or (and semicolon-token (cl-parser-kit:token-span semicolon-token))
                                         (cl-parser-kit:token-span number-token)))
     :children (remove nil
                       (list (cl-parser-kit:make-cst-node
                              :type :keyword
                              :value (cl-parser-kit:token-text let-token)
                              :span (cl-parser-kit:token-span let-token))
                             (cl-parser-kit:make-cst-node
                              :type :identifier
                              :value (cl-parser-kit:token-text identifier-token)
                              :span (cl-parser-kit:token-span identifier-token))
                             (cl-parser-kit:make-cst-node
                              :type :punctuation
                              :value (cl-parser-kit:token-text equals-token)
                              :span (cl-parser-kit:token-span equals-token))
                             (cl-parser-kit:make-cst-node
                              :type :number
                              :value (cl-parser-kit:token-text number-token)
                              :span (cl-parser-kit:token-span number-token))
                             (and semicolon-token
                                  (cl-parser-kit:make-cst-node
                                   :type :punctuation
                                   :value (cl-parser-kit:token-text semicolon-token)
                                   :span (cl-parser-kit:token-span semicolon-token))))))))

(defun parse-binding-cst (source &optional (tokenizer *cst-tokenizer*))
  (multiple-value-bind (ok value next failure)
      (cl-parser-kit:parse-source *binding-parser* source tokenizer)
    (if ok
        (values t (cl-parser-kit:cst-node->sexp (build-binding-cst value) :include-span t) next nil)
        (values nil nil next failure))))
