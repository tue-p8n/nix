{
  self,
  lib,
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
      ...
    }@args:
    let
      inherit (self) config;
      inherit (config) pkgs;
      resolvePkgs = p: if builtins.isFunction p then p pkgs else p;

      nixglPkg = if pkgs ? nixglhost then [ pkgs.nixglhost ] else [ ];
      gpuHook = if pkgs ? nixglhost then shell.hostGpuHook pkgs.nixglhost else "";

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
    (pkgs.mkShell.override { stdenv = config.stdenv; }) (
      passThroughAttrs
      // {
        inherit name;

        packages = nixglPkg ++ (resolvePkgs packages) ++ (resolvePkgs extraPackages) ++ config.packages;

        env =
          config.environment.variables
          // {
            MAMBA_ROOT_PREFIX = "${builtins.getEnv "HOME"}/.local/share/mamba";
            LD_LIBRARY_PATH = "${lib.makeLibraryPath config.libraries.packages}";
          }
          // env;

        shellHook = ''
          ${shell.exportEnv config.environment.variables}
          ${gpuHook}
          ${config.shellHook}
          eval "$(micromamba shell hook --shell bash)"
          ${fileHook}
          echo "Micromamba shell activated [${config.name}]"
          ${shellHook}
        '';

        passthru = passthru // {
          accelConfig = config;
        };
      }
    );
}
