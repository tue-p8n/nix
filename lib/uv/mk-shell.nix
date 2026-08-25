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
      resolvedName =
        if name != null then
          name
        else
          "uv-${builtins.replaceStrings [ "." "cuda-" ] [ "_" "cuda" ] accelConfig.name}";
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

        env =
          accelConfig.environment.variables
          // {
            UV_NO_SYNC = "1";
            UV_LOCKED = "1";
            UV_PYTHON_PREFERENCE = "only-managed";
            UV_PYTHON_DOWNLOADS = "auto";
          }
          // env;

        shellHook = ''
          ${internal.nixLdHook pkgs' libPath}

          export SSL_CERT_FILE="${pkgs'.cacert}/etc/ssl/certs/ca-bundle.crt"
          export NIX_SSL_CERT_FILE="${pkgs'.cacert}/etc/ssl/certs/ca-bundle.crt"

          export PATH="${pkgs'.ccache}/bin:$PATH"
          export CMAKE_C_COMPILER_LAUNCHER=ccache
          export CMAKE_CXX_COMPILER_LAUNCHER=ccache
          export CMAKE_CUDA_COMPILER_LAUNCHER=ccache

          export LIBRARY_PATH="${libPath}:$LIBRARY_PATH"
          export LD_LIBRARY_PATH="${libPath}:$LD_LIBRARY_PATH"

          ${internal.exportEnv accelConfig.environment.variables}
          ${internal.repoRootHook}
          ${internal.hostGpuHook nixglhost}
          ${accelConfig.shellHook}

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
        };
      }
    );
}
