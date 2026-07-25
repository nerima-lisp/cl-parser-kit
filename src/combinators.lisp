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

(defstruct (parser (:constructor make-parser (&key name fn))) name
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
  (multiple-value-bind (stream token-count too-many-p) (ensure-vector-up-to tokens *maximum-parser-tokens*)
    (if too-many-p (values nil (%parser-token-limit-failure token-count position))
      (values stream nil))))

(defun %run-parser-on-token-vector (parser input position)
  (if (>= *parser-recursion-depth* *maximum-parser-recursion-depth*) (values nil nil position (%recursion-depth-exceeded-failure position))
    (let ((*parser-recursion-depth* (1+ *parser-recursion-depth*)))
      (funcall (parser-fn parser) input position))))

(defun run-parser (parser input position)
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

(defun %progress-failure-object (position parser)
  (%make-parse-failure position :progressing-parser parser nil nil))

(defun %progress-failure-p (failure)
  (eql :progressing-parser (parse-failure-expected failure)))

(defmacro define-parser-function (name lambda-list parser-name &body body)
  `(defun ,name ,lambda-list
    (make-parser
      :name
      ,parser-name
      :fn
      (lambda (input position)
        ,@body))))

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
  (declare (ignore input))
  (%success value position))

(define-parser-function
  bind-parser
  (parser function)
  :bind
  (%run-parser/if-success
    parser
    input
    position
    (lambda (value next result)
      (multiple-value-bind (next-ok next-value next-position next-result) (%run-parser-on-token-vector (funcall function value) input next)
        (if next-ok (%success next-value next-position (%merge-diagnostics result next-result))
          (if (= next position) (%failure-from next-result)
            (%committed-failure-from next-result)))))))

(define-parser-function
  satisfies-token
  (predicate &key expected-name)
  expected-name
  (if (< position (length input)) (let ((token (aref input position)))
      (if (funcall predicate token) (%success token (1+ position))
        (%failure position expected-name token)))
    (%failure position expected-name :eof)))

(define-parser-function map-parser (parser function) :map
  (%run-parser/if-success
   parser input position
   (lambda (value next result)
     (%success (funcall function value) next result))))

(defun type-token (type)
  (satisfies-token
    (lambda (token)
      (eql (token-type token) type))
    :expected-name
    type))

(defun literal (text &key type)
  (satisfies-token
    (lambda (token)
      (and
        (if type (eql (token-type token) type)
          t)
        (string= (token-text token) text)))
    :expected-name
    (or type text)))

(defmacro define-token-mapped-function (name parser-form accessor lambda-list)
  `(defun ,name ,lambda-list
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
          (multiple-value-bind (ok value next result) (%run-parser-on-token-vector parser input current)
            (unless ok
              (setf best-failure (merge-parse-failures best-failure result))
              (return-from
                seq
                (if (= current position) (%failure-from best-failure)
                  (%committed-failure-from best-failure))))
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
          (multiple-value-bind (ok value next result) (%run-parser-on-token-vector parser input position)
            (if ok (return-from alt (%success value next result))
              (setf best-failure (merge-parse-failures best-failure result)))))
        parsers)
      (%failure-from best-failure))))

(define-parser-function
  seq
  (&rest parsers)
  :seq
  (%run-parser-sequence parsers input position))

(define-parser-function
  alt
  (&rest parsers)
  :alt
  (if (endp parsers) (%failure position :alternative nil)
    (%run-ordered-choice parsers input position)))
