(in-package :cl-parser-kit/test)

(defun example-file-names ()
  (sort (mapcar #'file-namestring
                (directory (project-file-path "examples/*.lisp")))
        #'string<))

(defun example-path (name)
  (project-file-path (concatenate 'string "examples/" name)))

(defun load-example-file (name)
  (load (example-path name)))

(defun call-example-function (name function-name &rest args)
  (load-example-file name)
  (let ((function (symbol-function (find-symbol function-name :cl-user))))
    (apply function args)))

(defmacro assert-example-values (form (ok value next failure) &body assertions)
  `(%assert-multiple-values ,form (,ok ,value ,next ,failure)
     ,@assertions))

(defmacro assert-example-success (form (value next failure) &body assertions)
  `(assert-example-values ,form (ok ,value ,next ,failure)
     (declare (ignorable ok))
     (expect ok :to-be-truthy)
     ,@assertions))

(defmacro assert-example-successes (&body specs)
  `(progn
     ,@(loop for (form (value next failure) . assertions) in specs
             collect `(assert-example-success ,form (,value ,next ,failure)
                        ,@assertions))))

(defmacro with-punctuated-example-parsers ((tokenizer group-parser binding-parser) &body body)
  `(let* ((,tokenizer (make-punctuated-example-tokenizer))
          (,group-parser
            (terminated-by
             (delimited-sep-by
              (literal "(" :type :lparen)
              (type-token-text :identifier)
              (literal "," :type :comma)
              (literal ")" :type :rparen))
             (literal ";" :type :semicolon)))
          (,binding-parser
            (seq-map
             (lambda (identifier operator value end-of-input)
               (declare (ignore end-of-input))
               (list identifier operator value))
             (type-token-text :identifier)
             (literal-value "=" :type :equals)
             (terminated-by
              (type-token-value :number)
              (literal-text ";" :type :semicolon))
             (end-of-input))))
     ,@body))

(defmacro assert-example-failure (form (value next failure) &body assertions)
  `(assert-example-values ,form (ok ,value ,next ,failure)
     (declare (ignorable ,value ,failure))
     (expect ok :to-be-falsy)
     (expect ,value :to-be-falsy)
     ,@assertions))

(defmacro register-example-test-case (name &body body)
  `(it-sequential ,(string-downcase (string name))
     ,@body))

(defmacro register-example-render-test (name file function snippets)
  `(register-example-test-case ,name
     (let ((rendered (call-example-function ,file ,function)))
       (expect (stringp rendered) :to-be-truthy)
       (assert-string-contains-all rendered ,snippets))))

(defmacro register-example-render-tests (&rest specs)
  `(progn
     ,@(loop for (name file function snippets) in specs
             collect `(register-example-render-test ,name ,file ,function ,snippets))))

(defmacro register-example-success-test (name file function form (value next failure) &body assertions)
  `(register-example-test-case ,name
     (assert-example-success
      (call-example-function ,file ,function ,@form)
      (,value ,next ,failure)
      ,@assertions)))

(defmacro register-example-success-tests (&rest specs)
  `(progn
     ,@(loop for (name file function form (value next failure) . assertions) in specs
             collect `(register-example-success-test ,name ,file ,function ,form
                           (,value ,next ,failure)
                        ,@assertions))))

(defmacro register-example-test-cases (&rest specs)
  `(progn
     ,@(loop for (name . body) in specs
             collect `(register-example-test-case ,name
                        ,@body))))
