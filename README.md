# cl-parser-kit

[![CI](https://github.com/nerima-lisp/cl-parser-kit/actions/workflows/ci.yml/badge.svg?branch=main)](https://github.com/nerima-lisp/cl-parser-kit/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![Documentation](https://img.shields.io/badge/docs-MkDocs%20Material-283593)](https://nerima-lisp.github.io/cl-parser-kit/)

`cl-parser-kit` is a small, dependency-free parser toolkit for Common Lisp,
targeting SBCL. It covers the pieces that recur in real text-language parsers —
tokenization, source spans, parser combinators, Pratt expression parsing,
structured diagnostics with fix-its, and AST/CST helpers — and deliberately
stops there. It is not a compiler framework, an editor integration layer, or a
language workbench. Since `v1.0.0` the 290 exported symbols are a frozen
contract, enforced by a test rather than by convention.

Full documentation is published at <https://nerima-lisp.github.io/cl-parser-kit/>.
The source for that site lives in [docs/src/](docs/src/index.md).

## Quick Start

```lisp
(asdf:load-system :cl-parser-kit)

(let ((tokenizer (cl-parser-kit:make-tokenizer
                  :rules (list (cl-parser-kit:make-whitespace-rule :skip-p t)
                               (cl-parser-kit:make-literal-rule :plus "+")
                               (cl-parser-kit:make-number-rule)
                               (cl-parser-kit:make-identifier-rule)))))
  (cl-parser-kit:tokenize-string "sum + 42" tokenizer))
;; => a vector of three tokens -- :IDENTIFIER "sum", :PLUS "+", :NUMBER 42 --
;;    each carrying the source span it came from.
```

Combinators, Pratt parsing, diagnostics and CST output are covered step by step
in [Recipes](https://nerima-lisp.github.io/cl-parser-kit/guide/recipes/).

## Install

```nix
# flake.nix
inputs.cl-parser-kit = {
  url = "github:nerima-lisp/cl-parser-kit/v1.0.0";
  inputs.nixpkgs.follows = "nixpkgs";
};
```

Note the pinned tag. Consumers inside this org pin a release tag rather than
following the default branch.

ASDF, Quicklisp, Ultralisp and manual-registry paths are described in
[Getting Started](https://nerima-lisp.github.io/cl-parser-kit/getting-started/).

## Documentation

- [Getting started](https://nerima-lisp.github.io/cl-parser-kit/getting-started/)
  — every install path, and how to verify a checkout.
- [Core concepts](https://nerima-lisp.github.io/cl-parser-kit/guide/core-concepts/)
  — tokens, spans, tokenizers, the parser and Pratt layers, diagnostics.
- [API reference](https://nerima-lisp.github.io/cl-parser-kit/reference/api/)
  — the exported surface grouped by concern.
- [Compatibility](https://nerima-lisp.github.io/cl-parser-kit/reference/compatibility/)
  — what `v1.0.0` froze, and what it deliberately did not.

## Development

```sh
nix develop          # SBCL and Perl, with the test dependency roots exported
nix run .#test       # run the test suite
nix flake check      # tests, compile check, coverage, lint, formatting, docs
nix fmt              # format Nix sources (treefmt)
```

Tests live in `t/` and run under
[cl-weave](https://github.com/nerima-lisp/cl-weave), the org's test framework;
parser-table invariants are additionally checked as executable
[cl-prolog](https://github.com/nerima-lisp/cl-prolog) queries. The suite also
runs from a raw checkout without Nix:

```sh
sbcl --script run-tests.lisp
```

See [Development](https://nerima-lisp.github.io/cl-parser-kit/project/development/) for
the coverage floor, the other entry points, and the release process.

## Contributing

See the org-wide
[CONTRIBUTING](https://github.com/nerima-lisp/.github/blob/main/CONTRIBUTING.md)
guide and the
[package standard](https://github.com/nerima-lisp/.github/blob/main/PACKAGE_STANDARD.md).

## Support

See [SUPPORT](https://github.com/nerima-lisp/.github/blob/main/SUPPORT.md).
Report vulnerabilities through
[private GitHub security advisories](https://github.com/nerima-lisp/cl-parser-kit/security/advisories/new),
not a public issue.

## License

MIT. See [LICENSE](LICENSE).
