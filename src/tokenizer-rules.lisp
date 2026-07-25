(in-package :cl-parser-kit)

(defun %ensure-non-empty-string (value argument-name)
  (unless (stringp value)
    (error "~A must be a string." argument-name))
  (when (zerop (length value))
    (error "~A must be a non-empty string." argument-name))
  value)

(defun %match-literal-token (source index literal &optional (test #'string=))
  (let* ((literal-length (length literal))
         (end (+ index literal-length)))
    (when (and (<= end (length source))
               ;; TEST is STRING= for the usual case-sensitive match and
               ;; STRING-EQUAL for a case-insensitive one; both accept the
               ;; :START2/:END2 window into SOURCE.
               (funcall test literal source :start2 index :end2 end))
      (values t literal-length literal literal end))))

(defun %emit-token-match (source index end value)
  (let ((text (%string-range source index end)))
    (values t (- end index) text value)))

(defmacro %skip-or-match (skip-p length &body non-skip-values-form)
  "Every rule constructor's matcher (here and in TOKENIZER-RULES-TEXT.LISP /
TOKENIZER-RULES-EXTRA.LISP) branches the same way once a candidate match's
LENGTH is known: SKIP-P true reports the bare length, since a skipped match's
TEXT/VALUE are never read (see %TOKENIZE-RULE-MATCH); otherwise
NON-SKIP-VALUES-FORM runs to produce the full (VALUES T LENGTH TEXT VALUE). A
macro, not a function, is required here -- passing NON-SKIP-VALUES-FORM as an
ordinary argument would evaluate it (and its %STRING-RANGE / VALUE-FUNCTION
work) even when SKIP-P is true, defeating the whole point."
  `(if ,skip-p
       (values t ,length nil nil)
       (progn ,@non-skip-values-form)))

(defun %scan-while (source index predicate)
  (declare (type string source) (type fixnum index) (optimize (speed 2) (safety 1)))
  (let ((length (length source)))
    (declare (type fixnum length))
    (loop while (< index length)
          while (funcall predicate (char source index))
          do (incf index)
          finally (return index))))

(defun %match-scanned-token (source index start-predicate scanner value-function)
  (when (and (< index (length source))
             (funcall start-predicate (char source index)))
    (let ((end (funcall scanner source index)))
      (%emit-token-match source index end
                         (funcall value-function
                                  (%string-range source index end))))))

(defmacro %token-rule (matcher)
  "Construct a TOKEN-RULE from the enclosing rule constructor's own TYPE and
SKIP-P parameters (every constructor in this library names them exactly
that) plus MATCHER, a (SOURCE INDEX) matcher lambda expression. Removes the
:TYPE TYPE :SKIP-P SKIP-P boilerplate every rule constructor in this file
and its siblings (TOKENIZER-RULES-TEXT.LISP, TOKENIZER-RULES-EXTRA.LISP)
otherwise repeats -- composable rather than wrapping the whole DEFUN, so it
fits equally well whether MATCHER is a bare lambda or one built up inside a
LET/LET* of precomputed bindings."
  `(make-token-rule :type type :skip-p skip-p :matcher ,matcher))

(defun make-literal-rule (type literal &key skip-p (case-sensitive t))
  "Match LITERAL verbatim (no identifier-boundary check, unlike MAKE-KEYWORD-RULE
-- `+` or `->` match anywhere, including inside a longer run of punctuation).

With CASE-SENSITIVE NIL the match ignores case (`select`, `SELECT`, and `Select`
all match `select`); the token TEXT and VALUE are the canonical LITERAL either
way, exactly as MAKE-KEYWORD-RULE documents."
  (%ensure-non-empty-string literal "literal")
  (let ((test (if case-sensitive #'string= #'string-equal)))
    (%token-rule
     (lambda (source index)
       (multiple-value-bind (matched-p literal-length text value)
           (%match-literal-token source index literal test)
         (when matched-p
           (values t literal-length text value)))))))

(defun make-keyword-rule (type literal &key skip-p (identifier-char-predicate #'identifier-char-p)
                                          (case-sensitive t))
  "Match LITERAL as a whole keyword: it matches only when not flanked by an
identifier character on either side (so `int` does not match inside `integer`).

With CASE-SENSITIVE NIL the keyword matches regardless of case (`SELECT`, `select`
and `Select` all match `select`); the token TEXT and VALUE are the canonical
LITERAL either way. IDENTIFIER-CHAR-PREDICATE decides what counts as a flanking
identifier character."
  (%ensure-non-empty-string literal "literal")
  (let ((test (if case-sensitive #'string= #'string-equal)))
    (%token-rule
     (lambda (source index)
       (let ((source-length (length source)))
         (multiple-value-bind (matched-p literal-length text value end)
             (%match-literal-token source index literal test)
           (when (and matched-p
                      (or (= index 0)
                          (not (funcall identifier-char-predicate
                                        (char source (1- index)))))
                      (or (= end source-length)
                          (not (funcall identifier-char-predicate
                                        (char source end)))))
             (values t literal-length text value))))))))

(defun make-whitespace-rule (&key (type :whitespace) skip-p)
  (%token-rule
   (lambda (source index)
     (let ((end (%scan-while source index #'char-whitespace-p)))
       (when (> end index)
         ;; A skipped run of whitespace -- usually the bulk of the
         ;; source -- avoids both the %STRING-RANGE and %TRIM-RANGE
         ;; subseq copies; see %SKIP-OR-MATCH.
         (%skip-or-match skip-p (- end index)
           (%emit-token-match source index end (%trim-range source index end))))))))

(defun %coerce-char-predicate (spec)
  "Coerce SPEC into a single-character predicate: a CHARACTER matches itself, a
FUNCTION is used as-is, and a SEQUENCE (string or list of characters) matches any
member."
  (etypecase spec
    (character (lambda (char) (char= char spec)))
    (function spec)
    (sequence (lambda (char) (and (find char spec) t)))))

(defun make-char-rule (type spec &key skip-p (value-function #'identity))
  "Match exactly one character described by SPEC -- a CHARACTER, a string/list of
characters (any member), or a predicate FUNCTION.

The token TEXT is the single matched character; its VALUE is (FUNCALL
VALUE-FUNCTION text). Handy for punctuation and single-character operators that do
not need MAKE-LITERAL-RULE's multi-character matching."
  (let ((predicate (%coerce-char-predicate spec)))
    (%token-rule
     (lambda (source index)
       (when (and (< index (length source))
                  (funcall predicate (char source index)))
         (%skip-or-match skip-p 1
           (let ((text (%string-range source index (1+ index))))
             (values t 1 text (funcall value-function text)))))))))

(defun make-predicate-rule (type predicate &key (min-length 1) skip-p (value-function #'identity))
  (check-type min-length (integer 1))
  (%token-rule
   (lambda (source index)
     (let ((end (%scan-while source index predicate)))
       (when (>= (- end index) min-length)
         (%skip-or-match skip-p (- end index)
           (%emit-token-match source index end
                              (funcall value-function
                                       (%string-range source index end)))))))))

(defun make-identifier-rule (&key (type :identifier)
                                  skip-p
                                  (start-predicate #'identifier-start-char-p)
                                  (continue-predicate #'identifier-char-p))
  (%token-rule
   (lambda (source index)
     (%match-scanned-token
      source index
      start-predicate
      (lambda (source index)
        (%scan-while source (1+ index) continue-predicate))
      #'identity))))

(defparameter *maximum-number-lexeme-length* 1024
  "Maximum character length MAKE-NUMBER-RULE scans for a single numeric
lexeme. Without a cap, a hostile run of digits (e.g. \"0.\" followed by
millions of nines) makes %PARSE-DECIMAL-TEXT build and divide multi-megabyte
bignums for what looks like one short token -- a CPU/memory DoS distinct from
the reader-avoidance below. The scanner simply stops at the cap, so any
remaining digits start a new number token, the same graceful split already
used for a stray interior '.'. Rebind or SETF to raise it for intentionally
high-precision literals.")

(defun %parse-decimal-text (text)
  "Parse a well-formed decimal run (as produced by the number scanner) without
using the Lisp reader. Feeding untrusted text to READ-FROM-STRING would intern
malformed runs as permanent symbols (an unbounded-memory DoS), so lexing is done
with PARSE-INTEGER only."
  (let ((dot (position #\. text)))
    (if dot
        (let ((integer-part (parse-integer text :end dot))
              (fraction-text (subseq text (1+ dot))))
          (coerce (+ integer-part
                     (/ (parse-integer fraction-text)
                        (expt 10 (length fraction-text))))
                  'single-float))
        (parse-integer text))))

(defun make-number-rule (&key (type :number) skip-p)
  (%token-rule
   (lambda (source index)
     (%match-scanned-token
      source index
      #'digit-char-p
      (lambda (source index)
        (let ((length (length source)))
          ;; Accept at most one interior decimal point so a hostile run
          ;; like "1.2.3.4" tokenizes as separate numbers rather than a
          ;; single malformed lexeme.
          (loop with end = (1+ index)
                with seen-dot = nil
                while (and (< end length)
                           (< (- end index) *maximum-number-lexeme-length*))
                do (let ((char (char source end)))
                     (cond
                       ((digit-char-p char) (incf end))
                       ((and (char= char #\.)
                             (not seen-dot)
                             (< (1+ end) length)
                             (digit-char-p (char source (1+ end))))
                        (setf seen-dot t)
                        (incf end))
                       (t (loop-finish))))
                finally (return end))))
      #'%parse-decimal-text))))
