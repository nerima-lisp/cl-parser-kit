;;;; This form comes FIRST, before any defsystem. ASDF binds *package* to
;;;; ASDF-USER only for a file it loads itself; read any other way -- a REPL
;;;; `load`, an editor evaluating the buffer, flake.nix parsing :version -- the
;;;; file is read in whatever package happens to be current. Saying it makes
;;;; the file self-contained.
(in-package #:asdf-user)

(asdf:defsystem "cl-parser-kit"
  :description "Small parser toolkit for Common Lisp text languages."
  :author "takeokunn <bararararatty@gmail.com>"
  :maintainer "takeokunn <bararararatty@gmail.com>"
  :license "MIT"
  :version "1.0.2"
  :homepage "https://github.com/nerima-lisp/cl-parser-kit"
  :bug-tracker "https://github.com/nerima-lisp/cl-parser-kit/issues"
  :source-control (:git "https://github.com/nerima-lisp/cl-parser-kit.git")
  ;; DEPENDENCY_POLICY.md places this package at L1 (general-purpose
  ;; utility): the runtime system depends on nothing outside the standard.
  ;; cl-weave and cl-prolog are test-only and belong to cl-parser-kit/test.
  :depends-on ()
  :pathname "src"
  :serial t
  :components
  ((:file "package")
   (:file "core")
   (:file "spans")
   (:file "tokens")
   (:file "tokenizer")
   (:file "tokenizer-rules")
   (:file "tokenizer-rules-text")
   (:file "tokenizer-rules-extra")
   (:file "diagnostics")
   (:file "diagnostics-fixes")
   (:file "diagnostics-format")
   (:file "tree")
   (:file "tree-macros")
   (:file "parse-failure")
   (:file "parse-failure-format")
   (:file "combinators")
   (:file "combinators-sequence")
   (:file "combinators-boundary")
   (:file "combinators-choice")
   (:file "combinators-repeat")
   (:file "combinators-apply")
   (:file "combinators-macros")
   (:file "combinators-token")
   (:file "combinators-recover")
   (:file "combinators-backtrack")
   (:file "combinators-permutation")
   (:file "combinators-expression")
   (:file "combinators-memoize")
   (:file "combinators-debug")
   (:file "pratt")
   (:file "pratt-parse")
   (:file "pratt-builders")
   (:file "parser")
   (:file "ast")
   (:file "cst"))
  :in-order-to ((asdf:test-op (asdf:test-op "cl-parser-kit/test"))))

(asdf:defsystem "cl-parser-kit/test"
  :description "Test system for cl-parser-kit."
  :author "takeokunn <bararararatty@gmail.com>"
  :maintainer "takeokunn <bararararatty@gmail.com>"
  :license "MIT"
  :version "1.0.2"
  :homepage "https://github.com/nerima-lisp/cl-parser-kit"
  :bug-tracker "https://github.com/nerima-lisp/cl-parser-kit/issues"
  :source-control (:git "https://github.com/nerima-lisp/cl-parser-kit.git")
  :depends-on ("cl-parser-kit" "cl-weave" "cl-prolog/weave")
  :pathname "t"
  :serial t
  :components
  ((:file "package")
   (:file "tokens-test")
   (:file "helpers-tokenizer")
   (:file "helpers-tokenizer-fixtures")
   (:file "tokenizer-basic-test")
   (:file "tokenizer-span-test")
   (:file "tokenizer-comment-test")
   (:file "tokenizer-string-test")
   (:file "tokenizer-comment-rules-test")
   (:file "tokenizer-keyword-test")
   (:file "tokenizer-identifier-test")
   (:file "tokenizer-char-rule-test")
   (:file "tokenizer-rules-extra-test")
   (:file "spans-test")
   (:file "diagnostics-test")
   (:file "diagnostics-format-test")
   (:file "diagnostics-fixes-test")
   (:file "parse-failure-format-test")
   (:file "mutation-testing-test")
   (:file "helpers-combinators")
   (:file "helpers-combinators-fixtures")
   (:file "combinators-core-test")
   (:file "combinators-chain-test")
   (:file "combinators-separator-test")
   (:file "combinators-delimited-test")
   (:file "combinators-control-test")
   (:file "combinators-transform-test")
   (:file "combinators-choice-test")
   (:file "combinators-repeat-test")
   (:file "combinators-apply-test")
   (:file "combinators-macros-test")
   (:file "combinators-token-test")
   (:file "combinators-recover-test")
   (:file "combinators-backtrack-test")
   (:file "combinators-permutation-test")
   (:file "combinators-expression-test")
   (:file "combinators-memoize-test")
   (:file "combinators-debug-test")
   (:file "helpers-pratt")
   (:file "helpers-pratt-fixtures")
   (:file "pratt-basic-test")
   (:file "pratt-failure-trailing-test")
   (:file "pratt-failure-test")
   (:file "pratt-source-test")
   (:file "pratt-contract-test")
   (:file "pratt-builders-test")
   (:file "prolog-contract-test")
   (:file "helpers-parser")
   (:file "parser-core-test")
   (:file "parser-diagnostic-test")
   (:file "parser-runtime-test")
   (:file "parser-contract-test")
   (:file "parser-properties-test")
   (:file "fuzz-test")
   (:file "helpers-examples-doc-data")
   (:file "helpers-examples-common")
   (:file "helpers-examples-doc")
   (:file "helpers-examples-file")
   (:file "helpers-examples-runtime")
   (:file "examples-docs-test")
   (:file "examples-snippets-core-test")
   (:file "examples-snippets-core-advanced-test")
   (:file "examples-snippets-structures-test")
   (:file "examples-snippets-runtime-test")
   (:file "examples-advanced-snippets-test")
   (:file "examples-files-test")
   (:file "examples-ops-test")
   (:file "trees-test")
   (:file "trees-traversal-test")
   (:file "api-surface-test"))
  :perform (asdf:test-op (op system)
             (declare (ignore op system))
             (unless (uiop:symbol-call :cl-weave
                                       :run-all
                                       :reporter :spec
                                       :pass-with-no-tests nil)
               (error "cl-parser-kit tests failed"))))
