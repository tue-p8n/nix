# CUDA Flake-parts module
# ========================
{
  inputs,
  lib,
  flake-parts-lib,
  ...
}:
{
  imports = [ ./default.nix ];

  options.perSystem = flake-parts-lib.mkPerSystemOption (
    { ... }:
    {
      options.p8n.cuda.capabilities = lib.mkOption {
        type = lib.types.nullOr (lib.types.listOf lib.types.str);
        default = null;
        example = [
          "8.6"
          "8.9"
        ];
        description = ''
          Optionally specify target CUDA compute capabilities (e.g., `["8.6" "8.9"]`)
          to restrict builds to specific GPU architectures and speed up compilation.
          If `null`, nixpkgs builds for all standard supported capabilities.
        '';
      };
    }
  );

  config.perSystem =
    {
      config,
      system,
      ...
    }:
    {
      _module.args.pkgs = import inputs.nixpkgs {
        inherit system;
        config =
          {
            cudaSupport = true;
            cudaForwardCompat = true;
            allowUnfree = true;
          }
          // (lib.optionalAttrs (config.p8n.cuda.capabilities != null) {
            cudaCapabilities = config.p8n.cuda.capabilities;
          });

        overlays = [ ];
      };
    };
}
