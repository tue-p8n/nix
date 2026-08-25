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
      name ? "uv-fhs-shell",
      packages ? (_ps: [ ]),
      extraPackages ? (_ps: [ ]),
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
      resolvedName =
        if name != "uv-fhs-shell" then
          name
        else
          "uv-fhs-${builtins.replaceStrings [ "." "cuda-" ] [ "_" "cuda" ] accelConfig.name}";
      passThroughAttrs = stripCustomArgs mkFHS args;

      fhs = pkgs'.buildFHSEnv (
        passThroughAttrs
        // {
          name = resolvedName;

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
            ++ accelConfig.packages
            ++ accelConfig.libraries.packages;

          profile = ''
            set -e

            ${internal.exportEnv accelConfig.environment.variables}
            ${internal.repoRootHook}
            ${internal.hostGpuHook nixglhost}
            ${accelConfig.shellHook}

            export UV_NO_SYNC=1
            export UV_LOCKED=1
            export UV_PYTHON_PREFERENCE=only-managed
            export UV_PYTHON_DOWNLOADS=auto
            export UV_PROJECT_ENVIRONMENT="$REPO_ROOT/.venvs/${resolvedName}"
            export VIRTUAL_ENV="$UV_PROJECT_ENVIRONMENT"

            # Colocate PyTorch JIT extension build artifacts inside the virtual
            # environment so deleting the venv automatically cleans up cached extensions.
            export TORCH_EXTENSIONS_DIR="''${TORCH_EXTENSIONS_DIR:-$REPO_ROOT/.venvs/${resolvedName}/torch_extensions}"

            echo " >>> UV FHS environment activated [${accelConfig.name}]"
            ${profile}
            set +e
          '';
        }
      );
    in
    {
      inherit fhs;
      env = fhs.env;
      passthru = passthru // {
        inherit fhs;
        config = accelConfig;
      };
    };
}
