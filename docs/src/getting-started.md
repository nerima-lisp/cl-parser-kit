# Getting Started

The library system (`cl-parser-kit`) has **no runtime dependencies** — only
the test system (`cl-parser-kit-test`) pulls in `cl-weave` and `cl-prolog`.
Loading it into an application never drags in the test tooling.

## ASDF

Place the repository in your `local-projects` directory or add the checkout
to your ASDF source registry:

```lisp
(asdf:load-system :cl-parser-kit)
```

## Quicklisp

A checkout under `~/quicklisp/local-projects/` (or `~/common-lisp/`) is
discovered automatically:

```lisp
(ql:quickload "cl-parser-kit")
```

## Ultralisp

If you use [Ultralisp](https://ultralisp.org/), you can add this repository
as a source and pull the library the same way once it is indexed.

## Manual registry entry

If you keep personal projects in `~/common-lisp/`, one typical setup is:

```lisp
(push #p"/path/to/cl-parser-kit/" asdf:*central-registry*)
(asdf:load-system :cl-parser-kit)
```

## Pinning a release

The repository ships tagged releases starting with `v0.1.0`. For production
or team use, pin a tagged release (or a reviewed commit) and rerun the
verification entry point from that checkout. See
[Versioning Policy](reference/compatibility.md) for the release model.

From `v1.0.0` on, the exported surface is frozen under semantic versioning: a
breaking change to any exported symbol requires a major release. The
[Versioning Policy](reference/compatibility.md) covers exactly what that
includes and what it deliberately does not.

## Test system

To load the repository test system explicitly:

```lisp
(asdf:load-system :cl-parser-kit-test)
```

The test system depends on `cl-weave` and `cl-prolog`, which are not
distributed through Quicklisp/Ultralisp; the Nix dev shell (`nix develop`)
and `nix flake check` resolve the pinned versions automatically. Outside
Nix, make matching checkouts of [`cl-weave`](https://github.com/nerima-lisp/cl-weave)
and [`cl-prolog`](https://github.com/nerima-lisp/cl-prolog) discoverable by
ASDF (see [`scripts/bootstrap.lisp`](https://github.com/nerima-lisp/cl-parser-kit/blob/main/scripts/bootstrap.lisp)
for the exact roots it expects). Running the library itself never requires
these.

## Confirming the install

From a repository checkout on a supported system, run the full suite with:

```sh
nix flake check
```

This resolves the pinned `cl-weave` and `cl-prolog` test dependencies, runs
the full suite, generates the coverage report, and checks Lisp structure
with `paredit-cli`.

If the checkout is already on your ASDF source registry, the equivalent
REPL entry point is:

```lisp
(asdf:test-system :cl-parser-kit)
```

[Development](project/development.md) covers the raw-checkout verification
scripts, the coverage report, and the implementation smoke path.

## Tokenize a string

```lisp
(asdf:load-system :cl-parser-kit)

(let* ((tokenizer (cl-parser-kit:make-tokenizer
                   :rules (list (cl-parser-kit:make-whitespace-rule :skip-p t)
                                (cl-parser-kit:make-literal-rule :plus "+")
                                (cl-parser-kit:make-number-rule)
                                (cl-parser-kit:make-identifier-rule))))
       (tokens (cl-parser-kit:tokenize-string "sum + 42" tokenizer)))
  tokens)
```

## Parse a token vector

If your pipeline already has tokens, `parse-tokens` runs a parser over them
directly. This is the smallest complete parse the library offers:

```lisp
(let* ((tokens (vector (cl-parser-kit:make-token :type :identifier :text "answer")
                       (cl-parser-kit:make-token :type :equals :text "=")
                       (cl-parser-kit:make-token :type :number :text "42" :value 42)))
       (parser (cl-parser-kit:seq
                (cl-parser-kit:type-token :identifier)
                (cl-parser-kit:type-token :equals)
                (cl-parser-kit:type-token :number))))
  (cl-parser-kit:parse-tokens parser tokens))
```

A parser returns four values: a success flag, the value, the next position,
and — on failure — a `parse-failure` you can render with
`parse-failure->string`.

## What's next

- [Core Concepts](guide/core-concepts.md) for the vocabulary behind these
  snippets — tokens, spans, tokenizers, parsers, Pratt parsing, and
  diagnostics.
- [Recipes](guide/recipes.md) for a worked tour of every parser construction
  style: custom lexical rules, Pratt tables, the seq helpers, lookahead,
  `chainl1` / `chainr1`, and diagnostics.
- [Parsing Patterns](guide/parsing-patterns.md) for how to choose the smallest
  stable layer for your grammar and shape committed failures deliberately.
- [Examples](guide/examples.md) for a guided tour through every sample file
  under `examples/`, in recommended reading order.
- [API Reference](reference/api.md) for the exported surface grouped by concern.
