(in-package :cl-parser-kit)

(defun %token-like-p (value)
  (typep value 'token))

(defun parse-failure-span (failure)
  "The source span of FAILURE's actual token, or NIL when the failure carries no
token (for example at end of input, where the actual is :EOF).

A convenience for rendering a caret or slicing the offending source region from a
failure without building a full diagnostic: pair it with SPAN-TEXT or the
SPAN-START-LINE / SPAN-START-COLUMN accessors."
  (let ((actual (parse-failure-actual failure)))
    (when (%token-like-p actual)
      (%token-effective-span actual :position (parse-failure-position failure)))))

(defun %parse-failure-token-string (token)
  (or (and (token-type token)
           (string-upcase (symbol-name (token-type token))))
      (and (token-text token)
           (prin1-to-string (token-text token)))
      "TOKEN"))

(defun %parse-failure-item->string (item)
  (typecase item
    (null "EOF")
    (token (%parse-failure-token-string item))
    (symbol (string-upcase (symbol-name item)))
    (string item)
    (t (prin1-to-string item))))

(defun %parse-failure-items->strings (items)
  (mapcar #'%parse-failure-item->string items))

(defun %parse-failure-item-list (expected)
  (%ensure-parse-failure-list-count :expected-count
                                    expected
                                    *maximum-parse-failure-expected-count*))

(defun %join-expected-items (items)
  "Join the rendered ITEMS (2 or more -- %PARSE-FAILURE-EXPECTED-STRING handles
0 and 1 itself before ever calling this) as \"a or b\" for exactly two, or a
plain comma-separated \"a, b, c\" for three or more."
  (let ((rendered (%parse-failure-items->strings items)))
    (if (= (length rendered) 2)
        (format nil "~A or ~A" (first rendered) (second rendered))
        (with-output-to-string (out)
          (write-string (first rendered) out)
          (dolist (item (rest rendered))
            (write-string ", " out)
            (write-string item out))))))

(defun %parse-failure-expected-string (expected)
  (let ((items (%parse-failure-item-list expected)))
    (cond
      ((null items) "unknown input")
      ((null (rest items))
       (%parse-failure-item->string (first items)))
      (t (format nil "one of ~A" (%join-expected-items items))))))

(defun %parse-failure-diagnostics-list (failure)
  (remove nil
          (%ensure-parse-failure-list-count
           :diagnostic-count
           (parse-failure-diagnostics failure)
           *maximum-parse-failure-diagnostic-count*)))

(defun %parse-failure-default-span (failure actual)
  ;; Only ever called (see %PARSE-FAILURE-DEFAULT-DIAGNOSTIC, below) after
  ;; PARSE-FAILURE->DIAGNOSTICS has already determined that this failure's
  ;; own %PARSE-FAILURE-DIAGNOSTICS-LIST is empty, so recomputing it here to
  ;; borrow a span from it would always return NIL -- a token is the only
  ;; source of a default span this function can ever actually use.
  (when (%token-like-p actual)
    (%token-effective-span actual :position (parse-failure-position failure))))

(defun %parse-failure-default-diagnostic (failure)
  (let ((actual (parse-failure-actual failure)))
    (error-diagnostic
     (format nil "Expected ~A, got ~A"
             (%parse-failure-expected-string
              (parse-failure-expected failure))
             (%parse-failure-item->string actual))
     :span (%parse-failure-default-span failure actual))))

(defun %write-diagnostics (diagnostics out)
  (labels ((write-one (diagnostic firstp)
             (when diagnostic
               (unless firstp
                 (terpri out)
                 (terpri out))
               (%write-diagnostic diagnostic out)
               nil)))
    (if (consp diagnostics)
        (let ((firstp t))
          (%walk-bounded-list diagnostics *maximum-diagnostic-count*
                              (lambda (count)
                                (error 'diagnostic-resource-limit-exceeded
                                       :kind :diagnostic-count
                                       :value count
                                       :limit *maximum-diagnostic-count*))
                              (lambda (diagnostic) (setf firstp (write-one diagnostic firstp)))))
        (write-one diagnostics t))))

(defun parse-failure->diagnostics (failure)
  "Return the list of structured DIAGNOSTIC objects describing FAILURE: its
attached diagnostics when it carries any, otherwise a single synthesized default
diagnostic (an \"Expected X, got Y\" error carrying the failure's span).

The structured counterpart of PARSE-FAILURE->STRING -- use it when rendering or
aggregating failures with your own tooling (fix-its, an LSP, a batched report)
rather than the built-in string form. Always returns at least one diagnostic."
  (or (%parse-failure-diagnostics-list failure)
      (list (%parse-failure-default-diagnostic failure))))

(defun parse-failure->string (failure)
  "Render FAILURE as a human-readable report -- PARSE-FAILURE->DIAGNOSTICS run
through DIAGNOSTICS->STRING -- so a failure with no diagnostics of its own
still prints its synthesized \"Expected X, got Y\" line. This is the string most
callers want to show a user directly."
  (let ((*diagnostic-source-line-start-cache* (make-hash-table :test 'eq)))
    (with-output-to-string (out)
      (%write-diagnostics (parse-failure->diagnostics failure) out))))

(defun diagnostics->string (diagnostics)
  "Render a LIST of diagnostics as one string, each rendered by DIAGNOSTIC->STRING
and separated by a blank line; NIL entries are ignored for output but still
counted against *MAXIMUM-DIAGNOSTIC-COUNT* while streaming. The
multi-diagnostic form of DIAGNOSTIC->STRING, handy for a recovery parse's
collected diagnostics or the result of PARSE-FAILURE->DIAGNOSTICS."
  (let ((*diagnostic-source-line-start-cache* (make-hash-table :test 'eq)))
    (with-output-to-string (out)
      (%write-diagnostics diagnostics out))))
