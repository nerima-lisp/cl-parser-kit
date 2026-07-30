(in-package :cl-parser-kit/test)

(it-sequential "tokenizer-basic"
  (let* ((tokenizer (make-tokenizer :rules (%basic-tokenizer-rules)))
         (tokens (tokenize-string "sum + 42" tokenizer)))
    (assert-tokenizer-tokens
     tokens
     (list (%make-tokenizer-token-spec :type :identifier :value "sum")
           (%make-tokenizer-token-spec :type :plus :value "+")
           (%make-tokenizer-token-spec :type :number :value 42)))))

(it-sequential "tokenizer-unknown-and-span-test"
  (let* ((tokenizer (make-tokenizer :rules (%number-only-tokenizer-rules)))
         (tokens (tokenize "1
?" tokenizer)))
    (assert-tokenizer-tokens
     tokens
     (list (%make-tokenizer-token-spec :type :number :value 1)
           (%make-tokenizer-token-spec :type :unknown
                                       :value #\?
                                       :text "?"
                                       :span '(2 1 2 2))))))

;;; Resource-limit guards (security hardening): TOKENIZE bounds source length
;;; and emitted-token count, and the number rule bounds a single lexeme, so
;;; hostile input fails gracefully instead of exhausting memory or CPU.

(it-sequential "tokenizer-source-length-limit-signals-resource-error-test"
  (let ((*maximum-tokenizer-source-length* 10))
    (expect (lambda ()
              (tokenize (make-string 11 :initial-element #\a)
                       (make-tokenizer :rules (%basic-tokenizer-rules))))
            :to-throw 'tokenizer-resource-limit-exceeded)))

(it-sequential "tokenizer-source-length-limit-allows-input-within-limit-test"
  (let ((*maximum-tokenizer-source-length* 10))
    (expect (tokenize (make-string 10 :initial-element #\a)
                      (make-tokenizer :rules (%basic-tokenizer-rules)))
            :to-satisfy (lambda (tokens) (= (length tokens) 1)))))

(it-sequential "tokenizer-token-count-limit-signals-resource-error-test"
  (let ((*maximum-tokenizer-tokens* 5))
    (expect (lambda ()
              (tokenize (format nil "~{~A~^ ~}" (loop repeat 10 collect "x"))
                       (make-tokenizer :rules (%basic-tokenizer-rules))))
            :to-throw 'tokenizer-resource-limit-exceeded)))

(it-sequential "tokenizer-token-count-limit-allows-input-within-limit-test"
  (let ((*maximum-tokenizer-tokens* 5))
    (expect (tokenize (format nil "~{~A~^ ~}" (loop repeat 5 collect "x"))
                      (make-tokenizer :rules (%basic-tokenizer-rules)))
            :to-satisfy (lambda (tokens) (= (length tokens) 5)))))

(it-sequential "tokenizer-rule-count-limit-rejects-excessive-rules-test"
  (let ((*maximum-tokenizer-rules* 1))
    (expect (lambda ()
              (tokenize "a" (make-tokenizer :rules (list (make-identifier-rule)
                                                         (make-number-rule)))))
            :to-throw 'tokenizer-resource-limit-exceeded)))

(it-sequential "tokenizer-rejects-improper-rule-list-test"
  (let ((rules (cons (make-identifier-rule) :tail)))
    (expect (lambda ()
              (tokenize "a" (make-tokenizer :rules rules)))
            :to-throw 'error)))

(it-sequential "number-rule-lexeme-length-limit-splits-hostile-digit-run-test"
  (let* ((*maximum-number-lexeme-length* 5)
         (tokenizer (make-tokenizer :rules (list (make-number-rule))))
         (tokens (tokenize (make-string 12 :initial-element #\9) tokenizer)))
    (expect (length tokens) :to-equal 3)
    (expect (map 'list #'token-text tokens)
            :to-equal '("99999" "99999" "99"))))

(it-sequential "number-rule-parses-a-decimal-number-test"
  (let* ((tokenizer (make-tokenizer :rules (list (make-number-rule))))
         (tokens (tokenize "3.14" tokenizer)))
    (assert-tokenizer-tokens
     tokens
     (list (%make-tokenizer-token-spec :type :number :text "3.14" :value 3.14)))))

(it-sequential "number-rule-saturates-instead-of-signalling-on-a-huge-decimal-test"
  ;; *MAXIMUM-NUMBER-LEXEME-LENGTH* caps the lexeme at 1024 characters, which
  ;; bounds the intermediate rational but still admits an integer part well past
  ;; MOST-POSITIVE-SINGLE-FLOAT -- 39 digits suffices. %PARSE-DECIMAL-TEXT used
  ;; to COERCE unguarded, so this input escaped TOKENIZE as an unhandled
  ;; FLOATING-POINT-OVERFLOW rather than producing a token.
  (let* ((tokenizer (make-tokenizer :rules (list (make-number-rule))))
         (source (concatenate 'string (make-string 40 :initial-element #\9) ".5"))
         (tokens (tokenize source tokenizer)))
    (expect (length tokens) :to-equal 1)
    (expect (token-value (elt tokens 0)) :to-equal most-positive-single-float)))

(it-sequential "number-rule-rejects-a-second-interior-decimal-point-test"
  ;; A second '.' is rejected once SEEN-DOT is already true, splitting a
  ;; hostile run like "1.2.3" into a decimal number, a lone unmatched dot, and
  ;; a trailing integer rather than one malformed lexeme.
  (let* ((tokenizer (make-tokenizer :rules (list (make-number-rule))))
         (tokens (tokenize "1.2.3" tokenizer)))
    (assert-tokenizer-tokens
     tokens
     (list (%make-tokenizer-token-spec :type :number :text "1.2" :value 1.2)
           (%make-tokenizer-token-spec :type :unknown :text "." :value #\.)
           (%make-tokenizer-token-spec :type :number :text "3" :value 3)))))

(it-sequential "tokenizer-rule-constructors-reject-zero-width-basic-rules-test"
  (expect (lambda () (make-literal-rule :empty ""))
          :to-throw 'error)
  (expect (lambda ()
            (make-predicate-rule :predicate
                                 (lambda (char)
                                   (declare (ignore char))
                                   t)
                                 :min-length 0))
          :to-throw 'error))

(it-sequential "tokenizer-predicate-rule-skip-p-emits-no-token-test"
  (let* ((tokenizer (make-tokenizer
                     :rules (list (make-predicate-rule :ws (lambda (char) (char= char #\Space))
                                                       :skip-p t)
                                  (make-identifier-rule))))
         (tokens (tokenize "  x" tokenizer)))
    (expect (length tokens) :to-equal 1)
    (expect (token-text (elt tokens 0)) :to-equal "x")))
