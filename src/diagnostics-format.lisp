(in-package :cl-parser-kit)

(defun %diagnostic-location-string (span)
  (when span
    (with-output-to-string (out)
      (princ (span-start-line span) out)
      (write-char #\: out)
      (princ (span-start-column span) out)
      (write-char #\- out)
      (princ (span-end-line span) out)
      (write-char #\: out)
      (princ (span-end-column span) out))))

(defun %write-span-reference (out span)
  (when span
    (write-string " [" out)
    (write-string (%diagnostic-location-string span) out)
    (write-char #\] out)))

(defparameter *maximum-diagnostic-line-length* 400
  "Maximum number of characters DIAGNOSTIC->STRING renders from a source line
or reserves for caret padding/width. Without a cap, a single pathological
line -- a minified file with no line breaks, or a span far into an
adversarially long line -- would make rendering ONE diagnostic allocate
output proportional to that line's full length. Longer lines are truncated
with an ellipsis; rebind or SETF to show more context.")

(defparameter *maximum-diagnostic-related-count* 1000
  "Maximum number of notes or fix-its DIAGNOSTIC->STRING renders for one diagnostic.")

(defparameter *maximum-diagnostic-count* 1000
  "Maximum number of input entries DIAGNOSTICS->STRING consumes in one batch.
NIL entries are skipped for rendering but still counted so nil-only or circular
batches terminate.")

(define-resource-limit-condition diagnostic-resource-limit-exceeded
    "Diagnostic ~A count ~D exceeds maximum ~D"
  :documentation "Signalled while rendering diagnostics when a caller-supplied
list exceeds one of the *MAXIMUM-DIAGNOSTIC-** bounds -- KIND names which one.
Catchable, so a hostile or runaway diagnostic batch becomes a reportable error
rather than an unbounded string.")

(defun %bounded-line-text (source start end)
  (let ((capped-end (min end (+ start *maximum-diagnostic-line-length*))))
    (if (< capped-end end)
        (concatenate 'string (subseq source start capped-end) "...")
        (subseq source start end))))

(defvar *diagnostic-source-line-start-cache* nil)

(defun %walk-line-breaks (source on-break)
  "Scan SOURCE for line breaks (LF, CRLF collapsed to one break, lone CR),
calling (FUNCALL ON-BREAK break-start next-line-start) at each one --
BREAK-START is the break character's own offset (the end of the line it
terminates); NEXT-LINE-START is the offset just past it (where the following
line begins -- BREAK-START+1, except after a CRLF pair). Stops as soon as
ON-BREAK returns non-NIL, returning that value; otherwise scans to the end of
SOURCE and returns NIL. Break handling mirrors ADVANCE-POSITION, so line
numbering stays consistent with it. Shared by %COMPUTE-SOURCE-LINE-STARTS
(collects every NEXT-LINE-START) and %SOURCE-LINE-AT's uncached fallback
\(stops at one target line, using both offsets)."
  (let ((length (length source))
        (index 0))
    (loop while (< index length)
          do (let ((char (char source index))
                   (break-start index))
               (cond
                 ((char= char #\Return)
                  (setf index
                        (if (and (< (1+ index) length)
                                 (char= (char source (1+ index)) #\Newline))
                            (+ index 2)
                            (1+ index)))
                  (let ((result (funcall on-break break-start index)))
                    (when result (return-from %walk-line-breaks result))))
                 ((source-line-break-p char)
                  (incf index)
                  (let ((result (funcall on-break break-start index)))
                    (when result (return-from %walk-line-breaks result))))
                 (t
                  (incf index)))))))

(defun %compute-source-line-starts (source)
  (let ((starts (list 0)))
    (%walk-line-breaks source
                       (lambda (break-start next-line-start)
                         (declare (ignore break-start))
                         (push next-line-start starts)
                         nil))
    (coerce (nreverse starts) 'vector)))

(defun %source-line-starts (source)
  ;; Only ever called (see %SOURCE-LINE-AT, below) inside a
  ;; *DIAGNOSTIC-SOURCE-LINE-START-CACHE* WHEN guard, so the cache variable is
  ;; always truthy by the time this runs -- no direct, uncached path exists.
  (multiple-value-bind (starts presentp)
      (gethash source *diagnostic-source-line-start-cache*)
    (if presentp
        starts
        (setf (gethash source *diagnostic-source-line-start-cache*)
              (%compute-source-line-starts source)))))

(defun %bounded-line-text-from-start (source start)
  (let* ((length (length source))
         (limit (min length (+ start *maximum-diagnostic-line-length*)))
         (index start))
    (loop while (< index limit)
          do (let ((char (char source index)))
               (when (or (char= char #\Return)
                         (source-line-break-p char))
                 (return-from %bounded-line-text-from-start
                   (subseq source start index)))
               (incf index)))
    (if (and (< limit length)
             (not (or (char= (char source limit) #\Return)
                      (source-line-break-p (char source limit)))))
        (concatenate 'string (subseq source start limit) "...")
        (subseq source start limit))))

(defun %source-line-at (source line-number)
  ;; A single forward scan that stops at LINE-NUMBER instead of splitting the
  ;; whole source into a fresh line list per diagnostic. Break handling (LF,
  ;; CRLF, lone CR) mirrors ADVANCE-POSITION so line numbering matches;
  ;; otherwise a CR-only source would render the wrong context line under a
  ;; caret.
  (when (and source (plusp line-number))
    (when *diagnostic-source-line-start-cache*
      (let ((starts (%source-line-starts source)))
        (when (<= line-number (length starts))
          (return-from %source-line-at
            (%bounded-line-text-from-start source
                                           (aref starts (1- line-number)))))))
    (let ((start 0)
          (current-line 1))
      (or (%walk-line-breaks source
                             (lambda (break-start next-line-start)
                               (prog1
                                   (when (= current-line line-number)
                                     (%bounded-line-text source start break-start))
                                 (incf current-line)
                                 (setf start next-line-start))))
          (when (= current-line line-number)
            (%bounded-line-text source start (length source)))))))

(defun %caret-padding (start-column)
  ;; The source line and caret line share the same "  | " gutter, so a 1-based
  ;; START-COLUMN needs START-COLUMN-1 leading spaces to sit under its
  ;; character. Capped at *MAXIMUM-DIAGNOSTIC-LINE-LENGTH* so a span far into
  ;; an adversarially long line doesn't allocate megabytes of padding.
  (make-string (max 0 (min (1- start-column) *maximum-diagnostic-line-length*))
              :initial-element #\Space))

(defun %caret-line (span)
  (let* ((start-column (max 1 (span-start-column span)))
         (end-column (max start-column (span-end-column span)))
         (caret-width (max 1 (min (- end-column start-column)
                                  *maximum-diagnostic-line-length*))))
    (concatenate 'string
                 "  | "
                 (%caret-padding start-column)
                 (make-string caret-width :initial-element #\^))))

(defun %write-span-context (out span)
  (let ((source-line (%source-line-at (span-source span) (span-start-line span))))
    (when source-line
      (terpri out)
      (write-string "  | " out)
      (write-string source-line out)
      (terpri out)
      (write-string (%caret-line span) out))))

(defun %write-note (out note)
  (terpri out)
  (write-string "note: " out)
  (write-string (diagnostic-message note) out)
  (%write-span-reference out (diagnostic-span note)))

(defun %write-fix-it (out fix-it)
  (terpri out)
  (write-string "fix-it" out)
  (%write-span-reference out (fix-it-span fix-it))
  (write-string ": replace with " out)
  (prin1 (fix-it-replacement fix-it) out))

(defun %write-diagnostic-related-items (items kind writer out)
  (if (consp items)
      (%walk-bounded-list items *maximum-diagnostic-related-count*
                          (lambda (count)
                            (error 'diagnostic-resource-limit-exceeded
                                   :kind kind
                                   :value count
                                   :limit *maximum-diagnostic-related-count*))
                          (lambda (item) (when item (funcall writer out item))))
      (when items
        (funcall writer out items))))

(defun %write-diagnostic (diagnostic out)
  (write-string (string-downcase (symbol-name (diagnostic-kind diagnostic))) out)
  (write-string ": " out)
  (write-string (diagnostic-message diagnostic) out)
  (let ((span (diagnostic-span diagnostic)))
    (%write-span-reference out span)
    (when span
      (%write-span-context out span)))
  (%write-diagnostic-related-items
   (diagnostic-notes diagnostic) :notes #'%write-note out)
  (%write-diagnostic-related-items
   (diagnostic-fixes diagnostic) :fixes #'%write-fix-it out))

(defun diagnostic->string (diagnostic)
  "Render DIAGNOSTIC as a human-readable multi-line string: its kind and message,
a file:line:column reference and the underlined source line when its span
carries source text, then its notes and fix-it suggestions. DIAGNOSTICS->STRING
is the list form."
  (with-output-to-string (out)
    (%write-diagnostic diagnostic out)))
