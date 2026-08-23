{
  lib,
  pkgs,
  config,
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
  mkOCI =
    {
      name,
      venv,
      tag ? "latest",
      accelerator ? "cuda",
      pkgs ? defaultPkgs,
      packages ? [ ],
      extraPackages ? [ ],
      extraLibs ? [ ],
      env ? { },
      cmd ? [ "${venv}/bin/python" ],
      entrypoint ? null,
      maxLayers ? 120,
      passthru ? { },
      ...
    }@args:
    let
      accelConfig = config.build pkgs accelerator;
      pkgs' = accelConfig.pkgs;
      libPath = pkgs'.lib.makeLibraryPath (accelConfig.libraries.packages ++ extraLibs);
      passThroughAttrs = stripCustomArgs mkOCI args;

      baseContents =
        with pkgs';
        [
          dockerTools.binSh
          dockerTools.caCertificates
          coreutils
          bashInteractive
        ]
        ++ accelConfig.packages
        ++ [ venv ]
        ++ packages
        ++ extraPackages;
    in
    pkgs'.dockerTools.buildLayeredImage (
      passThroughAttrs
      // {
        inherit name tag maxLayers;
        contents = baseContents;

        fakeRootCommands = ''
          mkdir -m 1777 tmp
        '';

        config = {
          Cmd = cmd;
          Entrypoint = entrypoint;
          Env = [
            "PATH=${lib.makeBinPath baseContents}:/bin:/usr/bin"
            "LD_LIBRARY_PATH=${libPath}"
            "SSL_CERT_FILE=${pkgs'.cacert}/etc/ssl/certs/ca-bundle.crt"
            "NIX_SSL_CERT_FILE=${pkgs'.cacert}/etc/ssl/certs/ca-bundle.crt"
            "TORCH_EXTENSIONS_DIR=/tmp/.torch-extensions"
            "CUDA_VISIBLE_DEVICES=all"
            "VIRTUAL_ENV=${venv}"
            "UV_PYTHON=${venv}/bin/python"
          ] ++ (lib.mapAttrsToList (k: v: "${k}=${v}") (accelConfig.environment.variables // env));
        };

        passthru = passthru // {
          inherit venv;
          config = accelConfig;
        };
      }
    );

  mkDocker = mkOCI;
}
