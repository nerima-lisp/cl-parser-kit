(in-package :cl-parser-kit/test)

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
