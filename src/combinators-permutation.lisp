(in-package :cl-parser-kit)

;;;; Permutation parsing.
;;;;
;;;; PERMUTE parses each parser once in any order and returns values in argument
;;;; order. It uses greedy first-match selection; committed failures propagate,
;;;; while recoverable failures try the next candidate.

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
                            ;; Report the farthest miss when no candidate matches.
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
