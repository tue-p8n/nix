{
  description = "A Micromamba project using tue-p8n/nix";

  inputs = {
    tue-p8n.url = "github:tue-p8n/nix";
    flake-parts.follows = "tue-p8n/flake-parts";

    # Use the `nixpkgs` from `tue-p8n/nix` by default.
    nixpkgs.follows = "tue-p8n/nixpkgs";

    # Alternatively, you can use the `nixpkgs` from `nixos/nixpkgs` directly.
    # nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    # tue-p8n.nixpkgs.follows = "nixpkgs";
  };

  outputs =
    inputs@{
      flake-parts,
      tue-p8n,
      ...
    }:
    flake-parts.lib.mkFlake { inherit inputs; } {
      systems = [ "x86_64-linux" ];

      perSystem =
        {
          system,
          pkgs,
          ...
        }:
        let
          mamba = tue-p8n.lib.micromamba { inherit pkgs; };
        in
        {
          _module.args.pkgs = import inputs.nixpkgs {
            inherit system;
            config = {
              cudaForwardCompat = true;
              cudaSupport = true;
              allowUnfree = true;
            };
            overlays = [ ];
          };

          # Native shell (requires nix-ld on NixOS).
          devShells.default = mamba.mkShell {
            name = "my-micromamba-env";
            file = ./environment.yaml;
            accelerator = "cuda";
          };

          # FHS shell (maximum compatibility for complex CUDA build steps).
          devShells.fhs =
            (mamba.mkFHS {
              name = "my-micromamba-fhs";
              file = ./environment.yaml;
              accelerator = "cuda";
            }).env;
        };
    };
}
