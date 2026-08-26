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
  mkFHS =
    {
      accelerator ? "cpu",
      pkgs ? defaultPkgs,
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
      accelConfig = config.build pkgs accelerator;
      pkgs' = accelConfig.pkgs;
      resolvePkgs = p: if builtins.isFunction p then p pkgs' else p;

      nixglhost = pkgs'.nixglhost or null;
      nixglPkg = if nixglhost != null then [ nixglhost ] else [ ];
      passThroughAttrs = stripCustomArgs mkFHS args;

      fileHook =
        if file != null then
          ''
            if [ -f "${file}" ]; then
              if ! micromamba env list | grep -q "${name}"; then
                echo " >>> Creating micromamba environment '${name}' from ${file}..."
                micromamba create -q -n "${name}" -f "${file}" -y
              fi
              micromamba activate "${name}"
            fi
          ''
        else
          "";

      fhs = pkgs'.buildFHSEnv (
        passThroughAttrs
        // {
          name = "${name}-fhs-env";

          targetPkgs =
            _ps:
            nixglPkg
            ++ (resolvePkgs packages)
            ++ (resolvePkgs extraPackages)
            ++ accelConfig.packages
            ++ accelConfig.libraries.packages;

          multiPkgs = _: accelConfig.libraries.packages;

          profile = ''
            export MAMBA_ROOT_PREFIX="$HOME/.local/share/mamba"
            ${internal.exportEnv accelConfig.environment.variables}
            ${internal.hostGpuHook nixglhost}
            ${accelConfig.shellHook}
            eval "$(micromamba shell hook --shell bash)"
            ${fileHook}
            echo " >>> Micromamba FHS environment activated [${accelConfig.name}]"
            ${profile}
          '';

          runScript = "bash";
        }
      );
    in
    {
      inherit fhs;
      env = fhs.env;
      passthru = passthru // {
        inherit fhs;
        config = accelConfig;
        p8n = {
          category = "python";
          flavor = "mamba";
          accelerator = accelConfig.name;
        };
      };
    };
}
