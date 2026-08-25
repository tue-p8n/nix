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
      passthru ? { },
      ...
    }@args:
    let
      accelConfig = config.build pkgs accelerator;
      pkgs' = accelConfig.pkgs;
      resolvePkgs = p: if builtins.isFunction p then p pkgs' else p;

      nixglhost = pkgs'.nixglhost or null;
      libPath = pkgs'.lib.makeLibraryPath accelConfig.libraries.packages;
      passThroughAttrs = stripCustomArgs mkShell args;
    in
    (pkgs'.mkShell.override { inherit (accelConfig) stdenv; }) (
      passThroughAttrs
      // {
        name =
          if name != null then
            name
          else
            "uv-${builtins.replaceStrings [ "." "cuda-" ] [ "_" "cuda" ] accelConfig.name}";

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
          ++ (resolvePkgs extraPackages);

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

          export UV_PROJECT_ENVIRONMENT="$REPO_ROOT/.venv"
          export VIRTUAL_ENV="$UV_PROJECT_ENVIRONMENT"

          # Set after the activation hook, which is what defines REPO_ROOT.
          # Keyed by accelerator because every variant of a repo shares one
          # `.venv`, so keying on that would let a CUDA build and a ROCm build
          # read each other's JIT-compiled extensions.
          export TORCH_EXTENSIONS_DIR="''${TORCH_EXTENSIONS_DIR:-$REPO_ROOT/.torch-extensions/${accelConfig.name}}"

          echo "🐍 UV shell activated: $(uv --version) [${accelConfig.name}]"
          ${shellHook}
        '';

        passthru = passthru // {
          config = accelConfig;
        };
      }
    );
}
