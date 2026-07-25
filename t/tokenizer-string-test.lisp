(in-package :cl-parser-kit/test)

(it-sequential "tokenizer-string-rule-test"
  (let* ((quote-char #\")
         (escape-char #\\)
         (string-text (format nil "~Ca~C~Cb~C"
                              quote-char
                              escape-char
                              quote-char
                              quote-char))
        (escaped-value (format nil "a~Cb" quote-char))
        (terminated-source (format nil "~A tail" string-text))
        (unterminated-source (format nil "~Cabc" quote-char))
         (tokenizer (%make-string-tokenizer :escape-char escape-char))
         (tokens (tokenize terminated-source tokenizer))
         (unterminated (tokenize unterminated-source tokenizer)))
    (assert-tokenizer-tokens
     tokens
     (list (%make-tokenizer-token-spec :type :string
                                       :text string-text
                                       :value escaped-value)
           (%make-tokenizer-token-spec :type :identifier :value "tail")))
    (assert-tokenizer-tokens
     unterminated
     (list (%make-tokenizer-token-spec :type :unknown
                                       :text (string quote-char)
                                       :value quote-char)
           (%make-tokenizer-token-spec :type :identifier :value "abc")))))

(it-sequential "tokenizer-string-rule-escape-and-empty-test"
  (let ((tokenizer (%make-string-tokenizer :escape-char #\\)))
    ;; An escaped escape character collapses to a single literal backslash.
    (assert-tokenizer-tokens
     (tokenize (format nil "~Ca~C~Cb~C" #\" #\\ #\\ #\") tokenizer)
     (list (%make-tokenizer-token-spec :type :string
                                       :value (format nil "a~Cb" #\\))))
    ;; An empty delimited string yields an empty value, not a failure.
    (assert-tokenizer-tokens
     (tokenize (format nil "~C~C" #\" #\") tokenizer)
     (list (%make-tokenizer-token-spec :type :string :value "")))))

(it-sequential "tokenizer-string-rule-unterminated-by-trailing-escape-char-test"
  ;; %DELIMITED-TOKEN-END's escape clause must not look past the end of SOURCE
  ;; when the escape character is itself the very last character -- there is
  ;; nothing after it to escape, so the string stays unterminated and the
  ;; escape char falls out as its own token.
  (let* ((tokenizer (%make-string-tokenizer :escape-char #\\))
         (source (format nil "~Ca~C" #\" #\\))
         (tokens (tokenize source tokenizer)))
    (assert-tokenizer-tokens
     tokens
     (list (%make-tokenizer-token-spec :type :unknown :text "\"" :value #\")
           (%make-tokenizer-token-spec :type :identifier :value "a")
           (%make-tokenizer-token-spec :type :unknown :text "\\" :value #\\)))))

(it-sequential "tokenizer-string-rule-matcher-declines-at-out-of-bounds-index-test"
  ;; TOKEN-RULE-MATCHER is public API; %MATCH-DELIMITED-TOKEN's EOF guard must
  ;; decline gracefully rather than index out of bounds when invoked directly
  ;; past the end of SOURCE.
  (let ((rule (make-string-rule)))
    (expect (funcall (token-rule-matcher rule) "\"a\"" 3) :to-be-falsy)))

(it-sequential "tokenizer-string-rule-declines-large-unterminated-candidate-test"
  (let* ((*maximum-tokenizer-source-length* 10000)
         (*maximum-tokenizer-tokens* 10)
         (tokenizer (%make-string-tokenizer :escape-char #\\))
         (source (concatenate 'string (string #\") (make-string 5000 :initial-element #\Space)))
         (tokens (tokenize source tokenizer)))
    (assert-tokenizer-tokens
     tokens
     (list (%make-tokenizer-token-spec :type :unknown
                                       :text (string #\")
                                       :value #\")))))

(it-sequential "tokenizer-predicate-rule-options-test"
  (let* ((tokenizer (%make-predicate-word-tokenizer))
         (tokens (tokenize "AB Z CDE" tokenizer)))
    (assert-tokenizer-tokens
     tokens
     (list (%make-tokenizer-token-spec :type :word :value "ab")
           (%make-tokenizer-token-spec :type :unknown :text "Z" :value #\Z)
           (%make-tokenizer-token-spec :type :word :value "cde")))))
