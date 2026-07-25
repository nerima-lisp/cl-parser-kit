(in-package :cl-user)

;; Example parsers for sequence helpers that project token text/value directly.

(defparameter *sequence-helper-tokenizer*
  (cl-parser-kit:make-tokenizer
   :rules (list (cl-parser-kit:make-whitespace-rule :skip-p t)
                (cl-parser-kit:make-literal-rule :lparen "(")
                (cl-parser-kit:make-literal-rule :rparen ")")
                (cl-parser-kit:make-literal-rule :comma ",")
                (cl-parser-kit:make-literal-rule :semicolon ";")
                (cl-parser-kit:make-identifier-rule))))

(defparameter *identifier-group-parser*
  (cl-parser-kit:terminated-by
   (cl-parser-kit:delimited-sep-by
    (cl-parser-kit:literal "(" :type :lparen)
    (cl-parser-kit:type-token-text :identifier)
    (cl-parser-kit:literal "," :type :comma)
    (cl-parser-kit:literal ")" :type :rparen))
   (cl-parser-kit:literal ";" :type :semicolon)))

(defparameter *trailing-identifier-group-parser*
  (cl-parser-kit:terminated-by
   (cl-parser-kit:delimited-sep-end-by
    (cl-parser-kit:literal "(" :type :lparen)
    (cl-parser-kit:type-token-text :identifier)
    (cl-parser-kit:literal "," :type :comma)
    (cl-parser-kit:literal ")" :type :rparen))
   (cl-parser-kit:literal ";" :type :semicolon)))

(defun parse-identifier-group-example (&optional (source "(x, y, z);"))
  (cl-parser-kit:parse-source
   *identifier-group-parser*
   source
   *sequence-helper-tokenizer*))

(defun parse-trailing-identifier-group-example (&optional (source "(x, y, z,);"))
  (cl-parser-kit:parse-source
   *trailing-identifier-group-parser*
   source
   *sequence-helper-tokenizer*))

(defun parse-binding-fields-example ()
  (cl-parser-kit:parse-tokens
   (cl-parser-kit:seq-map
    (lambda (identifier operator value end-of-input)
      (declare (ignore end-of-input))
      (list identifier operator value))
    (cl-parser-kit:type-token-text :identifier)
    (cl-parser-kit:literal-value "=" :type :equals)
    (cl-parser-kit:terminated-by
     (cl-parser-kit:type-token-value :number)
     (cl-parser-kit:literal-text ";" :type :semicolon))
    (cl-parser-kit:end-of-input))
   (vector (cl-parser-kit:make-token :type :identifier :text "answer")
           (cl-parser-kit:make-token :type :equals :text "=" :value :assign)
           (cl-parser-kit:make-token :type :number :text "42" :value 42)
           (cl-parser-kit:make-token :type :semicolon :text ";"))))

;; (parse-identifier-group-example)
;; (parse-trailing-identifier-group-example)
;; (parse-binding-fields-example)
