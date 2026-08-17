# tue-p8n/nix

This repository provides a centralized collection of Nix flakes designed to create
standardized and reproducible research environments, specifically tailored for
Machine Learning and Computer Vision projects.

## Overview

This project abstracts the complexity of hardware accelerators and environment
management into a clean, modular library.

### Key Features

- **Hardware Abstraction**: Unified support for **CPU**, **NVIDIA (CUDA)**, and **AMD (ROCM)**.
- **Environment Builders**:
  - **UV**: Modern, fast Python project management.
  - **Micromamba**: Reliable Conda-compatible environments for complex C++/CUDA dependencies.
- **Hybrid Runtimes**: Choose between **FHS** containers (max compatibility), **Native** shells with Nix-LD (native feel), or a fully **Nix-native** environment built via [uv2nix](https://pyproject-nix.github.io/uv2nix/introduction.html) (no runtime `uv sync`).
- **Document Systems**: Pre-configured builders and shells for **LaTeX** and **Typst**.
- **OCI Containers**: Standardized PyTorch images for deployment.

## Quick Start

### Python Development (UV)

```bash
# Enter a UV shell with the latest pinned CUDA support
nix develop .#uv-cuda13_0
```

### Python Development (Micromamba)

```bash
# Enter a Micromamba FHS environment
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
# UV Python project (native uv2nix build or devShell)
mkdir my-project && cd my-project
nix flake init -t github:tue-p8n/nix#uv
git init && git add .
nix develop

# Micromamba Conda-based project
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

Then use `tue-p8n.lib` to build your environments — all templates already do this.

## Using the Library in a Downstream Flake

```nix
{
  inputs = {
    tue-p8n.url = "github:tue-p8n/nix";
    nixpkgs.follows = "tue-p8n/nixpkgs";
  };

  outputs = { self, nixpkgs, tue-p8n, ... }:
    let
      system = builtins.currentSystem;
      pkgs = import nixpkgs {
        inherit system;
        config = { cudaSupport = true; cudaForwardCompat = true; allowUnfree = true; };
        overlays = [ ]; # explicit -- avoids nixpkgs reading local overlay files impurely
      };
      # Resolve environment for a given accelerator target:
      env = tue-p8n.lib.resolve { inherit pkgs; accelerator = "cuda"; };
    in
    {
      devShells.${system}.default = env.uv.mkShell {
        name = "my-project";
      };
    };
}
```

See [`docs/api.md`](docs/api.md) for the full library API reference.

## HPC Deployment (Snellius / Apptainer)

We provide OCI-compliant tarballs that are ready to run on HPC clusters using Apptainer (Singularity).

### 1. Build the image locally

```bash
nix build .#oci-pytorch2_8_0-cuda12_9-cudnn9-devel
```

### 2. Transfer and Run on Cluster

Transfer the `result` tarball to your cluster (e.g., via `rsync`). You can run it directly without conversion:

```bash
# On the login or compute node
apptainer run --nv docker-archive://path/to/result
```

_Note: The `--nv` flag is essential to enable NVIDIA GPU acceleration inside the container._

## Repository Structure

- `lib/`: Core library logic.
  - `default.nix`: Main entry point exposing `resolve`, `accelerators`, `getContainer`, and module wrappers.
  - `uv/`, `mamba/`: Environment builders (`mkShell`, `mkFHS`, `mkProject`).
  - `latex.nix`, `typst.nix`: Document building utilities (`mkShell`, `mkDocument`).
  - `accelerators/`: Centralized hardware configuration (`cpu`, `cuda`, `rocm`).
- `shells/`: Exported development shell definitions.
- `templates/`: Project templates (`uv`, `micromamba`, `latex`, `typst`).
- `tests/`: Unit and smoke tests run by `nix flake check`.
- `docs/`: API reference and guides.

## Continuous Integration

Two workflows split the checks by what a failure means.

`CI` evaluates every flake output,
then builds the checks that run on CPU alone.
It runs on every push and pull request.
A failure points at the change under review.

`Environments` builds the CUDA, ROCm, and TeX Live shells,
one per matrix job.
It runs when the lockfile changes, weekly, and on demand.
A failure points at the pinned `nixpkgs`,
or at a change to the shell definitions themselves.

## Binary Cache

Public caches carry only the default CUDA version,
so this project publishes the rest to `tue-p8n.cachix.org`.
Without it, the other CUDA versions compile NCCL from source.

Add it to `nix.conf`,
or to a consuming flake's `nixConfig`:

```
extra-substituters = https://tue-p8n.cachix.org
extra-trusted-public-keys = tue-p8n.cachix.org-1:OshT9P6F/UKw2M+vS11uEqih37k/hYF8K3RtIKrZfJs=
```

`Environments` writes to it on every run.


## License

MIT. See [LICENSE](LICENSE) for details.
