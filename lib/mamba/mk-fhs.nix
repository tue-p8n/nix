{ inputs, lib }:
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
  mkFHS =
    {
      packages ? (
        ps: with ps; [
          cacert
          micromamba
          git
        ]
      ),
      extraPackages ? (ps: [ ]),
      name ? "mamba-fhs-shell",
      file ? null,
      env ? { },
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

      nixglPkg = if pkgs' ? nixglhost then [ pkgs'.nixglhost ] else [ ];
      gpuHook = if pkgs' ? nixglhost then shell.hostGpuHook pkgs'.nixglhost else "";

      passThroughAttrs = stripCustomArgs mkFHS args;

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

      fhsEnv = pkgs'.buildFHSEnv (
        passThroughAttrs
        // {
          name = "${name}-fhs-env";

          targetPkgs =
            _:
            nixglPkg
            ++ (resolvePkgs packages)
            ++ (resolvePkgs extraPackages)
            ++ accelConfig'.packages
            ++ accelConfig'.systemLibs;

          multiPkgs = _: accelConfig'.systemLibs;

          profile = ''
            ${shell.exportEnv accelConfig'.env}
            ${gpuHook}
            ${accelConfig'.shellHook}
            export MAMBA_ROOT_PREFIX="$HOME/.local/share/mamba"
            eval "$(micromamba shell hook --shell bash)"
            ${fileHook}
            echo "Micromamba FHS environment activated [${accelConfig'.tag}]"
            ${profile}
          '';

          runScript = "bash";
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

