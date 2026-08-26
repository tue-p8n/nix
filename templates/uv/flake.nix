{
  description = "A UV project with CUDA support, built natively with uv2nix, using tue-p8n/nix";

  nixConfig = {
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
      imports = [ tue-p8n.flakeModules.cuda ];
      systems = [ "x86_64-linux" ];

      perSystem =
        {
          p8n,
          ...
        }:
        let
          pyproject = p8n.uv.readProject {
            name = "my-research-project";
            workspaceRoot = ./.;
          };
        in
        {
          # Interactive development shell (editable local install by default)
          devShells.default = pyproject.mkShell {
            accelerator = "cuda";
          };

          # Pure Nix virtual environment
          packages.default = pyproject.mkVenv {
            accelerator = "cuda";
          };

          # Apptainer SIF container ready for HPC cluster execution
          packages.sif = pyproject.mkSIF {
            accelerator = "cuda";
          };
        };
    };
}
