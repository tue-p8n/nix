{
  description = "A UV project with CUDA support, built natively with uv2nix, using tue-p8n/nix";

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

      perSystem = { system, ... }: {
        # CUDA support requires unfree packages and forward-compat.
        _module.args.pkgs = import inputs.nixpkgs {
          inherit system;
          config = {
            cudaForwardCompat = true;
            cudaSupport = true;
            allowUnfree = true;
          };
          overlays = [ ];
        };

        tue-p8n.uv.uv2nix.default = {
          name = "my-research-project";
          workspaceRoot = ./.;
          accelerator = "cuda";
        };
        # Alternatively, use an FHS-based shell, with is more compatible with some
        # Python packages.
        # tue-p8n.uv.shells.default = {
        #   name = "my-research-project";
        #   accelerator = "cuda";
        # };
      };
    };
}
