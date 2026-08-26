# tue-p8n/nix

This repository provides a centralized collection of Nix flakes designed to create
standardized and reproducible research environments, specifically tailored for
Machine Learning and Computer Vision projects.

## Overview

This project abstracts the complexity of hardware accelerators and environment
management into a clean, modular library.

### Key Features

- **Hardware Abstraction**: Unified support for **CPU**, **NVIDIA (CUDA)**, and **AMD (ROCM)**.
- **Bare Hardware Environments**: Standalone CUDA / ROCm compiler and runtime shells without Python (`p8n.accelerator.mkShell`, `p8n.accelerator.mkFHS`).
- **Python Environment Builders**:
  - **UV**: Modern, fast Python development with automatic Nix-LD host driver binding (`p8n.uv.mkShell`, `p8n.uv.mkFHS`, `p8n.uv.mkProject`).
  - **Micromamba**: Robust FHS-sandboxed Conda-compatible environments for legacy C++/CUDA dependencies (`p8n.mamba.mkFHS`).
- **Hybrid Runtimes**: Choose between **Native** shells with Nix-LD, **FHS** containers (max compatibility), or fully **Nix-native** environments built via [uv2nix](https://pyproject-nix.github.io/uv2nix/introduction.html) (hermetic, zero runtime `uv sync`).
- **Document Systems**: Pre-configured builders and shells for **LaTeX** and **Typst**.
- **DevShell Composition**: Conflict-free multi-toolchain devshell composition with automatic hardware accelerator and Python slot validation (`p8n.composeShells`).
- **OCI Containers**: Standardized PyTorch images for cluster deployment.

## Quick Start

### Bare Accelerator Shells (C++ / CUDA / ROCm)

```bash
# Enter a bare CUDA shell (nvcc, CUDA headers, GPU driver libraries, Nix-LD)
nix develop .#cuda
```

### Python Development (UV)

```bash
# Enter a UV shell with CUDA 13.0 support
nix develop .#uv-cuda13_0

# Enter a UV shell with CPU-only support
nix develop .#uv-cpu
```

### Python Development (Micromamba)

```bash
# Enter a Micromamba FHS environment with CUDA 12.9
nix develop .#mamba-fhs-py313cu129
```

### Document Creation

```bash
# Enter a LaTeX environment
nix develop .#latex

# Enter a Typst environment
nix develop .#typst
```

## Creating a New Project from a Template

Use `nix flake init` to scaffold a new project:

```bash
# UV Python project (native uv2nix build and interactive devShell)
mkdir my-project && cd my-project
nix flake init -t github:tue-p8n/nix#uv
git init && git add .
nix develop

# Micromamba Conda-based project (FHS environment)
nix flake init -t github:tue-p8n/nix#micromamba

# LaTeX paper
nix flake init -t github:tue-p8n/nix#latex

# Typst paper
nix flake init -t github:tue-p8n/nix#typst
```

Each template directory contains its own `README.md` with further guidance.

## Pinning nixpkgs in Downstream Flakes

To keep your downstream project in sync with the organisation's pinned `nixpkgs`
(and avoid duplicating the large closure), add the following to your `flake.nix`:

```nix
inputs = {
  tue-p8n.url = "github:tue-p8n/nix";
  # Follow the central pin — do NOT set nixpkgs.url separately.
  nixpkgs.follows = "tue-p8n/nixpkgs";
};
```

## Using the Library in a Downstream Flake

### With `flake-parts` (Recommended)

When using `flake-parts`, import the desired `tue-p8n.flakeModules`. The library helper `p8n` is automatically injected into `perSystem`:

```nix
{
  inputs = {
    tue-p8n.url = "github:tue-p8n/nix";
    nixpkgs.follows = "tue-p8n/nixpkgs";
    flake-parts.follows = "tue-p8n/flake-parts";
  };

  outputs = inputs@{ flake-parts, tue-p8n, ... }:
    flake-parts.lib.mkFlake { inherit inputs; } {
      # Use `tue-p8n.flakeModules.cuda` for GPU projects, or `default` for CPU/LaTeX/Typst
      imports = [
        tue-p8n.flakeModules.cuda
        tue-p8n.flakeModules.formatting # Optional: opinionated treefmt + pre-commit hooks
      ];
      systems = [ "x86_64-linux" ];

        # 1. Interactive UV development shell (dynamic uv add / uv sync)
        devShells.uv-shell = p8n.uv.mkShell {
          accelerator = "cuda12_9";
          extraPackages = [ pkgs.just ];
        };

        # 2. Pure Nix virtualenv & HPC Container Images via readProject
        let
          pyproject = p8n.uv.readProject {
            name = "my-project";
            workspaceRoot = ./.;
          };
        in
        {
          devShells.default = pyproject.mkShell {
            accelerator = "cuda12_9"; # Editable local install by default
          };
          packages.default = pyproject.mkVenv {
            accelerator = "cuda12_9";
          };
          packages.docker = pyproject.mkOCI {
            accelerator = "cuda12_9";
          };
          packages.sif = pyproject.mkSIF {
            accelerator = "cuda12_9"; # Ready for Snellius/Apptainer HPC!
          };
        };

        # 3. Paper compilation
        packages.paper = p8n.latex.mkDocument {
          name = "paper";
          src = ./paper;
        };
      };
    };
}
```

### Without `flake-parts` (Vanilla Flake)

```nix
{
  inputs = {
    tue-p8n.url = "github:tue-p8n/nix";
    nixpkgs.follows = "tue-p8n/nixpkgs";
  };

  outputs = { self, nixpkgs, tue-p8n, ... }:
    let
      system = "x86_64-linux";
      pkgs = import nixpkgs {
        inherit system;
        config = { cudaSupport = true; cudaForwardCompat = true; allowUnfree = true; };
        overlays = [ ];
      };
      p8n = tue-p8n.lib pkgs;
    in
    {
      devShells.${system}.default = p8n.uv.mkShell {
        name = "my-project";
        accelerator = "cuda";
      };
    };
}
```

See [`docs/api.md`](docs/api.md) for the full library API reference.

## HPC Deployment (Snellius / Apptainer)

We provide builders for both **Apptainer/Singularity SIF files** and **layered OCI/Docker archives** ready for HPC clusters:

### 1. Build an Apptainer SIF container directly

```bash
# Build from your project (p8n.uv.readProject or p8n.container.mkSIF)
nix build .#sif
# Generates ./result, which is the self-contained .sif image
```

### 2. Transfer and Run on Cluster

```bash
# On Snellius / compute node with host GPU drivers
apptainer run --nv ./result train.py --epochs 100
```

_Note: The `--nv` flag is essential to enable NVIDIA GPU acceleration inside the container._

## Repository Structure

- `lib/`: Core library logic.
  - `config/`: Hardware acceleration definitions and configuration module (`resolve`, `build`).
  - `accelerator/`: Bare hardware acceleration devShells and FHS builders (`mkShell`, `mkFHS`).
  - `uv/`: UV Python builders (`mkShell`, `mkFHS`, `mkProject`, `mkOCI`).
  - `mamba/`: Micromamba FHS environment builder (`mkFHS`).
  - `container/`: Container registry utilities and SIF converters (`get`, `mkSIF` / `mkApptainer`).
  - `latex.nix`, `typst.nix`: Document building utilities (`mkShell`, `mkDocument`).
  - `compose-shells.nix`: Devshell composition and toolchain conflict validation engine (`composeShells`).
- `templates/`: Project templates (`uv`, `micromamba`, `latex`, `typst`).
- `tests/`: Unit, derivation, and smoke tests run by `nix flake check`.
- `docs/`: API reference and guides.

## Continuous Integration

Two workflows split the checks by what a failure means:

- `CI` evaluates every flake output and builds all checks on CPU. Runs on every push and pull request.
- `Environments` builds the CUDA, ROCm, and TeX Live shells. Runs when the lockfile changes, weekly, and on demand.

## Binary Cache

Public caches carry only the default CUDA version, so this project publishes the rest to `tue-p8n.cachix.org`. Without it, non-default CUDA versions compile NCCL from source.

Add it to `nix.conf` or consuming flake's `nixConfig`:

```
extra-substituters = https://tue-p8n.cachix.org
extra-trusted-public-keys = tue-p8n.cachix.org-1:OshT9P6F/UKw2M+vS11uEqih37k/hYF8K3RtIKrZfJs=
```

## License

MIT. See [LICENSE](LICENSE) for details.
