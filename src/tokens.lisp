(in-package :cl-parser-kit)

(defstruct (token (:constructor %make-token
                        (&key type text value metadata span start end)))
  type
  text
  value
  metadata
  span
  start
  end)

(defun %token-metadata-source (token)
  (let ((metadata (and token (token-metadata token))))
    (and (listp metadata)
         (stringp (getf metadata :source))
         (getf metadata :source))))

(defun %make-offset-span (start end &key source)
  ;; NORMALIZED-END must be clamped against NORMALIZED-START, not the raw
  ;; (possibly negative) START -- otherwise a negative START with an END that
  ;; is negative but numerically larger (e.g. START -5, END -2) normalizes to
  ;; START 0 / END -2, an inverted span. Untrusted external tokens (see
  ;; TOKEN-METADATA's :SOURCE convention) may carry arbitrary START/END.
  (let* ((normalized-start (max 0 start))
         (normalized-end (max normalized-start end)))
    (if source
        (let* ((source-length (length source))
               (clamped-start (min normalized-start source-length))
               (clamped-end (min normalized-end source-length)))
          (multiple-value-bind (start-line start-column)
              (advance-position source 0 clamped-start 1 1)
            (multiple-value-bind (end-line end-column)
                (advance-position source clamped-start clamped-end start-line start-column)
              (make-span :source source
                         :start clamped-start
                         :end clamped-end
                         :start-line start-line
                         :start-column start-column
                         :end-line end-line
                         :end-column end-column))))
        (make-span :start normalized-start
                   :end normalized-end
                   :start-line 1
                   :start-column (1+ normalized-start)
                   :end-line 1
                   :end-column (1+ normalized-end)))))

(defun %token-effective-span (token &key (position 0))
  (if token
      (or (token-span token)
          (let* ((start (or (token-start token) position))
                 (end (max start (or (token-end token) start)))
                 (source (and (or (token-start token) (token-end token))
                              (%token-metadata-source token))))
            (%make-offset-span start end :source source)))
      (%make-offset-span position position)))

(defun filter-tokens (tokens predicate)
  "Return a fresh vector of the TOKENS satisfying PREDICATE, in order.

Useful for pruning a token stream before parsing -- e.g. dropping non-skipped
comment or whitespace tokens the tokenizer emitted:
  (filter-tokens toks (lambda (token) (not (eql (token-type token) :comment)))).
TOKENS may be any sequence; the result is always a vector, matching TOKENIZE."
  (multiple-value-bind (stream token-count too-many-p)
      (ensure-vector-up-to tokens *maximum-parser-tokens*)
    (when too-many-p
      (error "Token stream length ~D exceeds maximum ~D"
             token-count
             *maximum-parser-tokens*))
    (coerce (loop for token across stream
                  when (funcall predicate token)
                  collect token)
            'vector)))

(defun make-token (&key type text value metadata span start end)
  (let ((token (%make-token :type type
                            :text text
                            :value value
                            :metadata metadata
                            :span span
                            :start start
                            :end end)))
    (when (and (null span) (or start end))
      (setf (token-span token) (%token-effective-span token)))
    token))
