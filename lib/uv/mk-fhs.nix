{
  lib,
  self,
  pkgs,
  config,
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
  accelerators = import ../accelerators;
in
rec {
  mkFHS =
    {
      name ? "uv-fhs-shell",
      packages ? (_ps: [ ]),
      extraPackages ? (_ps: [ ]),
      profile ? "",
      passthru ? { },
      accelerator ? null,
      ...
    }@args:
    let
      config' =
        if accelerator != null && accelerator != (config.tag or "") then
          (accelerators { inherit pkgs lib; }).resolve accelerator
        else
          config;
      pkgs' = config'.pkgs;
      resolvePkgs = p: if builtins.isFunction p then p pkgs' else p;

      nixglhost = pkgs'.nixglhost or null;
      nixglPkg = if nixglhost != null then [ nixglhost ] else [ ];
      passThroughAttrs = stripCustomArgs mkFHS args;

      fhsEnv = pkgs'.buildFHSEnv (
        passThroughAttrs
        // {
          inherit name;

          targetPkgs =
            ps:
            nixglPkg
            ++ (with ps; [
              uv
              git
              coreutils
              bashInteractive
              zlib
              stdenv.cc.cc.lib
              fontconfig
              freetype
              dbus
              cacert
            ])
            ++ (resolvePkgs packages)
            ++ (resolvePkgs extraPackages)
            ++ config'.systemLibs;

          profile = ''
            set -e

            ${hooks.accelActivationHook {
              config = config';
              inherit nixglhost;
            }}
            ${hooks.uvBaseHook}

            # Set after the activation hook, which is what defines REPO_ROOT.
            # Keyed by accelerator because every variant of a repo shares one
            # `.venv`, so keying on that would let a CUDA build and a ROCm
            # build read each other's JIT-compiled extensions.
            export TORCH_EXTENSIONS_DIR="''${TORCH_EXTENSIONS_DIR:-$REPO_ROOT/.torch-extensions/${config'.tag}}"

            echo " >>> UV FHS environment activated [${config'.tag}]"
            ${profile}
            set +e
          '';
        }
      );
    in
    {
      env = fhsEnv;
      config = config';
      passthru = passthru // {
        config = config';
        fhsEnv = fhsEnv;
      };
    };
}
