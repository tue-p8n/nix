# Utilities for writing documents with LaTeX.
{ ... }:
{ pkgs, ... }:
let
  defaultTexpkgs = ps: { inherit (ps) scheme-full; };

  # Helper: extracts argument names from a function and strips them from args
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
      texpkgs ? defaultTexpkgs,
      packages ? (with pkgs; [ cacert ]),
      extraPackages ? [ ],
      shellHook ? "",
      env ? { },
      passthru ? { },
      ...
    }@args:
    let
      tex = pkgs.texlive.combine (texpkgs pkgs.texlive);
      # `rec` allows referencing `mkShell` here safely!
      passThroughAttrs = stripCustomArgs mkShell args;
    in
    pkgs.mkShell (
      passThroughAttrs
      // {
        env = env // {
          LATEX_ENV_ACTIVE = "1";
        };

        packages = [ tex ] ++ packages ++ extraPackages;

        shellHook = ''
          echo " >>> LaTeX environment activated"
          ${shellHook}
        '';

        passthru = passthru // {
          inherit tex;
        };
      }
    );

  mkDocument =
    {
      name,
      src,
      main ? "main.tex",
      texpkgs ? defaultTexpkgs,
      packages ? (with pkgs; [ cacert ]),
      extraPackages ? [ ],
      shellEscape ? false,
      latexmkFlags ? [ ],
      env ? { },
      passthru ? { },
      ...
    }@args:
    let
      tex = pkgs.texlive.combine (texpkgs pkgs.texlive);
      shellEscapeFlag = if shellEscape then "-shell-escape" else "";
      flagsStr = builtins.concatStringsSep " " (
        [
          "-pdf"
          "-interaction=nonstopmode"
          shellEscapeFlag
        ]
        ++ latexmkFlags
      );

      # `rec` allows referencing `mkDocument` here safely!
      passThroughAttrs = stripCustomArgs mkDocument args;
    in
    pkgs.stdenv.mkDerivation (
      passThroughAttrs
      // {
        inherit name src;

        env = env // {
          TEXINPUTS = ".:";
        };

        buildInputs = [ tex ] ++ packages ++ extraPackages;

        buildPhase = ''
          runHook preBuild

          export HOME=$(mktemp -d)
          latexmk ${flagsStr} ${main}

          runHook postBuild
        '';

        installPhase = ''
          runHook preInstall

          mkdir -p $out
          cp *.pdf $out/

          runHook postInstall
        '';

        passthru = passthru // {
          inherit tex;
        };
      }
    );
}
