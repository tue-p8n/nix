# Utilities for working with Typst documents.
{
  pkgs,
  ...
}:
let
  defaultPkgs = pkgs;
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
      pkgs ? defaultPkgs,
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
      pkgs ? defaultPkgs,
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
          throw "p8n.typst.readProject: expected a src path or an attribute set containing `src`.";

      customArgs = if builtins.isAttrs args then args else { };
      defaultMain =
        if builtins.pathExists (src + "/main.typ") then
          "main.typ"
        else if builtins.pathExists (src + "/document.typ") then
          "document.typ"
        else
          "main.typ";
    in
    rec {
      inherit src;
      main = customArgs.main or defaultMain;

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
