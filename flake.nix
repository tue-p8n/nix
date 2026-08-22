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
        ./flake-module.nix
      ];

      systems = [
        "x86_64-linux"
      ];

      flake = {
        lib = import ./lib { inherit inputs; lib = inputs.nixpkgs.lib; };

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
          config,
          pkgs,
          p8n,
          ...
        }:
        {
          # Development shells
          devShells = {
            default = pkgs.mkShell {
              name = "tue-p8n";
              packages =
                with pkgs;
                [
                  cacert
                  config.pre-commit.settings.package
                ]
                ++ config.pre-commit.settings.enabledPackages;
              env = { };
              shellHook = config.pre-commit.installationScript;
            };

            mamba-py313cu129 = (p8n.withAccelerator "cuda12_9").mamba.mkShell {
              name = "mamba-py313cu129";
            };
            cuda = (p8n.withAccelerator "cuda").uv.mkShell { name = "cuda"; };
            latex = (p8n.withAccelerator "cpu").latex.mkShell { };
            typst = (p8n.withAccelerator "cpu").typst.mkShell { };

            uv-cpu = (p8n.withAccelerator "cpu").uv.mkShell { };
            uv-cuda12_6 = (p8n.withAccelerator "cuda12_6").uv.mkShell { };
            uv-cuda13_0 = (p8n.withAccelerator "cuda13_0").uv.mkShell { };
            uv-rocm = (p8n.withAccelerator "rocm").uv.mkShell { };

            mamba-fhs-py313cu128 =
              ((p8n.withAccelerator "cuda12_8").mamba.mkFHS { name = "mamba-fhs-py313cu128"; }).env;
            mamba-fhs-py313cu129 =
              ((p8n.withAccelerator "cuda12_9").mamba.mkFHS { name = "mamba-fhs-py313cu129"; }).env;
          };

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
              clang-format.enable = true;
              clang-tidy.enable = true;
              deadnix.enable = true;
              ruff.check = true;
              ruff.format = true;
              shellcheck.enable = true;
              shfmt.enable = true;
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

          # Pre-commit
          pre-commit.settings = {
            package = pkgs.prek;
            hooks = {
              treefmt = {
                enable = true;
                package = config.treefmt.build.wrapper;
              };
              check-toml.enable = true;
              check-yaml.enable = true;
              check-json.enable = true;
              check-merge-conflicts.enable = true;
              check-added-large-files.enable = true;
              end-of-file-fixer.enable = true;
              trim-trailing-whitespace = {
                enable = true;
                args = [ "--markdown-linebreak-ext=md" ];
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
