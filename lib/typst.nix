# Utilities for working with Typst documents.
{
  pkgs,
  internal,
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
      name ? "typst",
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
      preCommit ? (args.self.preCommit or null),
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
        inherit name;

        packages =
          [ pkgs.typst ]
          ++ packages
          ++ extraPackages
          ++ (internal.preCommit.packages preCommit);

        shellHook = ''
          export TYPST_ENV_ACTIVE="1"
          ${internal.exportEnv env}
          echo " >>> Typst environment activated: $(${pkgs.typst}/bin/typst --version)"
          ${internal.preCommit.hook preCommit}
          ${shellHook}
        '';

        passthru = passthru // {
          typst = pkgs.typst;
          p8n = {
            category = "typst";
            name = name;
            typst = pkgs.typst;
          };
        };
      }
    );

  mkDocument =
    {
      name ? "document",
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
      resolvedMain =
        if builtins.isList main then
          main
        else if builtins.isString main then
          [ main ]
        else
          [ "main.typ" ];

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

          ${
            if builtins.length resolvedMain == 1 then
              "typst compile ${builtins.elemAt resolvedMain 0} ${output}"
            else
              builtins.concatStringsSep "\n" (map (m: "typst compile ${m}") resolvedMain)
          }

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
          inherit (pkgs) typst;
        };
      }
    );

  mkWatch =
    {
      name ? "typst-watch",
      src,
      pkgs ? defaultPkgs,
      main ? null,
      output ? "document.pdf",
      packages ? [ ],
      extraPackages ? [ ],
      ...
    }:
    let
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

      allPkgs = [ pkgs.typst ] ++ packages ++ extraPackages;
      pathStr = pkgs.lib.makeBinPath allPkgs;

      script = pkgs.writeShellScriptBin name ''
        export PATH="${pathStr}:$PATH"

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
            if [ -f "main.typ" ]; then
              TARGETS+=("main.typ")
            elif [ -f "document.typ" ]; then
              TARGETS+=("document.typ")
            else
              TARGETS+=("main.typ")
            fi
          ''
        }

        if [ ''${#TARGETS[@]} -eq 1 ]; then
          exec typst watch "''${TARGETS[0]}" ${if output != null then output else ""} "$@"
        else
          trap 'kill $(jobs -p) 2>/dev/null || true' EXIT INT TERM HUP
          echo ">>> Watching ''${#TARGETS[@]} Typst documents: ''${TARGETS[*]}"
          for target in "''${TARGETS[@]}"; do
            typst watch "$target" "$@" &
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
          throw "p8n.typst.readProject: expected a src path or an attribute set containing `src`.";

      customArgs = if builtins.isAttrs args then args else { };
      inferredName =
        customArgs.name or (
          if builtins.isPath src || builtins.isString src then
            builtins.baseNameOf (toString src)
          else
            "document"
        );
      defaultMain =
        if builtins.pathExists (src + "/main.typ") then
          "main.typ"
        else if builtins.pathExists (src + "/document.typ") then
          "document.typ"
        else
          "main.typ";
      mkDoc = mkDocument;
      mkSh = mkShell;
      mkWch = mkWatch;
    in
    {
      inherit src;
      name = inferredName;
      main = customArgs.main or defaultMain;

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
