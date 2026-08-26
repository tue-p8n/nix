{
  pkgs,
  config,
  internal,
  ...
}:
let
  defaultPkgs = pkgs;
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
      accelerator ? "cpu",
      pkgs ? defaultPkgs,
      name ? null,
      packages ? (_ps: [ ]),
      extraPackages ? (_ps: [ ]),
      env ? { },
      shellHook ? "",
      preCommit ? (args.self.preCommit or null),
      passthru ? { },
      ...
    }@args:
    let
      accelConfig = config.build pkgs accelerator;
      pkgs' = accelConfig.pkgs;
      resolvePkgs = p: if builtins.isFunction p then p pkgs' else p;

      nixglhost = pkgs'.nixglhost or null;
      libPath = pkgs'.lib.makeLibraryPath accelConfig.libraries.packages;
      baseName = if name != null then name else "uv";
      tag = accelConfig.name;
      resolvedName =
        if accelConfig.acceleration != "none" && tag != "none" && tag != "cpu" then
          "${baseName}+${tag}"
        else
          baseName;
      passThroughAttrs = stripCustomArgs mkShell args;
    in
    (pkgs'.mkShell.override { inherit (accelConfig) stdenv; }) (
      passThroughAttrs
      // {
        name = resolvedName;

        packages =
          accelConfig.packages
          ++ (with pkgs'; [
            uv
            git
            ninja
            pkg-config
            which
            just
            ccache
            cacert
            coreutils
          ])
          ++ (if nixglhost != null then [ nixglhost ] else [ ])
          ++ (resolvePkgs packages)
          ++ (resolvePkgs extraPackages)
          ++ (internal.preCommit.packages preCommit);

        shellHook = ''
          ${internal.nixLdHook pkgs' libPath}
          ${internal.exportEnv (accelConfig.environment.variables // env)}
          ${internal.repoRootHook}
          ${internal.hostGpuHook nixglhost}
          ${accelConfig.shellHook}

          export UV_NO_SYNC=''${UV_NO_SYNC:-1}
          export UV_LOCKED=''${UV_LOCKED:-1}
          export UV_PYTHON_PREFERENCE=''${UV_PYTHON_PREFERENCE:-only-system}
          export LD_LIBRARY_PATH="${libPath}:$LD_LIBRARY_PATH"

          export UV_PROJECT_ENVIRONMENT="$REPO_ROOT/.venvs/${resolvedName}"
          export VIRTUAL_ENV="$UV_PROJECT_ENVIRONMENT"

          # Colocate PyTorch JIT extension build artifacts inside the virtual
          # environment so deleting the venv automatically cleans up cached extensions.
          export TORCH_EXTENSIONS_DIR="''${TORCH_EXTENSIONS_DIR:-$REPO_ROOT/.venvs/${resolvedName}/torch_extensions}"

          echo "🐍 UV shell activated: $(uv --version) [${accelConfig.name}]"
          ${internal.preCommit.hook preCommit}
          ${shellHook}
        '';

        passthru = passthru // {
          config = accelConfig;
          p8n = {
            category = "python";
            flavor = "uv-dynamic";
            name = baseName;
            accelerator = tag;
          };
        };
      }
    );
}
