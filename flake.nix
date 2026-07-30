{
  description = "tue-p8n";

  nixConfig = {
    extra-substituters = [
      "https://nix-community.cachix.org"
      "https://cache.nixos-cuda.org"
    ];
    extra-trusted-public-keys = [
      "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
      "cache.nixos-cuda.org:74DUi4Ye579gUqzH4ziL9IyiJBlDpMRn9MBN8oNan9M="
    ];
  };

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";

    # Flake framework
    flake-parts.url = "github:hercules-ci/flake-parts";

    # Formatter
    treefmt.url = "github:numtide/treefmt-nix";

    # Pre-commit hooks
    git-hooks.url = "github:cachix/git-hooks.nix";
    git-hooks.inputs.nixpkgs.follows = "nixpkgs";

    # NixGL
    nix-gl-host.url = "github:numtide/nix-gl-host";
    nix-gl-host.inputs.nixpkgs.follows = "nixpkgs";

    # Python
    pyproject-nix = {
      url = "github:pyproject-nix/pyproject.nix";
      inputs = {
        nixpkgs.follows = "nixpkgs";
      };
    };
    pyproject-build-systems = {
      url = "github:pyproject-nix/build-system-pkgs";
      inputs = {
        pyproject-nix.follows = "pyproject-nix";
        uv2nix.follows = "uv2nix";
        nixpkgs.follows = "nixpkgs";
      };
    };
    uv2nix = {
      url = "github:pyproject-nix/uv2nix";
      inputs = {
        pyproject-nix.follows = "pyproject-nix";
        nixpkgs.follows = "nixpkgs";
      };
    };
  };

  outputs =
    inputs@{
      self,
      flake-parts,
      ...
    }:
    flake-parts.lib.mkFlake { inherit inputs; } {
      imports = [
        inputs.git-hooks.flakeModule
        inputs.treefmt.flakeModule
      ];

      systems = [
        "x86_64-linux"
      ];

      flake = {
        lib = import ./lib { inherit inputs; };
        flakeModule = import ./flake-module.nix;
        templates = {
          uv = {
            path = ./templates/uv;
            description = "UV-based Python project with CUDA support and Conda-compatible environment.";
          };
          micromamba = {
            path = ./templates/micromamba;
            description = "Micromamba project with Conda-compatible environment.";
          };
          latex = {
            path = ./templates/latex;
            description = "LaTeX project with document builder and shell";
          };
          typst = {
            path = ./templates/typst;
            description = "Typst project with document builder and shell";
          };
        };
      };

      perSystem =
        {
          self',
          config,
          system,
          pkgs,
          ...
        }:
        {
          # CUDA support requires unfree packages and forward-compat.
          _module.args.pkgs = import self.inputs.nixpkgs {
            inherit system;
            config = {
              # Set `cudaCapabilities = ["8.6" …];` to restrict per-arch builds.
              cudaForwardCompat = true;
              cudaSupport = true;
              allowUnfree = true;
            };
            # Without this, nixpkgs reads ~/.config/nixpkgs/overlays.nix /
            # $NIXPKGS_OVERLAYS impurely, so two machines could silently get
            # different `pkgs` from the identical flake.
            overlays = [ ];
          };

          # Development shells
          devShells = {
            default = pkgs.mkShell {
              name = "tue-p8n";
              packages = with pkgs; [
                cacert
              ];
              env = { };
              shellHook = "";
            };
          }
          // (import ./shells {
            inherit inputs pkgs;
          });

          # Packages
          packages = {
            # Curated OCI containers
            oci-pytorch2_8_0-cuda12_9-cudnn9-devel = pkgs.dockerTools.pullImage (
              self.lib.getContainer "pytorch/pytorch:2.8.0-cuda12.9-cudnn9-devel"
            );
          };

          # Treefmt enables formatting of multiple languages through `nix fmt`.
          # This configuration enables multiple formatters and linters, and is
          # intended as an opinionated starting point beyond the languages used in
          # this repository.
          treefmt = {
            programs = {
              ruff = {
                enable = true;
                check = true;
                format = true;
              };
              shellcheck.enable = true;
            };
            settings = {
              formatter = {
                shellcheck.options = [
                  "-s"
                  "bash"
                ];
                ruff-check.priority = 1;
                ruff-check.options = [ "--fix-only" ];
                ruff-format.priority = 2;
              };
            };
          };

          # Checks
          checks = import ./tests {
            inherit pkgs inputs;
          };
        };
    };
}
