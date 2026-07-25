(in-package :cl-parser-kit/test)

(register-example-test-cases
 (readme-seq-helper-projection-snippet-test
  (with-punctuated-example-parsers (tokenizer group-parser binding-parser)
    (assert-example-successes
     ((parse-source group-parser "(answer, result);" tokenizer)
      (value next failure)
      (expect next :to-equal 6)
      (expect value :to-equal '("answer" "result")))
     ((parse-tokens
       binding-parser
       (vector (make-token :type :identifier :text "answer")
               (make-token :type :equals :text "=" :value :assign)
               (make-token :type :number :text "42" :value 42)
               (make-token :type :semicolon :text ";")))
      (value next failure)
      (expect next :to-equal 4)
      (expect value :to-equal '("answer" :assign 42))))))
 (examples-guide-opt-trailing-separator-snippet-test
  (let* ((tokenizer (make-punctuated-example-tokenizer))
         (parser
           (delimited-sep-end-by
            (literal "(" :type :lparen)
            (type-token-text :identifier)
            (literal "," :type :comma)
            (literal ")" :type :rparen))))
    (assert-example-successes
     ((parse-source parser "(answer, result)" tokenizer)
      (value next failure)
      (expect next :to-equal 5)
      (expect value :to-equal '("answer" "result")))
     ((parse-source parser "(answer, result,)" tokenizer)
      (value next failure)
      (expect next :to-equal 6)
      (expect value :to-equal '("answer" "result"))))))
 (readme-parse-tokens-snippet-test
  (let* ((tokens (vector (make-token :type :identifier :text "answer")
                         (make-token :type :equals :text "=")
                         (make-token :type :number :text "42" :value 42)))
         (parser (seq
                  (type-token :identifier)
                  (type-token :equals)
                  (type-token :number))))
    (assert-example-success
     (parse-tokens parser tokens)
     (value next failure)
     (expect next :to-equal 3)
     (expect (token-text (first value)) :to-equal "answer")
     (expect (token-text (second value)) :to-equal "=")
     (expect (token-value (third value)) :to-equal 42))))
 (readme-token-navigation-snippet-test
  (let* ((tokens (vector (make-token :type :identifier :text "answer")
                         (make-token :type :equals :text "=")
                         (make-token :type :number :text "42" :value 42)))
         (parser
           (seq-map
            (lambda (identifier-token equals-token number-value end-of-input)
              (declare (ignore equals-token end-of-input))
              (list (token-text identifier-token) number-value))
            (satisfies-token
             (lambda (token)
               (and (eql (token-type token) :identifier)
                    (> (length (token-text token)) 3)))
             :expected-name :long-identifier)
            (type-token :equals)
            (type-token-value :number)
            (end-of-input))))
    (multiple-value-bind (first next)
        (next-token tokens 0)
      (expect (token-text (peek-token tokens 0)) :to-equal "answer")
      (expect (token-text first) :to-equal "answer")
      (expect next :to-equal 1)
      (expect (eof-token-p tokens next) :to-be-falsy)
      (assert-example-success
       (parse-tokens parser tokens)
       (value parse-next failure)
       (expect parse-next :to-equal 3)
       (expect value :to-equal '("answer" 42))
       (expect failure :to-be-falsy))
      (expect (eof-token-p tokens (length tokens)) :to-be-truthy)))))
