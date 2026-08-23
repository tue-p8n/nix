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
      imports = [ tue-p8n.flakeModule ];
      systems = [ "x86_64-linux" ];

      perSystem =
        {
          p8n,
          ...
        }:
        {
          p8n.nixpkgs.manage = true;
          p8n.nixpkgs.cuda.enable = true;

          # FHS shell (reliable compatibility for complex CUDA environments)
          devShells.default =
            (p8n.mamba.mkFHS {
              name = "my-micromamba-fhs";
              file = ./environment.yaml;
              accelerator = "cuda";
            }).env;
        };
    };
}
