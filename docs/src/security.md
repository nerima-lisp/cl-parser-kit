# Security Policy

`cl-parser-kit` is a small library, not a hosted service. Security reports
should therefore focus on repository content and verified library
behavior from this checkout.

## Reporting

If you discover a security issue in `cl-parser-kit`, report it privately
instead of opening a public issue. Use
[GitHub's private vulnerability reporting](https://github.com/nerima-lisp/cl-parser-kit/security/advisories/new)
for this repository (the **Security** tab → **Report a vulnerability**),
which opens a private advisory visible only to the maintainers.

Include:

- the affected commit or local checkout state
- the Common Lisp implementation and version you tested
- a minimal reproduction
- the impact you observed
- any suggested fix, if available

Do not publish exploit details until the issue has been acknowledged and
a fix has been coordinated.

## Scope

Reports are most actionable when they involve one of these areas:

- parser or tokenizer behavior that can be driven into unsafe or
  misleading states by untrusted input
- diagnostics that expose source text unexpectedly
- release or packaging metadata that points users at the wrong code or
  support channel
- example or documentation workflows that claim a security property the
  tests do not verify

## Support Boundary

The current verified baseline is the repository-local verification set
documented in [Support Policy](support.md). On a machine with Nix, the
whole gate runs as a single reproducible command:

```sh
nix flake check
```

Without Nix, run the equivalent raw-checkout scripts directly:

```sh
sbcl --script scripts/run-compile-check.lisp
sbcl --script scripts/run-tests.lisp
sbcl --script scripts/run-examples.lisp
./scripts/run-implementation-smoke.sh
```

If a report depends on a different Lisp implementation, custom ASDF
setup, or downstream application embedding, include those details
explicitly. Portability issues may still matter, but they are easier to
triage when separated from the repository's current verified
implementation set.

## Disclosure Expectations

- prefer private reporting first
- allow time to reproduce and narrow the root cause before public
  discussion
- once fixed, update the relevant tests or docs so the security contract
  is auditable from the repository
