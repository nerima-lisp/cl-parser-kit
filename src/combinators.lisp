(in-package :cl-parser-kit)

(defun %token-stream-token-at (input position)
  (let ((tokens (ensure-vector input)))
    (and (< position (length tokens)) (aref tokens position))))

(defun %unexpected-token-diagnostic (message token expected)
  (let ((span (and token (%token-effective-span token))))
    (and
      span
      (list
        (error-diagnostic
          message
          :span
          span
          :data
          (list :expected expected :actual (token-type token)))))))

(defstruct (parser (:constructor make-parser (&key name fn)))
  "A parser: FN is a function of (INPUT POSITION) returning RUN-PARSER's four
values, and NAME identifies it in failure reports and traces.

Every combinator in this library returns one of these, so parsers compose as
ordinary values and a grammar is just a data structure built at run time. Call
one through RUN-PARSER rather than funcalling FN directly -- the entry points
are what enforce the recursion and token limits."
  name
  fn)

(defparameter *maximum-parser-recursion-depth* 4000
  "Maximum recursion RUN-PARSER performs before yielding a parse failure
instead of exhausting the control stack. Every combinator (SEQ, ALT, BETWEEN,
BIND-PARSER, MAP-PARSER, and any user-composed recursive-descent grammar)
invokes its sub-parsers through RUN-PARSER, so this bounds hostile input --
e.g. thousands of nested opening delimiters, or a long chain of CHAINR1
operators -- so parsing fails gracefully instead of exhausting the control
stack. Rebind or SETF to raise it for intentionally deep grammars or inputs.")

(defvar *parser-recursion-depth* 0
  "Current combinator recursion depth; bound dynamically during a parse.")

(defparameter *maximum-parser-repetition-count* 1000000
  "Maximum bounded repetition or computed parser-list count accepted by parser
combinators.")

(defun %recursion-depth-failure (position message-control-string limit)
  "Build a PARSE-FAILURE reporting that a recursion-depth guard rejected
POSITION: (FORMAT NIL MESSAGE-CONTROL-STRING LIMIT) becomes its diagnostic
message, with :EXPECTED :MAXIMUM-RECURSION-DEPTH so callers can recognize the
failure kind regardless of which guard (combinator or Pratt) produced it.
Shared by %RECURSION-DEPTH-EXCEEDED-FAILURE here and PRATT-PARSE.LISP's
%PRATT-DEPTH-EXCEEDED-FAILURE, which differ only in their message wording and
which *MAXIMUM-*-RECURSION-DEPTH* special they report."
  (make-parse-failure
    :position
    position
    :expected
    :maximum-recursion-depth
    :actual
    nil
    :diagnostics
    (list (error-diagnostic (format nil message-control-string limit)))))

(defun %recursion-depth-exceeded-failure (position)
  (%recursion-depth-failure
    position
    "Maximum parser recursion depth ~D exceeded"
    *maximum-parser-recursion-depth*))

(defun %parser-token-limit-failure (token-count &optional (position 0))
  (make-parse-failure
    :position
    position
    :expected
    :maximum-parser-tokens
    :actual
    token-count
    :diagnostics
    (list
      (error-diagnostic
        (format
          nil
          "Parser token count ~D exceeds maximum ~D"
          token-count
          *maximum-parser-tokens*)))))

(defun %ensure-parser-token-vector (tokens &optional (position 0))
  (multiple-value-bind (stream token-count too-many-p)
      (ensure-vector-up-to tokens *maximum-parser-tokens*)
    (if too-many-p (values nil (%parser-token-limit-failure token-count position))
      (values stream nil))))

(defun %run-parser-on-token-vector (parser input position)
  (if (>= *parser-recursion-depth* *maximum-parser-recursion-depth*)
      (values nil nil position (%recursion-depth-exceeded-failure position))
    (let ((*parser-recursion-depth* (1+ *parser-recursion-depth*)))
      (funcall (parser-fn parser) input position))))

(defun run-parser (parser input position)
  "Run PARSER against the token stream INPUT starting at POSITION and return four
values: OK, VALUE, NEXT-POSITION, and -- depending on OK -- either the
diagnostics collected during a successful parse or the PARSE-FAILURE that
stopped it.

The primitive every other entry point is built on; PARSE-TOKENS, PARSE-ALL, and
PARSE-SOURCE are the conveniences that start at 0 and, for the latter two, also
require full consumption. Recursion is capped by
*MAXIMUM-PARSER-RECURSION-DEPTH* and stream length by *MAXIMUM-PARSER-TOKENS*,
each surfacing as a resource-limit PARSE-FAILURE rather than exhausting the
control stack or the heap on adversarial input."
  (multiple-value-bind (stream limit-failure) (%ensure-parser-token-vector input position)
    (if limit-failure (values nil nil position limit-failure)
      (%run-parser-on-token-vector parser stream position))))

(defun %success (value position &optional diagnostics)
  (values t value position diagnostics))

(defun %merge-diagnostics (&rest diagnostics-lists)
  ;; Avoid APPLY/APPEND over an attacker-influenced number of diagnostic groups;
  ;; accumulate explicitly so merging stays linear in emitted diagnostics.
  ;;
  ;; DIAGNOSTICS-LISTS itself never escapes this function -- it is only ever
  ;; walked by the DOLIST below, and %ENSURE-PARSE-FAILURE-LIST-COUNT is
  ;; handed each individual element list, never the REST list itself -- so
  ;; DYNAMIC-EXTENT is safe here, unlike a closure that might be stored or
  ;; returned. Verified empirically (a controlled before/after byte-consed
  ;; measurement): a 2-argument call here otherwise heap-allocates a fresh
  ;; 2-cons list on every single call, EVEN WHEN both arguments are NIL --
  ;; and this function runs on every combinator step across the whole library
  ;; (SEQ, ALT, MANY, SEP-BY, and everything else that calls it), making it
  ;; the single most-executed allocation site in the codebase.
  (declare (dynamic-extent diagnostics-lists))
  (let ((merged nil)
        (count 0))
    (dolist (diagnostics diagnostics-lists (nreverse merged))
      (dolist (diagnostic
               (%ensure-parse-failure-list-count
                :diagnostics diagnostics *maximum-parse-failure-diagnostic-count*))
        (incf count)
        (when (> count *maximum-parse-failure-diagnostic-count*)
          (%parse-failure-resource-limit
           :diagnostics count *maximum-parse-failure-diagnostic-count*))
        (push diagnostic merged)))))

(defun %failure (position expected &optional actual diagnostics committed-p)
  (values
    nil
    nil
    position
    (%make-parse-failure position expected actual diagnostics committed-p)))

(defun %failure-from (failure)
  (values nil nil (parse-failure-position failure) (%copy-parse-failure failure)))

(defun %committed-failure-from (failure)
  (values
    nil
    nil
    (parse-failure-position failure)
    (%copy-parse-failure failure :committed-p t)))

(defun %failure-committed-if-consumed (failure current start)
  "Return FAILURE as a committed failure when input was consumed between START
and CURRENT, and as a plain backtrackable one when it was not -- SEQ's
commitment rule, which BIND-PARSER, %RUN-PARSER-SEQUENCE, %RUN-FIXED-REPETITION,
MANY-TILL and TIMES-BETWEEN each state in prose and used to re-derive inline.

Committing once a branch has consumed input is what makes ALT report the
specific error from inside the intended alternative instead of a generic \"no
alternative matched\": a branch that failed without moving is still ambiguous
and may be backtracked over, whereas one that failed midway had clearly been
selected. Only failure paths reach here, so naming the rule costs nothing a
parse actually pays for."
  (if (= current start) (%failure-from failure)
    (%committed-failure-from failure)))

(defun %progress-failure-object (position parser)
  (%make-parse-failure position :progressing-parser parser nil nil))

(defun %progress-failure-p (failure)
  (eql :progressing-parser (parse-failure-expected failure)))

(defmacro define-parser-function (name lambda-list parser-name &body body)
  "Define NAME as a function of LAMBDA-LIST returning a PARSER named PARSER-NAME
whose :FN is (LAMBDA (INPUT POSITION) BODY...).

A docstring at the head of BODY documents NAME itself, not the inner :FN
lambda: it is hoisted onto the generated DEFUN, so DOCUMENTATION and DESCRIBE
report it for the combinator a caller actually names. Splicing it into the
lambda along with the rest of BODY -- the obvious expansion -- silently
attaches it to an anonymous closure no caller can reach, which is exactly how
14 hand-written combinator docstrings went missing before v1.0.0. A lone
string BODY stays a return value, since only a string *followed by* more forms
is a docstring."
  ;; This STRINGP test runs while whatever file calls DEFINE-PARSER-FUNCTION is
  ;; being compiled, never at program-execution time, so SB-COVER can never
  ;; mark it covered however thoroughly it is exercised -- the third
  ;; attribution artifact category docs/src/development.md documents, the same one as
  ;; %ASSERT-SUCCESS-VALUES' declare-stripping loop. Both arms are genuinely
  ;; tested: t/api-surface-test.lisp macroexpands one form with a docstring and
  ;; one whose whole body is a string, and compares the resulting DEFUNs.
  (let ((docstring (when (and (stringp (first body)) (rest body))
                     (pop body))))
    `(defun ,name ,lambda-list
       ,@(when docstring (list docstring))
       (make-parser
         :name
         ,parser-name
         :fn
         (lambda (input position)
           ,@body)))))

(defun %run-progressing-parser/cps (parser input position success failure)
  (multiple-value-bind (ok value next result) (%run-parser-on-token-vector parser input position)
    (cond
      ((not ok) (funcall failure result))
      ((= next position) (funcall failure (%progress-failure-object position parser)))
      (t (funcall success value next result)))))

(defun %run-parser/if-success (parser input position on-success &optional on-failure)
  (multiple-value-bind (ok value next result) (%run-parser-on-token-vector parser input position)
    (if ok (funcall on-success value next result)
      (if on-failure (funcall on-failure result next)
        (%failure-from result)))))

(define-parser-function
  return-parser
  (value)
  :return
  "Succeed with VALUE without consuming any input.

The unit of the parser monad: BIND-PARSER's callback needs some way to lift a
plain value back into a parser, and this is it. Also the way to give an
optional construct a default without a real match."
  (declare (ignore input))
  (%success value position))

(define-parser-function
  bind-parser
  (parser function)
  :bind
  "Run PARSER, then call FUNCTION on its value to obtain the next parser and run
that from where PARSER stopped.

The context-sensitive sequencing operator: unlike SEQ and MAP-PARSER, the
parser that runs second is chosen by what the first one parsed, which is what a
length-prefixed field or a tag-dispatched body needs. FUNCTION never runs on
failure. Reach for MAP-PARSER when only the value needs transforming."
  (%run-parser/if-success
    parser
    input
    position
    (lambda (value next result)
      (multiple-value-bind (next-ok next-value next-position next-result)
          (%run-parser-on-token-vector (funcall function value) input next)
        (if next-ok (%success next-value next-position (%merge-diagnostics result next-result))
          (%failure-committed-if-consumed next-result next position))))))

(define-parser-function
  satisfies-token
  (predicate &key expected-name)
  expected-name
  "Match a single token for which PREDICATE is true, returning that token;
EXPECTED-NAME is what a failure reports as the expected form.

The primitive terminal matcher LITERAL and TYPE-TOKEN are built on -- use it
directly for a condition those two cannot express, such as matching on
TOKEN-VALUE or on METADATA. At end of input the failure reports :EOF as the
actual token rather than NIL, so the two cases stay distinguishable."
  (if (< position (length input)) (let ((token (aref input position)))
      (if (funcall predicate token) (%success token (1+ position))
        (%failure position expected-name token)))
    (%failure position expected-name :eof)))

(define-parser-function map-parser (parser function) :map
  "Run PARSER and pass its value through FUNCTION, leaving position, diagnostics,
and failure behavior untouched -- the plain value transformer, for turning a
matched token into the AST node or scalar it stands for.

FUNCTION never runs on failure. Use BIND-PARSER when the next parser depends on
the parsed value, and SEQ-MAP to map over a whole sequence's values at once
rather than destructuring a SEQ result by position."
  (%run-parser/if-success
   parser input position
   (lambda (value next result)
     (%success (funcall function value) next result))))

(defun type-token (type)
  "Match a single token whose TOKEN-TYPE is EQL to TYPE, returning the token
itself. Failures report TYPE as the expected form. TYPE-TOKEN-TEXT and
TYPE-TOKEN-VALUE are the variants returning the token's payload instead."
  (satisfies-token
    (lambda (token)
      (eql (token-type token) type))
    :expected-name
    type))

(defun literal (text &key type)
  "Match a single token whose TOKEN-TEXT is STRING= to TEXT, returning the token
itself; TYPE additionally constrains its TOKEN-TYPE, which is how a keyword is
distinguished from an identifier that merely spells the same thing. Failures
report TYPE, or TEXT when no TYPE is given. LITERAL-TEXT and LITERAL-VALUE are
the payload-returning variants."
  (satisfies-token
    (lambda (token)
      (and
        (if type (eql (token-type token) type)
          t)
        (string= (token-text token) text)))
    :expected-name
    (or type text)))

(defmacro define-token-mapped-function (name parser-form accessor lambda-list)
  "Define NAME as PARSER-FORM's match projected through ACCESSOR.

The four LITERAL/TYPE-TOKEN payload variants differ only in which matcher they
wrap and which token slot they read, so each is one MAP-PARSER over the other."
  `(defun ,name ,lambda-list
     ,(format nil "Match as ~A does, returning the matched token's ~A instead of ~
the token itself -- the projection that keeps a grammar from threading ~
MAP-PARSER through every terminal."
              (first parser-form) accessor)
     (map-parser ,parser-form #',accessor)))

(define-token-mapped-function
  type-token-text
  (type-token type)
  token-text
  (type))

(define-token-mapped-function
  type-token-value
  (type-token type)
  token-value
  (type))

(define-token-mapped-function
  literal-text
  (literal text :type type)
  token-text
  (text &key type))

(define-token-mapped-function
  literal-value
  (literal text :type type)
  token-value
  (text &key type))

(defun operator-parser (parser function)
  "Match with PARSER but discard its token, yielding FUNCTION as the value.

The adapter CHAINL1 and CHAINR1 expect: they need an operator parser whose
value is the binary function to apply, so (OPERATOR-PARSER (LITERAL \"+\") #'+)
turns the token into the operation it denotes."
  (map-parser
    parser
    (lambda (_token)
      (declare (ignore _token))
      function)))

(defun %run-parser-sequence (parsers input position)
  (block seq
    (let ((values (quote ()))
          (current position)
          (diagnostics (quote ()))
          (best-failure nil))
      (map
        nil
        (lambda (parser)
          (multiple-value-bind (ok value next result)
              (%run-parser-on-token-vector parser input current)
            (unless ok
              (setf best-failure (merge-parse-failures best-failure result))
              (return-from
                seq
                (%failure-committed-if-consumed best-failure current position)))
            (push value values)
            (setf diagnostics (%merge-diagnostics diagnostics result))
            (setf current next)))
        parsers)
      (%success (nreverse values) current diagnostics))))

(defun %run-ordered-choice (parsers input position)
  (block alt
    (let ((best-failure nil))
      (map
        nil
        (lambda (parser)
          (multiple-value-bind (ok value next result)
              (%run-parser-on-token-vector parser input position)
            (if ok (return-from alt (%success value next result))
              (setf best-failure (merge-parse-failures best-failure result)))))
        parsers)
      (%failure-from best-failure))))

(define-parser-function
  seq
  (&rest parsers)
  :seq
  "Run PARSERS in order, all of which must match, and return the list of their
values.

The basic sequencing combinator. Its value is positional, so prefer SEQ-MAP
when the results feed a constructor -- naming the parts in a lambda list beats
destructuring by FIRST/SECOND/THIRD at the call site. SEQUENCE-OF is the
variant taking its parsers as a runtime list."
  (%run-parser-sequence parsers input position))

(define-parser-function
  alt
  (&rest parsers)
  :alt
  "Try PARSERS in order at the current position and return the first match,
backtracking to that position after each failure.

Ordered choice, not the longest match: put the more specific alternative first.
A branch that fails after committing (see COMMIT, or a bounded repetition that
already matched a separator) stops the search instead of being backtracked
over, so the reported error is the specific one from inside the intended
branch rather than \"no alternative matched\". With no PARSERS this always
fails. CHOICE is the variant taking its alternatives as a runtime list."
  (if (endp parsers) (%failure position :alternative nil)
    (%run-ordered-choice parsers input position)))
