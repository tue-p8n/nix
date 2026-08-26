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

          if [ -f "${output}" ]; then
            target_name="${name}.pdf"
            cp "${output}" "$out/$target_name"
            if [ "${output}" != "$target_name" ]; then
              ln -s "$target_name" "$out/${output}"
            fi
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
      resolvedMain =
        if main != null then
          main
        else if builtins.pathExists (src + "/main.typ") then
          "main.typ"
        else if builtins.pathExists (src + "/document.typ") then
          "document.typ"
        else
          "main.typ";

      allPkgs = [ pkgs.typst ] ++ packages ++ extraPackages;
      pathStr = pkgs.lib.makeBinPath allPkgs;

      script = pkgs.writeShellScriptBin name ''
        export PATH="${pathStr}:$PATH"
        cd "${src}"
        exec typst watch "${resolvedMain}" "${output}" "$@"
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
        mkSh (
          customArgs
          // (if builtins.isAttrs shellArgs then shellArgs else { })
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
