(in-package :cl-parser-kit)

(defparameter *maximum-tokenizer-source-length* 10000000
  "Maximum SOURCE length (in characters) TOKENIZE accepts before signaling
TOKENIZER-RESOURCE-LIMIT-EXCEEDED instead of tokenizing. Guards against an
adversarially huge source string exhausting memory. Rebind or SETF to raise
it for intentionally large legitimate inputs.")

(defparameter *maximum-tokenizer-tokens* 2000000
  "Maximum number of tokens TOKENIZE emits before signaling
TOKENIZER-RESOURCE-LIMIT-EXCEEDED instead of continuing. Guards against a
source that is short but expands into an unbounded number of token structs
(each carrying its own span). Rebind or SETF to raise it for intentionally
token-dense inputs.")

(defparameter *maximum-tokenizer-rules* 100000
  "Maximum number of token rules TOKENIZE accepts on a tokenizer before
signaling TOKENIZER-RESOURCE-LIMIT-EXCEEDED. Guards against circular or
adversarially huge rule lists at the public tokenizer boundary.")

(defparameter *maximum-tokenizer-rule-alternatives* 100000
  "Maximum number of literal alternatives accepted by rule constructors such as
MAKE-OPERATOR-RULE before signaling TOKENIZER-RESOURCE-LIMIT-EXCEEDED.")

(define-resource-limit-condition tokenizer-resource-limit-exceeded
    "Tokenizer resource limit exceeded: ~A is ~A, limit is ~A"
  :documentation "Signaled by TOKENIZE and tokenizer rule constructors when a
public tokenizer boundary exceeds its configured resource limits. Catchable so
embedders can turn a hostile input into a diagnostic instead of an unbounded
allocation.")

(defstruct (token-rule (:constructor make-token-rule
                            (&key type matcher skip-p)))
  "One tokenizer rule: MATCHER is called with (SOURCE INDEX) and returns NIL for
no match, or T plus the matched length and optionally the text and value of a
token of TYPE. SKIP-P T consumes the match without emitting a token, which is
how whitespace and comments disappear before the parser ever sees them.

Written directly only for a custom lexeme; the MAKE-*-RULE constructors cover
the usual classes."
  type
  matcher
  skip-p)

(defstruct (tokenizer (:constructor make-tokenizer
                          (&key rules (unknown-token-type :unknown))))
  "An ordered list of TOKEN-RULEs applied to source text by TOKENIZE.

Order is the disambiguation mechanism: the first rule that matches at a
position wins, so a keyword rule must precede the identifier rule that would
also match it. When no rule matches, one character is consumed as a token of
UNKNOWN-TOKEN-TYPE rather than the tokenizer stalling or erroring, leaving the
decision about bad input to the parser."
  rules
  unknown-token-type)

(defun token-rule-match (rule source index)
  (funcall (token-rule-matcher rule) source index))

(defun %ensure-vector-within-tokenizer-limit (items limit kind)
  "Coerce ITEMS to a vector via ENSURE-VECTOR-UP-TO, signalling
TOKENIZER-RESOURCE-LIMIT-EXCEEDED (tagged KIND) instead of returning one
longer than LIMIT. Shared by %ENSURE-TOKENIZER-RULE-VECTOR and
%ENSURE-TOKENIZER-RULE-ALTERNATIVES-VECTOR, which differ only in which
limit/kind applies."
  (multiple-value-bind (stream count too-many-p)
      (ensure-vector-up-to items limit)
    (when too-many-p
      (error 'tokenizer-resource-limit-exceeded
             :kind kind
             :value count
             :limit limit))
    stream))

(defun %ensure-tokenizer-rule-vector (rules)
  (%ensure-vector-within-tokenizer-limit rules *maximum-tokenizer-rules* :rule-count))

(defun %ensure-tokenizer-rule-alternatives-vector (alternatives kind)
  (%ensure-vector-within-tokenizer-limit
   alternatives *maximum-tokenizer-rule-alternatives* kind))

(defun %tokenize-emit (tokens source type text value start end
                       start-line start-column end-line end-column)
  (push (make-token :type type
                    :text text
                    :value value
                    :start start
                    :end end
                    :span (make-span :source source
                                     :start start
                                     :end end
                                     :start-line start-line
                                     :start-column start-column
                                     :end-line end-line
                                     :end-column end-column))
        tokens)
  tokens)

(defun %tokenize-rule-match (rule source index line column tokens)
  "Try RULE at INDEX. Returns (values matched-p end end-line end-column tokens);
the four position/accumulator values are passed via multiple values to avoid
consing a fresh step object per token."
  (multiple-value-bind (ok rule-length text value)
      (token-rule-match rule source index)
    (if ok
        (progn
          (when (<= rule-length 0)
            (error "Tokenizer rule ~S matched without consuming input at position ~D"
                   rule index))
          (let ((end (+ index rule-length)))
            (multiple-value-bind (end-line end-column)
                (advance-position source index end line column)
              (values t end end-line end-column
                      (if (token-rule-skip-p rule)
                          tokens
                          (%tokenize-emit tokens source
                                          (token-rule-type rule) text value
                                          index end
                                          line column end-line end-column))))))
        (values nil index line column tokens))))

(defun %tokenize-first-match (rules source index line column tokens)
  "Returns (values matched-p end end-line end-column tokens) for the first
matching rule, or (values nil ...) when none match."
  (loop for rule across rules
        do (multiple-value-bind (ok end end-line end-column next-tokens)
               (%tokenize-rule-match rule source index line column tokens)
             (when ok
               (return (values t end end-line end-column next-tokens))))
        finally (return (values nil index line column tokens))))

(defun %tokenize-unknown (tokenizer source index line column tokens)
  "Emit a single unknown-token step. Returns (values end end-line end-column tokens)."
  (let* ((char (char source index))
         (text (string char))
         (end (1+ index)))
    (multiple-value-bind (end-line end-column)
        (advance-position source index end line column)
      (values end end-line end-column
              (%tokenize-emit tokens source
                              (tokenizer-unknown-token-type tokenizer)
                              text char
                              index end
                              line column end-line end-column)))))

(defun tokenize (source tokenizer)
  "Tokenize SOURCE using TOKENIZER."
  (check-type source string)
  (let ((length (length source)))
    (when (> length *maximum-tokenizer-source-length*)
      (error 'tokenizer-resource-limit-exceeded
             :kind :source-length :value length :limit *maximum-tokenizer-source-length*))
    (let ((rules (%ensure-tokenizer-rule-vector (tokenizer-rules tokenizer)))
          (tokens '())
          (token-count 0)
          (index 0)
          (line 1)
          (column 1))
      (declare (type fixnum token-count))
      (loop while (< index length)
            do (let ((previous-tokens tokens))
                 (multiple-value-bind (matched-p end end-line end-column next-tokens)
                     (%tokenize-first-match rules source index line column tokens)
                   (if matched-p
                       (setf index end line end-line column end-column tokens next-tokens)
                       (multiple-value-setq (index line column tokens)
                         (%tokenize-unknown tokenizer source index line column tokens))))
                 ;; Emitting a token always conses a fresh list head (see
                 ;; %TOKENIZE-EMIT), so an EQ check against the pre-iteration
                 ;; list detects an emission in O(1) without walking TOKENS.
                 (unless (eq tokens previous-tokens)
                   (incf token-count)
                   (when (> token-count *maximum-tokenizer-tokens*)
                     (error 'tokenizer-resource-limit-exceeded
                            :kind :token-count :value token-count :limit *maximum-tokenizer-tokens*))))
            finally (return (coerce (nreverse tokens) 'vector))))))

(defun tokenize-string (source tokenizer)
  "Alias for TOKENIZE, named for call sites that read more clearly as
\"tokenize this string\" than \"tokenize this source\" -- both names are
public and equivalent; pick whichever reads better at the call site."
  (tokenize source tokenizer))
