# Base Flake-parts module
# ========================
args@{
  ...
}:
let
  module =
    {
      inputs,
      lib,
      flake-parts-lib,
      ...
    }:
    let
      p8n-lib =
        if args ? p8nLib && args.p8nLib != null then
          args.p8nLib
        else if inputs ? tue-p8n then
          inputs.tue-p8n.lib
        else
          import ../lib {
            inherit lib inputs;
          };
    in
    {
      options.perSystem = flake-parts-lib.mkPerSystemOption (
        {
          pkgs,
          ...
        }:
        {
          config = {
            # Expose the library per-system bound to the current packages.
            _module.args.p8n = p8n-lib pkgs;
          };
        }
      );

      config.flake.nixConfig = {
        extra-substituters = [
          "https://tue-p8n.cachix.org"
          "https://cache.nixos-cuda.org"
          "https://nix-community.cachix.org"
        ];
        extra-trusted-public-keys = [
          "tue-p8n.cachix.org-1:OshT9P6F/UKw2M+vS11uEqih37k/hYF8K3RtIKrZfJs="
          "cache.nixos-cuda.org:74DUi4Ye579gUqzH4ziL9IyiJBlDpMRn9MBN8oNan9M="
          "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
        ];
      };
    };
in
if args ? flake-parts-lib then module args else module
