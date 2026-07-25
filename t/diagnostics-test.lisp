(in-package :cl-parser-kit/test)

(defun %circular-list (&rest items)
  (let ((list (copy-list items)))
    (setf (cdr (last list)) list)
    list))

(it-sequential "diagnostic-cr-only-source-line-context-test"
  ;; A classic-Mac (CR-only) source must still resolve the correct context line
  ;; under a caret; line splitting has to agree with advance-position.
  (let* ((source (format nil "aa~Cbb" #\Return))
         (diag (error-diagnostic "boom"
                                 :span (make-span :source source
                                                  :start 3 :end 5
                                                  :start-line 2 :start-column 1
                                                  :end-line 2 :end-column 3))))
    (assert-rendered-contains-all
     (diagnostic->string diag)
     '("boom" "2:1-2:3" "bb" "^"))))

(it-sequential "diagnostic-string-truncates-pathologically-long-line-test"
  ;; A single huge line (a minified file with no line breaks, or a span far
  ;; into an adversarially long line) must not make rendering one diagnostic
  ;; allocate output proportional to that line's full length (security
  ;; hardening).
  (let* ((*maximum-diagnostic-line-length* 10)
         (source (make-string 1000 :initial-element #\a))
         (diag (error-diagnostic "boom"
                                 :span (make-span :source source
                                                  :start 0 :end 1
                                                  :start-line 1 :start-column 1
                                                  :end-line 1 :end-column 2))))
    (let ((rendered (diagnostic->string diag)))
      (expect (search "..." rendered) :to-be-truthy)
      (expect (< (length rendered) 100) :to-be-truthy))))

(it-sequential "diagnostic-string-rendered-length-independent-of-source-size-test"
  ;; The default limit alone must keep DIAGNOSTIC->STRING's output bounded
  ;; for a pathologically large single-line source (a minified file with no
  ;; line breaks), regardless of how large SOURCE grows.
  (let ((lengths
          (mapcar (lambda (source-length)
                    (let ((diag (error-diagnostic
                                "boom"
                                :span (make-span :source (make-string source-length
                                                                      :initial-element #\a)
                                                 :start 0 :end 1
                                                 :start-line 1 :start-column 1
                                                 :end-line 1 :end-column 2))))
                      (length (diagnostic->string diag))))
                  '(1000 500000))))
    (expect (first lengths) :to-equal (second lengths))
    (expect (< (first lengths) 1000) :to-be-truthy)))

(defun %related-items (slot variant)
  "Build a NOTES/FIXES-shaped list of three items (SLOT decides which
constructor) in either a normal, circular, or improper VARIANT shape --
shared by every DIAGNOSTIC-RELATED-COUNT-LIMIT-* test below."
  (let ((make (if (eq slot :notes)
                  #'note-diagnostic
                  (lambda (text) (make-fix-it :replacement text)))))
    (ecase variant
      (:normal (list (funcall make "one") (funcall make "two") (funcall make "three")))
      (:circular (%circular-list (funcall make "one") (funcall make "two")))
      (:improper (cons (funcall make "one") :tail)))))

(it-each ((:notes :normal) (:notes :circular) (:notes :improper)
          (:fixes :normal) (:fixes :circular) (:fixes :improper))
    "diagnostic-related-count-limit-~(~A~)-~(~A~)-test"
    (slot variant)
  ;; A 2x3 table (SLOT x malformed-VARIANT) sharing the identical
  ;; resource-limit assertion; the individual scenarios below were the same
  ;; six lines of setup repeated with only SLOT/VARIANT varying.
  (let* ((*maximum-diagnostic-related-count* 2)
         (diagnostic (apply #'make-diagnostic :message "too many items"
                            slot (list (%related-items slot variant)))))
    (expect (lambda () (diagnostic->string diagnostic))
            :to-throw 'diagnostic-resource-limit-exceeded)))

(it-sequential "diagnostic-string-renders-a-bare-single-note-not-wrapped-in-a-list-test"
  ;; %WRITE-DIAGNOSTIC-RELATED-ITEMS accepts NOTES/FIXES as either a list or a
  ;; single bare item directly -- every other test wraps notes in a LIST.
  (let ((diagnostic (make-diagnostic :message "boom"
                                     :notes (note-diagnostic "a bare note"))))
    (assert-rendered-contains-all
     (diagnostic->string diagnostic)
     '("boom" "a bare note"))))

(it-sequential "parse-failure-string-joins-three-or-more-expected-items-test"
  ;; Exercises the comma-joined branch of the expected-item formatter (2-item
  ;; "X or Y" is covered elsewhere; 3+ items use a distinct code path).
  (let ((failure (make-parse-failure :position 0
                                     :expected '(:identifier :number :string)
                                     :actual :plus)))
    (assert-rendered-contains-all
     (parse-failure->string failure)
     '("one of IDENTIFIER, NUMBER, STRING" "got PLUS"))))

(it-sequential "parse-failure-diagnostics-synthesizes-default-test"
  ;; A failure with no attached diagnostics yields one synthesized error
  ;; diagnostic carrying the failure's data.
  (let* ((failure (make-parse-failure :position 0 :expected :identifier :actual :plus))
         (diagnostics (parse-failure->diagnostics failure)))
    (expect (length diagnostics) :to-equal 1)
    (expect (diagnostic-kind (first diagnostics)) :to-equal :error)
    (expect (search "Expected IDENTIFIER" (diagnostic-message (first diagnostics)))
            :to-be-truthy)))

(it-sequential "parse-failure-diagnostics-synthesizes-default-when-diagnostics-are-all-nil-test"
  ;; A failure whose DIAGNOSTICS field is a non-empty list of nothing but NIL
  ;; entries (a legitimate input elsewhere -- NIL entries are always tolerated
  ;; and skipped, per DIAGNOSTICS->STRING's contract) still synthesizes a
  ;; default diagnostic instead of crashing when %PARSE-FAILURE-DEFAULT-SPAN
  ;; looks for a span to borrow from the (filtered-to-empty) list.
  (let* ((failure (make-parse-failure :position 0 :expected :identifier :actual :plus
                                      :diagnostics (list nil nil)))
         (diagnostics (parse-failure->diagnostics failure)))
    (expect (length diagnostics) :to-equal 1)
    (expect (diagnostic-kind (first diagnostics)) :to-equal :error)
    (expect (diagnostic-span (first diagnostics)) :to-be-falsy)))

(it-sequential "parse-failure-diagnostics-returns-attached-diagnostics-test"
  ;; When the failure already carries diagnostics, those are returned verbatim.
  (let* ((note (error-diagnostic "custom problem"))
         (failure (make-parse-failure :position 0 :expected :identifier :actual :plus
                                      :diagnostics (list note)))
         (diagnostics (parse-failure->diagnostics failure)))
    (expect diagnostics :to-equal (list note))))

(it-sequential "parse-failure-expected-count-limit-caps-rendering-test"
  (let ((*maximum-parse-failure-expected-count* 2)
        (failure (make-parse-failure :position 0
                                     :expected '(:one :two :three)
                                     :actual :plus)))
    (expect (lambda () (parse-failure->string failure))
            :to-throw 'parse-failure-resource-limit-exceeded)))

(it-sequential "parse-failure-expected-count-limit-caps-circular-rendering-test"
  (let ((*maximum-parse-failure-expected-count* 2)
        (failure (make-parse-failure :position 0
                                     :expected (%circular-list :one :two)
                                     :actual :plus)))
    (expect (lambda () (parse-failure->string failure))
            :to-throw 'parse-failure-resource-limit-exceeded)))

(it-sequential "parse-failure-expected-list-rejects-improper-rendering-test"
  (let ((failure (make-parse-failure :position 0
                                     :expected (cons :one :two)
                                     :actual :plus)))
    (expect (lambda () (parse-failure->string failure))
            :to-throw 'parse-failure-resource-limit-exceeded)))

(it-sequential "parse-failure-diagnostic-count-limit-caps-rendering-test"
  (let* ((*maximum-parse-failure-diagnostic-count* 2)
         (failure (make-parse-failure
                   :position 0
                   :expected :identifier
                   :actual :plus
                   :diagnostics (list (error-diagnostic "one")
                                      (error-diagnostic "two")
                                      (error-diagnostic "three")))))
    (expect (lambda () (parse-failure->diagnostics failure))
            :to-throw 'parse-failure-resource-limit-exceeded)))

(it-sequential "parse-failure-diagnostic-count-limit-caps-circular-rendering-test"
  (let* ((*maximum-parse-failure-diagnostic-count* 2)
         (failure (make-parse-failure
                   :position 0
                   :expected :identifier
                   :actual :plus
                   :diagnostics (%circular-list (error-diagnostic "one")
                                               (error-diagnostic "two")))))
    (expect (lambda () (parse-failure->diagnostics failure))
            :to-throw 'parse-failure-resource-limit-exceeded)))

(it-sequential "parse-failure-diagnostic-list-rejects-improper-rendering-test"
  (let ((failure (make-parse-failure
                  :position 0
                  :expected :identifier
                  :actual :plus
                  :diagnostics (cons (error-diagnostic "one")
                                     (error-diagnostic "two")))))
    (expect (lambda () (parse-failure->diagnostics failure))
            :to-throw 'parse-failure-resource-limit-exceeded)))

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

(it-sequential "diagnostics-string-renders-list-test"
  (let* ((first-diagnostic (error-diagnostic "first problem"))
         (second-diagnostic (warning-diagnostic "second problem"))
         (rendered (diagnostics->string (list first-diagnostic nil second-diagnostic))))
    (expect (search "first problem" rendered) :to-be-truthy)
    (expect (search "second problem" rendered) :to-be-truthy)))

(it-sequential "diagnostics-string-renders-nothing-for-an-empty-list-test"
  ;; %WRITE-DIAGNOSTICS's own CONSP check takes its non-list branch for an
  ;; empty (NIL) diagnostics list -- distinct from a list of NIL entries,
  ;; which is still a CONS -- and must render an empty string, not error.
  (expect (diagnostics->string nil) :to-equal ""))

(it-each ((:mixed) (:all-nil) (:circular-nil) (:improper))
    "diagnostics-string-count-limit-~(~A~)-diagnostic-list-test"
    (variant)
  ;; Every variant below is a different malformed shape hitting the same
  ;; *MAXIMUM-DIAGNOSTIC-COUNT* resource-limit assertion.
  (let ((*maximum-diagnostic-count* 2)
        (diagnostics (ecase variant
                       (:mixed (list (error-diagnostic "one") nil
                                     (warning-diagnostic "two") (note-diagnostic "three")))
                       (:all-nil (list nil nil nil))
                       (:circular-nil (%circular-list nil nil))
                       (:improper (cons (error-diagnostic "one") :tail)))))
    (expect (lambda () (diagnostics->string diagnostics))
            :to-throw 'diagnostic-resource-limit-exceeded)))

(it-sequential "diagnostics-string-reuses-source-line-cache-test"
  (let* ((source (format nil "first~%second~%third"))
         (diagnostics (loop repeat 5
                            collect (error-diagnostic
                                     "boom"
                                     :span (make-span :source source
                                                      :start 6 :end 12
                                                      :start-line 2 :start-column 1
                                                      :end-line 2 :end-column 7))))
         (rendered (diagnostics->string diagnostics)))
    (expect (count #\^ rendered) :to-equal 30)
    (expect (search "second" rendered) :to-be-truthy)))

(it-sequential "diagnostic-source-line-cache-computes-once-per-source-test"
  (let* ((source (format nil "first~%second~%third"))
         (cl-parser-kit::*diagnostic-source-line-start-cache* (make-hash-table :test 'eq)))
    (expect (hash-table-count cl-parser-kit::*diagnostic-source-line-start-cache*)
            :to-equal 0)
    (expect (cl-parser-kit::%source-line-at source 2) :to-equal "second")
    (let ((cached (gethash source cl-parser-kit::*diagnostic-source-line-start-cache*)))
      (expect (hash-table-count cl-parser-kit::*diagnostic-source-line-start-cache*)
              :to-equal 1)
      (expect (cl-parser-kit::%source-line-at source 3) :to-equal "third")
      (expect (eq cached
                  (gethash source cl-parser-kit::*diagnostic-source-line-start-cache*))
              :to-be-truthy))))

(it-sequential "diagnostic-source-line-cache-handles-crlf-and-lone-cr-breaks-test"
  ;; %COMPUTE-SOURCE-LINE-STARTS and %BOUNDED-LINE-TEXT-FROM-START (the cached
  ;; path) must treat CRLF as one break and a lone CR as a break too, mirroring
  ;; ADVANCE-POSITION -- otherwise a Windows-style or classic-Mac-style source
  ;; would misnumber lines only when the cache is active.
  (let ((cl-parser-kit::*diagnostic-source-line-start-cache* (make-hash-table :test 'eq)))
    (let ((crlf-source (format nil "first~C~Csecond~C~Cthird" #\Return #\Newline #\Return #\Newline)))
      (expect (cl-parser-kit::%source-line-at crlf-source 2) :to-equal "second")
      (expect (cl-parser-kit::%source-line-at crlf-source 3) :to-equal "third"))
    (let ((cr-only-source (format nil "first~Csecond~Cthird" #\Return #\Return)))
      (expect (cl-parser-kit::%source-line-at cr-only-source 2) :to-equal "second")
      (expect (cl-parser-kit::%source-line-at cr-only-source 3) :to-equal "third"))))

(it-sequential "diagnostic-source-line-uncached-fallback-handles-crlf-and-lone-cr-breaks-test"
  ;; %SOURCE-LINE-AT's uncached fallback (no *DIAGNOSTIC-SOURCE-LINE-START-CACHE*
  ;; bound, the default) has its own independent linear scan with the same
  ;; CRLF/lone-CR handling as the cached path above -- it must not regress on
  ;; its own.
  (let ((crlf-source (format nil "first~C~Csecond~C~Cthird" #\Return #\Newline #\Return #\Newline)))
    (expect (cl-parser-kit::%source-line-at crlf-source 2) :to-equal "second")
    (expect (cl-parser-kit::%source-line-at crlf-source 3) :to-equal "third"))
  (let ((cr-only-source (format nil "first~Csecond~Cthird" #\Return #\Return)))
    (expect (cl-parser-kit::%source-line-at cr-only-source 2) :to-equal "second")
    (expect (cl-parser-kit::%source-line-at cr-only-source 3) :to-equal "third")))

(it-sequential "diagnostic-source-line-cache-truncates-a-long-line-test"
  ;; %BOUNDED-LINE-TEXT-FROM-START must cap and ellipsize a line longer than
  ;; *MAXIMUM-DIAGNOSTIC-LINE-LENGTH* on the cached path exactly as
  ;; %BOUNDED-LINE-TEXT does on the uncached one.
  (let ((cl-parser-kit::*diagnostic-source-line-start-cache* (make-hash-table :test 'eq))
        (*maximum-diagnostic-line-length* 5))
    (let ((source (format nil "0123456789~%next")))
      (expect (cl-parser-kit::%source-line-at source 1) :to-equal "01234...")
      ;; A line no longer than the cap renders without an ellipsis.
      (expect (cl-parser-kit::%source-line-at source 2) :to-equal "next"))))

(it-sequential "diagnostic-source-line-cache-truncation-lands-exactly-on-break-omits-ellipsis-test"
  ;; When the truncation cap lands EXACTLY on the character that starts the
  ;; next line break, %BOUNDED-LINE-TEXT-FROM-START must not append "..." --
  ;; there was nothing more of THIS line to elide.
  (let ((cl-parser-kit::*diagnostic-source-line-start-cache* (make-hash-table :test 'eq))
        (*maximum-diagnostic-line-length* 5))
    (let ((source (format nil "01234~%next")))
      (expect (cl-parser-kit::%source-line-at source 1) :to-equal "01234")
      (expect (cl-parser-kit::%source-line-at source 2) :to-equal "next"))))

(it-sequential "diagnostic-source-line-cache-returns-nil-for-an-out-of-range-line-number-test"
  ;; %SOURCE-LINE-AT's CACHED branch must also decline (return NIL) when the
  ;; requested line is beyond the cached STARTS vector's length, exactly as
  ;; the uncached scan does for the same out-of-range request.
  (let ((cl-parser-kit::*diagnostic-source-line-start-cache* (make-hash-table :test 'eq))
        (source (format nil "first~%second")))
    (expect (cl-parser-kit::%source-line-at source 5) :to-be-falsy)))

(it-sequential "diagnostic-source-line-cache-handles-a-lone-trailing-cr-test"
  ;; %COMPUTE-SOURCE-LINE-STARTS's CR clause must not look past the end of
  ;; SOURCE when the CR is the very last character -- the cached path's own
  ;; guard distinct from %SOURCE-LINE-AT's uncached one below.
  (let ((cl-parser-kit::*diagnostic-source-line-start-cache* (make-hash-table :test 'eq))
        (source (format nil "abc~C" #\Return)))
    (expect (cl-parser-kit::%source-line-at source 1) :to-equal "abc")
    (expect (cl-parser-kit::%source-line-at source 2) :to-equal "")))

(it-sequential "diagnostic-source-line-uncached-handles-a-lone-trailing-cr-test"
  ;; The uncached linear scan's own CR clause has the same trailing-CR guard,
  ;; instrumented independently from the cached path above.
  (let ((source (format nil "abc~C" #\Return)))
    (expect (cl-parser-kit::%source-line-at source 1) :to-equal "abc")
    (expect (cl-parser-kit::%source-line-at source 2) :to-equal "")))

(it-sequential "diagnostic-string-renders-a-middle-line-of-a-plain-lf-source-uncached-test"
  ;; DIAGNOSTIC->STRING (singular) never binds the source-line-start cache, so
  ;; it always exercises %SOURCE-LINE-AT's uncached linear scan. Requesting a
  ;; MIDDLE line of a plain-LF (not CR/CRLF) source must resolve via the early
  ;; return inside the scan's own line-break clause, not by falling through to
  ;; the end-of-loop check.
  (let* ((source (format nil "first~%second~%third"))
         (diag (error-diagnostic "boom"
                                 :span (make-span :source source
                                                  :start 6 :end 12
                                                  :start-line 2 :start-column 1
                                                  :end-line 2 :end-column 7))))
    (assert-rendered-contains-all
     (diagnostic->string diag)
     '("boom" "2:1-2:7" "second"))))

(it-sequential "diagnostic-string-omits-context-for-an-out-of-range-line-number-uncached-test"
  ;; %SOURCE-LINE-AT's uncached scan returns NIL when the requested line is
  ;; beyond the source's actual line count, so DIAGNOSTIC->STRING must omit the
  ;; source/caret context entirely rather than erroring.
  (let* ((source "foo")
         (diag (error-diagnostic "boom"
                                 :span (make-span :source source
                                                  :start 0 :end 1
                                                  :start-line 2 :start-column 1
                                                  :end-line 2 :end-column 2))))
    (let ((rendered (diagnostic->string diag)))
      (expect (search "boom" rendered) :to-be-truthy)
      (expect (search "|" rendered) :to-be-falsy))))

(it-sequential "parse-failure-string-renders-token-and-string-expectations-test"
  ;; A type-less token falls back to its printed text, and a raw string
  ;; expectation passes through unchanged.
  (let ((failure (make-parse-failure
                  :position 0
                  :expected "a binding name"
                  :actual (make-token :type nil :text "foo" :start 0 :end 3))))
    (assert-rendered-contains-all
     (parse-failure->string failure)
     '("Expected a binding name" "\"foo\""))))

(it-sequential "diagnostic-string-test"
  (let ((diag (error-diagnostic "bad token"
                                :span (make-span :source "foo + bar"
                                                 :start 0 :end 3 :start-line 1 :start-column 1
                                                 :end-line 1 :end-column 2)
                                :notes (list (note-diagnostic "check syntax"
                                                              :span (make-span :start 4 :end 5
                                                                               :start-line 1 :start-column 5
                                                                               :end-line 1 :end-column 6)))
                                :fixes (list (make-fix-it :span (make-span :start 0 :end 1)
                                                          :replacement "x"))
                                :data '(:kind :token))))
    (assert-rendered-contains-all
     (diagnostic->string diag)
     '("bad token"
       "1:1-1:2"
       "foo + bar"
       "^"
       "note: check syntax [1:5-1:6]"
       "fix-it [1:1-1:1]: replace with \"x\""))))

(it-sequential "parse-failure-merge-test"
  (let ((left (make-parse-failure :position 1 :expected '(:number) :actual :plus))
        (right (make-parse-failure :position 1 :expected '(:identifier) :actual :plus)))
    (let ((merged (merge-parse-failures left right)))
      (expect (parse-failure-position merged) :to-equal 1)
      (expect (sort (copy-list (parse-failure-expected merged)) #'string< :key #'symbol-name) :to-equal '(:identifier :number))
      (expect (parse-failure-actual merged) :to-equal :plus))))

(it-sequential "parse-failure-merge-deduplicates-overlapping-expected-items-test"
  ;; %MERGE-PARSE-FAILURE-LISTS-UNIQUE's dedup hash must actually skip an item
  ;; it has already seen -- :IDENTIFIER appears in both failures' EXPECTED
  ;; lists here, so the merged result must list it only once.
  (let ((left (make-parse-failure :position 1 :expected '(:number :identifier) :actual :plus))
        (right (make-parse-failure :position 1 :expected '(:identifier :string) :actual :plus)))
    (let ((merged (merge-parse-failures left right)))
      (expect (sort (copy-list (parse-failure-expected merged)) #'string< :key #'symbol-name)
              :to-equal '(:identifier :number :string)))))

(it-sequential "parse-failure-merge-prefers-farthest-position-test"
  (let ((near (make-parse-failure :position 2 :expected :identifier :actual :plus))
        (far (make-parse-failure :position 5 :expected :number :actual :minus)))
    (let ((merged (merge-parse-failures near far)))
      (expect (parse-failure-position merged) :to-equal 5)
      (expect (parse-failure-expected merged) :to-equal :number)
      (expect (parse-failure-actual merged) :to-equal :minus))))

(it-sequential "parse-failure-merge-preserves-commit-and-diagnostics-test"
  (let* ((left-diagnostic (error-diagnostic "expected number"))
         (right-diagnostic (note-diagnostic "after prefix operator"))
         (left (make-parse-failure :position 3
                                   :expected :number
                                   :actual :plus
                                   :diagnostics (list left-diagnostic)))
         (right (make-parse-failure :position 3
                                    :expected :identifier
                                    :actual :plus
                                    :diagnostics (list right-diagnostic)
                                    :committed-p t)))
    (let ((merged (merge-parse-failures left right)))
      (expect (parse-failure-committed-p merged) :to-be-truthy)
      (expect (parse-failure-diagnostics merged) :to-equal (list left-diagnostic right-diagnostic)))))

(it-sequential "parse-failure-merge-rejects-excessive-expected-list-test"
  (let ((*maximum-parse-failure-expected-count* 2)
        (left (make-parse-failure :position 1 :expected '(:one :two) :actual :plus))
        (right (make-parse-failure :position 1 :expected :three :actual :plus)))
    (expect (lambda () (merge-parse-failures left right))
            :to-throw 'parse-failure-resource-limit-exceeded)))

(it-sequential "parse-failure-merge-rejects-improper-expected-list-test"
  (let ((left (make-parse-failure :position 1 :expected (cons :one :two) :actual :plus))
        (right (make-parse-failure :position 1 :expected :three :actual :plus)))
    (expect (lambda () (merge-parse-failures left right))
            :to-throw 'parse-failure-resource-limit-exceeded)))

(it-sequential "parse-failure-merge-rejects-excessive-diagnostic-list-test"
  (let* ((*maximum-parse-failure-diagnostic-count* 2)
         (left (make-parse-failure :position 1
                                   :expected :identifier
                                   :actual :plus
                                   :diagnostics (list (error-diagnostic "one")
                                                      (error-diagnostic "two"))))
         (right (make-parse-failure :position 1
                                    :expected :number
                                    :actual :plus
                                    :diagnostics (list (error-diagnostic "three")))))
    (expect (lambda () (merge-parse-failures left right))
            :to-throw 'parse-failure-resource-limit-exceeded)))

(it-sequential "parse-failure-merge-rejects-improper-diagnostic-list-test"
  (let ((left (make-parse-failure :position 1
                                  :expected :identifier
                                  :actual :plus
                                  :diagnostics (cons (error-diagnostic "one")
                                                     (error-diagnostic "two"))))
        (right (make-parse-failure :position 1
                                   :expected :number
                                   :actual :plus)))
    (expect (lambda () (merge-parse-failures left right))
            :to-throw 'parse-failure-resource-limit-exceeded)))

(it-sequential "parse-failure-string-test"
  (let* ((diagnostic (error-diagnostic "bad token"
                                       :span (make-span :source "foo + bar"
                                                        :start 0 :end 3 :start-line 1 :start-column 1
                                                        :end-line 1 :end-column 2)))
         (failure (make-parse-failure :position 0
                                      :expected :identifier
                                      :actual :plus
                                      :diagnostics (list diagnostic))))
    (assert-rendered-contains-all
     (parse-failure->string failure)
     '("bad token" "foo + bar"))))

(it-sequential "parse-failure-string-fallback-test"
  (dolist (case
           (list
            (list (make-parse-failure :position 1
                                      :expected '(:identifier :number)
                                      :actual (make-token :type :plus
                                                          :text "+"
                                                          :start 7
                                                          :end 8
                                                          :metadata (list :source "answer
+")))
                  '("Expected one of IDENTIFIER or NUMBER, got PLUS"
                    "2:1-2:2"
                    "+"
                    "^"))
            (list (make-parse-failure :position 1
                                      :expected '(:identifier :number)
                                      :actual (make-token :type :plus
                                                          :text "+"
                                                          :start 8
                                                          :end 9
                                                          :metadata (list :source (format nil "answer~C~C+"
                                                                                           #\Return
                                                                                           #\Newline))))
                  '("Expected one of IDENTIFIER or NUMBER, got PLUS"
                    "2:1-2:2"
                    "+"
                    "^"))))
    (destructuring-bind (failure snippets) case
      (assert-rendered-contains-all (parse-failure->string failure) snippets))))

(it-sequential "parse-failure-string-fallback-eof-test"
  (let ((failure (make-parse-failure :position 4
                                     :expected :identifier
                                     :actual nil)))
    (let ((text (parse-failure->string failure)))
      (expect (search "Expected IDENTIFIER, got EOF" text) :to-be-truthy)
      (expect (search "[" text) :to-be-falsy))))

(it-sequential "parse-failure-string-renders-unknown-input-for-an-empty-expected-list-test"
  ;; %PARSE-FAILURE-EXPECTED-STRING falls back to "unknown input" when EXPECTED
  ;; renders to no items at all.
  (let ((failure (make-parse-failure :position 0 :expected nil :actual :plus)))
    (expect (search "Expected unknown input" (parse-failure->string failure))
            :to-be-truthy)))

(it-sequential "parse-failure-string-renders-a-non-standard-actual-item-test"
  ;; %PARSE-FAILURE-ITEM->STRING's TYPECASE falls back to PRIN1-TO-STRING for an
  ;; ACTUAL that is neither NULL, a TOKEN, a SYMBOL, nor a STRING.
  (let ((failure (make-parse-failure :position 0 :expected :number :actual 42)))
    (expect (search "got 42" (parse-failure->string failure)) :to-be-truthy)))

(it-sequential "parse-failure-string-renders-a-typeless-token-by-its-text-test"
  ;; %PARSE-FAILURE-TOKEN-STRING falls back to the token's (PRIN1-TO-STRING TEXT)
  ;; when it has text but no TOKEN-TYPE.
  (let ((failure (make-parse-failure
                  :position 0 :expected :number
                  :actual (make-token :type nil :text "??"))))
    (expect (search "got \"??\"" (parse-failure->string failure)) :to-be-truthy)))

(it-sequential "parse-failure-string-renders-a-typeless-textless-token-as-token-fallback-test"
  ;; %PARSE-FAILURE-TOKEN-STRING falls all the way back to the literal "TOKEN"
  ;; when the token has neither a TOKEN-TYPE nor TEXT to fall back on.
  (let ((failure (make-parse-failure
                  :position 0 :expected :number
                  :actual (make-token :type nil :text nil))))
    (expect (search "got TOKEN" (parse-failure->string failure)) :to-be-truthy)))

(it-sequential "parse-failure-string-ignores-nil-diagnostics-test"
  (let* ((diagnostic (error-diagnostic "bad token"
                                       :span (make-span :source "foo"
                                                        :start 0 :end 3
                                                        :start-line 1 :start-column 1
                                                        :end-line 1 :end-column 4)))
         (failure (make-parse-failure :position 0
                                     :expected :identifier
                                     :actual :plus
                                     :diagnostics (list nil diagnostic))))
    (assert-rendered-contains-all
     (parse-failure->string failure)
     '("bad token" "foo"))))

(it-sequential "parse-failure-public-accessor-contract-test"
  (let* ((diagnostic (warning-diagnostic "recoverable"))
         (failure (make-parse-failure :position 4
                                      :expected '(:identifier :number)
                                      :actual :plus
                                      :diagnostics (list diagnostic)
                                      :committed-p t)))
    (expect (typep failure 'parse-failure) :to-be-truthy)
    (expect (parse-failure-position failure) :to-equal 4)
    (expect (parse-failure-expected failure) :to-equal '(:identifier :number))
    (expect (parse-failure-actual failure) :to-equal :plus)
    (expect (parse-failure-diagnostics failure) :to-equal (list diagnostic))
    (expect (parse-failure-committed-p failure) :to-be-truthy)))

(it-sequential "diagnostic-public-accessor-contract-test"
  (let* ((span (make-span :source "abc"
                          :start 1 :end 2
                          :start-line 1 :start-column 2
                          :end-line 1 :end-column 3))
         (note (note-diagnostic "context" :span span))
         (fix (make-fix-it :span span :replacement "z"))
         (diagnostic (make-diagnostic :kind :warning
                                      :message "problem"
                                      :span span
                                      :notes (list note)
                                      :fixes (list fix)
                                      :data '(:origin :test)))
         (warning (warning-diagnostic "warn" :span span)))
    (expect (diagnostic-kind diagnostic) :to-equal :warning)
    (expect (diagnostic-message diagnostic) :to-equal "problem")
    (expect (diagnostic-span diagnostic) :to-equal span)
    (expect (diagnostic-notes diagnostic) :to-equal (list note))
    (expect (diagnostic-fixes diagnostic) :to-equal (list fix))
    (expect (diagnostic-data diagnostic) :to-equal '(:origin :test))
    (expect (fix-it-span fix) :to-equal span)
    (expect (fix-it-replacement fix) :to-equal "z")
    (expect (diagnostic-kind warning) :to-equal :warning)
    (expect (diagnostic-message warning) :to-equal "warn")))
