# Flake-parts module
# ==================
{
  inputs,
  lib,
  flake-parts-lib,
  ...
}:
let
  p8n-lib = import ./lib { inherit lib inputs; };
in
{
  options.perSystem = flake-parts-lib.mkPerSystemOption (
    {
      config,
      pkgs,
      system,
      ...
    }:
    let
      this = config.p8n;
    in
    {
      options.p8n = {
        config = lib.mkOption {
          type = lib.types.nullOr lib.types.attrs;
          default = p8n-lib.accelerators.resolve "cpu";
          example = lib.literalExpression ''
            p8n-lib.accelerators.resolve "cuda12_9"
          '';
          description = ''
            Accelerator configuration object for dev shells and projects.
            Typically constructed via `tueLib.accelerators.resolve "cuda12_9"` or
            as an explicit attribute set.
            Set to `null` to disable automatic library instantiation in `_module.args.p8n`.
          '';
        };

        nixpkgs = {
          manage = lib.mkOption {
            type = lib.types.bool;
            default = false;
            example = true;
            description = ''
              Whether to override `_module.args.pkgs` with a customized Nixpkgs package set
              (e.g., configuring CUDA support).
            '';
          };

          cuda = {
            enable = lib.mkOption {
              type = lib.types.bool;
              default = false;
              description = ''
                Whether to configure `pkgs` with `cudaSupport = true`, `cudaForwardCompat = true`,
                and `allowUnfree = true` when `p8n.nixpkgs.manage` is enabled.
              '';
            };

            capabilities = lib.mkOption {
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
          };
        };
      };

      config = {
        # Expose the library per-system bound to the current packages and default accelerator.
        _module.args.p8n = lib.mkIf (this.config != null) (
          p8n-lib.build pkgs this.config
        );

        _module.args.pkgs = lib.mkIf this.nixpkgs.manage (
          import inputs.nixpkgs {
            inherit system;
            config =
              (lib.optionalAttrs this.nixpkgs.cuda.enable {
                cudaSupport = true;
                cudaForwardCompat = true;
                allowUnfree = true;
              })
              // (lib.optionalAttrs (this.nixpkgs.cuda.capabilities != null) {
                cudaCapabilities = this.nixpkgs.cuda.capabilities;
              });

            overlays = [ ];
          }
        );
      };
    }
  );
}
