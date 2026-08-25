# Utilities for writing documents with LaTeX.
{
  inputs ? { },
  pkgs,
  ...
}:
let
  defaultPkgs = pkgs;
  defaultTexpkgs = ps: { inherit (ps) scheme-full; };

  resolveTexlive =
    target:
    if builtins.isAttrs target then
      target
    else if builtins.isString target then
      let
        v = builtins.replaceStrings [ "." ] [ "_" ] target;
      in
      if target == "default" || target == "latest" then
        pkgs.texlive
      else if v == "2024" || v == "24_05" then
        if inputs ? nixpkgs-24-05 then
          inputs.nixpkgs-24-05.legacyPackages.${pkgs.stdenv.hostPlatform.system}.texlive
        else
          throw "p8n.latex: inputs.nixpkgs-24-05 is not available."
      else if v == "2023" || v == "23_11" then
        if inputs ? nixpkgs-23-11 then
          inputs.nixpkgs-23-11.legacyPackages.${pkgs.stdenv.hostPlatform.system}.texlive
        else
          throw "p8n.latex: inputs.nixpkgs-23-11 is not available."
      else
        throw ''
          p8n.latex: unrecognised texlive version "${target}".
          Expected: "default" | "latest" | "2024" | "24.05" | "2023" | "23.11" or a texlive package set.
        ''
    else
      throw "p8n.latex: invalid texlive argument.";

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
      pkgs ? defaultPkgs,
      texlive ? (if version != null then version else "default"),
      version ? null,
      texpkgs ? defaultTexpkgs,
      packages ? (with pkgs; [ cacert ]),
      extraPackages ? [ ],
      shellHook ? "",
      env ? { },
      passthru ? { },
      ...
    }@args:
    let
      resolvedTexlive = resolveTexlive texlive;
      tex = resolvedTexlive.combine (texpkgs resolvedTexlive);
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
      pkgs ? defaultPkgs,
      texlive ? (if version != null then version else "default"),
      version ? null,
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
      resolvedTexlive = resolveTexlive texlive;
      tex = resolvedTexlive.combine (texpkgs resolvedTexlive);
      shellEscapeFlag = if shellEscape then "-shell-escape" else "";
      flagsStr = builtins.concatStringsSep " " (
        [
          "-pdf"
          "-interaction=nonstopmode"
          shellEscapeFlag
        ]
        ++ latexmkFlags
      );

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

  readProject =
    args:
    let
      src =
        if builtins.isPath args || builtins.isString args then
          args
        else if builtins.isAttrs args && args ? src then
          args.src
        else if builtins.isAttrs args && args ? workspaceRoot then
          args.workspaceRoot
        else
          throw "p8n.latex.readProject: expected a src path or an attribute set containing `src`.";

      customArgs = if builtins.isAttrs args then args else { };
      hasLatexmkrc = builtins.pathExists (src + "/.latexmkrc");
      defaultMain =
        if builtins.pathExists (src + "/main.tex") then
          "main.tex"
        else if builtins.pathExists (src + "/paper.tex") then
          "paper.tex"
        else
          "main.tex";
    in
    rec {
      inherit src;
      main = customArgs.main or defaultMain;
      hasCustomLatexmkrc = hasLatexmkrc;

      mkDocument =
        docArgs:
        mkDocument (
          customArgs
          // docArgs
          // {
            inherit src;
            main = docArgs.main or main;
          }
        );

      mkShell =
        shellArgs:
        mkShell (
          customArgs
          // shellArgs
        );
    };
}
