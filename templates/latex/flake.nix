{
  description = "A LaTeX project using tue-p8n/nix";

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
      imports = [ tue-p8n.flakeModule ];
      systems = [ "x86_64-linux" ];

      perSystem =
        { p8n, ... }:
        {
          devShells.default = p8n.latex.mkShell { };

          packages.default = p8n.latex.mkDocument {
            name = "my-latex-document";
            src = ./.;
          };
        };
    };
}
