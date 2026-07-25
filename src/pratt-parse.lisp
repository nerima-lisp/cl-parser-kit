(in-package :cl-parser-kit)

(defparameter *maximum-pratt-recursion-depth* 4000
  "Maximum recursion PARSE-PRATT performs before yielding a parse failure
instead of exhausting the control stack. This bounds hostile input so it fails
gracefully rather than crashing the process. The count grows with both nested
depth (e.g. thousands of leading prefix operators or parentheses) AND the length
of a flat operator chain (each infix operator's right operand recurses), so an
expression with more than this many operators fails with a
`:maximum-recursion-depth` failure even when it is not deeply nested. Rebind or
SETF to raise it for intentionally large or deep expressions.")

(defvar *pratt-recursion-depth* 0
  "Current Pratt recursion depth; bound dynamically during a parse.")

(defun %pratt-depth-exceeded-failure (position)
  (%recursion-depth-failure position
                            "Maximum expression depth ~D exceeded"
                            *maximum-pratt-recursion-depth*))

(defun %token-key (token)
  (or (token-type token) (token-text token)))

(defun %token-span (token &key (position 0))
  (%token-effective-span token :position position))

(defun %pratt-error (position token expected)
  (make-parse-failure
   :position position
   :expected expected
   :actual token
   :diagnostics (list (error-diagnostic (format nil "Expected ~A" expected)
                                        :span (%token-span token :position position)))))

;; As with the macro-generated code in TREE-MACROS.LISP and
;; COMBINATORS-SEQUENCE.LISP, SB-COVER attributes this DECLAIM'd inline
;; function's body to each of its call sites (in %PRATT-STEP-LED-LOOP/CPS and
;; %PRATT-START-EXPRESSION/CPS) rather than to this definition, so it reads as
;; permanently uncovered here regardless of how thoroughly Pratt parsing is
;; tested -- removing the INLINE declaration would "fix" the number but cost a
;; function-call per token lookup in the hot Pratt loop, so it stays.
(declaim (inline %pratt-token-at))

(defun %pratt-token-at (tokens index)
  (and (< index (length tokens))
       (aref tokens index)))

(defun %pratt-lookup-prefix (table token)
  (gethash (%token-key token) (pratt-table-prefixes table)))

(defun %pratt-lookup-infix (table token)
  (gethash (%token-key token) (pratt-table-infixes table)))

(defun %pratt-lookup-postfix (table token)
  (gethash (%token-key token) (pratt-table-postfixes table)))

(defun %pratt-call-prefix (entry token tokens next table)
  (funcall (pratt-prefix-entry-nud entry) token tokens next table))

(defun %pratt-call-postfix (entry left token tokens next table)
  (funcall (pratt-postfix-entry-led entry) left token tokens next table))

(defun %pratt-call-infix (entry left token right right-next table)
  (funcall (pratt-infix-entry-led entry) left token right right-next table))

(defun %pratt-postfix-eligible-p (entry min-binding-power)
  (and entry
       (>= (pratt-postfix-entry-binding-power entry)
           min-binding-power)))

(defun %pratt-infix-eligible-p (entry min-binding-power)
  (and entry
       (>= (pratt-infix-entry-left-binding-power entry)
           min-binding-power)))

(defun %pratt-finish-led-loop/cps (left next success)
  (funcall success left next nil))

;; Run a led parser and continue the Pratt loop only when it succeeds.
;;
;; As with the other macro-generated code in this library, SB-COVER
;; attributes this expansion to its two call sites (%PRATT-CONTINUE-POSTFIX/CPS
;; and %PRATT-CONTINUE-INFIX/CPS below) rather than to this definition, so this
;; macro body showing as uncovered is a reporting artifact -- both call sites
;; are exercised by every Pratt test that parses an infix or postfix operator.
(defmacro %pratt-led-step/cps ((tokens table min-binding-power success failure)
                               led-call)
  (let ((ok (gensym "OK"))
        (left (gensym "LEFT"))
        (next (gensym "NEXT"))
        (led-failure (gensym "LED-FAILURE")))
    `(multiple-value-bind (,ok ,left ,next ,led-failure)
         ,led-call
       (if ,ok
           (%pratt-step-led-loop/cps ,tokens ,table ,min-binding-power
                                     ,left ,next ,success ,failure)
           (funcall ,failure ,next ,led-failure)))))

(defun %pratt-continue-postfix/cps (tokens table min-binding-power postfix left current next
                                    success failure)
  (%pratt-led-step/cps (tokens table min-binding-power success failure)
      (%pratt-call-postfix postfix left current tokens (1+ next) table)))

(defun %pratt-continue-infix/cps (tokens table min-binding-power infix left current next
                                  success failure)
  (%pratt-parse/cps
   tokens
   table
   (1+ next)
   (pratt-infix-entry-right-binding-power infix)
   (lambda (right right-next _diagnostics)
     (declare (ignore _diagnostics))
     (%pratt-led-step/cps (tokens table min-binding-power success failure)
         (%pratt-call-infix infix left current right right-next table)))
   failure))

(defun %pratt-step-led-loop/cps (tokens table min-binding-power left next success failure)
  (let* ((current (%pratt-token-at tokens next))
         (postfix (and current (%pratt-lookup-postfix table current)))
         (infix (and current (%pratt-lookup-infix table current))))
    (cond
      ((null current)
       (%pratt-finish-led-loop/cps left next success))
      ((%pratt-postfix-eligible-p postfix min-binding-power)
       (%pratt-continue-postfix/cps
        tokens table min-binding-power postfix left current next success failure))
      ((%pratt-infix-eligible-p infix min-binding-power)
       (%pratt-continue-infix/cps
        tokens table min-binding-power infix left current next success failure))
      (t
       (%pratt-finish-led-loop/cps left next success)))))

(defun %pratt-start-expression/cps (tokens table position min-binding-power success failure)
  (let ((token (%pratt-token-at tokens position)))
    (cond
      ((null token)
       (funcall failure position (%pratt-error position nil :expression)))
      (t
       (let ((prefix (%pratt-lookup-prefix table token)))
         (if prefix
             (%pratt-led-step/cps (tokens table min-binding-power success failure)
                 (%pratt-call-prefix prefix token tokens (1+ position) table))
             (funcall failure position (%pratt-error position token :prefix))))))))

(defun %pratt-parse/cps (tokens table position min-binding-power success failure)
  (if (>= *pratt-recursion-depth* *maximum-pratt-recursion-depth*)
      (funcall failure position (%pratt-depth-exceeded-failure position))
      (let ((*pratt-recursion-depth* (1+ *pratt-recursion-depth*)))
        (%pratt-start-expression/cps
         tokens table position min-binding-power success failure))))

(defun parse-pratt (tokens table &key (position 0) (min-binding-power 0))
  "Parse an expression from TOKENS using TABLE."
  (multiple-value-bind (stream limit-failure)
      (%ensure-parser-token-vector tokens)
    (if limit-failure
        (values nil nil 0 limit-failure)
        (%pratt-parse/cps
         stream
         table
         position
         min-binding-power
         (lambda (value next diagnostics)
           (%success value next diagnostics))
         (lambda (next failure)
           (values nil nil next failure))))))

(defun parse-pratt-all (tokens table &key (position 0) (min-binding-power 0))
  "Parse a precedence expression from TOKENS with TABLE exactly as PARSE-PRATT
does, but additionally require that the expression consume every token: a parse
that stops early becomes a trailing-input PARSE-FAILURE. The whole-input form,
matching PARSE-ALL's relationship to PARSE-TOKENS."
  (%parse-with-full-consumption (tokens)
      (parse-pratt tokens table
                   :position position
                   :min-binding-power min-binding-power)))

(defun parse-pratt-source (source tokenizer table &key (position 0) (min-binding-power 0))
  "Tokenize the string SOURCE with TOKENIZER, then PARSE-PRATT-ALL the result with
TABLE -- the one-call path from expression text to a precedence-parsed value,
and the Pratt counterpart of PARSE-SOURCE."
  (let ((tokens (tokenize source tokenizer)))
    (parse-pratt-all tokens table
                     :position position
                     :min-binding-power min-binding-power)))
