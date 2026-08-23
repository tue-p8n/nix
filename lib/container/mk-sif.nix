{
  pkgs,
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
  mkSIF =
    {
      name,
      ociImage,
      pkgs ? defaultPkgs,
      passthru ? { },
      ...
    }@args:
    let
      passThroughAttrs = stripCustomArgs mkSIF args;
    in
    pkgs.stdenv.mkDerivation (
      passThroughAttrs
      // {
        name = "${name}.sif";
        nativeBuildInputs = [ pkgs.apptainer ];

        buildCommand = ''
          export HOME=$(mktemp -d)
          apptainer build $out docker-archive:${ociImage}
        '';

        passthru = passthru // {
          inherit ociImage;
        };
      }
    );

  mkApptainer = mkSIF;
}
