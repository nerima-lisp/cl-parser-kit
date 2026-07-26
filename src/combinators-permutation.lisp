(in-package :cl-parser-kit)

;;;; Permutation parsing.
;;;;
;;;; PERMUTE parses a fixed set of parsers that may appear in ANY order, each
;;;; exactly once, and returns their values in the ORIGINAL argument order. This
;;;; is the classic use case of attribute lists, keyword-argument blocks, and
;;;; record fields where order is irrelevant.
;;;;
;;;; The strategy is greedy first-match, which mirrors the commitment model used
;;;; throughout the library: at each round every not-yet-matched parser is tried
;;;; at the current position in original order; the FIRST that succeeds is taken.
;;;; A committed sub-failure propagates immediately (the element began matching
;;;; and then failed hard); a recoverable sub-failure just moves on to the next
;;;; candidate. When no remaining parser matches, the permutation is complete iff
;;;; every element has matched, otherwise it fails. Each parser is removed once
;;;; matched, so the loop runs at most N rounds and always terminates -- even if
;;;; some element matched without consuming input.
;;;;
;;;; Greedy first-match resolves an unambiguous permutation grammar (one whose
;;;; elements are distinguishable by their leading token) exactly; overlapping
;;;; alternatives should be disambiguated with ATTEMPT, as in ordinary ALT code.

(defun permute (&rest parsers)
  "Parse PARSERS in any order, each exactly once, returning their values as a
list in the ORIGINAL argument order.

  (permute name-attr id-attr class-attr)

matches the three attributes however they are arranged in the source and always
returns (name id class). A committed failure inside any element propagates; a
recoverable failure lets the other elements be tried first. Fails if any element
never matches. See ATTEMPT for disambiguating elements with overlapping starts."
  (let* ((items (%ensure-parser-list-vector "PERMUTE" parsers))
         (count (length items)))
    (make-parser
     :name :permute
     :fn (lambda (input position)
           (let ((results (make-array count :initial-element nil))
                 (active (make-array count :initial-element t)))
             (labels ((next-round (current remaining-count diagnostics)
                        (if (zerop remaining-count)
                            (%success (coerce results 'list) current diagnostics)
                            (try-candidates current remaining-count 0 diagnostics nil)))
                      (try-candidates (current remaining-count index diagnostics best-failure)
                        (if (= index count)
                            ;; No remaining element matched at CURRENT: a required
                            ;; element is missing. Report the farthest miss. BEST-FAILURE
                            ;; is always non-NIL here: REMAINING-COUNT > 0 (checked by
                            ;; NEXT-ROUND before ever calling TRY-CANDIDATES) guarantees
                            ;; at least one active element is tried during this sweep,
                            ;; and MERGE-PARSE-FAILURES always returns non-NIL once given
                            ;; a real failure to merge in.
                            (%failure-from best-failure)
                            (if (not (aref active index))
                                (try-candidates current remaining-count (1+ index)
                                                diagnostics best-failure)
                                (%run-parser/if-success
                                 (aref items index) input current
                                 (lambda (value next result)
                                   (setf (aref results index) value)
                                   (setf (aref active index) nil)
                                   (next-round next
                                               (1- remaining-count)
                                               (%merge-diagnostics diagnostics result)))
                                 (lambda (result failed-next)
                                   (declare (ignore failed-next))
                                   (if (parse-failure-committed-p result)
                                       (%committed-failure-from result)
                                       (try-candidates
                                        current remaining-count (1+ index) diagnostics
                                        (merge-parse-failures best-failure result)))))))))
               (next-round position count '())))))))
