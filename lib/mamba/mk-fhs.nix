{
  self,
  config,
  pkgs,
  ...
}:
let
  stripCustomArgs =
    fn: args:
    let
      customKeys = builtins.attrNames (builtins.functionArgs fn);
    in
    builtins.removeAttrs args customKeys;
  shell = self.internal;
in
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
      extraPackages ? (_ps: [ ]),
      name ? "mamba-fhs-shell",
      file ? null,
      profile ? "",
      passthru ? { },
      ...
    }@args:
    let
      resolvePkgs = p: if builtins.isFunction p then p pkgs else p;

      nixglPkg = if pkgs ? nixglhost then [ pkgs.nixglhost ] else [ ];
      gpuHook = if pkgs ? nixglhost then shell.hostGpuHook pkgs.nixglhost else "";

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

      fhsEnv = pkgs.buildFHSEnv (
        passThroughAttrs
        // {
          name = "${name}-fhs-env";

          targetPkgs =
            _:
            nixglPkg
            ++ (resolvePkgs packages)
            ++ (resolvePkgs extraPackages)
            ++ config.packages
            ++ config.libraries.packages;

          multiPkgs = _: config.libraries.packages;

          profile = ''
            ${shell.exportEnv config.environment.variables}
            ${gpuHook}
            ${config.shellHook}
            export MAMBA_ROOT_PREFIX="$HOME/.local/share/mamba"
            eval "$(micromamba shell hook --shell bash)"
            ${fileHook}
            echo "Micromamba FHS environment activated [${config.name}]"
            ${profile}
          '';

          runScript = "bash";
        }
      );
    in
    {
      env = fhsEnv;
      accelConfig = config;
      passthru = passthru // {
        accelConfig = config;
        fhsEnv = fhsEnv;
      };
    };
}
