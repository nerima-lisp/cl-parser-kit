(in-package :cl-parser-kit/test)

(defparameter *dsl-sample-source*
  "if $value /* note */ \"ok\" ; trailing comment
if?")

(defparameter *diagnostic-sample-source* "foo + bar")

(defparameter *document-required-snippets*
  '(("README.md"
     "run-tests.lisp"
     "nix flake check"
     "nix develop"
     "docs/src/"
     "nerima-lisp.github.io/cl-parser-kit")
    ("docs/src/development.md"
     "run-tests.lisp"
     "scripts/run-compile-check.lisp"
     "scripts/run-coverage.lisp"
     "scripts/run-examples.lisp"
     "scripts/run-implementation-smoke.sh"
     "nix flake check"
     "nix run .#test"
     "nix fmt"
     "CL_PARSER_KIT_CL_WEAVE_ROOT"
     "it-property")
    ("docs/src/compatibility.md"
     "290 symbols"
     "t/api-surface-test.lisp"
     "leading `%`"
     "resource-limit defaults"
     "style-warning")
    ("docs/src/roadmap.md"
     "nix flake check"
     "coverage"
     "CHANGELOG.md")
    ("docs/src/api-reference.md/recommended-entry-points"
     "## Recommended Entry Points"
     "## Quick Start Surface"
     "parsing-patterns.md"
     "tokenize source with `make-tokenizer` and `tokenize-string`"
     "For comma-separated or bracketed forms, start with `sep-by`, `sep-by1`"
     "start with `chainl1` or `chainr1`; pair them with `operator-parser`"
     "use `make-ast-node` or `make-cst-node` to shape downstream data"
     "use `ast-node->sexp` or `cst-node->sexp`")
    ("docs/src/parsing-patterns.md"
     "## Start With The Smallest Stable Layer"
     "Prefer Sequence Helpers Over Manual Delimiter Loops"
     "Use `delimited-sep-by` or `delimited-sep-by1`"
     "`sep-end-by` / `sep-end-by1` keep that same committed-item rule"
     "Use `type-token-text` or `type-token-value`"
     "alt` returns the farthest branch failure"
     "Move to Pratt parsing when you need:"
     "Replace hand-written delimiter plumbing with `preceded-by`")
    ("docs/src/api-reference.md/canonical-entry-points"
     "## Parser Entry Points"
     "`parse-tokens`"
     "`parse-all`"
     "`parse-source`"
     "`parse-pratt`"
     "`parse-pratt-source`"
     "End-to-end entry points intentionally stay small"))
  "Per-document required-snippet fixture table for DOCUMENT-REQUIRED-SNIPPETS,
kept apart from the lookup so the data itself -- what each doc must
contain -- reads as a table, not a dispatch chain.

Contribution, conduct, governance, support, security and maintainer policy are
org-wide files served from nerima-lisp/.github, so this repository no longer
ships copies of them and there is nothing here to assert about them.")

(defun document-required-snippets (document)
  (or (cdr (assoc document *document-required-snippets* :test #'string=))
      (error "Unknown document snippet contract: ~S" document)))

(defparameter *published-documents*
  '("README.md"
    "CHANGELOG.md"
    "docs/src/index.md"
    "docs/src/installation.md"
    "docs/src/quick-start.md"
    "docs/src/core-concepts.md"
    "docs/src/parsing-patterns.md"
    "docs/src/examples.md"
    "docs/src/api-reference.md"
    "docs/src/compatibility.md"
    "docs/src/architecture.md"
    "docs/src/development.md"
    "docs/src/roadmap.md")
  "Every Markdown document this repository publishes, in nav order. Excludes
docs/src/changelog.md, whose entire body is a pymdownx.snippets include that
only resolves when MkDocs runs.")
