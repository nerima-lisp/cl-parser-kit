(in-package :cl-parser-kit)

;;;; Additional numeric and operator tokenizer rules.
;;;;
;;;; These complement MAKE-NUMBER-RULE (plain base-10 integers and simple
;;;; fixed-point decimals) with radix integers (0x/0b/0o and arbitrary bases),
;;;; floating literals with an exponent, and a longest-match operator rule. Like
;;;; the base rules they NEVER feed untrusted text to the Lisp reader (which
;;;; would intern malformed runs as permanent symbols) -- values come from
;;;; PARSE-INTEGER and bounded arithmetic only -- and they cap the lexeme length
;;;; and exponent magnitude so a hostile run cannot force an unbounded bignum.

(defun %scan-radix-digits (source index radix limit-end)
  "Scan characters valid in RADIX from INDEX up to LIMIT-END; return the end."
  (declare (type string source) (type fixnum index radix limit-end))
  (loop with end of-type fixnum = index
        while (and (< end limit-end)
                   (digit-char-p (char source end) radix))
        do (incf end)
        finally (return end)))

(defun make-radix-integer-rule (&key (type :integer) (radix 16) (prefix "0x") skip-p)
  "Match an integer written in RADIX, optionally introduced by PREFIX, and yield
its numeric value.

RADIX is 2..36; PREFIX is a literal string that must precede the digits (matched
case-insensitively, so `0x`/`0X` both work) or the empty string / NIL for bare
digits. At least one RADIX-valid digit must follow the prefix, otherwise the rule
declines so a later rule can try. Examples:
  (make-radix-integer-rule :type :hex :radix 16 :prefix \"0x\")   ; 0xFF   -> 255
  (make-radix-integer-rule :type :bin :radix 2  :prefix \"0b\")   ; 0b1010 -> 10
  (make-radix-integer-rule :type :oct :radix 8  :prefix \"0o\").  ; 0o17   -> 15
The digit run is capped at *MAXIMUM-NUMBER-LEXEME-LENGTH* so a hostile run splits
into separate tokens rather than building a multi-megabyte bignum."
  (check-type radix (integer 2 36))
  (let* ((prefix (or prefix ""))
         (prefix-length (length prefix)))
    (%token-rule
     (lambda (source index)
       (let* ((source-length (length source))
              (digits-start (+ index prefix-length)))
         (when (and (<= digits-start source-length)
                    (or (zerop prefix-length)
                        (string-equal prefix source
                                      :start2 index :end2 digits-start)))
           (let ((end (%scan-radix-digits source digits-start radix
                                          (min source-length
                                               (+ digits-start
                                                  *maximum-number-lexeme-length*)))))
             (when (> end digits-start)
               (%skip-or-match skip-p (- end index)
                   (values t (- end index)
                           (%string-range source index end)
                           (parse-integer source :start digits-start :end end
                                                 :radix radix)))))))))))

(defparameter *maximum-number-exponent* 1000
  "Maximum absolute base-10 exponent MAKE-FLOAT-RULE honours before saturating.
An exponent beyond this magnitude is clamped, so a literal such as `1e999999`
neither builds a gigantic bignum via (EXPT 10 exponent) nor traps: a huge
positive exponent saturates to the largest representable float of the rule's
FLOAT-TYPE and a huge negative one underflows to zero. Rebind or SETF to widen
the honoured range.")

(defun %coerce-bounded-float (rational float-type)
  "Coerce RATIONAL to FLOAT-TYPE, saturating to the largest representable
magnitude on overflow instead of signalling (underflow already yields zero)."
  (handler-case (coerce rational float-type)
    (arithmetic-error ()
      (let ((most (ecase float-type
                    (single-float most-positive-single-float)
                    (double-float most-positive-double-float)
                    (short-float most-positive-short-float)
                    (long-float most-positive-long-float))))
        (if (minusp rational) (- most) most)))))

(defun %scan-float-fractional-part (source after-int limit-end)
  "If a '.' at AFTER-INT is followed by at least one digit, scan the fractional
digit run. Returns (values frac-start frac-end new-after-int); FRAC-START is
NIL and FRAC-END/NEW-AFTER-INT both equal AFTER-INT when no fractional part is
present, so a caller can test FRAC-START alone to know whether one matched."
  (if (and (< after-int limit-end)
           (char= (char source after-int) #\.)
           (< (1+ after-int) limit-end)
           (digit-char-p (char source (1+ after-int))))
      (let* ((frac-start (1+ after-int))
             (frac-end (%scan-radix-digits source frac-start 10 limit-end)))
        (values frac-start frac-end frac-end))
      (values nil after-int after-int)))

(defun %scan-float-exponent-part (source after-int limit-end)
  "If an 'e'/'E' at AFTER-INT is followed by an optional sign and at least one
digit, scan the exponent digit run. Returns (values has-exp-p exp-sign
exp-start exp-end new-after-int); HAS-EXP-P is NIL and EXP-END/NEW-AFTER-INT
both equal AFTER-INT when no exponent is present (a bare 'e' with no digits
after it, or after an optional sign, does not count as one)."
  (let ((p (1+ after-int))
        (exp-sign 1))
    (if (and (< after-int limit-end) (member (char source after-int) '(#\e #\E)))
        (progn
          (when (and (< p limit-end) (member (char source p) '(#\+ #\-)))
            (when (char= (char source p) #\-) (setf exp-sign -1))
            (incf p))
          (if (and (< p limit-end) (digit-char-p (char source p)))
              (let ((exp-end (%scan-radix-digits source p 10 limit-end)))
                (values t exp-sign p exp-end exp-end))
              (values nil 1 nil after-int after-int)))
        (values nil 1 nil after-int after-int))))

(defun %float-lexeme-value (source int-start int-end frac-start frac-end
                            has-exp-p exp-sign exp-start exp-end sign float-type)
  "Combine the integer, optional fractional, and optional exponent digit runs
%SCAN-FLOAT-FRACTIONAL-PART / %SCAN-FLOAT-EXPONENT-PART located into a single
FLOAT-TYPE value, applying SIGN and saturating on overflow via
%COERCE-BOUNDED-FLOAT (see MAKE-FLOAT-RULE for the security rationale: this
never calls the Lisp reader, only PARSE-INTEGER and bounded arithmetic)."
  (let* ((int-value (parse-integer source :start int-start :end int-end))
         (frac-value (if frac-start
                         (/ (parse-integer source :start frac-start :end frac-end)
                            (expt 10 (- frac-end frac-start)))
                         0))
         (mantissa (* sign (+ int-value frac-value)))
         (exponent (if has-exp-p
                       (* exp-sign (parse-integer source :start exp-start :end exp-end))
                       0))
         (clamped (max (- *maximum-number-exponent*)
                       (min *maximum-number-exponent* exponent)))
         (scaled (if (>= clamped 0)
                     (* mantissa (expt 10 clamped))
                     (/ mantissa (expt 10 (- clamped))))))
    (%coerce-bounded-float scaled float-type)))

(defun make-float-rule (&key (type :float) (float-type 'double-float)
                          (require-fractional t) allow-sign skip-p)
  "Match a floating-point literal -- integer digits with an optional fractional
part and an optional decimal exponent -- and yield its value as a FLOAT-TYPE.

Recognises forms like 3.14, 1e10, 6.022e23 and 2.5E-3. By default the rule
matches ONLY lexemes carrying a fractional part or an exponent (REQUIRE-FRACTIONAL
t), so it composes with a separate integer rule; pass REQUIRE-FRACTIONAL NIL to
also match a bare digit run (yielding e.g. 42.0). ALLOW-SIGN t additionally
accepts a leading +/-; it defaults off, because a lexer normally leaves a leading
sign to the parser as a unary operator (otherwise `a-1` would lex `-1`).

The exponent magnitude is clamped at *MAXIMUM-NUMBER-EXPONENT* and the lexeme
length at *MAXIMUM-NUMBER-LEXEME-LENGTH*, so no input forces an unbounded bignum;
the value is produced by PARSE-INTEGER and bounded arithmetic, never the reader."
  (%token-rule
   (lambda (source index)
     (let* ((source-length (length source))
            (limit-end (min source-length (+ index *maximum-number-lexeme-length*)))
            (cursor index)
            (sign 1))
       (when (and allow-sign (< cursor limit-end)
                  (member (char source cursor) '(#\+ #\-)))
         (when (char= (char source cursor) #\-) (setf sign -1))
         (incf cursor))
       (let* ((int-start cursor)
              (int-end (%scan-radix-digits source cursor 10 limit-end)))
         (when (> int-end int-start)         ; require at least one integer digit
           (multiple-value-bind (frac-start frac-end after-int)
               (%scan-float-fractional-part source int-end limit-end)
             (multiple-value-bind (has-exp-p exp-sign exp-start exp-end end)
                 (%scan-float-exponent-part source after-int limit-end)
               (when (or (not require-fractional) frac-start has-exp-p)
                 (%skip-or-match skip-p (- end index)
                     (values t (- end index)
                             (%string-range source index end)
                             (%float-lexeme-value source int-start int-end
                                                  frac-start frac-end
                                                  has-exp-p exp-sign exp-start exp-end
                                                  sign float-type))))))))))))

(defun make-operator-rule (type operators &key skip-p)
  "Match the LONGEST of a set of literal OPERATORS at the current position,
yielding the matched operator string as both TEXT and VALUE.

OPERATORS is a list of strings; the rule sorts them by descending length once, so
`==` wins over `=` and `<=` over `<` without the caller having to order a
separate literal rule per operator:
  (make-operator-rule :op '(\"==\" \"=\" \"<=\" \"<\" \">=\" \">\" \"->\" \"-\")).
Every token produced carries TYPE; distinguish operators by their TEXT."
  (let ((operator-vector (%ensure-tokenizer-rule-alternatives-vector
                          operators :operator-count)))
    (loop for operator across operator-vector
          do (%ensure-non-empty-string operator "operator"))
    (let ((buckets (make-hash-table)))
      (loop for operator across operator-vector
            do (push operator (gethash (char operator 0) buckets)))
      (maphash (lambda (char operators)
                 (setf (gethash char buckets)
                       (sort operators #'> :key #'length)))
               buckets)
      (%token-rule
       (lambda (source index)
         (let ((source-length (length source)))
           (when (< index source-length)
             (dolist (operator (gethash (char source index) buckets) nil)
               (let* ((operator-length (length operator))
                      (end (+ index operator-length)))
                 (when (and (<= end source-length)
                            (string= operator source :start2 index :end2 end))
                   (return (%skip-or-match skip-p operator-length
                               (values t operator-length operator operator)))))))))))))
