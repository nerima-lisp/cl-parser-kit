(defpackage :cl-parser-kit/test
  (:use :cl :cl-parser-kit :cl-weave)
  (:shadowing-import-from :cl-weave #:describe))

(in-package :cl-parser-kit/test)

(defun assert-string-contains-all (haystack snippets)
  "Assert every snippet is a substring of HAYSTACK, reporting every miss at once."
  (with-soft-assertions
    (dolist (snippet snippets)
      (expect (search snippet haystack) :to-be-truthy))))

(defmacro assert-rendered-contains-all (form snippets)
  `(let ((rendered ,form))
     (assert-string-contains-all rendered ,snippets)
     rendered))

(defmacro %assert-multiple-values (form (ok value next failure) &body assertions)
  `(multiple-value-bind (,ok ,value ,next ,failure)
       ,form
     ,@assertions))

;; The DECLARE-stripping LOOP just below (and its twin in
;; %ASSERT-FAILURE-VALUES) runs at macroexpansion time -- while compiling
;; whatever test file calls ASSERT-COMBINATOR-SUCCESS/-FAILURE -- never at
;; program-execution time, so SB-COVER can never mark it covered no matter how
;; many call sites pass a leading DECLARE (verified: several tests do, and
;; still count 0 hits here). A third variant of the two attribution artifacts
;; already documented in CONTRIBUTING.md, not a real gap.
(defmacro %assert-success-values (form (value next failure) &body assertions)
  (let ((declarations (loop while (and assertions
                                        (consp (first assertions))
                                        (eq (first (first assertions)) 'declare))
                            collect (pop assertions))))
    `(%assert-multiple-values ,form (ok ,value ,next ,failure)
       (declare (ignorable ,failure))
       ,@declarations
       (expect ok :to-be-truthy)
       ,@assertions)))

(defmacro %assert-failure-values (form (value next failure) &body assertions)
  (let ((declarations (loop while (and assertions
                                        (consp (first assertions))
                                        (eq (first (first assertions)) 'declare))
                            collect (pop assertions))))
    `(%assert-multiple-values ,form (ok ,value ,next ,failure)
       (declare (ignorable ,value ,failure))
       ,@declarations
       (expect ok :to-be-falsy)
       (expect ,value :to-be-falsy)
       ,@assertions)))

(defun %circular-list (&rest items)
  (let ((list (copy-list items)))
    (setf (cdr (last list)) list)
    list))

(defun %assert-diagnostic-span (diagnostic start-line start-column end-line end-column)
  (let ((span (diagnostic-span diagnostic)))
    (expect diagnostic :to-be-truthy)
    (expect (span-start-line span) :to-equal start-line)
    (expect (span-start-column span) :to-equal start-column)
    (expect (span-end-line span) :to-equal end-line)
    (expect (span-end-column span) :to-equal end-column)))
