(eval-when (:compile-toplevel :load-toplevel :execute)
  (load (merge-pathnames "bootstrap.lisp"
                         (make-pathname :name nil
                                        :type nil
                                        :version nil
                                        :defaults (or *load-pathname*
                                                      *compile-file-pathname*)))))

(let ((project-root (current-project-root))
      (checks 0)
      (failures 0))
  (labels ((example-path (name)
             (merge-pathnames (concatenate 'string "examples/" name) project-root))
           (load-example (name)
             (load (example-path name)))
           (kit-symbol (name)
             (or (find-symbol name "CL-PARSER-KIT")
                 (error "Missing CL-PARSER-KIT symbol ~A" name)))
           (kit-call (name &rest args)
             (apply (symbol-function (kit-symbol name)) args))
           (call-example (name function-name &rest args)
             (load-example name)
             (apply (symbol-function (find-symbol function-name :cl-user)) args))
           (pass (label)
             (format t "PASS ~A~%" label))
           (fail (label format-control &rest format-args)
             (incf failures)
             (apply #'format *error-output*
                    (concatenate 'string "FAIL " label ": " format-control "~%")
                    format-args))
           (check (label thunk)
             (incf checks)
             (handler-case
                 (progn
                   (funcall thunk)
                   (pass label))
               (error (condition)
                 (fail label "~A" condition))))
           (ensure (condition format-control &rest format-args)
             (unless condition
               (apply #'error format-control format-args)))
           (contains (needle string)
             (not (null (search needle string)))))
    (require :asdf)
    (package-symbol-call :cl-user :load-project-asd-definitions project-root)
    (package-symbol-call :cl-user :load-project-sources project-root)

    (check "tokenizer-example.lisp / tokenize-sum-example"
           (lambda ()
             (let ((tokens (call-example "tokenizer-example.lisp"
                                         "TOKENIZE-SUM-EXAMPLE")))
               (ensure (= 3 (length tokens)) "expected 3 tokens")
               (ensure (eql :identifier (kit-call "TOKEN-TYPE" (aref tokens 0)))
                       "expected identifier token")
               (ensure (eql :plus (kit-call "TOKEN-TYPE" (aref tokens 1)))
                       "expected plus token")
               (ensure (= 42 (kit-call "TOKEN-VALUE" (aref tokens 2)))
                       "expected numeric value 42"))))

    (check "tokenizer-example.lisp / tokenize-custom-language-example"
           (lambda ()
             (let ((tokens (call-example "tokenizer-example.lisp"
                                         "TOKENIZE-CUSTOM-LANGUAGE-EXAMPLE")))
               (ensure (= 4 (length tokens)) "expected 4 tokens")
               (ensure (eql :if (kit-call "TOKEN-TYPE" (aref tokens 0)))
                       "expected keyword token")
               (ensure (string= "$value" (kit-call "TOKEN-VALUE" (aref tokens 1)))
                       "expected identifier payload")
               (ensure (string= "ok" (kit-call "TOKEN-VALUE" (aref tokens 2)))
                       "expected string payload")
               (ensure (string= "if?" (kit-call "TOKEN-VALUE" (aref tokens 3)))
                       "expected trailing identifier payload"))))

    (check "combinator-example.lisp / parse-let-list-example"
           (lambda ()
             (multiple-value-bind (ok value next failure)
                 (call-example "combinator-example.lisp"
                               "PARSE-LET-LIST-EXAMPLE")
               (declare (ignore failure))
               (ensure ok "expected successful parse")
               (ensure (= 9 next) "expected cursor 9, got ~A" next)
               (ensure (string= "x" (kit-call "TOKEN-TEXT" (first (first value))))
                       "expected first identifier x")
               (ensure (string= "z" (kit-call "TOKEN-TEXT" (third (first value))))
                       "expected third identifier z"))))

    (check "sequence-helper-example.lisp / parse-identifier-group-example"
           (lambda ()
             (ensure (equal '(t ("x" "y" "z") 8 nil)
                            (multiple-value-list
                             (call-example "sequence-helper-example.lisp"
                                           "PARSE-IDENTIFIER-GROUP-EXAMPLE")))
                     "unexpected identifier group result")))

    (check "sequence-helper-example.lisp / parse-trailing-identifier-group-example"
           (lambda ()
             (ensure (equal '(t ("x" "y" "z") 9 nil)
                            (multiple-value-list
                             (call-example "sequence-helper-example.lisp"
                                           "PARSE-TRAILING-IDENTIFIER-GROUP-EXAMPLE")))
                     "unexpected trailing identifier group result")))

    (check "sequence-helper-example.lisp / parse-binding-fields-example"
           (lambda ()
             (ensure (equal '(t ("answer" :assign 42) 4 nil)
                            (multiple-value-list
                             (call-example "sequence-helper-example.lisp"
                                           "PARSE-BINDING-FIELDS-EXAMPLE")))
                     "unexpected binding fields result")))

    (check "operator-chain-example.lisp / parse-left-associative-chain-example"
           (lambda ()
             (multiple-value-bind (ok value next failure)
                 (call-example "operator-chain-example.lisp"
                               "PARSE-LEFT-ASSOCIATIVE-CHAIN-EXAMPLE")
               (declare (ignore failure))
               (ensure ok "expected successful parse")
               (ensure (= 5 next) "expected cursor 5, got ~A" next)
               (ensure (= 5 value) "expected value 5, got ~A" value))))

    (check "operator-chain-example.lisp / parse-right-associative-chain-example"
           (lambda ()
             (multiple-value-bind (ok value next failure)
                 (call-example "operator-chain-example.lisp"
                               "PARSE-RIGHT-ASSOCIATIVE-CHAIN-EXAMPLE")
               (declare (ignore failure))
               (ensure ok "expected successful parse")
               (ensure (= 5 next) "expected cursor 5, got ~A" next)
               (ensure (= 512 value) "expected value 512, got ~A" value))))

    (check "token-stream-example.lisp / render-trailing-token-example"
           (lambda ()
             (let ((rendered (call-example "token-stream-example.lisp"
                                           "RENDER-TRAILING-TOKEN-EXAMPLE")))
               (ensure (contains "Unexpected trailing token" rendered)
                       "expected trailing-token diagnostic")
               (ensure (contains "answer = 42 extra" rendered)
                       "expected source excerpt")
               (ensure (contains "^^^^^" rendered)
                       "expected highlight marker"))))

    (check "token-navigation-example.lisp / inspect-token-navigation-example"
           (lambda ()
             (ensure (equal '(:peek "answer"
                              :next ("answer" 1)
                              :eof-before nil
                              :parse (:ok t :value ("answer" 42) :next 3 :failure nil)
                              :eof-after t)
                            (call-example "token-navigation-example.lisp"
                                          "INSPECT-TOKEN-NAVIGATION-EXAMPLE"))
                     "unexpected token navigation result")))

    (check "external-token-diagnostic-example.lisp / render-external-token-diagnostic-example"
           (lambda ()
             (let ((rendered (call-example "external-token-diagnostic-example.lisp"
                                           "RENDER-EXTERNAL-TOKEN-DIAGNOSTIC-EXAMPLE")))
               (ensure (contains "Unexpected trailing token" rendered)
                       "expected trailing-token diagnostic")
               (ensure (contains "2:1-2:2" rendered)
                       "expected line/column range")
               (ensure (contains "  | +" rendered)
                       "expected source gutter"))))

    (check "failure-shaping-example.lisp / inspect-binding-failure-example"
           (lambda ()
             (ensure (equal '(1 :binding-name t :equals)
                            (call-example "failure-shaping-example.lisp"
                                          "INSPECT-BINDING-FAILURE-EXAMPLE"))
                     "unexpected failure-shaping result")))

    (check "expression-parser.lisp / parse-addition-example"
           (lambda ()
             (multiple-value-bind (ok value next failure)
                 (call-example "expression-parser.lisp"
                               "PARSE-POSTFIX-PRECEDENCE-EXAMPLE")
               (declare (ignore failure))
               (ensure ok "expected successful parse")
               (ensure (= 4 next) "expected cursor 4, got ~A" next)
               (ensure (equal '(:add 1 (:fact 2)) value)
                       "unexpected expression parse result"))))

    (check "operator-precedence-example.lisp / parse-arithmetic-expression-example"
           (lambda ()
             (multiple-value-bind (ok value next failure)
                 (call-example "operator-precedence-example.lisp"
                               "PARSE-ARITHMETIC-EXPRESSION-EXAMPLE")
               (declare (ignore failure))
               (ensure ok "expected successful parse")
               (ensure (= 5 next) "expected cursor 5, got ~A" next)
               (ensure (eql 7 value) "unexpected arithmetic result ~A" value))))

    (check "json-parser-example.lisp / parse-json-example"
           (lambda ()
             (multiple-value-bind (ok value next failure)
                 (call-example "json-parser-example.lisp" "PARSE-JSON-EXAMPLE")
               (declare (ignore failure))
               (ensure ok "expected successful parse")
               (ensure (= 17 next) "expected cursor 17, got ~A" next)
               (ensure (equal '(("ok" . t) ("vals" 1.0d0 2.5d0) ("tag" . :null)) value)
                       "unexpected JSON decode ~A" value))))

    (check "error-recovery-example.lisp / parse-error-recovery-example"
           (lambda ()
             (multiple-value-bind (ok value next failure)
                 (call-example "error-recovery-example.lisp"
                               "PARSE-ERROR-RECOVERY-EXAMPLE")
               (declare (ignore failure))
               (ensure ok "expected successful (recovered) parse")
               (ensure (= 11 next) "expected cursor 11, got ~A" next)
               (ensure (equal '((:stmt "a" 1) :error (:stmt "c" 3)) (getf value :results))
                       "unexpected recovery results ~A" (getf value :results))
               (ensure (= 1 (getf value :error-count)) "expected 1 recovered error")
               (ensure (= 1 (getf value :diagnostic-count))
                       "expected 1 collected diagnostic"))))

    (check "csv-parser-example.lisp / parse-csv-example"
           (lambda ()
             (multiple-value-bind (ok value next failure)
                 (call-example "csv-parser-example.lisp" "PARSE-CSV-EXAMPLE")
               (declare (ignore failure))
               (ensure ok "expected successful parse")
               (ensure (= 12 next) "expected cursor 12, got ~A" next)
               (ensure (equal '(("a" "b" "c") ("d" "e,f" "g")) value)
                       "unexpected CSV decode ~A" value))))

    (check "diagnostic-example.lisp / parse-expression-source"
           (lambda ()
             (multiple-value-bind (ok value next failure)
                 (call-example "diagnostic-example.lisp"
                               "PARSE-EXPRESSION-SOURCE"
                               "1 + +")
               (declare (ignore failure))
               (ensure (null ok) "expected parse failure")
               (ensure (= 2 next) "expected cursor 2, got ~A" next)
               (ensure (contains "Expected PREFIX" value)
                       "expected prefix failure message")
               (ensure (contains "1 + +" value)
                       "expected source excerpt"))))

    (check "diagnostic-example.lisp / render-manual-diagnostic-example"
           (lambda ()
             (let ((rendered (call-example "diagnostic-example.lisp"
                                           "RENDER-MANUAL-DIAGNOSTIC-EXAMPLE")))
               (ensure (contains "bad token" rendered)
                       "expected error message")
               (ensure (contains "note: check syntax [1:5-1:6]" rendered)
                       "expected note span")
               (ensure (contains "fix-it [1:1-1:1]: replace with \"x\"" rendered)
                       "expected fix-it hint"))))

    (check "mini-language-parser.lisp / parse-let-statement-example"
           (lambda ()
             (multiple-value-bind (ok value next failure)
                 (call-example "mini-language-parser.lisp"
                               "PARSE-LET-STATEMENT-EXAMPLE")
               (declare (ignore failure))
               (ensure ok "expected successful parse")
               (ensure (= 5 next) "expected cursor 5, got ~A" next)
               (ensure (eql :let (kit-call "TOKEN-TYPE" (first value)))
                       "expected let token")
               (ensure (= 42 (kit-call "TOKEN-VALUE" (fourth value)))
                       "expected numeric payload 42"))))

    (check "cst-example.lisp / parse-binding-cst"
           (lambda ()
             (multiple-value-bind (ok value next failure)
                 (call-example "cst-example.lisp"
                               "PARSE-BINDING-CST"
                               "let answer = 42;")
               (declare (ignore failure))
               (ensure ok "expected successful parse")
               (ensure (= 5 next) "expected cursor 5, got ~A" next)
               (ensure (equal :binding (getf value :type))
                       "expected CST root type :binding")
               (ensure (equal "answer"
                              (getf (second (getf value :children)) :value))
                       "expected CST identifier value answer"))))

    (format t "~&~D example checks, ~D failures~%" checks failures)
    (when (> failures 0)
      #+sbcl (sb-ext:exit :code 1)
      #-sbcl (error "Example checks failed"))))
