(in-package :cl-parser-kit)

(defun %clamp-fix-it-span (length fix-it)
  "Clamp FIX-IT's span offsets to [0, LENGTH], so an out-of-range fix cannot
error. Shared by every fix-application path, each of which clamps against a
different notion of \"current length\" (the untouched source, or the
shrinking/growing length left by prior fixes in a sequential pass)."
  (let* ((span (fix-it-span fix-it))
         (start (max 0 (min (span-start span) length)))
         (end (max start (min (span-end span) length))))
    (values start end)))

(defun apply-fix-it (source fix-it)
  "Return SOURCE with the region covered by FIX-IT's span replaced by its
replacement string (a NIL replacement deletes the region). Span offsets are
clamped to SOURCE, so an out-of-range fix cannot error. The single-fix form of
APPLY-FIXES -- turning a fix-it (structured suggestion data) into corrected text."
  (multiple-value-bind (start end) (%clamp-fix-it-span (length source) fix-it)
    (concatenate 'string
                 (subseq source 0 start)
                 (or (fix-it-replacement fix-it) "")
                 (subseq source end))))

(defun %fix-it-region (source fix-it)
  (multiple-value-bind (start end) (%clamp-fix-it-span (length source) fix-it)
    (values start end (or (fix-it-replacement fix-it) ""))))

(defun %fix-it-region-conflicts-p (start end previous-start previous-end)
  "True when [START,END) overlaps the previous region [.., PREVIOUS-END), or
shares PREVIOUS-START without both regions being the same zero-width
insertion (same-position zero-width inserts are the one case two fixes are
allowed to share a start: %DESCENDING-FIXES-BY-START-PRESERVING-EQUAL-ORDER
then emits them in their original relative order)."
  (or (< start previous-end)
      (and previous-start
           (= start previous-start)
           (or (/= start end)
               (/= previous-start previous-end)))))

(defun %non-overlapping-fix-it-regions (source ordered-fixes)
  (let ((length (length source))
        (regions '())
        (previous-start nil)
        (previous-end 0))
    (dolist (fix ordered-fixes (nreverse regions))
      (let* ((span (fix-it-span fix))
             (raw-start (span-start span))
             (raw-end (span-end span)))
        (unless (and (<= 0 raw-start)
                     (<= raw-start raw-end)
                     (<= raw-end length))
          (return-from %non-overlapping-fix-it-regions)))
      (multiple-value-bind (start end replacement) (%fix-it-region source fix)
        (when (%fix-it-region-conflicts-p start end previous-start previous-end)
          (return-from %non-overlapping-fix-it-regions))
        (push (list start end replacement) regions)
        (setf previous-start start
              previous-end end)))))

(defun %apply-non-overlapping-fixes (source regions)
  (with-output-to-string (out)
    (let ((cursor 0))
      (dolist (region regions)
        (destructuring-bind (start end replacement) region
          (write-string source out :start cursor :end start)
          (write-string replacement out)
          (setf cursor end)))
      (write-string source out :start cursor))))

(defun %piece-length (piece)
  (- (fourth piece) (third piece)))

(defun %make-text-piece (text)
  (let ((length (length text)))
    (unless (zerop length)
      (list :text text 0 length))))

(defun %piece-slice (piece start end)
  (when (< start end)
    (list (first piece)
          (second piece)
          (+ (third piece) start)
          (+ (third piece) end))))

(defun %replace-piece-range (pieces start end replacement)
  (let ((replacement-piece (%make-text-piece replacement))
        (inserted nil)
        (cursor 0)
        (result '()))
    (labels ((emit (piece)
               (when piece
                 (push piece result)))
             (emit-replacement ()
               (unless inserted
                 (emit replacement-piece)
                 (setf inserted t))))
      (dolist (piece pieces)
        (let* ((piece-length (%piece-length piece))
               (piece-start cursor)
               (piece-end (+ cursor piece-length)))
          (cond
            ((<= piece-end start)
             (emit piece))
            ((>= piece-start end)
             (emit-replacement)
             (emit piece))
            (t
             (let ((left-end (max 0 (min piece-length (- start piece-start))))
                   (right-start (max 0 (min piece-length (- end piece-start)))))
               (emit (%piece-slice piece 0 left-end))
               (emit-replacement)
               (emit (%piece-slice piece right-start piece-length)))))
          (setf cursor piece-end)))
      (emit-replacement)
      (nreverse result))))

(defun %pieces->string (pieces)
  (with-output-to-string (out)
    (dolist (piece pieces)
      (write-string (second piece) out :start (third piece) :end (fourth piece)))))

(defun %apply-sequential-fixes (source ordered-fixes)
  (let ((pieces (list (list :source source 0 (length source))))
        (current-length (length source)))
    (dolist (fix ordered-fixes (%pieces->string pieces))
      (let ((replacement (or (fix-it-replacement fix) "")))
        (multiple-value-bind (start end) (%clamp-fix-it-span current-length fix)
          (setf pieces
                (%replace-piece-range pieces start end replacement)
                current-length
                (+ (- current-length (- end start))
                   (length replacement))))))))

(defun %present-fixes (fixes)
  (let ((present '()))
    (%walk-bounded-list fixes *maximum-diagnostic-fix-count*
                        (lambda (count)
                          (error 'diagnostic-resource-limit-exceeded
                                 :kind :fix-count
                                 :value count
                                 :limit *maximum-diagnostic-fix-count*))
                        (lambda (fix) (when fix (push fix present))))
    (nreverse present)))

(defun %descending-fixes-by-start-preserving-equal-order (ascending-fixes)
  (let ((groups '())
        (current-start nil)
        (current-group '()))
    (labels ((flush-group ()
               (when current-group
                 (push (nreverse current-group) groups)
                 (setf current-group nil))))
      (dolist (fix ascending-fixes)
        (let ((start (span-start (fix-it-span fix))))
          (if (and current-group (= start current-start))
              (push fix current-group)
              (progn
                (flush-group)
                (setf current-start start
                      current-group (list fix))))))
      (flush-group)
      (loop for group in groups append group))))

(defun apply-fixes (source fixes)
  "Return SOURCE with every fix-it in FIXES applied. Non-overlapping fixes use a
single source-ordered pass; overlapping fixes fall back to last-to-first
application so each edit leaves the offsets of the not-yet-applied earlier fixes
valid. NIL entries are ignored. Fixes sharing a start position preserve input
order, so same-position zero-width insertions are emitted in that order. Pair it
with DIAGNOSTIC-FIXES to auto-apply a diagnostic's suggestions:
  (apply-fixes source (diagnostic-fixes diagnostic))."
  (let ((present-fixes (%present-fixes fixes)))
    ;; No fix survives filtering (FIXES was empty or all-NIL) -- the common
    ;; case for a clean parse's diagnostics -- so return SOURCE itself rather
    ;; than pay for a sort, a region scan, and a full character-by-character
    ;; copy through %APPLY-SEQUENTIAL-FIXES to rebuild a string identical to
    ;; the one already in hand.
    (if (null present-fixes)
        source
        (let* ((ascending (stable-sort present-fixes
                                       #'<
                                       :key (lambda (fix) (span-start (fix-it-span fix)))))
               (regions (%non-overlapping-fix-it-regions source ascending)))
          (if regions
              (%apply-non-overlapping-fixes source regions)
              (%apply-sequential-fixes
               source
               (%descending-fixes-by-start-preserving-equal-order ascending)))))))
