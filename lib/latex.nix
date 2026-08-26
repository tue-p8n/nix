# Utilities for writing documents with LaTeX.
{
  inputs ? { },
  pkgs,
  internal,
  ...
}:
let
  defaultPkgs = pkgs;
  defaultTexpkgs = ps: { inherit (ps) scheme-full; };

  resolveTexlive =
    target:
    let
      tueP8n = inputs.tue-p8n or inputs.self or { };
      pkgs2024 =
        if inputs ? nixpkgs-24-05 then
          inputs.nixpkgs-24-05
        else if tueP8n ? inputs && tueP8n.inputs ? nixpkgs-24-05 then
          tueP8n.inputs.nixpkgs-24-05
        else
          null;
      pkgs2023 =
        if inputs ? nixpkgs-23-11 then
          inputs.nixpkgs-23-11
        else if tueP8n ? inputs && tueP8n.inputs ? nixpkgs-23-11 then
          tueP8n.inputs.nixpkgs-23-11
        else
          null;
    in
    if builtins.isAttrs target then
      target
    else if builtins.isString target then
      let
        v = builtins.replaceStrings [ "." ] [ "_" ] target;
      in
      if target == "default" || target == "latest" then
        pkgs.texlive
      else if v == "2024" || v == "24_05" then
        if pkgs2024 != null then
          pkgs2024.legacyPackages.${pkgs.stdenv.hostPlatform.system}.texlive
        else
          throw "p8n.latex: nixpkgs-24-05 is not available in inputs or tue-p8n.inputs."
      else if v == "2023" || v == "23_11" then
        if pkgs2023 != null then
          pkgs2023.legacyPackages.${pkgs.stdenv.hostPlatform.system}.texlive
        else
          throw "p8n.latex: nixpkgs-23-11 is not available in inputs or tue-p8n.inputs."
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
      name ? "latex",
      pkgs ? defaultPkgs,
      texlive ? (if version != null then version else "default"),
      version ? null,
      texpkgs ? defaultTexpkgs,
      packages ? [ ],
      extraPackages ? [ ],
      shellHook ? "",
      preCommit ? (args.self.preCommit or null),
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
        inherit name;

        packages =
          [ tex ]
          ++ packages
          ++ extraPackages
          ++ (internal.preCommit.packages preCommit);

        shellHook = ''
          export LATEX_ENV_ACTIVE="1"
          ${internal.exportEnv env}
          echo " >>> LaTeX environment activated"
          ${internal.preCommit.hook preCommit}
          ${shellHook}
        '';

        passthru = passthru // {
          inherit tex;
          p8n = {
            category = "latex";
            name = name;
            texlive = if builtins.isString texlive then texlive else "custom";
            inherit tex;
          };
        };
      }
    );

  mkDocument =
    {
      name ? "document",
      src,
      pkgs ? defaultPkgs,
      texlive ? (if version != null then version else "default"),
      version ? null,
      main ? null,
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

      hasLatexmkrc =
        builtins.pathExists (src + "/latexmkrc")
        || builtins.pathExists (src + "/.latexmkrc");
      resolvedMain =
        if main != null then
          main
        else if hasLatexmkrc then
          ""
        else if builtins.pathExists (src + "/main.tex") then
          "main.tex"
        else if builtins.pathExists (src + "/paper.tex") then
          "paper.tex"
        else
          "main.tex";

      passThroughAttrs = stripCustomArgs mkDocument args;
    in
    pkgs.stdenv.mkDerivation (
      passThroughAttrs
      // {
        inherit name src;

        env = env // {
          TEXINPUTS = ".:";
        };

        nativeBuildInputs = [ tex ] ++ packages ++ extraPackages;
        buildInputs = [ tex ] ++ packages ++ extraPackages;

        buildPhase = ''
          runHook preBuild

          export HOME=$(mktemp -d)
          latexmk ${flagsStr}${if resolvedMain != "" then " " + resolvedMain else ""}

          runHook postBuild
        '';

        installPhase = ''
          runHook preInstall

          mkdir -p $out

          pdf_count=$(ls -1 *.pdf 2>/dev/null | wc -l)
          if [ "$pdf_count" -eq 1 ]; then
            orig_pdf=$(ls -1 *.pdf)
            target_name="${name}.pdf"
            cp "$orig_pdf" "$out/$target_name"
            if [ "$orig_pdf" != "$target_name" ]; then
              ln -s "$target_name" "$out/$orig_pdf"
            fi
          else
            for pdf in *.pdf; do
              [ -f "$pdf" ] || continue
              target_name="${name}-$pdf"
              cp "$pdf" "$out/$target_name"
              ln -s "$target_name" "$out/$pdf"
            done
          fi

          runHook postInstall
        '';

        passthru = passthru // {
          inherit tex;
        };
      }
    );

  mkWatch =
    {
      name ? "latex-watch",
      src,
      pkgs ? defaultPkgs,
      texlive ? (if version != null then version else "default"),
      version ? null,
      main ? null,
      texpkgs ? defaultTexpkgs,
      packages ? [ ],
      extraPackages ? [ ],
      shellEscape ? false,
      latexmkFlags ? [ ],
      ...
    }:
    let
      resolvedTexlive = resolveTexlive texlive;
      tex = resolvedTexlive.combine (texpkgs resolvedTexlive);
      shellEscapeFlag = if shellEscape then "-shell-escape" else "";
      flagsStr = builtins.concatStringsSep " " (
        [
          "-pvc"
          "-pdf"
          "-interaction=nonstopmode"
          shellEscapeFlag
        ]
        ++ latexmkFlags
      );
      hasLatexmkrc =
        builtins.pathExists (src + "/latexmkrc")
        || builtins.pathExists (src + "/.latexmkrc");
      resolvedMain =
        if main != null then
          main
        else if hasLatexmkrc then
          ""
        else if builtins.pathExists (src + "/main.tex") then
          "main.tex"
        else if builtins.pathExists (src + "/paper.tex") then
          "paper.tex"
        else
          "main.tex";

      allPkgs = [ tex ] ++ packages ++ extraPackages;
      pathStr = pkgs.lib.makeBinPath allPkgs;

      script = pkgs.writeShellScriptBin name ''
        export PATH="${pathStr}:$PATH"
        export TEXINPUTS=".:$TEXINPUTS"
        cd "${src}"
        exec latexmk ${flagsStr}${if resolvedMain != "" then " " + resolvedMain else ""} "$@"
      '';
    in
    {
      type = "app";
      program = "${script}/bin/${name}";
      meta = script.meta or { };
    };

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
      inferredName =
        customArgs.name or (
          if builtins.isPath src || builtins.isString src then
            builtins.baseNameOf (toString src)
          else
            "document"
        );
      hasLatexmkrc =
        builtins.pathExists (src + "/latexmkrc")
        || builtins.pathExists (src + "/.latexmkrc");
      defaultMain =
        if hasLatexmkrc then
          ""
        else if builtins.pathExists (src + "/main.tex") then
          "main.tex"
        else if builtins.pathExists (src + "/paper.tex") then
          "paper.tex"
        else
          "main.tex";
      mkDoc = mkDocument;
      mkSh = mkShell;
      mkWch = mkWatch;
    in
    {
      inherit src;
      name = inferredName;
      main = customArgs.main or defaultMain;
      hasCustomLatexmkrc = hasLatexmkrc;

      mkDocument =
        docArgs:
        let
          args' = if builtins.isAttrs docArgs then docArgs else { };
        in
        mkDoc (
          {
            name = inferredName;
          }
          // customArgs
          // args'
          // {
            inherit src;
            main = args'.main or (customArgs.main or defaultMain);
          }
        );

      mkShell =
        shellArgs:
        let
          args' = if builtins.isAttrs shellArgs then shellArgs else { };
        in
        mkSh (
          {
            name = inferredName;
          }
          // customArgs
          // args'
        );

      mkWatch =
        watchArgs:
        let
          args' = if builtins.isAttrs watchArgs then watchArgs else { };
        in
        mkWch (
          {
            name = "${inferredName}-watch";
          }
          // customArgs
          // args'
          // {
            inherit src;
            main = args'.main or (customArgs.main or defaultMain);
          }
        );
    };
}
