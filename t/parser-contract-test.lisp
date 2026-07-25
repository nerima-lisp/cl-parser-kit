(in-package :cl-parser-kit/test)

(it-sequential "public-parser-entry-points-are-exported-test"
  (dolist (name '(seq
                  alt
                  opt
                  label
                  parse-tokens
                  parse-all
                  parse-source
                  parse-pratt
                  parse-pratt-source))
    (multiple-value-bind (symbol status)
        (find-symbol (symbol-name name) :cl-parser-kit)
      (expect symbol :to-be-truthy)
      (expect status :to-equal :external))))

(it-sequential "parser-resource-limit-specials-are-exported-and-bound-test"
  (dolist (name '(*maximum-parser-recursion-depth*
                  *maximum-parser-tokens*
                  *maximum-parser-repetition-count*))
    (multiple-value-bind (symbol status)
        (find-symbol (symbol-name name) :cl-parser-kit)
      (expect symbol :to-be-truthy)
      (expect status :to-equal :external)
      (expect (boundp symbol) :to-be-truthy)
      (expect (integerp (symbol-value symbol)) :to-be-truthy)
      (expect (plusp (symbol-value symbol)) :to-be-truthy))))

(it-each ((parse-tokens nil nil) (parse-tokens t nil)
          (parse-all nil nil) (run-parser t t))
    "~(~A~)-enforces-token-count-limit-on-a-~:[vector~;list~]-test"
    (fn as-list-p needs-position-p)
  ;; PARSE-TOKENS, PARSE-ALL, and RUN-PARSER each have their own
  ;; %ENSURE-PARSER-TOKEN-VECTOR call ahead of the shared token-vector
  ;; coercion, so each needs its own enforcement test rather than trusting
  ;; that testing one entry point covers the others; AS-LIST-P additionally
  ;; exercises the LIST (not just VECTOR) coercion path on two of the four.
  (let* ((*maximum-parser-tokens* 1)
         (raw (list (make-token :type :identifier :text "a")
                    (make-token :type :identifier :text "b")))
         (tokens (if as-list-p raw (coerce raw 'vector))))
    (assert-combinator-failure
        (if needs-position-p
            (funcall fn (type-token :identifier) tokens 0)
            (funcall fn (type-token :identifier) tokens))
        (value next failure)
      (expect next :to-equal 0)
      (expect (parse-failure-expected failure) :to-equal :maximum-parser-tokens)
      (expect (parse-failure-actual failure) :to-equal 2))))

(it-sequential "parse-all-rejects-circular-token-list-test"
  (let ((*maximum-parser-tokens* 1)
        (tokens (list (make-token :type :identifier :text "a"))))
    (setf (cdr tokens) tokens)
    (expect (lambda ()
              (parse-all (type-token :identifier) tokens))
            :to-throw 'error)))

(it-sequential "parse-all-rejects-improper-token-list-test"
  (let ((tokens (cons (make-token :type :identifier :text "a") :tail)))
    (expect (lambda ()
              (parse-all (type-token :identifier) tokens))
            :to-throw 'error)))


(it-sequential "run-parser-rejects-circular-token-list-test"
  (let ((*maximum-parser-tokens* 1)
        (tokens (list (make-token :type :identifier :text "a"))))
    (setf (cdr tokens) tokens)
    (expect (lambda ()
              (run-parser (type-token :identifier) tokens 0))
            :to-throw 'error)))

(it-sequential "run-parser-rejects-improper-token-list-test"
  (let ((tokens (cons (make-token :type :identifier :text "a") :tail)))
    (expect (lambda ()
              (run-parser (type-token :identifier) tokens 0))
            :to-throw 'error)))

(it-sequential "run-parser-accepts-a-plain-token-list-test"
  (let ((tokens (list (make-token :type :identifier :text "a"))))
    (assert-combinator-success (run-parser (type-token :identifier) tokens 0)
        (value next diagnostics)
      (declare (ignore diagnostics))
      (expect (token-text value) :to-equal "a")
      (expect next :to-equal 1))))

(it-sequential "ensure-vector-stops-circular-list-coercion-at-token-count-limit-test"
  (let ((*maximum-parser-tokens* 1)
        (tokens (list (make-token :type :identifier :text "a"))))
    (setf (cdr tokens) tokens)
    (expect (lambda ()
              (cl-parser-kit::ensure-vector tokens))
            :to-throw 'error)))

(it-sequential "ensure-vector-rejects-improper-token-list-test"
  (let ((tokens (cons (make-token :type :identifier :text "a") :tail)))
    (expect (lambda ()
              (cl-parser-kit::ensure-vector tokens))
            :to-throw 'error)))

(it-sequential "ensure-list-passes-through-a-proper-list-test"
  (expect (cl-parser-kit::ensure-list (list 1 2 3)) :to-equal '(1 2 3)))

(it-sequential "ensure-list-wraps-a-non-list-atom-test"
  (expect (cl-parser-kit::ensure-list :atom) :to-equal '(:atom)))

(it-sequential "ensure-list-rejects-a-circular-list-test"
  (let ((items (list 1 2 3)))
    (setf (cdr (last items)) items)
    (expect (lambda () (cl-parser-kit::ensure-list items)) :to-throw 'error)))

(it-sequential "ensure-list-rejects-an-improper-list-test"
  (expect (lambda () (cl-parser-kit::ensure-list (cons 1 2))) :to-throw 'error))

(it-sequential "ensure-vector-rejects-a-plain-too-long-vector-test"
  ;; A finite (non-circular) vector or string past *MAXIMUM-PARSER-TOKENS* must
  ;; also raise -- ENSURE-VECTOR's length check is not only reachable through
  ;; the circular-list detection path exercised above.
  (let ((*maximum-parser-tokens* 1))
    (expect (lambda ()
              (cl-parser-kit::ensure-vector
               (vector (make-token :type :identifier :text "a")
                      (make-token :type :identifier :text "b"))))
            :to-throw 'error)))

(it-sequential "ensure-vector-rejects-a-plain-too-long-string-test"
  (let ((*maximum-parser-tokens* 1))
    (expect (lambda () (cl-parser-kit::ensure-vector "ab")) :to-throw 'error)))

(it-sequential "ensure-vector-coerces-a-string-within-the-limit-test"
  ;; A string already satisfies VECTOR, so COERCE returns it unchanged.
  (expect (cl-parser-kit::ensure-vector "ab") :to-equal "ab"))

(it-sequential "ensure-vector-rejects-a-value-that-is-neither-string-vector-nor-list-test"
  ;; ENSURE-VECTOR-UP-TO's ETYPECASE has no catch-all clause, so a token-stream
  ;; argument of any other type (an integer here) signals a TYPE-ERROR
  ;; directly, distinct from every other rejection above, which all involve a
  ;; malformed LIST.
  (expect (lambda () (cl-parser-kit::ensure-vector 42)) :to-throw 'type-error))

(it-sequential "api-guide-documents-all-exported-symbols-test"
  (let* ((documented
           (remove-if (lambda (line) (string= line ""))
                      (uiop:split-string
                       (uiop:run-program
                        (list "perl"
                              "-ne"
                              "if (/^```/) { $in = !$in; next } next if $in; while (/`([^`]+)`/g) { print lc($1), qq(\\n) }"
                              (namestring (parser-project-file-path "docs/src/api-reference.md")))
                        :output :string)
                       :separator '(#\Newline))))
         (exported
           (let ((symbols '()))
             (do-external-symbols (symbol :cl-parser-kit)
               (push (string-downcase (symbol-name symbol)) symbols))
             (sort symbols #'string<)))
         (missing (loop for name in exported
                        unless (member name documented :test #'string=)
                        collect name)))
    (expect missing :to-equal '())))
