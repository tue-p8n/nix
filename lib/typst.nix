# Utilities for working with Typst documents.
{ pkgs, ... }:
let
  # Helper: extracts argument names directly from a function signature and strips them from args
  stripCustomArgs =
    fn: args:
    let
      customKeys = builtins.attrNames (builtins.functionArgs fn);
    in
    builtins.removeAttrs args customKeys;
in
rec {
  mkShell =
    {
      packages ? (
        with pkgs;
        [
          hayagriva
          typstyle
        ]
      ),
      extraPackages ? [ ],
      shellHook ? "",
      env ? { },
      passthru ? { },
      ...
    }@args:
    let
      # Automatically strips [ "pkgs" "packages" "extraPackages" "shellHook" "env" "passthru" ]
      passThroughAttrs = stripCustomArgs mkShell args;
    in
    pkgs.mkShell (
      passThroughAttrs
      // {
        env = env // {
          TYPST_ENV_ACTIVE = "1";
        };

        packages = [ pkgs.typst ] ++ packages ++ extraPackages;

        shellHook = ''
          echo " >>> Typst environment activated: $(${pkgs.typst}/bin/typst --version)"
          ${shellHook}
        '';

        passthru = passthru // {
          typst = pkgs.typst;
        };
      }
    );

  mkDocument =
    {
      name,
      src,
      main ? "main.typ",
      output ? "document.pdf",
      buildInputs ? [ ],
      extraBuildInputs ? [ ],
      nativeBuildInputs ? [ ],
      extraNativeBuildInputs ? [ ],
      env ? { },
      passthru ? { },
      ...
    }@args:
    let
      # Automatically inspects mkDocument's signature and strips all top-level parameters
      passThroughAttrs = stripCustomArgs mkDocument args;
    in
    pkgs.stdenv.mkDerivation (
      passThroughAttrs
      // {
        inherit name src;

        env = env;

        buildInputs = buildInputs ++ extraBuildInputs;
        nativeBuildInputs = [ pkgs.typst ] ++ nativeBuildInputs ++ extraNativeBuildInputs;

        buildPhase = ''
          runHook preBuild

          typst compile ${main} ${output}

          runHook postBuild
        '';

        installPhase = ''
          runHook preInstall

          mkdir -p $out
          cp ${output} $out/

          runHook postInstall
        '';

        passthru = passthru // {
          inherit (pkgs) typst;
        };
      }
    );
}
