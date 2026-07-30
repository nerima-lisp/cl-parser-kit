(in-package :cl-parser-kit/test)

(defmacro %pratt-success (value next)
  `(values t ,value ,next nil))

(defun %build-add (left right)
  (list :add left right))

(defun %build-mul (left right)
  (list :mul left right))

(defun %build-pow (left right)
  (list :pow left right))

(defun %build-fact (value)
  (list :fact value))

(defun %pratt-postfix-led (left operator stream next current-table)
  (declare (ignore operator stream current-table))
  (%pratt-success (%build-fact left) next))

(defun %pratt-fact-led (left operator stream next current-table)
  (%pratt-postfix-led left operator stream next current-table))

(defun %assert-pratt-failure-shape (failure position expected actual-type)
  (expect (parse-failure-position failure) :to-equal position)
  (expect (parse-failure-expected failure) :to-equal expected)
  (expect (token-type (parse-failure-actual failure)) :to-equal actual-type)
  (expect (parse-failure-diagnostics failure) :to-have-length 1))

(defmacro with-pratt-diagnostic-context ((tokenizer table) &body body)
  `(let* ((,tokenizer (make-tokenizer
                       :rules (list (make-whitespace-rule :skip-p t)
                                    (make-literal-rule :plus "+")
                                    (make-number-rule))))
          (,table (make-pratt-demo-table)))
     ,@body))

(defmacro with-pratt-number-table ((table) &body body)
  `(let ((,table (make-pratt-table)))
     (register-prefix-operator ,table :number 0 #'%pratt-number-nud)
     ,@body))

(defmacro with-pratt-plus-table ((table) &body body)
  `(with-pratt-number-table (,table)
     (register-infix-operator ,table :plus 10 11 #'%pratt-add-led)
     ,@body))

(defmacro assert-pratt-failure-rendering ((source tokenizer table) expected-snippets)
  `(multiple-value-bind (ok value next failure)
       (parse-pratt-source ,source ,tokenizer ,table)
     (declare (ignore value next))
     (expect ok :to-be-falsy)
     (expect failure :to-be-truthy)
     (assert-string-contains-all
      (parse-failure->string failure)
      ,expected-snippets)))

(defmacro assert-pratt-success-values (form (value next) &body assertions)
  `(%assert-success-values ,form (,value ,next failure)
     ,@assertions))

(defmacro assert-pratt-failure-values (form (value next failure) &body assertions)
  `(%assert-failure-values ,form (,value ,next ,failure)
     ,@assertions))

(defun %pratt-number-nud (token stream next current-table)
  (declare (ignore stream current-table))
  (%pratt-success (token-value token) next))

(defun %pratt-add-led (left op right next current-table)
  (declare (ignore op current-table))
  (%pratt-success (list :add left right) next))

(defun make-pratt-demo-table ()
  (with-pratt-plus-table (table)
    table))

(defun %pratt-token-vector-from-specs (specs)
  (coerce (mapcar (lambda (spec)
                    (apply #'make-token spec))
                  specs)
          'vector))

(defun %run-pratt-parse (entry-point token-specs operator-specs &rest arguments)
  (let ((table (make-pratt-table))
        (tokens (%pratt-token-vector-from-specs token-specs)))
    (register-pratt-operators table operator-specs)
    (apply entry-point tokens table arguments)))

(defun %run-pratt-source-parse (source literal-specs operator-specs &rest arguments)
  (let ((table (make-pratt-table))
        (tokenizer (apply #'%make-pratt-tokenizer literal-specs)))
    (register-pratt-operators table operator-specs)
    (apply #'parse-pratt-source source tokenizer table arguments)))

(defun %register-number-prefix (table &key (key :number) (binding-power 0))
  (register-prefix-operator table key binding-power
                            (lambda (token stream next current-table)
                              (declare (ignore stream current-table))
                              (%pratt-success (token-value token) next))))

(defun %register-infix-builder (table key left-binding-power right-binding-power builder)
  (register-infix-operator table key left-binding-power right-binding-power
                           (lambda (left op right next current-table)
                             (declare (ignore op current-table))
                             (%pratt-success (funcall builder left right) next))))

(defun %register-postfix-builder (table key binding-power builder)
  (register-postfix-operator table key binding-power
                             (lambda (left op stream next current-table)
                               (declare (ignore op stream current-table))
                               (%pratt-success (funcall builder left) next))))

(defun register-pratt-operators (table operator-specs)
  (dolist (spec operator-specs table)
    (destructuring-bind (kind key binding builder &optional right-binding-power) spec
      (ecase kind
        (:prefix
         (%register-number-prefix table :key key :binding-power binding))
        (:infix
         (%register-infix-builder table key binding right-binding-power builder))
        (:postfix
         (%register-postfix-builder table key binding builder))))))

(defun %make-pratt-tokenizer (&rest literal-keys)
  (make-tokenizer
   :rules (append (list (make-whitespace-rule :skip-p t))
                  (mapcar (lambda (literal-key)
                            (apply #'make-literal-rule literal-key))
                          literal-keys)
                  (list (make-number-rule)))))

(defun %make-number-prefix-table ()
  (let ((table (make-pratt-table)))
    (%register-number-prefix table)
    table))

(defun %register-plus-builder (table builder)
  (register-infix-operator table :plus 10 11
                           (lambda (left op right next current-table)
                             (declare (ignore op current-table))
                             (%pratt-success (funcall builder left right) next))))

(defun %run-pratt-plus-rhs-metadata-failure ()
  (let* ((source "1
+
+")
         (table (%make-number-prefix-table))
         (tokens (vector (make-token :type :number
                                     :text "1"
                                     :value 1
                                     :start 0
                                     :end 1
                                     :metadata (list :source source))
                         (make-token :type :plus
                                     :text "+"
                                     :start 2
                                     :end 3
                                     :metadata (list :source source))
                         (make-token :type :plus
                                     :text "+"
                                     :start 4
                                     :end 5
                                     :metadata (list :source source)))))
    (%register-plus-builder table (lambda (left right)
                                    (declare (ignore left right))
                                    nil))
    (parse-pratt tokens table)))

(defun %run-pratt-trailing-metadata-failure ()
  (let* ((source "1 + 1
2")
         (table (%make-number-prefix-table))
         (tokens (vector (make-token :type :number
                                     :text "1"
                                     :value 1
                                     :start 0
                                     :end 1
                                     :metadata (list :source source))
                         (make-token :type :plus
                                     :text "+"
                                     :start 2
                                     :end 3
                                     :metadata (list :source source))
                         (make-token :type :number
                                     :text "1"
                                     :value 1
                                     :start 4
                                     :end 5
                                     :metadata (list :source source))
                         (make-token :type :number
                                     :text "2"
                                     :value 2
                                     :start 6
                                     :end 7
                                     :metadata (list :source source)))))
    (%register-plus-builder table #'+)
    (parse-pratt-all tokens table)))
