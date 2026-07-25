(in-package :cl-user)

;; Inspect a pre-tokenized stream and apply a custom token predicate.

(defun inspect-token-navigation-example ()
  (let* ((tokens (vector (cl-parser-kit:make-token :type :identifier
                                                   :text "answer")
                         (cl-parser-kit:make-token :type :equals
                                                   :text "=")
                         (cl-parser-kit:make-token :type :number
                                                   :text "42"
                                                   :value 42)))
         (parser
           (cl-parser-kit:seq-map
            (lambda (identifier-token equals-token number-value end-of-input)
              (declare (ignore equals-token end-of-input))
              (list (cl-parser-kit:token-text identifier-token) number-value))
            (cl-parser-kit:satisfies-token
             (lambda (token)
               (and (eql (cl-parser-kit:token-type token) :identifier)
                    (> (length (cl-parser-kit:token-text token)) 3)))
             :expected-name :long-identifier)
            (cl-parser-kit:type-token :equals)
            (cl-parser-kit:type-token-value :number)
            (cl-parser-kit:end-of-input))))
    (labels ((parse-summary ()
               (multiple-value-bind (ok value next failure)
                   (cl-parser-kit:parse-all parser tokens)
                 (list :ok ok
                       :value value
                       :next next
                       :failure failure))))
      (multiple-value-bind (first next)
          (cl-parser-kit:next-token tokens 0)
        (list :peek (cl-parser-kit:token-text
                     (cl-parser-kit:peek-token tokens 0))
              :next (list (cl-parser-kit:token-text first) next)
              :eof-before (cl-parser-kit:eof-token-p tokens next)
              :parse (parse-summary)
              :eof-after (cl-parser-kit:eof-token-p tokens (length tokens)))))))

;; (inspect-token-navigation-example)
