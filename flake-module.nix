# Flake-parts module
# ==================
# CUDA pkgs re-import (cudaSupport / allowUnfree / cudaCapabilities) is handled
# automatically by the accelerator module whenever a CUDA accelerator is selected.
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
      system,
      ...
    }:
    let
      p8n = p8n-lib.build system (
        if config.p8n.accelerator.name != null then
          (p8n-lib.accelerators.resolve config.p8n.accelerator.name)
        else
          config.p8n.accelerator.config
      );

    in
    {
      options.p8n = {
        accelerator = {
          name = lib.mkOption {
            type = lib.types.nullOr lib.types.str;
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
            type = lib.types.nullOr lib.types.attrs;
            default = null;
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
      };

      config = {
        # p8n is built from `system` (not from `pkgs`), so assigning pkgs here
        # is safe — there is no circular dependency.
        _module.args.p8n = p8n;
        _module.args.pkgs = p8n.config.pkgs;
      };
    }
  );
}
