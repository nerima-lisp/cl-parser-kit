{
  description = "cl-parser-kit: parser combinators and text parsing utilities for Common Lisp";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    cl-weave = {
      url = "github:nerima-lisp/cl-weave/v0.11.0";
      flake = false;
    };
    cl-prolog = {
      url = "github:nerima-lisp/cl-prolog/v0.8.0";
      flake = false;
    };
    paredit-cli = {
      url = "github:nerima-lisp/paredit-cli";
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
    }:
    let
      systems = [
        "x86_64-linux"
        "aarch64-linux"
      ];
      forAllSystems =
        function: nixpkgs.lib.genAttrs systems (system: function (import nixpkgs { inherit system; }));

      mkDocs =
        pkgs:
        pkgs.stdenvNoCC.mkDerivation {
          pname = "cl-parser-kit-docs";
          version = "0.3.0";
          src = pkgs.lib.fileset.toSource {
            root = ./docs;
            fileset = pkgs.lib.fileset.unions [
              ./docs/mkdocs.yml
              ./docs/src
            ];
          };
          nativeBuildInputs = [ pkgs.python3Packages.mkdocs-material ];
          # Build fully offline: Material for MkDocs bundles all of its assets,
          # so no network access is required inside the Nix sandbox. --strict
          # promotes broken links and unlisted pages to build failures.
          buildPhase = ''
            runHook preBuild
            mkdocs build --strict --config-file mkdocs.yml --site-dir "$out"
            runHook postBuild
          '';
          dontInstall = true;
          meta = {
            description = "Rendered MkDocs (Material) documentation for cl-parser-kit";
            homepage = "https://github.com/nerima-lisp/cl-parser-kit";
            license = pkgs.lib.licenses.mit;
          };
        };
    in
    {
      devShells = forAllSystems (pkgs: {
        default = pkgs.mkShell {
          packages = [
            pkgs.perl
            pkgs.sbcl
            paredit-cli.packages.${pkgs.stdenv.hostPlatform.system}.default
          ];
          CL_PARSER_KIT_CL_WEAVE_ROOT = toString cl-weave;
          CL_PARSER_KIT_CL_PROLOG_ROOT = toString cl-prolog;
        };
      });

      formatter = forAllSystems (pkgs: pkgs.nixfmt);

      packages = forAllSystems (pkgs: {
        docs = mkDocs pkgs;

        default = pkgs.stdenvNoCC.mkDerivation {
          pname = "cl-parser-kit";
          version = "0.3.0";
          src = self;
          nativeBuildInputs = [ pkgs.sbcl ];
          buildPhase = ''
            export HOME="$TMPDIR/home"
            mkdir -p "$HOME"
            export CL_PARSER_KIT_CL_WEAVE_ROOT="${toString cl-weave}"
            export CL_PARSER_KIT_CL_PROLOG_ROOT="${toString cl-prolog}"
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
            platforms = pkgs.lib.platforms.linux;
          };
        };
      });

      checks = forAllSystems (
        pkgs:
        let
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
                export CL_PARSER_KIT_CL_WEAVE_ROOT="${toString cl-weave}"
                export CL_PARSER_KIT_CL_PROLOG_ROOT="${toString cl-prolog}"
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
          package = self.packages.${pkgs.stdenv.hostPlatform.system}.default;

          test = mkCheck {
            name = "cl-parser-kit-test";
            command = [
              "sbcl"
              "--script"
              "scripts/run-tests.lisp"
            ];
          };

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

          paredit-lint = paredit-cli.lib.${pkgs.stdenv.hostPlatform.system}.mkLintCheck {
            src = self;
            name = "cl-parser-kit-paredit-lint";
          };
        }
      );
    };
}
