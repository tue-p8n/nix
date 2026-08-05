{ lib, ... }:
let
  stripCustomArgs =
    fn: args:
    let
      customKeys = builtins.attrNames (builtins.functionArgs fn);
    in
    builtins.removeAttrs args customKeys;
  shell = import ../_internal { inherit lib; };
  accelerators = import ../accelerators;
in
accelConfig@{ pkgs, ... }:
rec {
  mkShell =
    {
      packages ? (
        ps: with ps; [
          cacert
          micromamba
          git
        ]
      ),
      extraPackages ? (_ps: [ ]),
      name ? "mamba-shell",
      file ? null,
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

      nixglPkg = if pkgs' ? nixglhost then [ pkgs'.nixglhost ] else [ ];
      gpuHook = if pkgs' ? nixglhost then shell.hostGpuHook pkgs'.nixglhost else "";

      passThroughAttrs = stripCustomArgs mkShell args;

      fileHook =
        if file != null then
          ''
            if [ -f "${file}" ]; then
              echo " >>> Creating/updating micromamba environment from ${file}..."
              micromamba create -q -n "${name}" -f "${file}" -y || true
              micromamba activate "${name}" || true
            fi
          ''
        else
          "";
    in
    (pkgs'.mkShell.override { stdenv = accelConfig'.stdenv; }) (
      passThroughAttrs
      // {
        inherit name;

        packages =
          nixglPkg ++ (resolvePkgs packages) ++ (resolvePkgs extraPackages) ++ accelConfig'.packages;

        env =
          (accelConfig'.env or { })
          // {
            MAMBA_ROOT_PREFIX = "${builtins.getEnv "HOME"}/.local/share/mamba";
            LD_LIBRARY_PATH = "${lib.makeLibraryPath accelConfig'.systemLibs}";
          }
          // env;

        shellHook = ''
          ${shell.exportEnv accelConfig'.env}
          ${gpuHook}
          ${accelConfig'.shellHook}
          eval "$(micromamba shell hook --shell bash)"
          ${fileHook}
          echo "Micromamba shell activated [${accelConfig'.tag}]"
          ${shellHook}
        '';

        passthru = passthru // {
          accelConfig = accelConfig';
        };
      }
    );
}
