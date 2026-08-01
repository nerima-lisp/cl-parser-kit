# Diagnostics

How a parse failure becomes something a user can read, and how to build a
diagnostic by hand when the parser is not the one reporting the problem.

## Failure rendering with source excerpts

```lisp
(let* ((tokenizer (cl-parser-kit:make-tokenizer
                   :rules (list (cl-parser-kit:make-whitespace-rule :skip-p t)
                                (cl-parser-kit:make-literal-rule :plus "+")
                                (cl-parser-kit:make-number-rule))))
       (table (cl-parser-kit:make-pratt-table)))
  (cl-parser-kit:register-prefix-operator
   table :number 0
   (lambda (token stream next current-table)
     (declare (ignore stream current-table))
     (values t (cl-parser-kit:token-value token) next nil)))
  (cl-parser-kit:register-infix-operator
   table :plus 10 11
   (lambda (left op right next current-table)
     (declare (ignore op current-table))
     (values t (list :add left right) next nil)))
  (multiple-value-bind (ok value next failure)
      (cl-parser-kit:parse-pratt-source "1 + +" tokenizer table)
    (declare (ignore next))
    (if ok
        value
        (cl-parser-kit:parse-failure->string failure))))
```
## Building diagnostics directly

When callers need to construct a user-facing diagnostic directly, the
public API also supports notes and fix-its:

```lisp
(cl-parser-kit:diagnostic->string
 (cl-parser-kit:error-diagnostic
  "bad token"
  :span (cl-parser-kit:make-span :source "foo + bar"
                                 :start 0 :end 3
                                 :start-line 1 :start-column 1
                                 :end-line 1 :end-column 2)
  :notes (list (cl-parser-kit:note-diagnostic
                "check syntax"
                :span (cl-parser-kit:make-span :start 4 :end 5
                                               :start-line 1 :start-column 5
                                               :end-line 1 :end-column 6)))
  :fixes (list (cl-parser-kit:make-fix-it
                :span (cl-parser-kit:make-span :start 0 :end 1)
                :replacement "x"))))
```
