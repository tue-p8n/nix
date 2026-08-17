{
  lib,
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
      accelConfig' =
        if accelerator != null && accelerator != (accelConfig.tag or "") then
          (accelerators { inherit pkgs lib; }).resolve accelerator
        else
          accelConfig;
      pkgs' = accelConfig'.pkgs;
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
            ++ accelConfig'.systemLibs;

          profile = ''
            set -e

            ${uvShell.accelActivationHook { accelConfig = accelConfig'; inherit nixglhost; }}
            ${uvShell.uvBaseHook}

            # Set after the activation hook, which is what defines REPO_ROOT.
            # Keyed by accelerator because every variant of a repo shares one
            # `.venv`, so keying on that would let a CUDA build and a ROCm
            # build read each other's JIT-compiled extensions.
            export TORCH_EXTENSIONS_DIR="''${TORCH_EXTENSIONS_DIR:-$REPO_ROOT/.torch-extensions/${accelConfig'.tag}}"

            echo " >>> UV FHS environment activated [${accelConfig'.tag}]"
            ${profile}
            set +e
          '';
        }
      );
    in
    {
      env = fhsEnv;
      accelConfig = accelConfig';
      passthru = passthru // {
        accelConfig = accelConfig';
        fhsEnv = fhsEnv;
      };
    };
}
