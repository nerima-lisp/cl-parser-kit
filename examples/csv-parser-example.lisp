(in-package :cl-user)

;; A small CSV parser -- a line-oriented counterpoint to the JSON example. It
;; keeps the newline as a REAL token (not skipped), so rows are separated
;; structurally with SEP-END-BY (a trailing newline is allowed), fields with
;; SEP-BY. A field is either a quoted string (which may contain commas) or a bare
;; run of non-delimiter characters. Parses to a list of rows, each a list of
;; field strings. (Embedded doubled-quote escaping is out of scope for this
;; compact demo.)

(defun %csv-field-char-p (char)
  (not (member char '(#\, #\Newline #\Return #\"))))

(defparameter *csv-tokenizer*
  (cl-parser-kit:make-tokenizer
   :rules (list (cl-parser-kit:make-string-rule :type :quoted :delimiter #\")
                (cl-parser-kit:make-char-rule :comma #\,)
                (cl-parser-kit:make-char-rule :newline #\Newline)
                (cl-parser-kit:make-predicate-rule :field #'%csv-field-char-p))))

(defparameter *field*
  (cl-parser-kit:alt (cl-parser-kit:type-token-value :quoted)
                     (cl-parser-kit:type-token-value :field)))

;; SEP-BY1 (at least one field) so that after a trailing newline the row parse
;; fails at end of input, letting SEP-END-BY stop cleanly instead of matching a
;; spurious empty row.
(defparameter *row*
  (cl-parser-kit:sep-by1 *field* (cl-parser-kit:type-token :comma)))

(defparameter *csv-table*
  (cl-parser-kit:sep-end-by *row* (cl-parser-kit:type-token :newline)))

(defun parse-csv (source)
  "Tokenize and parse SOURCE as CSV, returning the standard
(values ok rows next failure) where ROWS is a list of lists of field strings."
  (cl-parser-kit:parse-source *csv-table* source *csv-tokenizer*))

(defun parse-csv-example ()
  "Parse a two-row CSV whose second row has a quoted field containing a comma."
  (parse-csv (format nil "a,b,c~%d,\"e,f\",g~%")))

;; (parse-csv-example)
;; => T, (("a" "b" "c") ("d" "e,f" "g")), <next>, NIL
