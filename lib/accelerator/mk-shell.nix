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
  mkShell =
    {
      accelerator ? "cpu",
      pkgs ? defaultPkgs,
      name ? null,
      packages ? (_ps: [ ]),
      extraPackages ? (_ps: [ ]),
      env ? { },
      shellHook ? "",
      passthru ? { },
      ...
    }@args:
    let
      accelConfig = config.build pkgs accelerator;
      pkgs' = accelConfig.pkgs;
      resolvePkgs = p: if builtins.isFunction p then p pkgs' else p;

      nixglhost = pkgs'.nixglhost or null;
      libPath = pkgs'.lib.makeLibraryPath accelConfig.libraries.packages;
      passThroughAttrs = stripCustomArgs mkShell args;
    in
    (pkgs'.mkShell.override { inherit (accelConfig) stdenv; }) (
      passThroughAttrs
      // {
        name =
          if name != null then
            name
          else
            "accelerator-${builtins.replaceStrings [ "." "cuda-" ] [ "_" "cuda" ] accelConfig.name}";

        packages =
          accelConfig.packages
          ++ (if nixglhost != null then [ nixglhost ] else [ ])
          ++ (resolvePkgs packages)
          ++ (resolvePkgs extraPackages);

        env = accelConfig.environment.variables // env;

        shellHook = ''
          ${internal.nixLdHook pkgs' libPath}

          export LIBRARY_PATH="${libPath}:$LIBRARY_PATH"
          export LD_LIBRARY_PATH="${libPath}:$LD_LIBRARY_PATH"

          ${internal.exportEnv accelConfig.environment.variables}
          ${internal.hostGpuHook nixglhost}
          ${accelConfig.shellHook}

          echo " >>> Accelerator shell activated [${accelConfig.name}]"
          ${shellHook}
        '';

        passthru = passthru // {
          config = accelConfig;
        };
      }
    );
}
