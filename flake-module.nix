# Flake-parts module
# ==================
args@{
  p8nLib ? null,
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
        if p8nLib != null then
          p8nLib
        else if inputs ? tue-p8n then
          inputs.tue-p8n.lib
        else
          import ./lib {
            inherit lib;
            inputs = inputs.self.inputs or inputs;
          };
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
            # Expose the library per-system bound to the current packages.
            _module.args.p8n = p8n-lib pkgs;

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
    };
in
if args ? flake-parts-lib then module args else module
