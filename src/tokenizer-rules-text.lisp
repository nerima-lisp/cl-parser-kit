(in-package :cl-parser-kit)

(defun %decode-escape-char (char escape-map)
  "Translate CHAR through ESCAPE-MAP (an alist of (from-char . to-char)); return
CHAR unchanged when ESCAPE-MAP is NIL or has no entry for it."
  (or (and escape-map (cdr (assoc char escape-map :test #'char=)))
      char))

(defun %delimited-token-end (source index delimiter escape-char)
  (let ((length (length source)))
    (do ((scan index (1+ scan)))
        ((>= scan length) nil)
      (let ((char (char source scan)))
        (cond
          ((and escape-char (char= char escape-char))
           (when (< (1+ scan) length)
             (incf scan)))
          ((char= char delimiter)
           (return (1+ scan))))))))

(defun %write-delimited-token-value (source index end escape-char buffer
                                     &optional escape-map)
  (do ((scan index (1+ scan)))
      ((>= scan (1- end)))
    (let ((char (char source scan)))
      (if (and escape-char
               (char= char escape-char)
               (< (1+ scan) (1- end)))
          (progn
            ;; With ESCAPE-MAP, an escape sequence such as \n is decoded to its
            ;; replacement character; without one the escaped character is taken
            ;; literally (so \" yields ", \\ yields \).
            (write-char (%decode-escape-char (char source (1+ scan)) escape-map) buffer)
            (incf scan))
          (write-char char buffer)))))

(defun %match-delimited-token (source index delimiter escape-char &optional escape-map)
  (let ((length (length source)))
    (when (and (< index length)
               (char= (char source index) delimiter))
      (let ((end (%delimited-token-end source (1+ index) delimiter escape-char)))
        (when end
          (%emit-token-match
           source index end
           (if escape-char
               (let ((buffer (make-string-output-stream)))
                 (%write-delimited-token-value source (1+ index) end escape-char buffer
                                               escape-map)
                 (get-output-stream-string buffer))
               (subseq source (1+ index) (1- end)))))))))

(defun make-string-rule (&key (type :string) (delimiter #\") escape-char escapes skip-p)
  "Match a DELIMITER-quoted string, returning the unquoted contents as the token
VALUE.

ESCAPE-CHAR, when supplied, lets a delimiter (or the escape character itself)
appear inside the string. By default the character following ESCAPE-CHAR is taken
literally; supply ESCAPES -- an alist of (escaped-char . replacement-char), e.g.
'((#\\n . #\\Newline) (#\\t . #\\Tab)) -- to decode common escape sequences into
their control characters. A character not present in ESCAPES is still taken
literally."
  (declare (type character delimiter))
  (%token-rule
   (lambda (source index)
     (%match-delimited-token source index delimiter escape-char escapes))))

(defun %line-comment-end (source start)
  (or (position-if #'source-line-break-p source :start start)
      (length source)))

(defun %block-comment-end (source start delimiter)
  ;; An unterminated block comment consumes the rest of the source, mirroring
  ;; %line-comment-end. Returning NIL here would crash %emit-token-match on
  ;; untrusted input that opens a comment without closing it.
  (let ((closing (search delimiter source :start2 start)))
    (if closing
        (+ closing (length delimiter))
        (length source))))

(defun %make-prefixed-comment-rule (type skip-p value-function prefix end-fn)
  (%token-rule
   (lambda (source index)
     (let* ((prefix-length (length prefix))
            (source-length (length source))
            (match-end (+ index prefix-length)))
       (when (and (<= match-end source-length)
                  (string= prefix source :start2 index :end2 match-end))
         (let ((end (funcall end-fn source match-end)))
           ;; Comments are almost always skipped; see %SKIP-OR-MATCH.
           (%skip-or-match skip-p (- end index)
               (%emit-scanned-token-match source index end value-function))))))))

(defun make-line-comment-rule (&key (type :comment) (prefix ";") (skip-p t) (value-function #'identity))
  "Build a TOKEN-RULE matching a comment that starts at PREFIX and runs to the end
of the line (or the end of the source) as a token of TYPE.

SKIP-P defaults to T, since a line comment is normally discarded; pass NIL to
keep it, for a formatter or a CST that must round-trip the original text."
  (%ensure-non-empty-string prefix "prefix")
  (%make-prefixed-comment-rule type skip-p value-function prefix #'%line-comment-end))

(defun make-block-comment-rule (&key (type :comment) (start "/*") (end "*/") (skip-p t)
                                  (value-function #'identity))
  "Build a TOKEN-RULE matching a comment delimited by START and END as a token of
TYPE, ending at the first END (or the end of the source when it is never
closed) -- these comments do not nest; use MAKE-NESTED-BLOCK-COMMENT-RULE when
they must.

SKIP-P defaults to T, as for MAKE-LINE-COMMENT-RULE."
  (%ensure-non-empty-string start "start")
  (%ensure-non-empty-string end "end")
  (%make-prefixed-comment-rule type skip-p value-function start
                               (lambda (source match-end)
                                 (%block-comment-end source match-end end))))

(defun %nested-block-comment-end (source match-end start end)
  ;; MATCH-END points just past the opening START delimiter, so the comment
  ;; begins at nesting depth 1. Each further START increments the depth and each
  ;; END decrements it; the comment closes when the depth returns to 0. An
  ;; unterminated nested comment consumes the rest of the source, mirroring
  ;; %BLOCK-COMMENT-END, so untrusted input that opens without closing does not
  ;; crash %EMIT-TOKEN-MATCH.
  (let ((length (length source))
        (start-length (length start))
        (end-length (length end))
        (depth 1)
        (index match-end))
    (loop
      (when (>= index length) (return length))
      (cond
        ((and (<= (+ index start-length) length)
              (string= start source :start2 index :end2 (+ index start-length)))
         (incf depth)
         (incf index start-length))
        ((and (<= (+ index end-length) length)
              (string= end source :start2 index :end2 (+ index end-length)))
         (decf depth)
         (incf index end-length)
         (when (zerop depth)
           (return index)))
        (t
         (incf index))))))

(defun make-nested-block-comment-rule (&key (type :comment) (start "/*") (end "*/") (skip-p t)
                                         (value-function #'identity))
  "Match a block comment delimited by START and END that may NEST -- an inner
START opens a new level that its own END closes, so the comment terminates only
when every level has closed.

Unlike MAKE-BLOCK-COMMENT-RULE (which stops at the first END), this handles
languages whose block comments nest, such as Rust `/* .. /* .. */ .. */` or
Common Lisp `#| .. #| .. |# .. |#`. An unterminated comment consumes to end of
input. START and END must be distinct, non-empty strings; comments are skipped by
default."
  (%ensure-non-empty-string start "start")
  (%ensure-non-empty-string end "end")
  (when (string= start end)
    (error "start and end must be distinct strings."))
  (%make-prefixed-comment-rule type skip-p value-function start
                               (lambda (source match-end)
                                 (%nested-block-comment-end source match-end start end))))
