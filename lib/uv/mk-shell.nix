{
  self,
  config,
  pkgs,
  ...
}:
let
  inherit (self.uv) hooks;
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
      name ? null,
      packages ? (_ps: [ ]),
      extraPackages ? (_ps: [ ]),
      env ? { },
      shellHook ? "",
      passthru ? { },
      ...
    }@args:
    let
      resolvePkgs = p: if builtins.isFunction p then p pkgs else p;

      nixglhost = pkgs.nixglhost or null;
      libPath = pkgs.lib.makeLibraryPath config.systemLibs;
      passThroughAttrs = stripCustomArgs mkShell args;
    in
    (pkgs.mkShell.override { inherit (config) stdenv; }) (
      passThroughAttrs
      // {
        name =
          if name != null then
            name
          else
            "uv-${builtins.replaceStrings [ "." "cuda-" ] [ "_" "cuda" ] config.tag}";

        packages =
          config.packages
          ++ (with pkgs; [
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

        env = (config.env or { }) // env;

        shellHook = ''
          ${self.internal.nixLdHook pkgs libPath}

          export SSL_CERT_FILE="${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt"
          export NIX_SSL_CERT_FILE="${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt"

          export PATH="${pkgs.ccache}/bin:$PATH"
          export CMAKE_C_COMPILER_LAUNCHER=ccache
          export CMAKE_CXX_COMPILER_LAUNCHER=ccache
          export CMAKE_CUDA_COMPILER_LAUNCHER=ccache

          export LIBRARY_PATH="${libPath}:$LIBRARY_PATH"
          export LD_LIBRARY_PATH="${libPath}:$LD_LIBRARY_PATH"

          ${hooks.accelActivationHook {
            inherit nixglhost;
          }}
          ${hooks.uvBaseHook}

          # Set after the activation hook, which is what defines REPO_ROOT.
          # Keyed by accelerator because every variant of a repo shares one
          # `.venv`, so keying on that would let a CUDA build and a ROCm build
          # read each other's JIT-compiled extensions.
          export TORCH_EXTENSIONS_DIR="''${TORCH_EXTENSIONS_DIR:-$REPO_ROOT/.torch-extensions/${config.tag}}"

          echo "🐍 UV shell activated: $(uv --version) [${config.name}]"
          ${shellHook}
        '';

        passthru = passthru // {
          config = config;
        };
      }
    );
}
