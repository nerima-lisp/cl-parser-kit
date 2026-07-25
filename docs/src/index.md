# cl-parser-kit

`cl-parser-kit` is a small, practical parser toolkit for Common Lisp. It
focuses on the pieces that recur in real text-language parsers: tokenization,
source spans, parser combinators, Pratt parsing, structured diagnostics, and
AST/CST helpers — deliberately compact rather than a compiler framework.

!!! tip "New to cl-parser-kit?"

    Load it into any ASDF-visible checkout and tokenize your first source
    string in a few lines:

    ```lisp
    (asdf:load-system :cl-parser-kit)

    (cl-parser-kit:tokenize-string
     "sum + 42"
     (cl-parser-kit:make-tokenizer
      :rules (list (cl-parser-kit:make-whitespace-rule :skip-p t)
                   (cl-parser-kit:make-literal-rule :plus "+")
                   (cl-parser-kit:make-number-rule)
                   (cl-parser-kit:make-identifier-rule))))
    ```

    Continue with [Installation](installation.md) → [Quick Start](quick-start.md)
    → [Core Concepts](core-concepts.md).

## Explore the docs

<div class="grid cards" markdown>

-   :material-rocket-launch:{ .lg .middle } &nbsp; **Getting Started**

    ---

    Every install path (ASDF, Quicklisp, Ultralisp, or a Nix checkout), and
    the verification commands that prove a checkout is release-ready.

    [:octicons-arrow-right-24: Installation](installation.md) ·
    [Quick Start](quick-start.md)

-   :material-book-open-variant:{ .lg .middle } &nbsp; **Writing Parsers**

    ---

    Tokens, spans, tokenizers, combinators, and Pratt parsing — the concepts
    behind the public surface, plus the recommended composition and upgrade
    patterns for real grammars.

    [:octicons-arrow-right-24: Core Concepts](core-concepts.md) ·
    [Parsing Patterns](parsing-patterns.md) ·
    [Examples](examples.md)

-   :material-file-tree-outline:{ .lg .middle } &nbsp; **Reference**

    ---

    The full exported surface grouped by concern, the layer model and
    dependency direction, and the remaining public-facing roadmap.

    [:octicons-arrow-right-24: API Reference](api.md) ·
    [Architecture](architecture.md) ·
    [Roadmap](roadmap.md)

-   :material-shield-check-outline:{ .lg .middle } &nbsp; **Governance & Support**

    ---

    The maintainer-led decision process, the verified support boundary,
    private security reporting, and the release gate every tag must pass.

    [:octicons-arrow-right-24: Support Policy](support.md) ·
    [Security Policy](security.md) ·
    [Governance](governance.md)

</div>

## Status

This repository is in active development, but the core API is already
usable. The current codebase includes:

- a rule-based tokenizer with literal, keyword, identifier, number, string,
  predicate, char, whitespace, and line/block comment rules
- span, token, and diagnostic types with structured notes and fix-its
- parser combinators — sequencing, alternation, repetition, lookahead,
  failure propagation, and practical `sep-by` / `preceded-by` / `between`
  style helpers
- a Pratt parser for prefix, infix, and postfix expression grammars
- AST/CST constructors and inspection helpers (`walk`, `find`, `map`,
  `collect`, `count`, `depth`, stable `*-node->sexp` conversion)
- exported resource-limit specials so hostile input fails gracefully instead
  of exhausting memory or the control stack
- a test system wired into `asdf:test-system`, with parser-table invariants
  additionally checked as executable `cl-prolog/weave` queries
- runnable examples under `examples/`, regression-tested as user-facing
  workflows

The implementation is designed to stay small enough that the behavior is
easy to audit from the tests. See [Architecture](architecture.md) for the
layer model and [Roadmap](roadmap.md) for the remaining public-facing work.

## Guide Map

- [Installation](installation.md) — ASDF, Quicklisp, Ultralisp, and Nix
  install paths, plus the verification commands for a release-ready
  checkout.
- [Quick Start](quick-start.md) — tokenizing, parser combinators, Pratt
  parsing, seq helpers, diagnostics, and CST output in runnable snippets.
- [Core Concepts](core-concepts.md) — tokens, spans, tokenizers, the parser
  layer, the Pratt layer, diagnostics, and AST/CST helpers.
- [Parsing Patterns](parsing-patterns.md) — how to choose the smallest
  stable layer for a grammar, the committed-failure contract, and how to
  upgrade an existing hand-written parser.
- [Examples](examples.md) — a map of every sample file under `examples/`
  and the recommended reading order.
- [API Reference](api.md) — the exported surface grouped by concern, with
  the common entry point for each layer.
- [Architecture](architecture.md) — the layer model and dependency
  direction.
- [Roadmap](roadmap.md) — the near-term, mid-term, and explicit non-goals.

## Design Non-Goals

This project is deliberately not trying to be a CLI framework, a
terminal/TTY layer, a Prolog engine, an event system, a dataflow engine, a
generic utility package, large compiler infrastructure, a full language
workbench, or an editor integration layer.

## Nix Workflow

The [flake.nix](https://github.com/nerima-lisp/cl-parser-kit/blob/main/flake.nix)
at the repository root packages `cl-parser-kit` as a Nix flake:

- `nix develop` — a devShell with SBCL and Perl, with `CL_PARSER_KIT_CL_WEAVE_ROOT`
  and `CL_PARSER_KIT_CL_PROLOG_ROOT` pre-wired to the pinned test dependencies,
  and [`paredit-cli`](https://github.com/nerima-lisp/paredit-cli) for structural
  S-expression lint checks.
- `nix flake check` — the full reproducible CI gate: the library package
  build, the `cl-weave`/`cl-prolog` test suite, the 90%/80% coverage gate,
  and `paredit-lint`, for `x86_64-linux`, `aarch64-linux`, and
  `aarch64-darwin`.
- `nix build .#docs` — builds this documentation site with MkDocs (Material)
  in `--strict` mode, so broken links fail the build.
- `nix fmt` — formats `flake.nix` with `nixfmt`.

Running `direnv allow` loads the devShell automatically.

## Support

Use [Support Policy](support.md) for the canonical support boundary and
release-readiness expectations.

Use [private GitHub security advisories](https://github.com/nerima-lisp/cl-parser-kit/security/advisories/new)
for vulnerability reporting — see [Security Policy](security.md). Do not put
exploit details in a public issue.

## Project Operations

- Contributing guide: [contributing.md](contributing.md)
- Code of Conduct: [code-of-conduct.md](code-of-conduct.md)
- Governance: [governance.md](governance.md)
- Maintainers: [maintainers.md](maintainers.md)
- Support policy: [support.md](support.md)
- Security policy: [security.md](security.md)
- Versioning policy: [versioning.md](versioning.md)
- Release process: [releasing.md](releasing.md)
- Pull request queue: <https://github.com/nerima-lisp/cl-parser-kit/pulls>
- Issue tracker: <https://github.com/nerima-lisp/cl-parser-kit/issues>
- Release notes: <https://github.com/nerima-lisp/cl-parser-kit/releases>
- Security advisories: <https://github.com/nerima-lisp/cl-parser-kit/security/advisories/new>

## License

MIT. See [LICENSE](https://github.com/nerima-lisp/cl-parser-kit/blob/main/LICENSE).
