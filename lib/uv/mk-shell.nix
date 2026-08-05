{
  lib,
  shell,
  uvShell,
  ...
}:
let
  stripCustomArgs =
    fn: args:
    let
      customKeys = builtins.attrNames (builtins.functionArgs fn);
    in
    builtins.removeAttrs args customKeys;
  accelerators = import ../accelerators;
in
accelConfig@{ pkgs, ... }:
rec {
  mkShell =
    {
      name ? null,
      packages ? (_ps: [ ]),
      extraPackages ? (_ps: [ ]),
      env ? { },
      shellHook ? "",
      passthru ? { },
      accelerator ? null,
      ...
    }@args:
    let
      accelConfig' =
        if accelerator != null && accelerator != (accelConfig.tag or "") then
          (accelerators { inherit pkgs lib; }).resolve accelerator
        else
          accelConfig;
      pkgs' = accelConfig'.pkgs;
      resolvePkgs = p: if builtins.isFunction p then p pkgs' else p;

      nixglhost = pkgs'.nixglhost or null;
      libPath = pkgs'.lib.makeLibraryPath accelConfig'.systemLibs;
      passThroughAttrs = stripCustomArgs mkShell args;
    in
    (pkgs'.mkShell.override { inherit (accelConfig') stdenv; }) (
      passThroughAttrs
      // {
        name =
          if name != null then
            name
          else
            "uv-${builtins.replaceStrings [ "." "cuda-" ] [ "_" "cuda" ] accelConfig'.tag}";

        packages =
          accelConfig'.packages
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

        env = (accelConfig'.env or { }) // env;

        shellHook = ''
          ${shell.nixLdHook pkgs' libPath}

          export SSL_CERT_FILE="${pkgs'.cacert}/etc/ssl/certs/ca-bundle.crt"
          export NIX_SSL_CERT_FILE="${pkgs'.cacert}/etc/ssl/certs/ca-bundle.crt"

          export TORCH_EXTENSIONS_DIR="$VIRTUAL_ENV/torch_extensions"

          export PATH="${pkgs'.ccache}/bin:$PATH"
          export CMAKE_C_COMPILER_LAUNCHER=ccache
          export CMAKE_CXX_COMPILER_LAUNCHER=ccache
          export CMAKE_CUDA_COMPILER_LAUNCHER=ccache

          export LIBRARY_PATH="${libPath}:$LIBRARY_PATH"
          export LD_LIBRARY_PATH="${libPath}:$LD_LIBRARY_PATH"

          ${uvShell.accelActivationHook { accelConfig = accelConfig'; inherit nixglhost; }}
          ${uvShell.uvBaseHook}

          echo "🐍 UV shell activated: $(uv --version) [${accelConfig'.tag}]"
          ${shellHook}
        '';

        passthru = passthru // {
          accelConfig = accelConfig';
        };
      }
    );
}
