{
  description = "cl-parser-kit: parser combinators and text parsing utilities for Common Lisp";

  inputs = {
    # nixos-unstable, not nixpkgs-unstable: it advances only after the NixOS
    # release tests pass, so it is less likely to land a broken build.
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

    # Sibling packages are always pinned to a release tag: a bare
    # `github:nerima-lisp/cl-weave` would follow that repo's default branch and
    # an upstream push to main would break this repo's CI without warning.
    #
    # cl-weave and cl-prolog are `flake = false` on purpose. scripts/bootstrap.lisp
    # consumes them as plain source trees -- it reads their .asd forms directly
    # rather than going through ASDF's registry -- so nothing here evaluates
    # their flake outputs. Taking them as flakes would pull their transitive
    # inputs (cl-prolog alone brings paredit-cli v0.7.0 and rust-overlay) into
    # this lock purely to be ignored, which is the opposite of what the
    # `inputs.nixpkgs.follows` rule is trying to achieve. A non-flake input has
    # no inputs of its own, so there is no nixpkgs for it to follow; declaring
    # one makes Nix warn about an override for a non-existent input.
    cl-weave = {
      url = "github:nerima-lisp/cl-weave/v1.0.0";
      flake = false;
    };
    cl-prolog = {
      url = "github:nerima-lisp/cl-prolog/v1.0.1";
      flake = false;
    };
    paredit-cli = {
      url = "github:nerima-lisp/paredit-cli/v0.8.0";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    treefmt-nix = {
      url = "github:numtide/treefmt-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    {
      self,
      nixpkgs,
      cl-weave,
      cl-prolog,
      paredit-cli,
      treefmt-nix,
    }:
    let
      # Only what is verified: x86_64-linux by CI, aarch64-darwin by the
      # maintainer's local `nix flake check`. aarch64-linux and x86_64-darwin
      # are not declared because nothing runs them, and a platform no runner
      # can build makes `nix flake check --all-systems` fail with "platform
      # mismatch" rather than skip it. See ADR-0078.
      systems = [
        "x86_64-linux"
        "aarch64-darwin"
      ];
      forAllSystems = nixpkgs.lib.genAttrs systems;

      # Single source of truth for the package version: the `:version` form in
      # cl-parser-kit.asd. A release edits that one line and every derivation
      # here follows. Nix regexes are whole-string anchored and `.` never spans
      # newlines, so the version is extracted line-by-line rather than with one
      # multi-line match.
      version =
        let
          lines = nixpkgs.lib.splitString "\n" (builtins.readFile ./cl-parser-kit.asd);
          versionLine = builtins.head (
            builtins.filter (line: builtins.match "[[:space:]]*:version \"[^\"]*\"" line != null) lines
          );
        in
        builtins.head (builtins.match "[[:space:]]*:version \"([^\"]*)\"" versionLine);

      # The test bootstrap locates cl-weave and cl-prolog through these two
      # variables rather than CL_SOURCE_REGISTRY, because scripts/bootstrap.lisp
      # reads the .asd forms directly instead of going through ASDF's registry.
      dependencyEnv = ''
        export CL_PARSER_KIT_CL_WEAVE_ROOT="${cl-weave}"
        export CL_PARSER_KIT_CL_PROLOG_ROOT="${cl-prolog}"
      '';

      # treefmt drives `nix fmt` and the `checks.<system>.formatting` gate.
      # Scope is Nix only: nixfmt (RFC-style) is a zero-footgun, low-diff
      # formatter, whereas YAML formatters mangle the GitHub Actions `on:` key
      # and Markdown reformatting would churn the whole docs tree.
      treefmtEval = forAllSystems (
        system:
        treefmt-nix.lib.evalModule nixpkgs.legacyPackages.${system} {
          projectRootFile = "flake.nix";
          programs.nixfmt.enable = true;
        }
      );
    in
    {
      devShells = forAllSystems (
        system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
        in
        {
          default = pkgs.mkShell {
            packages = [
              pkgs.perl
              pkgs.sbcl
              paredit-cli.packages.${system}.default
            ];
            CL_PARSER_KIT_CL_WEAVE_ROOT = toString cl-weave;
            CL_PARSER_KIT_CL_PROLOG_ROOT = toString cl-prolog;
          };
        }
      );

      # `nix fmt` entry point.
      formatter = forAllSystems (system: treefmtEval.${system}.config.build.wrapper);

      packages = forAllSystems (
        system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
        in
        {
          default = pkgs.stdenvNoCC.mkDerivation {
            pname = "cl-parser-kit";
            inherit version;
            src = self;
            nativeBuildInputs = [ pkgs.sbcl ];
            buildPhase = ''
              export HOME="$TMPDIR/home"
              mkdir -p "$HOME"
              ${dependencyEnv}
              sbcl --noinform --non-interactive \
                --script scripts/run-compile-check.lisp
            '';
            installPhase = ''
              mkdir -p "$out/share/common-lisp/source/cl-parser-kit"
              cp -R . "$out/share/common-lisp/source/cl-parser-kit"
            '';
            meta = {
              description = "Small parser toolkit for Common Lisp text languages";
              homepage = "https://github.com/nerima-lisp/cl-parser-kit";
              license = pkgs.lib.licenses.mit;
              platforms = systems;
            };
          };

          # Rendered documentation site (Material for MkDocs). Builds fully
          # offline: Material bundles its assets, so no network access is
          # required inside the sandbox. --strict promotes broken links and
          # unlisted pages to build failures.
          #
          # CHANGELOG.md is part of the source because docs/src/changelog.md
          # pulls it in with a pymdownx.snippets include, which is what keeps
          # the site's changelog from drifting away from the root file.
          docs = pkgs.stdenvNoCC.mkDerivation {
            pname = "cl-parser-kit-docs";
            inherit version;
            src = pkgs.lib.fileset.toSource {
              root = ./.;
              fileset = pkgs.lib.fileset.unions [
                ./docs/mkdocs.yml
                ./docs/src
                ./CHANGELOG.md
              ];
            };
            nativeBuildInputs = [ pkgs.python3Packages.mkdocs-material ];
            buildPhase = ''
              runHook preBuild
              mkdocs build --strict --config-file docs/mkdocs.yml --site-dir "$out"
              runHook postBuild
            '';
            dontInstall = true;
            meta = {
              description = "Rendered MkDocs (Material) documentation for cl-parser-kit";
              homepage = "https://github.com/nerima-lisp/cl-parser-kit";
              license = pkgs.lib.licenses.mit;
            };
          };
        }
      );

      # Granularity lives here, NOT in extra GitHub Actions jobs: `nix flake
      # check` evaluates each attribute as its own derivation, in parallel, with
      # build caching. Add a check here rather than a job in ci.yml.
      checks = forAllSystems (
        system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
          lib = pkgs.lib;
          mkCheck =
            {
              name,
              command,
              postCommand ? [ ],
              timeoutSeconds ? 360,
              artifacts ? [ ],
            }:
            pkgs.stdenvNoCC.mkDerivation {
              inherit name;
              src = self;
              nativeBuildInputs = [
                pkgs.perl
                pkgs.sbcl
              ];
              buildPhase = ''
                export HOME="$TMPDIR/home"
                mkdir -p "$HOME"
                ${dependencyEnv}
                perl scripts/with-timeout.pl \
                  ${toString timeoutSeconds} \
                  ${lib.escapeShellArgs command}
                ${lib.optionalString (postCommand != [ ]) (lib.escapeShellArgs postCommand)}
                ${lib.concatMapStringsSep "\n" (artifact: "test -e ${lib.escapeShellArg artifact}") artifacts}
              '';
              installPhase = ''
                mkdir -p "$out"
                ${lib.concatMapStringsSep "\n" (
                  artifact: "cp -R ${lib.escapeShellArg artifact} \"$out/\""
                ) artifacts}
              '';
            };
        in
        {
          # The SBCL suite. Named `default` because PACKAGE_STANDARD.md makes
          # `checks.default` the test gate every repository is expected to have.
          default = mkCheck {
            name = "cl-parser-kit-test";
            command = [
              "sbcl"
              "--script"
              "run-tests.lisp"
            ];
          };

          # Proves the system still compiles from a raw checkout, which the
          # test run alone does not: run-tests.lisp loads sources interpreted.
          package = self.packages.${system}.default;

          coverage = mkCheck {
            name = "cl-parser-kit-coverage";
            command = [
              "sbcl"
              "--script"
              "scripts/run-coverage.lisp"
            ];
            postCommand = [
              "perl"
              "scripts/check-coverage.pl"
              "cl-parser-kit-coverage-report/cover-index.html"
              "src"
              "90"
              "80"
            ];
            artifacts = [
              "cl-parser-kit.coverage"
              "cl-parser-kit-coverage-report/"
            ];
          };

          paredit-lint = paredit-cli.lib.${system}.mkLintCheck {
            src = self;
            name = "cl-parser-kit-paredit-lint";
          };

          # Fails `nix flake check` when any tracked Nix file is unformatted,
          # turning the formatter into an enforced CI gate.
          formatting = treefmtEval.${system}.config.build.check self;

          # The docs package runs `mkdocs build --strict`, so a broken link or a
          # page missing from the nav fails here. Without this the docs are only
          # built by the publish workflow, which runs after a merge to main --
          # meaning such a break would surface as a failed deploy rather than as
          # a failed pull request.
          docs = self.packages.${system}.docs;
        }
      );

      apps = forAllSystems (
        system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
          test' = pkgs.writeShellApplication {
            name = "cl-parser-kit-test";
            runtimeInputs = [
              pkgs.perl
              pkgs.sbcl
            ];
            # Run against the working tree rather than ${self}: the suite
            # writes scratch files under t/, which would fail against a
            # read-only store path. `nix run .#test` is a dev-loop command and
            # is expected to be invoked from the checkout root; `nix flake
            # check` is what exercises the immutable copy.
            text = ''
              ${dependencyEnv}
              exec sbcl --script run-tests.lisp
            '';
          };
        in
        rec {
          test = {
            type = "app";
            program = "${test'}/bin/cl-parser-kit-test";
            meta.description = "Run the cl-parser-kit test suite against the working tree";
          };
          default = test;
        }
      );
    };
}
