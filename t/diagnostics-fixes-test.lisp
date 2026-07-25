(in-package :cl-parser-kit/test)

(it-sequential "apply-fix-it-replaces-span-region-test"
  ;; Replace "teh" (offsets 4..7) with "the".
  (let ((fix (make-fix-it :span (make-span :start 4 :end 7) :replacement "the")))
    (expect (apply-fix-it "fix teh bug" fix) :to-equal "fix the bug")))

(it-sequential "apply-fix-it-nil-replacement-deletes-region-test"
  ;; Delete the two spaces at offsets 3..5 in "abc  def" -> "abcdef".
  (let ((fix (make-fix-it :span (make-span :start 3 :end 5) :replacement nil)))
    (expect (apply-fix-it "abc  def" fix) :to-equal "abcdef")))

(it-sequential "apply-fix-it-clamps-out-of-range-spans-test"
  (let ((prefix (make-fix-it :span (make-span :start -5 :end 2) :replacement "AB"))
        (suffix (make-fix-it :span (make-span :start 10 :end 20) :replacement "Z")))
    (expect (apply-fix-it "abcde" prefix) :to-equal "ABcde")
    (expect (apply-fix-it "abcde" suffix) :to-equal "abcdeZ")))

(it-sequential "apply-fixes-with-no-fixes-returns-source-unchanged-test"
  ;; Exercises APPLY-FIXES's fast path: when no fix survives %PRESENT-FIXES
  ;; filtering (an empty list, or a list of only NIL entries), it returns
  ;; SOURCE itself rather than rebuilding an equal string.
  (let ((source "hello world"))
    (expect (apply-fixes source nil) :to-be source)
    (expect (apply-fixes source (list nil nil)) :to-be source)))

(it-sequential "apply-fixes-applies-multiple-back-to-front-test"
  ;; Two edits whose earlier one would shift the later's offsets if applied
  ;; front-to-back; APPLY-FIXES orders them so both land correctly.
  (let ((fixes (list (make-fix-it :span (make-span :start 0 :end 1) :replacement "X")
                     (make-fix-it :span (make-span :start 4 :end 5) :replacement "Y"))))
    (expect (apply-fixes "a b c" fixes) :to-equal "X b Y")))

(it-sequential "apply-fixes-handles-many-non-overlapping-edits-test"
  (let* ((source (make-string 10000 :initial-element #\a))
         (fixes (loop for index below 1000 by 2
                      collect (make-fix-it :span (make-span :start index :end (1+ index))
                                           :replacement "b")))
         (fixed (apply-fixes source fixes)))
    (expect (length fixed) :to-equal (length source))
    (loop for index below 1000 by 2
          do (expect (char fixed index) :to-equal #\b))
      (loop for index from 1 below 1000 by 2
            do (expect (char fixed index) :to-equal #\a))))

(it-sequential "apply-fixes-handles-many-same-anchor-insertions-test"
  (let* ((fixes (loop for index below 1000
                      collect (make-fix-it :span (make-span :start 1 :end 1)
                                           :replacement (write-to-string (mod index 10)))))
         (fixed (apply-fixes "ab" fixes)))
    (expect (length fixed) :to-equal 1002)
    (expect (subseq fixed 0 12) :to-equal "a01234567890")
    (expect (subseq fixed (- (length fixed) 11)) :to-equal "0123456789b")))

(defun %assert-apply-fixes-matches-sequential-fallback (source fixes)
  "APPLY-FIXES's documented fallback for a set of FIXES it can't apply as one
non-overlapping pass: reduce them one at a time, last-to-first by span start,
over SOURCE. Shared by every test below that exercises that fallback path
rather than the non-overlapping fast path."
  (expect (apply-fixes source fixes)
          :to-equal
          (reduce (lambda (current fix) (apply-fix-it current fix))
                  (stable-sort (copy-list fixes)
                               #'>
                               :key (lambda (fix) (span-start (fix-it-span fix))))
                  :initial-value source)))

(it-sequential "apply-fixes-preserves-overlapping-fallback-behavior-test"
  (let ((fixes (list (make-fix-it :span (make-span :start 0 :end 3) :replacement "X")
                     (make-fix-it :span (make-span :start 2 :end 4) :replacement "Y"))))
    (%assert-apply-fixes-matches-sequential-fallback "abcd" fixes)))

(it-sequential "apply-fixes-preserves-same-start-overlapping-fallback-order-test"
  (let ((fixes (list (make-fix-it :span (make-span :start 0 :end 2) :replacement "X")
                     (make-fix-it :span (make-span :start 0 :end 1) :replacement "Y"))))
    (%assert-apply-fixes-matches-sequential-fallback "abcd" fixes)))

(it-sequential "apply-fixes-preserves-out-of-range-fallback-behavior-test"
  (let ((fixes (list (make-fix-it :span (make-span :start 10 :end 14) :replacement "TT")
                     (make-fix-it :span (make-span :start 9 :end 16) :replacement "N")
                     (make-fix-it :span (make-span :start 10 :end 15) :replacement "U")
                     (make-fix-it :span (make-span :start 4 :end 8) :replacement "BB"))))
    (%assert-apply-fixes-matches-sequential-fallback "sqjhbkqgg" fixes)))

(it-sequential "apply-fixes-preserves-negative-start-fallback-behavior-test"
  ;; A negative raw START on any fix (even alongside otherwise non-overlapping
  ;; fixes) fails %NON-OVERLAPPING-FIX-IT-REGIONS's raw-bounds guard, forcing
  ;; the same last-to-first sequential fallback as a genuinely overlapping set.
  (let ((fixes (list (make-fix-it :span (make-span :start -3 :end 1) :replacement "X")
                     (make-fix-it :span (make-span :start 3 :end 4) :replacement "Y"))))
    (expect (apply-fixes "abcde" fixes) :to-equal "XbcYe")))

(it-sequential "apply-fixes-overlapping-deletion-collapses-to-no-text-piece-test"
  ;; An overlapping fix-it whose replacement deletes text (NIL replacement)
  ;; forces %APPLY-SEQUENTIAL-FIXES's piece-splicing path to build a
  ;; zero-length replacement piece -- %MAKE-TEXT-PIECE must decline to emit
  ;; that piece (returning NIL rather than a phantom empty node) so the
  ;; stitched-together result comes out right.
  (let ((fixes (list (make-fix-it :span (make-span :start 1 :end 4) :replacement nil)
                     (make-fix-it :span (make-span :start 3 :end 5) :replacement "Z"))))
    (expect (apply-fixes "abcdef" fixes) :to-equal "af")))

(it-sequential "apply-fixes-handles-many-overlapping-edits-test"
  (let* ((source (make-string 10000 :initial-element #\a))
         (fixes (loop for index below 1000
                      collect (make-fix-it :span (make-span :start index
                                                            :end (+ index 2))
                                           :replacement "b"))))
    (%assert-apply-fixes-matches-sequential-fallback source fixes)))

(it-sequential "apply-fixes-uses-diagnostic-fixes-test"
  (let* ((diagnostic (error-diagnostic "typo"
                                       :fixes (list (make-fix-it
                                                     :span (make-span :start 0 :end 2)
                                                     :replacement "hi"))))
         (fixed (apply-fixes "yo there" (diagnostic-fixes diagnostic))))
    (expect fixed :to-equal "hi there")))

(it-sequential "apply-fixes-count-limit-caps-fix-list-test"
  (let ((*maximum-diagnostic-fix-count* 2)
        (fixes (list nil
                     (make-fix-it :span (make-span :start 0 :end 1)
                                  :replacement "a")
                     (make-fix-it :span (make-span :start 1 :end 2)
                                  :replacement "b"))))
    (expect (lambda () (apply-fixes "xy" fixes))
            :to-throw 'diagnostic-resource-limit-exceeded)))

(it-sequential "apply-fixes-count-limit-caps-circular-nil-fix-list-test"
  (let ((*maximum-diagnostic-fix-count* 2))
    (expect (lambda () (apply-fixes "xy" (%circular-list nil nil)))
            :to-throw 'diagnostic-resource-limit-exceeded)))

(it-sequential "apply-fixes-count-limit-rejects-improper-fix-list-test"
  (let ((fixes (cons (make-fix-it :span (make-span :start 0 :end 1)
                                  :replacement "a")
                     :not-a-list)))
    (expect (lambda () (apply-fixes "xy" fixes))
            :to-throw 'diagnostic-resource-limit-exceeded)))
