;;;; Test entry point. PACKAGE_STANDARD.md puts this at the repository root so
;;;; that `sbcl --script run-tests.lisp` works from a raw checkout without
;;;; knowing where the helper scripts live; the shared loader stays in
;;;; scripts/bootstrap.lisp, which is also used by run-coverage.lisp and
;;;; run-compile-check.lisp.
(eval-when (:compile-toplevel :load-toplevel :execute)
  (load (merge-pathnames "scripts/bootstrap.lisp"
                         (make-pathname :name nil
                                        :type nil
                                        :version nil
                                        :defaults (or *load-pathname*
                                                      *compile-file-pathname*)))))

(let ((project-root (current-project-root)))
  (require :asdf)
  (load-project-tests project-root)
  (let ((plan (package-symbol-call "CL-WEAVE" "LIST-TESTS"
                                   :reporter :json
                                   :stream (make-broadcast-stream))))
    (format t "Loaded ~D tests.~%" (length plan))
    (when (zerop (length plan))
      (error "cl-parser-kit loaded zero tests")))
  (unless (package-symbol-call :cl-weave
                               :run-all
                               :reporter :spec
                               :pass-with-no-tests nil)
    (uiop:quit 1)))
