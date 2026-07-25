(in-package :cl-parser-kit)

;;;; Packrat memoization.
;;;;
;;;; A parser here is a pure function of (input, position) -- there is no user
;;;; state -- so its result at a given position can be cached and reused. MEMOIZE
;;;; wraps a parser to do exactly that within a WITH-PARSE-MEMOIZATION dynamic
;;;; extent, turning the exponential re-parsing of an ambiguous / heavily
;;;; backtracking grammar into linear-time packrat parsing. It is opt-in: outside
;;;; WITH-PARSE-MEMOIZATION a MEMOIZE parser runs its inner parser directly with
;;;; no caching, so nothing changes for grammars that do not need it.
;;;;
;;;; The cache is keyed by (POSITION . PARSER) and scoped to a single parse: the
;;;; table is created fresh by WITH-PARSE-MEMOIZATION, so it can never serve a
;;;; result computed against a different input. Because every combinator recurses
;;;; through RUN-PARSER, memoizing the few genuinely expensive, re-visited
;;;; sub-parsers (rather than every parser) is the effective use.

(defvar *parse-memo-table* nil
  "When bound to a hash table (by WITH-PARSE-MEMOIZATION), MEMOIZE-wrapped parsers
cache their results in it keyed by (POSITION . PARSER); NIL -- the default --
disables memoization so a MEMOIZE parser simply runs its inner parser.")

(defvar %memoize-in-progress-marker '%memoize-in-progress
  "Sentinel GETHASH value marking a (POSITION . PARSER) key whose computation is
currently in flight -- as opposed to a genuine cached result, always a
(OK VALUE NEXT RESULT) list. Never returned to a caller; MEMOIZE checks for it
before treating a hit as a cached result.")

(define-condition left-recursion-detected (error)
  ((parser :initarg :parser :reader left-recursion-detected-parser)
   (position :initarg :position :reader left-recursion-detected-position))
  (:report (lambda (condition stream)
             (format stream
                     "Left recursion detected: the MEMOIZE-wrapped parser ~S was ~
re-entered at token position ~D while its own result at that position was ~
still being computed. MEMOIZE provides packrat memoization only, not Warth-style ~
left-recursion support -- rewrite the rule to remove the left recursion (e.g. ~
via SEP-BY/CHAINL1/CHAINL), or use the Pratt operator-precedence layer ~
(REGISTER-INFIX-LEFT), which does support left-recursive expression grammars."
                     (left-recursion-detected-parser condition)
                     (left-recursion-detected-position condition))))
  (:documentation "Signalled by MEMOIZE when a memoized parser calls itself, directly or
through other memoized parsers, at the same token position before its first
call there has produced a result. Without this check such a grammar would
instead run until *MAXIMUM-PARSER-RECURSION-DEPTH* trips a generic recursion-
depth failure -- a correct but unhelpfully generic diagnostic for what is
always a grammar-authoring bug, not hostile input."))

(defmacro with-parse-memoization (&body body)
  "Evaluate BODY with a fresh per-parse memoization table active, so every MEMOIZE
parser run within the dynamic extent computes its result at each position at most
once (packrat parsing). Wrap a top-level parse call:

  (with-parse-memoization (parse-tokens grammar tokens))

The table is discarded when BODY returns; run one parse per WITH-PARSE-MEMOIZATION
so a cached result is never reused against a different input."
  `(let ((*parse-memo-table* (make-hash-table :test 'equal)))
     ,@body))

(define-parser-function memoize (parser) :memoize
  "Wrap PARSER so that, inside a WITH-PARSE-MEMOIZATION extent, its full result at
each position is computed once and reused on any later visit to that position;
outside such an extent PARSER runs normally with no caching.

Use it on the few expensive, re-entered sub-parsers of an ambiguous or heavily
backtracking grammar to avoid re-parsing the same span repeatedly. PARSER must be
a pure parser (this library's parsers always are); its success value, next
position, diagnostics, and failure/commitment are all cached and returned
unchanged.

Signals LEFT-RECURSION-DETECTED, instead of computing forever, if PARSER (direct
or through other memoized parsers) calls itself again at the same position
before its first call there has returned -- MEMOIZE is plain packrat memoization,
not a left-recursion algorithm."
  ;; Deliberately direct-style, not %RUN-PARSER/IF-SUCCESS: caching must record
  ;; the raw OK flag alongside VALUE/NEXT/RESULT so a cache hit can replay all
  ;; four return channels verbatim via VALUES-LIST. Splitting that into
  ;; success/failure continuations would mean writing the same
  ;; (SETF GETHASH ...) in two closures instead of once, for no clarity gain.
  (if *parse-memo-table*
      (let ((key (cons position parser)))
        (multiple-value-bind (cached hit) (gethash key *parse-memo-table*)
          (cond
            ((eq cached %memoize-in-progress-marker)
             (error 'left-recursion-detected :parser parser :position position))
            (hit (values-list cached))
            (t
             (setf (gethash key *parse-memo-table*) %memoize-in-progress-marker)
             (multiple-value-bind (ok value next result)
                 (run-parser parser input position)
               (setf (gethash key *parse-memo-table*) (list ok value next result))
               (values ok value next result))))))
      (run-parser parser input position)))
