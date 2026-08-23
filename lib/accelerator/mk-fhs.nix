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
      name ? "accelerator-fhs-shell",
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
      passThroughAttrs = stripCustomArgs mkFHS args;

      fhs = pkgs'.buildFHSEnv (
        passThroughAttrs
        // {
          inherit name;

          targetPkgs =
            ps:
            nixglPkg
            ++ (with ps; [
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
            ${internal.hostGpuHook nixglhost}
            ${accelConfig.shellHook}

            echo " >>> Accelerator FHS environment activated [${accelConfig.name}]"
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
