# Flake-parts module
# ==================
# Consumers must arrange `_module.args.pkgs` with `cudaSupport`/`cudaForwardCompat`/
# `allowUnfree` themselves if they declare any CUDA shell.
{
  inputs,
  lib,
  flake-parts-lib,
  ...
}:
let
  tueLib = import ./lib { inherit lib inputs; };
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
        accelerator = {
          name = lib.mkOption {
            type = lib.nullOr lib.types.str;
            default = "cpu";
            example = "cuda12_9";
            description = ''
              Default accelerator selector for all dev shells and projects.
              `"cpu"` | `"cuda"` | `"cudaX_Y"` | `"rocm"`.
              ROCm has no version-pinned form -- only one toolchain exists per
              nixpkgs revision.
              Set to `null` to define the accelerator configuration manually via `config`.
            '';
          };
          config = lib.mkOption {
            type = lib.nullOr lib.types.attrs;
            default = -null;
            description = ''
              Resolved accelerator configuration. If `accelerator.name` is non-null, this is
              automatically derived from that. Otherwise, you can specify a custom
              accelerator configuration here. See `lib/accelerators/default.nix` for the
              expected structure.
              Set to `null` to disable automatic accelerator configuration. This will cause
              `p8n` not to be instantiated.
            '';
          };
        };
        cuda = {
          enable = lib.mkOption {
            type = lib.types.bool;
            default = false;
            description = ''
              Whether to automatically re-import `pkgs` for this system target with
              `cudaSupport = true`, `cudaForwardCompat = true`, and `allowUnfree = true`.
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

      config = {
        # Expose the library per-system bound to the current packages and default accelerator.
        _module.args.p8n = tueLib.build pkgs (
          if this.accelerator.name != null then
            this.accelerator.config
          else
            (tueLib.accelerators.resolve this.accelerator.name)
        );

        # CUDA support requires unfree packages and forward-compat.
        _module.args.pkgs = lib.mkIf this.cuda.enable (
          import inputs.nixpkgs {
            inherit system;
            config = {
              cudaSupport = true;
              cudaForwardCompat = true;
              allowUnfree = true;
            }
            // (lib.optionalAttrs (this.cuda.capabilities != null) {
              cudaCapabilities = this.cuda.capabilities;
            });

            # Without this, nixpkgs reads ~/.config/nixpkgs/overlays.nix /
            # $NIXPKGS_OVERLAYS impurely, so two machines could silently get
            # different `pkgs` from the identical flake.
            overlays = [ ];
          }
        );
      };
    }
  );
}
