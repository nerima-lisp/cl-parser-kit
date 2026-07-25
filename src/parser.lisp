(in-package :cl-parser-kit)

(defun peek-token (tokens position)
  "Return the token at POSITION in TOKENS without consuming it, or NIL when
POSITION is at or past the end. TOKENS may be any sequence a parser accepts;
it is coerced to a vector first."
  (%token-stream-token-at tokens position))

(defun next-token (tokens position)
  "Return two values: the token at POSITION in TOKENS, and the position after
it. At or past the end both the token and the advance stop -- the token is NIL
and the returned position is POSITION unchanged -- so a caller that loops on
NEXT-TOKEN terminates instead of running off the stream."
  (let ((token (peek-token tokens position)))
    (values
      token
      (if token (1+ position)
        position))))

(defun eof-token-p (tokens position)
  "True when POSITION is at or past the end of TOKENS. A list TOKENS is
end-of-input at the first NIL element, matching how a list token stream
terminates, so this is not simply a length comparison for that case."
  (etypecase tokens
    ((or string vector) (>= position (length tokens)))
    (list (and (not (minusp position)) (null (nth position tokens))))))

(defun %parse-token-vector (parser stream)
  (multiple-value-bind (ok value next failure) (%run-parser-on-token-vector parser stream 0)
    (if ok (values t value next nil)
      (values nil nil next failure))))

(defun parse-tokens (parser tokens)
  "Run PARSER over TOKENS from position 0 and return RUN-PARSER's four values:
OK, VALUE, NEXT-POSITION, and a PARSE-FAILURE when OK is NIL.

Unlike PARSE-ALL this does not require the parse to consume every token, so a
successful result may leave NEXT-POSITION short of the end -- check it, or use
PARSE-ALL, when trailing input should be an error. Streams longer than
*MAXIMUM-PARSER-TOKENS* fail with a resource-limit PARSE-FAILURE rather than
being parsed."
  (multiple-value-bind (stream limit-failure) (%ensure-parser-token-vector tokens)
    (if limit-failure (values nil nil 0 limit-failure)
      (%parse-token-vector parser stream))))

(defun parse-all (parser tokens)
  "Run PARSER over TOKENS exactly as PARSE-TOKENS does, but additionally require
full consumption: a parse that succeeds while leaving tokens unread is turned
into a trailing-input PARSE-FAILURE. This is the entry point to reach for when
TOKENS is a whole document rather than a fragment."
  (multiple-value-bind (stream limit-failure) (%ensure-parser-token-vector tokens)
    (if limit-failure (values nil nil 0 limit-failure)
      (%parse-with-full-consumption (stream) (%parse-token-vector parser stream)))))

(defun parse-source (parser source tokenizer)
  "Tokenize the string SOURCE with TOKENIZER, then PARSE-ALL the result with
PARSER -- the one-call path from source text to a parsed value, returning the
same four values. Tokenizer resource limits are enforced during TOKENIZE and
signal rather than returning a failure; parser limits still surface as a
PARSE-FAILURE."
  (let ((tokens (tokenize source tokenizer)))
    (parse-all parser tokens)))
