(in-package :cl-parser-kit)

;; SBCL's default policy balances speed/safety/space/debug; this library's
;; combinators/tokenizer run in tight per-token, per-parser-step loops where
;; that balance costs real throughput. SAFETY stays at 1 (not 0) deliberately
;; -- this codebase's resource-limit guards throughout (tokenizer/parser/
;; diagnostics) depend on type and bounds checks still signalling cleanly on
;; malformed or hostile input rather than being compiled away.
(declaim (optimize (speed 3) (safety 1)))

;; Called only from DEFINE-RESOURCE-LIMIT-CONDITION's own macro body (below),
;; so every invocation happens at macroexpansion time -- compiling whichever
;; file calls DEFINE-RESOURCE-LIMIT-CONDITION -- never at program-execution
;; time; SB-COVER's runtime instrumentation cannot observe that regardless of
;; how many callers exist. The same category as the macro-internal-control-flow
;; pattern documented in docs/src/project/development.md, just via a helper DEFUN rather than
;; inline LET/LOOP forms.
(defun %resource-limit-reader-symbol (name slot)
  (intern (format nil "~A-~A" (string-upcase (symbol-name name)) (string-upcase (symbol-name slot)))
          (symbol-package name)))

(defmacro define-resource-limit-condition (name report-control-string &key documentation)
  "Define NAME as an ERROR condition carrying :KIND, :VALUE, and :LIMIT
initargs with matching NAME-KIND / NAME-VALUE / NAME-LIMIT readers, whose
report calls (FORMAT STREAM REPORT-CONTROL-STRING KIND VALUE LIMIT).

Every public resource-limit boundary in this library (tokenizer, diagnostic,
parse-failure) signals one of these conditions instead of exhausting memory or
the control stack on adversarial input; NAME and REPORT-CONTROL-STRING are the
only things that differ between boundaries."
  (let ((kind-reader (%resource-limit-reader-symbol name 'kind))
        (value-reader (%resource-limit-reader-symbol name 'value))
        (limit-reader (%resource-limit-reader-symbol name 'limit)))
    `(define-condition ,name (error)
       ((kind :initarg :kind :reader ,kind-reader)
        (value :initarg :value :reader ,value-reader)
        (limit :initarg :limit :reader ,limit-reader))
       (:report (lambda (condition stream)
                  (format stream ,report-control-string
                          (,kind-reader condition)
                          (,value-reader condition)
                          (,limit-reader condition))))
       ,@(when documentation `((:documentation ,documentation))))))

(defmacro define-value-limit-condition (name value-slot report-control-string
                                         &key (reader-prefix name) documentation)
  "Define NAME as an ERROR condition carrying VALUE-SLOT and :LIMIT initargs
with matching READER-PREFIX-VALUE-SLOT / READER-PREFIX-LIMIT readers (READER-PREFIX
defaults to NAME; override it to keep a public reader name shorter than the
condition's own, as TREE-DEPTH-LIMIT-EXCEEDED does), whose report calls
(FORMAT STREAM REPORT-CONTROL-STRING value limit).

The single-limit sibling of DEFINE-RESOURCE-LIMIT-CONDITION above: use this
for a boundary with exactly one limit kind, so no :KIND discriminator or
report argument is needed. DOCUMENTATION, as there, becomes the condition
class's own docstring -- supply it for every exported condition, since a
:REPORT alone tells a reader what one instance prints, not when the condition
is signalled."
  (let ((value-reader (%resource-limit-reader-symbol reader-prefix value-slot))
        (limit-reader (%resource-limit-reader-symbol reader-prefix 'limit)))
    `(define-condition ,name (error)
       ((,value-slot :initarg ,(intern (symbol-name value-slot) :keyword) :reader ,value-reader)
        (limit :initarg :limit :reader ,limit-reader))
       (:report (lambda (condition stream)
                  (format stream ,report-control-string
                          (,value-reader condition)
                          (,limit-reader condition))))
       ,@(when documentation `((:documentation ,documentation))))))

(defun %walk-bounded-list (list limit on-limit-exceeded item-fn)
  "Call (FUNCALL ITEM-FN item) for each item in LIST in order, bounding the
walk against a hostile LIST the same way everywhere in this library: a
circular LIST signals as soon as a repeated cons is seen, an improper LIST
signals when the walk runs off its final cons, and any LIST longer than
LIMIT items signals before ITEM-FN ever sees the (LIMIT+1)th one. Signalling
means (FUNCALL ON-LIMIT-EXCEEDED count), where COUNT is the offending count;
ON-LIMIT-EXCEEDED is expected to (ERROR ...) and never return.

Shared by every public boundary that folds or renders a caller-supplied list
under a resource limit -- parse-failure expected/diagnostic lists, fix-it
batches, and diagnostic related-item batches all had their own copy of this
exact loop, differing only in what ITEM-FN does with each item and which
condition ON-LIMIT-EXCEEDED signals. Most callers already guard the empty-LIST
case themselves before calling in (an empty list has nothing to fold or
render), but the guard lives here too -- see %DO-PROPER-LIST and
%DO-TREE-CHILDREN for the same pattern -- so every caller, present or future,
gets it for free rather than needing to remember it."
  (when list
    (loop with count = 0
          with seen = (make-hash-table :test 'eq)
          for tail = list then (cdr tail)
          while (consp tail)
          for item = (car tail)
          do (when (gethash tail seen)
               (funcall on-limit-exceeded (1+ limit)))
             (setf (gethash tail seen) t)
             (incf count)
             (when (> count limit)
               (funcall on-limit-exceeded count))
             (funcall item-fn item)
          finally
             (when tail
               (funcall on-limit-exceeded (1+ limit))))))

(defmacro %do-proper-list ((cursor thing) &body body)
  "Walk THING cons by cons, binding CURSOR to the current cons cell and
running BODY once per element -- BODY may (RETURN value) to stop early, since
it expands inside the walk's own LOOP and shares its implicit NIL block. An
improper tail or a repeated (EQ) cons signals immediately. Factors out the
cycle/properness check %CHECK-PROPER-ACYCLIC-LIST and ENSURE-VECTOR-UP-TO's
LIST clause each used to duplicate, down to the identical error messages."
  `(when ,thing
     ;; THING is checked once, up front, so the empty list -- by far the most
     ;; common case, since every diagnostics-less parser step's diagnostics
     ;; list is NIL -- never pays for the hash table below at all.
     (loop with seen = (make-hash-table :test 'eq)
           with ,cursor = ,thing
           do (cond
                ((null ,cursor) (return))
                ((not (consp ,cursor))
                 (error "Expected a proper list, got improper tail ~S." ,cursor))
                ((gethash ,cursor seen)
                 (error "Expected a proper acyclic list, got circular list."))
                (t
                 (setf (gethash ,cursor seen) t)
                 ,@body
                 (setf ,cursor (cdr ,cursor)))))))

(defun %check-proper-acyclic-list (thing)
  (%do-proper-list (cursor thing))
  thing)

(defun ensure-list (thing)
  (if (listp thing)
      (%check-proper-acyclic-list thing)
      (list thing)))

(defparameter *maximum-parser-tokens* 2000000
  "Maximum token stream length accepted by public parser/token stream entry
points before returning or signaling a resource-limit failure instead of
allocating or walking attacker-controlled token streams. Rebind or SETF to raise
it for intentionally large parser inputs.")

(defun ensure-vector-up-to (thing maximum-length)
  (etypecase thing
    ;; A STRING already satisfies VECTOR (it needs no separate coercion --
    ;; (COERCE a-string 'VECTOR) is a verified no-op, returning the same
    ;; object), so one clause covers both, matching EOF-TOKEN-P's (OR STRING
    ;; VECTOR) in PARSER.LISP.
    ((or string vector)
     (let ((length (length thing)))
       (if (> length maximum-length)
           (values nil length t)
           (values thing length nil))))
    (list
     (let ((stream (make-array 0 :adjustable t :fill-pointer 0))
           (count 0))
       (%do-proper-list (cursor thing)
         (incf count)
         (when (> count maximum-length)
           (return-from ensure-vector-up-to (values nil count t)))
         (vector-push-extend (car cursor) stream))
       (values stream count nil)))))

(defun ensure-vector (thing)
  (multiple-value-bind (stream count too-many-p)
      (ensure-vector-up-to thing *maximum-parser-tokens*)
    (if too-many-p
        (error "Sequence length ~D exceeds maximum ~D." count *maximum-parser-tokens*)
        stream)))

(defun char-whitespace-p (char)
  (case char
    ((#\Space #\Tab #\Newline #\Linefeed #\Return #\Page) t)
    (t nil)))

(defun digit-char-p* (char)
  (and (digit-char-p char) t))

(defun identifier-start-char-p (char)
  (or (alpha-char-p char)
      (case char ((#\_ #\-) t) (t nil))))

(defun identifier-char-p (char)
  (or (identifier-start-char-p char)
      (digit-char-p* char)))

(defun source-line-break-p (char)
  (or (char= char #\Newline)
      (char= char #\Linefeed)
      (char= char #\Return)))

(defun advance-position (string start end line column)
  (declare (type string string)
           (type fixnum start end line column)
           (optimize (speed 2) (safety 1)))
  (loop with current-line of-type fixnum = line
        with current-column of-type fixnum = column
        with index of-type fixnum = start
        while (< index end)
        do (let ((char (char string index)))
             (cond
               ((char= char #\Return)
                (incf current-line)
                (setf current-column 1)
                (when (and (< (1+ index) end)
                           (char= (char string (1+ index)) #\Newline))
                  (incf index)))
               ((source-line-break-p char)
                (incf current-line)
                (setf current-column 1))
               (t
                (incf current-column))))
           (incf index)
        finally (return (values current-line current-column))))

(defun %string-range (string start end)
  (subseq string start end))

(defun %trim-range (string start end)
  (string-trim '(#\Space #\Tab #\Newline #\Linefeed #\Return #\Page)
               (subseq string start end)))
