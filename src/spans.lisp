(in-package :cl-parser-kit)

(defstruct (span (:constructor make-span
                      (&key source (start 0) (end 0)
                            (start-line 1) (start-column 1)
                            (end-line 1) (end-column 1))))
  "A half-open source region [START, END) in character offsets, together with the
1-based line/column pair for each end and the SOURCE string it came from.

Carrying both representations is deliberate: offsets make merging and slicing
cheap, while line/column is what a diagnostic has to print. SOURCE lets
SPAN-TEXT recover the covered text without the caller threading the original
string around."
  source
  start
  end
  start-line
  start-column
  end-line
  end-column)

(defun span-length (span)
  "Return the number of characters SPAN covers. A reversed span (END before
START) reports 0 rather than a negative length, so arithmetic on a malformed
span stays in range."
  (max 0 (- (span-end span) (span-start span))))

(defun span-empty-p (span)
  "True when SPAN covers no characters, including the reversed case SPAN-LENGTH
clamps to 0. An empty span still carries a position, which is how a zero-width
diagnostic points between two characters."
  (zerop (span-length span)))

(defun span-contains-position-p (span position)
  "True when the character offset POSITION lies within SPAN, treating the span as
the half-open interval [start, end). An empty span contains no position."
  (and (<= (span-start span) position)
       (< position (span-end span))))

(defun span-text (span &optional (source (span-source span)))
  "Return the substring of SOURCE that SPAN covers, or NIL when no string SOURCE
is available. SOURCE defaults to the span's own SPAN-SOURCE, so a span produced
from source text can recover its slice directly; offsets are clamped to SOURCE."
  (when (stringp source)
    (let* ((length (length source))
           (start (max 0 (min (span-start span) length)))
           (end (max start (min (span-end span) length))))
      (subseq source start end))))

(defun span-merge (left right)
  "Return the smallest span covering both LEFT and RIGHT: the earlier START and
the later END, with each end's line/column taken from whichever argument
actually supplied that offset. SOURCE comes from LEFT when it has one. LEFT and
RIGHT need not already be in source order -- this is the combinator-friendly
way to widen a node's span as its children are parsed."
  ;; Choose start-line/column and end-line/column from whichever argument
  ;; actually has the smaller START / larger END offset, instead of trusting
  ;; LEFT/RIGHT to already be in source order. Otherwise a caller merging two
  ;; spans out of source order gets an internally inconsistent span (offsets
  ;; correct via MIN/MAX, but end-line before start-line).
  (let ((start-span (if (<= (span-start left) (span-start right)) left right))
        (end-span (if (>= (span-end left) (span-end right)) left right)))
    (make-span :source (or (span-source left) (span-source right))
               :start (span-start start-span)
               :end (span-end end-span)
               :start-line (span-start-line start-span)
               :start-column (span-start-column start-span)
               :end-line (span-end-line end-span)
               :end-column (span-end-column end-span))))
