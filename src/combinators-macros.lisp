(in-package :cl-parser-kit)

;;;; Parser-definition and monadic binding macros.

(defun %lazy-parser (builder)
  "Runtime core of PARSER-LAZY / DEFPARSER.

BUILDER is a thunk that returns a parser. The parser it returns is constructed
on first use and memoized, so forward references and recursive grammars work:
BUILDER is not called until the lazy parser actually runs, by which point the
referenced parser is defined."
  (let ((cache nil))
    (make-parser
     :name :lazy
     :fn (lambda (input position)
           (run-parser (or cache (setf cache (funcall builder)))
                       input position)))))

(defmacro parser-lazy (form)
  "Defer construction of the parser FORM until the first time it actually runs.

Returns a parser whose sub-parser is built (by evaluating FORM) on first use and
memoized thereafter. This enables forward references -- FORM may name a parser
defined later -- and directly recursive grammars, where eagerly evaluating FORM
would recurse forever at build time:

  (defparameter *expr*
    (alt (type-token :number)
         (between (literal \"(\") (parser-lazy *expr*) (literal \")\"))))

Left-recursive grammars still loop at parse time; that is a grammar property,
not something PARSER-LAZY can fix."
  `(%lazy-parser (lambda () ,form)))

(defmacro defparser (name lambda-list &body body)
  "Define NAME as a function returning a parser lazily built from BODY.

BODY is wrapped in PARSER-LAZY, so references to NAME (or to parsers defined
later in the file) resolve at parse time instead of at definition/load time.
This lets self- and mutually-recursive grammars be written in natural order:

  (defparser expression ()
    (alt (type-token :number)
         (between (literal \"(\") (expression) (literal \")\"))))

Each call to a self-reference returns an unbuilt lazy parser, so construction
terminates; only actual (non-left) recursion during parsing descends."
  `(defun ,name ,lambda-list
     (parser-lazy (progn ,@body))))

(defmacro parse-let* (bindings &body body)
  "Sequential monadic binding over parsers, in the style of do-notation.

Each binding (VAR PARSER-FORM) runs PARSER-FORM in sequence and binds its result
to VAR, which is visible to every later binding and to BODY. BODY is an ordinary
Lisp expression evaluated once all bindings have parsed; its value becomes the
parser's result (wrapped with RETURN-PARSER, so BODY yields a plain value, not a
parser). Each binding variable is declared IGNORABLE, so a placeholder such as _
for a discarded result needs no extra ceremony.

  (parse-let* ((name (type-token :identifier))
               (_    (literal \"=\"))
               (val  expression))
    (list :assign name val))

expands to nested BIND-PARSER calls, so it commits exactly as a hand-written
SEQ/BIND chain would: once an early binding consumes input, a later failure
stays committed."
  (if (null bindings)
      `(return-parser (progn ,@body))
      (destructuring-bind ((var parser-form) &rest rest) bindings
        `(bind-parser ,parser-form
                      (lambda (,var)
                        (declare (ignorable ,var))
                        (parse-let* ,rest ,@body))))))
