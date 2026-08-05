(in-package :cl-parser-kit/test)

(defun %make-combinator-span (spec)
  (destructuring-bind (&key source
                            (start 0)
                            (end 0)
                            (start-line 1)
                            (start-column 1)
                            (end-line 1)
                            (end-column 1))
      spec
    (make-span :source source
               :start start
               :end end
               :start-line start-line
               :start-column start-column
               :end-line end-line
               :end-column end-column)))

(defun %normalize-combinator-token-spec (spec)
  (if (member :span spec)
      (let ((normalized-spec (copy-list spec)))
        (setf (getf normalized-spec :span)
              (%make-combinator-span (getf normalized-spec :span)))
        normalized-spec)
      spec))

(defun %make-combinator-token (spec)
  (apply #'make-token (%normalize-combinator-token-spec spec)))

(defun %make-combinator-tokens (specs)
  (coerce (mapcar #'%make-combinator-token specs) 'vector))

(defmacro with-combinator-tokens ((tokens token-specs) &body body)
  `(let ((,tokens (%make-combinator-tokens ,token-specs)))
     ,@body))

(defmacro assert-combinator-values (form (ok value next failure) &body assertions)
  `(%assert-multiple-values ,form (,ok ,value ,next ,failure)
     ,@assertions))

(defmacro assert-combinator-success (form (value next failure) &body assertions)
  `(%assert-success-values ,form (,value ,next ,failure)
     ,@assertions))

(defmacro assert-combinator-failure (form (value next failure) &body assertions)
  `(%assert-failure-values ,form (,value ,next ,failure)
     ,@assertions))

(defmacro assert-combinator-projected-values (form (value next failure)
                                              expected-next expected-values
                                              projector)
  `(assert-combinator-success ,form (,value ,next ,failure)
     (expect ,next :to-equal ,expected-next)
     (expect (mapcar ,projector ,value) :to-equal ,expected-values)))

(defun %assert-rendered-diagnostic-contains (diagnostic &rest snippets)
  (expect diagnostic :to-be-truthy)
  (assert-string-contains-all (diagnostic->string diagnostic) snippets))

(defun %assert-single-diagnostic (diagnostics &rest snippets)
  (expect diagnostics :to-have-length 1)
  (apply #'%assert-rendered-diagnostic-contains (first diagnostics) snippets))

(defmacro assert-separator-combinator-failure (form expected-next expected-expected expected-actual)
  (let ((expected-next-value (gensym "EXPECTED-NEXT")))
    `(let ((,expected-next-value ,expected-next))
       (assert-combinator-failure ,form (value next failure)
         (check-type failure parse-failure)
         (expect next :to-equal ,expected-next-value)
         (expect (parse-failure-position failure) :to-equal ,expected-next-value)
         (expect (parse-failure-expected failure) :to-equal ,expected-expected)
         (let ((actual (parse-failure-actual failure)))
           (expect (if (cl-parser-kit::parser-p actual) (parser-name actual) actual)
                   :to-equal ,expected-actual))))))
