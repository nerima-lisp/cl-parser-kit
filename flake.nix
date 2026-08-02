{
  description = "cl-parser-kit: parser combinators and text parsing utilities for Common Lisp";

  inputs = {
    # nixos-unstable, not nixpkgs-unstable: it advances only after the NixOS
    # release tests pass, so it is less likely to land a broken build.
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

    # The org flake preset. Everything this file used to spell out by hand --
    # the `:version` extraction out of the .asd, `forAllSystems`, the treefmt
    # eval wired to both `formatter` and `checks.formatting`, the mkdocs
    # package plus its check, the run-tests.lisp gate, the source filter, the
    # `apps.test`/`apps.default` pair, the devShell and the overlay -- is the
    # single `mkPackageFlake` call below, so none of it can drift from the
    # other 20 repositories. PACKAGE_STANDARD.md's "flake.nix の書き方"
    # mandates exactly this shape.
    #
    # Sibling packages are ALWAYS pinned to a release tag: a bare
    # `github:nerima-lisp/cl-nix-forge` follows that repo's default branch, so
    # an upstream push to main would change this build without warning.
    #
    # `inputs.nixpkgs.follows` is mandatory on every input: without it each
    # one drags in its own nixpkgs, inflating flake.lock and rebuilding the
    # same derivations.
    cl-nix-forge = {
      url = "github:nerima-lisp/cl-nix-forge/v0.4.0";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # cl-weave and cl-prolog are the test-only dependencies of the
    # `cl-parser-kit/test` system (see cl-parser-kit.asd `:depends-on`).
    #
    # Both are full flakes now, where they used to be `flake = false` source
    # trees. The old comment argued that nothing here evaluated their flake
    # outputs because scripts/bootstrap.lisp reads their `.asd` forms
    # directly; that is still true of bootstrap, but no longer true of the
    # flake: `lispCheckDependencies` below needs cl-weave as a BUILT ASDF
    # system, which v1.1.0 publishes as `packages.<system>.cl-weave`, and
    # that attribute only exists on a real flake.
    #
    # Their own inputs are collapsed onto this flake's wherever the name
    # exists upstream, which is what keeps taking them as flakes from
    # inflating this lock. cl-weave's `cl-nix-forge` is deliberately NOT
    # followed: it pins v0.3.0, and forcing v0.4.0 on it would build the
    # released cl-weave with a preset it was never released against.
    cl-weave = {
      url = "github:nerima-lisp/cl-weave/v1.1.4";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.paredit-cli.follows = "paredit-cli";
      inputs.treefmt-nix.follows = "treefmt-nix";
    };
    cl-prolog = {
      url = "github:nerima-lisp/cl-prolog/v1.3.0";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.cl-weave.follows = "cl-weave";
      inputs.paredit-cli.follows = "paredit-cli";
      inputs.treefmt-nix.follows = "treefmt-nix";
    };

    # paredit-cli provides structural S-expression tooling for this repo's
    # Lisp sources: a dev-shell binary for agent-driven refactors, and the
    # `checks.paredit-lint` gate below built from the same library.
    paredit-cli = {
      url = "github:nerima-lisp/paredit-cli/v1.4.0";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # treefmt drives `nix fmt` and the `checks.formatting` gate. Scope is Nix
    # only: nixfmt (RFC-style) is a zero-footgun, low-diff formatter, whereas
    # YAML formatters mangle the GitHub Actions `on:` key and Markdown
    # reformatting would churn the whole docs tree. That is also
    # `mkPackageFlake`'s default, so nothing configures it below.
    treefmt-nix = {
      url = "github:numtide/treefmt-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    {
      self,
      nixpkgs,
      cl-nix-forge,
      cl-weave,
      cl-prolog,
      paredit-cli,
      treefmt-nix,
    }:
    let
      lib = nixpkgs.lib;

      # Only what is verified, and CI verifies exactly one platform:
      # x86_64-linux. aarch64-darwin was dropped in the 2026-08-01 revision of
      # PACKAGE_STANDARD.md -- it rested on the maintainer running `nix flake
      # check` locally, which nothing enforces, so it was a promise without a
      # gate. aarch64-linux and x86_64-darwin were never declared.
      #
      # Consequence: `nix develop` and `nix build` no longer resolve on macOS,
      # because mkPackageFlake generates packages/checks/apps/devShells from
      # this one list. Development happens on Linux.
      systems = [ "x86_64-linux" ];

      # cl-weave as an ASDF SYSTEM, for `lispCheckDependencies`.
      #
      # Taken straight off the flake rather than rebuilt from its source with
      # `lispDerivation`, which is what cl-json-kit and cl-prolog still do:
      # v1.1.0 is migrated, so `packages.<system>.cl-weave` IS the
      # registry-composable ASDF system. (`packages.default` is a different
      # thing -- the delivered CLI binary -- and is not what belongs here.)
      clWeaveSystem = ctx: cl-weave.packages.${ctx.system}.cl-weave;

      # cl-prolog as an ASDF SYSTEM. Built from the input's source because
      # v1.1.0 predates its own migration: it has no `cl-nix-forge` input at
      # all, so there is no `packages.cl-prolog` attribute to consume.
      #
      # `cl-prolog/weave` and not `cl-prolog`: that is the system
      # cl-parser-kit.asd names, so building it is what validates the thing
      # actually needed. The derivation still carries the whole source tree,
      # so the other systems in the same .asd stay resolvable.
      clPrologSystem =
        ctx:
        ctx.cl.lispDerivation {
          pname = "cl-prolog";
          version = ctx.cl.fromAsdSystem "${cl-prolog}/cl-prolog.asd";
          src = cl-prolog;
          lispSystem = "cl-prolog/weave";
          lispDependencies = [ (clWeaveSystem ctx) ];
        };

      # scripts/bootstrap.lisp does NOT use `asdf:load-system` for cl-weave
      # and cl-prolog: it reads their `.asd` `defsystem` forms and `load`s the
      # listed source files itself. So it never consults CL_SOURCE_REGISTRY,
      # and cl-nix-forge composing that registry transitively -- correct as it
      # is, and what makes `lispCheckDependencies` above worth declaring --
      # cannot be what lets the suite find them. These two variables are, and
      # they are what bootstrap's own fallback ("place cl-weave next to the
      # project checkout") degenerates to inside a sandbox that has no
      # sibling checkouts.
      #
      # They point at the raw INPUT trees, not at the built derivations above,
      # for the same reason bootstrap exists: it wants a directory with an
      # `.asd` at its root and the components that `.asd` names, which is
      # exactly what a source tree is. Pointing them at a `lispDerivation`
      # output would additionally couple this to that output's layout for no
      # gain -- bootstrap loads `.lisp` files, never fasls.
      dependencyRoots = {
        CL_PARSER_KIT_CL_WEAVE_ROOT = "${cl-weave}";
        CL_PARSER_KIT_CL_PROLOG_ROOT = "${cl-prolog}";
      };

      # `nix run .#test`, and through `apps.default` the README's headline
      # `nix run github:nerima-lisp/cl-parser-kit`.
      #
      # This does not REPLACE the preset's generated runner, it wraps it: the
      # registry it composes, its time limit and its throwaway HOME are all
      # wanted. The only thing it cannot know is `dependencyRoots`, because
      # `mkTestApp` builds a shell wrapper from scratch instead of inheriting
      # the package derivation's environment the way the generated checks do.
      # perl joins it for the same reason it is in `nativeCheckInputs` below:
      # t/examples-ops-test.lisp actually EXECUTES scripts/with-timeout.pl.
      testApp =
        ctx:
        let
          generated = ctx.generated.apps.test;
          wrapper = ctx.pkgs.writeShellApplication {
            name = "cl-parser-kit-test";
            runtimeInputs = [ ctx.pkgs.perl ];
            text = ''
              ${lib.concatStringsSep "\n" (
                lib.mapAttrsToList (name: value: "export ${name}=${lib.escapeShellArg value}") dependencyRoots
              )}
              exec ${generated.program} "$@"
            '';
          };
        in
        generated // { program = lib.getExe wrapper; };
    in
    # `mkPackageFlake` spans systems -- it obtains a `pkgs` and its own
    # cl-nix-forge instance per entry in `systems` -- so the per-system `lib`
    # this function is taken from contributes nothing but the function itself.
    cl-nix-forge.lib.${builtins.head systems}.mkPackageFlake {
      inherit self systems nixpkgs;

      pname = "cl-parser-kit";

      # Single source of truth for the version: the `:version` form in
      # cl-parser-kit.asd. A release edits that one line and every derivation
      # carrying a version -- the package, the docs site, and both store paths
      # -- follows. There is deliberately no `version` argument to pass.
      asd = ./cl-parser-kit.asd;

      # Spelled out rather than left to `mkPackageFlake`'s `self` default,
      # which does not evaluate: a flake's `self` is an attrset carrying an
      # `outPath`, and `lib.fileset` refuses string-like values. `./.` is the
      # same directory as a path literal. `self` is still what the preset
      # hands the treefmt gate, which wants the UNFILTERED tree.
      root = ./.;

      # `mkLispSource` is an allowlist -- `*.asd` and `*.lisp` under the root,
      # nothing else unless named here -- so every non-Lisp file the SUITE
      # reads at run time has to be named. Each of these is read by a test,
      # and dropping one does not fail to build, it fails an assertion about a
      # file that is simply absent:
      #
      #   README.md, docs/src/*.md                t/examples-docs-test.lisp and
      #     t/helpers-examples-doc-data.lisp assert that every documented
      #     snippet still appears in the document that documents it, over 12
      #     named pages under docs/src plus README.md.
      #   scripts/run-implementation-smoke.sh     t/examples-ops-test.lisp reads
      #     it to assert the smoke script still drives the checked-in entry
      #     points for all five implementations.
      #   scripts/with-timeout.pl                 the same file reads it AND
      #     runs it under perl, asserting it exits 124 and kills the whole
      #     process group.
      #   LICENSE                                 `public-doc-links-resolve-test`
      #     walks every relative Markdown link in README.md and resolves it on
      #     disk; README links to LICENSE twice. Omitting it does not merely
      #     lose a file, it turns a green suite red -- which is how this entry
      #     was found rather than guessed.
      #
      # One more, read by a CHECK rather than by the suite:
      #
      #   scripts/check-coverage.pl               `checks.coverage`'s validation
      #     command runs it out of the build tree, so it has to be IN that tree.
      #
      # docs/src is named as a directory rather than as 12 paths: the set of
      # pages is fixed by docs/mkdocs.yml's nav, and a page added there and
      # not here would fail in the suite rather than in the docs build.
      sourceInclude = [
        ./README.md
        ./LICENSE
        ./docs/src
        ./scripts/check-coverage.pl
        ./scripts/run-implementation-smoke.sh
        ./scripts/with-timeout.pl
      ];

      # `platforms = systems`, NOT `lib.platforms.unix` like the two reference
      # migrations use. nixpkgs' check-meta.nix actually ENFORCES
      # `meta.platforms`, so letting it drift wider than the `systems` list
      # this flake verifies means advertising a build nothing has ever run --
      # a real bug this repository has already fixed once.
      meta = {
        description = "Small parser toolkit for Common Lisp text languages";
        homepage = "https://github.com/nerima-lisp/cl-parser-kit";
        license = lib.licenses.mit;
        platforms = systems;
      };

      # Both are needed to COMPILE AND RUN the suite and nothing else -- the
      # library itself is dependency-free (DEPENDENCY_POLICY.md L1) -- so they
      # are `lispCheckDependencies` and must not enter `packages.cl-parser-kit`'s
      # closure or the overlay's `pkgs.cl-parser-kit`. They are BUILT
      # DERIVATIONS, never CL_SOURCE_REGISTRY strings: assembling that registry
      # is cl-nix-forge's job and it does it transitively.
      lispCheckDependencies = ctx: [
        (clWeaveSystem ctx)
        (clPrologSystem ctx)
      ];

      # Everything outside `lispDerivation`'s own argument list reaches
      # `mkDerivation`, so this is how the two bootstrap variables become
      # environment variables on the package derivation -- and therefore on
      # `package.enableCheck`, which is what `mkScriptCheck` (`checks.default`)
      # and `mkCommandCheck` (`checks.coverage`) each `overrideAttrs` rather
      # than build fresh. Confirmed by running both, not by reading:
      # bootstrap's "Missing dependency ASD ~A. Set ~A ..." error is what a
      # broken hand-off looks like, and neither check raises it.
      #
      # `nativeCheckInputs` and not `nativeBuildInputs`: stdenv only adds it
      # when `doCheck` is true, so perl lands on the two checks that run
      # scripts/with-timeout.pl and scripts/check-coverage.pl without becoming
      # a build input of the library itself, whose compile has no use for it.
      packageArgs = ctx: dependencyRoots // { nativeCheckInputs = [ ctx.pkgs.perl ]; };

      # Drives BOTH `checks.default` and the runner `apps.test` wraps, from
      # this one number, so the gate CI runs and the command a contributor
      # runs by hand cannot drift apart. 360s is the budget the hand-written
      # `mkCheck` this replaces used.
      #
      # `killAfterSeconds` sends SIGKILL 30s after the SIGTERM deadline: SBCL
      # defers signals to safepoints, so a tight compiled loop (a runaway
      # combinator repeat is exactly this) can outlive a bare SIGTERM and fall
      # through to the enclosing CI job timeout instead of failing here with
      # an attributable error. Both are set explicitly rather than left to the
      # preset's defaults because every command timeout in this repository is
      # a deliberate number.
      timeoutSeconds = 360;
      killAfterSeconds = 30;

      # docs/mkdocs.yml + docs/src/, built with `--strict` so a broken link or
      # a page missing from the nav is a build failure. `checks.docs` comes
      # with it and is the point: without that gate the docs are only built by
      # the publish workflow, which runs after a merge to main, so such a
      # break surfaces as a failed deploy rather than as a failed pull
      # request. Material for MkDocs bundles its assets, so this builds
      # offline inside the sandbox.
      #
      # `root` is the REPOSITORY root and not `./docs`, with an explicit
      # fileset, because `mkdocsYmlName` is a repo-root-relative path. It used
      # to be root-rooted for a second reason as well -- docs/src/changelog.md
      # was a one-line `--8<-- "CHANGELOG.md"` snippet include needing the
      # top-level file in the tree -- but both files were abolished in the
      # 2026-08-01 revision and pymdownx.snippets is no longer configured.
      docs = {
        root = ./.;
        fileset = lib.fileset.unions [
          ./docs/mkdocs.yml
          ./docs/src
        ];
        mkdocsYmlName = "docs/mkdocs.yml";
      };

      # ONE treefmt evaluation drives `nix fmt` and `checks.formatting`, so
      # formatting inside the dev shell cannot disagree with the gate.
      # `evalModule` is passed in rather than closed over so this repo picks
      # its own treefmt-nix version.
      treefmt.evalModule = treefmt-nix.lib.evalModule;

      # The interactive-only extras, and only those. sbcl, cl-weave and
      # cl-prolog all arrive through `inputsFrom` on the derivation the preset
      # builds this shell from -- the CHECK-ENABLED one, whose `registryPath`
      # carries `lispCheckDependencies` -- so naming any of them again here
      # would be a second source of truth. Verified with
      # `nix develop -c which sbcl`.
      #
      # perl does NOT arrive that way: it is a `nativeCheckInputs` entry, and
      # `mkShell`'s `inputsFrom` takes a derivation's inputs but not its
      # check-only ones. The suite runs scripts/with-timeout.pl, so a dev
      # shell without perl fails a test that CI passes.
      devShellPackages = ctx: [
        ctx.pkgs.perl
        paredit-cli.packages.${ctx.system}.default
      ];

      # The two generated outputs that do NOT inherit the package
      # derivation's environment, and so do not get `dependencyRoots` from
      # `packageArgs` above. Both are wrapped rather than replaced.
      overrideOutputs = ctx: {
        # `mkTestApp` builds a `writeShellApplication` from scratch; see
        # `testApp`.
        apps.test = testApp ctx;
        apps.default = testApp ctx;

        # `mkDevShell` is `pkgs.mkShell { inputsFrom = [ drv ]; ... }`, and
        # `inputsFrom` merges a derivation's dependency lists, not its
        # arbitrary environment -- so `nix develop` would otherwise be the one
        # place `sbcl --script run-tests.lisp` still failed in bootstrap.
        # `overrideAttrs` on the generated shell keeps its registry export and
        # its banner.
        devShells.default = ctx.generated.devShells.default.overrideAttrs (_: dependencyRoots);
      };

      # Granularity lives here, NOT in extra GitHub Actions jobs: `nix flake
      # check` evaluates each attribute as its own derivation, in parallel,
      # with build caching. Add a check here rather than a job in ci.yml.
      extraOutputs = ctx: {
        checks = {
          # `nix flake check` only EVALUATES `packages` and `apps`, it does not
          # realise their derivations, and the preset's generated checks are
          # all `enableCheck.overrideAttrs` variants -- distinct derivations
          # from `packages.cl-parser-kit`. Without this, the package a
          # downstream flake actually consumes is never built in CI. It also
          # proves the system still compiles through ASDF from a clean source,
          # which the test run alone does not: run-tests.lisp loads the
          # sources interpreted.
          package = ctx.package;

          # ADR-0063 in CODING_STANDARD.md sets a coverage FLOOR -- 90%
          # expression, 80% branch, must not decrease -- so this is
          # deliberately NOT `cl.mkCoverageReport`, which builds the same
          # sb-cover report but gates on nothing except its own non-emptiness.
          # `mkCommandCheck` keeps the threshold: scripts/check-coverage.pl
          # runs as a validation command, after the artifacts are asserted
          # present and non-empty and outside the Lisp time limit, and a
          # number below the floor fails the check.
          #
          # Both artifacts are published into `$out` so CI can retrieve the
          # HTML report rather than only a pass/fail bit.
          coverage = ctx.cl.mkCommandCheck {
            drv = ctx.package;
            name = "cl-parser-kit-coverage";
            command = [
              "sbcl"
              "--script"
              "scripts/run-coverage.lisp"
            ];
            validationCommands = [
              "perl scripts/check-coverage.pl cl-parser-kit-coverage-report/cover-index.html src 90 80"
            ];
            artifacts = [
              "cl-parser-kit.coverage"
              "cl-parser-kit-coverage-report"
            ];
            timeoutSeconds = 360;
            killAfterSeconds = 30;
          };

          # Structural parse gate over every Lisp source in the filtered tree:
          # fails if any .lisp/.asd file is not a balanced S-expression
          # document.
          paredit-lint = paredit-cli.lib.${ctx.system}.mkLintCheck {
            inherit (ctx) src;
            name = "cl-parser-kit-paredit-lint";
          };
        };
      };
    };
}
