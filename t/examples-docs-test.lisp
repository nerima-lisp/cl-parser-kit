(in-package :cl-parser-kit/test)

;;; mkdocs --strict already fails on a broken link between two pages under
;;; docs/src/, but only for files it renders. This keeps the same guarantee for
;;; README.md and CHANGELOG.md, which are read on GitHub and never pass through
;;; MkDocs, and it fails in the test suite rather than in the docs build.
(it-sequential "public-doc-links-resolve-test"
  (dolist (doc-name *published-documents*)
    (let ((missing '()))
      (dolist (target (markdown-local-links doc-name))
        (unless (probe-file (markdown-link-pathname doc-name target))
          (push target missing)))
      (expect (nreverse missing) :to-equal '()))))

(it-sequential "examples-guide-covers-all-example-files-test"
  (let* ((contents (doc-file-contents "docs/src/guide/examples.md"))
         (missing (loop for name in (example-file-names)
                        unless (search name contents :test #'char-equal)
                        collect name)))
    (expect missing :to-equal '())))

(register-document-snippet-tests
  (readme-documents-verification-and-docs-entry-points-test
   "README.md"
   (document-required-snippets "README.md"))
  (development-guide-documents-verification-contract-test
   "docs/src/project/development.md"
   (document-required-snippets "docs/src/project/development.md"))
  (compatibility-documents-public-surface-contract-test
   "docs/src/reference/compatibility.md"
   (document-required-snippets "docs/src/reference/compatibility.md"))
  (roadmap-documents-current-oss-gaps-test
   "docs/src/project/roadmap.md"
   (document-required-snippets "docs/src/project/roadmap.md"))
  (api-guide-documents-recommended-entry-points-test
   "docs/src/reference/api.md"
   (document-required-snippets "docs/src/reference/api.md/recommended-entry-points")))

(register-document-snippet-tests
  (parsing-patterns-guide-documents-recommended-upgrade-path-test
   "docs/src/guide/parsing-patterns.md"
   (document-required-snippets "docs/src/guide/parsing-patterns.md"))
  (api-guide-documents-canonical-entry-points-test
   "docs/src/reference/api.md"
   (document-required-snippets "docs/src/reference/api.md/canonical-entry-points")))

(it-sequential "api-guide-covers-all-exported-symbols-test"
  (let* ((documented (markdown-code-identifiers "docs/src/reference/api.md"))
         (missing (sort (loop for symbol being the external-symbols of (find-package :cl-parser-kit)
                              for name = (string-downcase (symbol-name symbol))
                              unless (member name documented :test #'string=)
                              collect name)
                        #'string<)))
    (expect missing :to-equal '())))

;;; Both systems live in the single cl-parser-kit.asd, so this asserts the full
;;; eight-field metadata set PACKAGE_STANDARD.md requires rather than only the
;;; three fields the two-file layout used to check.
(it-sequential "asdf-systems-publish-oss-metadata-test"
  (let ((contents (repository-file-contents "cl-parser-kit.asd")))
    (dolist (field '(":description" ":author" ":maintainer" ":license"
                     ":version" ":homepage" ":bug-tracker" ":source-control"))
      (expect (string-contains-p field contents) :to-be-truthy))
    (expect (string-contains-p ":author \"takeokunn <bararararatty@gmail.com>\"" contents)
            :to-be-truthy)
    (expect (string-contains-p "defsystem \"cl-parser-kit/test\"" contents)
            :to-be-truthy)))

(it-sequential "examples-guide-documents-raw-checkout-example-verification-test"
  (assert-document-contains-all
   "docs/src/guide/examples.md"
   '("scripts/run-examples.lisp"
     "raw-checkout regression pass")))
