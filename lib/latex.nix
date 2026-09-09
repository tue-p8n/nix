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

  # A nixpkgs release ships the TeX Live of the *previous* year or older, so
  # the two numbers must be mapped explicitly. Keys are TeX Live releases;
  # the nixpkgs release is also accepted, for pinning a channel directly.
  texliveSources = {
    "2022" = "nixpkgs-23-11";
    "2023" = "nixpkgs-24-05";
    "2024" = "nixpkgs-25-05";
    "2025" = "nixpkgs-25-11";
    "23_11" = "nixpkgs-23-11";
    "24_05" = "nixpkgs-24-05";
    "25_05" = "nixpkgs-25-05";
    "25_11" = "nixpkgs-25-11";
  };

  resolveTexlive =
    target:
    let
      tueP8n = inputs.tue-p8n or inputs.self or { };
      channel =
        input:
        if inputs ? ${input} then
          inputs.${input}
        else if tueP8n ? inputs && tueP8n.inputs ? ${input} then
          tueP8n.inputs.${input}
        else
          throw "p8n.latex: ${input} is not available in inputs or tue-p8n.inputs.";
    in
    if builtins.isAttrs target then
      target
    else if builtins.isString target then
      let
        v = builtins.replaceStrings [ "." ] [ "_" ] target;
      in
      if target == "default" || target == "latest" then
        pkgs.texlive
      else if texliveSources ? ${v} then
        (channel texliveSources.${v}).legacyPackages.${pkgs.stdenv.hostPlatform.system}.texlive
      else
        throw ''
          p8n.latex: unrecognised texlive version "${target}".
          Expected a TeX Live release ("2022" | "2023" | "2024" | "2025"),
          a nixpkgs release ("23.11" | "24.05" | "25.05" | "25.11"),
          "default" | "latest", or a texlive package set.
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
          (if builtins.isList main then builtins.concatStringsSep " " main else main)
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

      relDir =
        if builtins.isPath src then
          pkgs.lib.removePrefix "/" (pkgs.lib.removePrefix (toString ./.) (toString src))
        else if builtins.isString src then
          src
        else
          "";

      explicitTargets =
        if main == null then
          null
        else if builtins.isList main then
          main
        else if builtins.isString main then
          pkgs.lib.filter (s: s != "") (pkgs.lib.splitString " " main)
        else
          [ ];

      explicitTargetsStr =
        if explicitTargets != null then
          builtins.concatStringsSep " " (map (f: ''"${f}"'') explicitTargets)
        else
          "";

      allPkgs = [ tex ] ++ packages ++ extraPackages;
      pathStr = pkgs.lib.makeBinPath allPkgs;

      script = pkgs.writeShellScriptBin name ''
        export PATH="${pathStr}:$PATH"
        export TEXINPUTS=".:$TEXINPUTS"

        REPO_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || pwd)
        if [ -n "${relDir}" ] && [ -d "$REPO_ROOT/${relDir}" ]; then
          cd "$REPO_ROOT/${relDir}"
        elif [ -d "${toString src}" ]; then
          cd "${toString src}"
        fi

        ${
          if explicitTargets != null then ''
            TARGETS=(${explicitTargetsStr})
          '' else ''
            TARGETS=()
            if [ -f "./latexmkrc" ] || [ -f "./.latexmkrc" ]; then
              while IFS= read -r f; do
                [ -n "$f" ] && TARGETS+=("$f")
              done < <(perl -e '
                do "./latexmkrc" if -f "./latexmkrc";
                do "./.latexmkrc" if -f "./.latexmkrc";
                if (@default_files) {
                  for my $f (@default_files) {
                    print "$f\n" if length($f);
                  }
                }
              ' 2>/dev/null)
            fi

            if [ ''${#TARGETS[@]} -eq 0 ]; then
              if [ -f "main.tex" ]; then
                TARGETS+=("main.tex")
              elif [ -f "paper.tex" ]; then
                TARGETS+=("paper.tex")
              else
                TARGETS+=("main.tex")
              fi
            fi
          ''
        }

        if [ ''${#TARGETS[@]} -eq 1 ]; then
          exec latexmk ${flagsStr} "$@" "''${TARGETS[0]}"
        else
          trap 'kill $(jobs -p) 2>/dev/null || true' EXIT INT TERM HUP
          echo ">>> Watching ''${#TARGETS[@]} LaTeX documents: ''${TARGETS[*]}"
          for target in "''${TARGETS[@]}"; do
            latexmk ${flagsStr} "$@" "$target" &
          done
          wait
        fi
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
