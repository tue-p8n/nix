# Library API Reference & Cookbooks

This page documents the complete public API and use-case cookbooks exported by `github:tue-p8n/nix`.

---

## Table of Contents
1. [Accessing the Library](#accessing-the-library)
2. [Accelerator Selectors](#accelerator-selectors)
3. [Module API Reference](#module-api-reference)
   - [`p8n.accelerator` (Bare C++/CUDA/ROCm Toolchains)](#p8naccelerator-module)
   - [`p8n.uv` (UV & uv2nix Python Development)](#p8nuv-module)
   - [`p8n.mamba` (Micromamba FHS Environments)](#p8nmamba-module)
   - [`p8n.container` (Apptainer/SIF & OCI Images)](#p8ncontainer-module)
   - [`p8n.latex` & `p8n.typst` (Paper Documents)](#p8nlatex--p8ntypst-modules)
   - [`p8n.composeShells` (DevShell Composition)](#p8ncomposeshells)
   - [`p8n.config` (Hardware Engine)](#p8nconfig-module)
4. [Use-Case Cookbooks & Examples](#use-case-cookbooks--examples)
   - [Cookbook 1: Pure-Nix Python Project with SIF & OCI Output (`uv.mkProject`)](#cookbook-1-pure-nix-python-project-with-sif--oci-output)
   - [Cookbook 2: Interactive Fast Prototyping Shell (`uv.mkShell`)](#cookbook-2-interactive-fast-prototyping-shell)
   - [Cookbook 3: Bare CUDA / C++ Development Shell](#cookbook-3-bare-cuda--c-development-shell)
   - [Cookbook 4: Micromamba Conda Environment](#cookbook-4-micromamba-conda-environment)
   - [Cookbook 5: HPC Cluster Deployment & SLURM Integration](#cookbook-5-hpc-cluster-deployment--slurm-integration)
   - [Cookbook 6: Building SIF Containers from Curated Registry Images](#cookbook-6-building-sif-containers-from-curated-registry-images)
   - [Cookbook 7: Advanced uv2nix Overrides (C++/CUDA Extensions)](#cookbook-7-advanced-uv2nix-overrides-ccuda-extensions)
   - [Cookbook 8: Writing Academic Papers (LaTeX & Typst)](#cookbook-8-writing-academic-papers-latex--typst)
   - [Cookbook 9: Composing Multi-Environment Shells (Python + LaTeX)](#cookbook-9-composing-multi-environment-shells)
   - [Cookbook 10: Extending the Library via `p8n.extend`](#cookbook-10-extending-the-library-via-p8nextend)
5. [`flakeModule` Options Reference](#flakemodule-configuration-options)

---

## Accessing the Library

### In `flake-parts` (Recommended)

When using `flake-parts`, import the desired `tue-p8n.flakeModules` (`default`, `cuda`, `formatting`). The library instance is automatically bound to `pkgs` and injected as `p8n` into `perSystem`:

```nix
{
  inputs = {
    tue-p8n.url = "github:tue-p8n/nix";
    nixpkgs.follows = "tue-p8n/nixpkgs";
    flake-parts.follows = "tue-p8n/flake-parts";
  };

  outputs = inputs@{ flake-parts, tue-p8n, ... }:
    flake-parts.lib.mkFlake { inherit inputs; } {
      # Use `cuda` for GPU projects, or `default` for CPU/LaTeX/Typst
      imports = [
        tue-p8n.flakeModules.cuda
        tue-p8n.flakeModules.formatting
      ];
      systems = [ "x86_64-linux" ];

      perSystem = { pkgs, p8n, ... }: {
        devShells.default = p8n.uv.mkShell {
          accelerator = "cuda12_9";
        };
      };
    };
}
```

### In Vanilla Flakes

Instantiate the library by passing your evaluated `pkgs` set to `tue-p8n.lib`:

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
      p8n = tue-p8n.lib pkgs; # or tue-p8n.lib.build pkgs
    in
    {
      devShells.${system}.default = p8n.uv.mkShell {
        accelerator = "cuda12_9";
      };
    };
}
```

---

## Accelerator Selectors

Every builder accepting an `accelerator` argument supports either a selector string or an explicit configuration attribute set:

| Selector                        | Meaning                                                |
| ------------------------------- | ------------------------------------------------------ |
| `"cpu"`                         | CPU-only (default)                                     |
| `"cuda"`                        | NVIDIA CUDA, **default** version of the pinned nixpkgs |
| `"cudaX_Y"` (e.g. `"cuda12_9"`) | NVIDIA CUDA pinned to a specific major.minor           |
| `"rocm"`                        | AMD ROCm toolchain                                     |

- **CPU-only**: `accelerator = "cpu"` uses the provided `pkgs` instance **as-is**, without overriding CUDA/ROCm flags or injecting hardware driver hooks.
- **Pinning CUDA Versions**: `accelerator = "cuda12_6"` switches the shell to a `pkgs` instance where `cudaPackages` defaults to 12.6 using nixpkgs' `cudaPackages_X_Y.pkgs` rescoping. CUDA-aware libraries (`cudnn`, `nccl`, `libcublas`) are rebuilt against the chosen CUDA version while non-CUDA tools are reused.
- **ROCm Selection**: ROCm toolchains do not support version sub-pinning in nixpkgs. Pass `"rocm"`.

---

## Module API Reference

### `p8n.accelerator` Module

Creates bare development environments with CUDA/ROCm compilers, GPU driver libraries, and Nix-LD/FHS without Python, UV, or Conda.

#### `p8n.accelerator.mkShell { accelerator?, name?, packages?, extraPackages?, env?, shellHook?, passthru? }`
- **`accelerator`** (`string | attrs`, default `"cpu"`): Target hardware accelerator.
- **`name`** (`string | null`, default `null`): Shell derivation name.
- **`packages` / `extraPackages`** (`[drv] | (pkgs -> [drv])`, default `[]`): Additional tools.
- **`env`** (`attrs`, default `{}`): Environment variables.
- **`shellHook`** (`string`, default `""`): Bash commands executed on entry.

#### `p8n.accelerator.mkFHS { accelerator?, name?, packages?, extraPackages?, profile?, passthru? }`
Creates a `buildFHSEnv` sandbox for standalone C++/CUDA tools that require a traditional `/usr/lib` layout.

---

### `p8n.uv` Module

Python environment builders powered by [uv](https://github.com/astral-sh/uv) and [uv2nix](https://pyproject-nix.github.io/uv2nix/).

#### `p8n.uv.mkShell { accelerator?, name?, packages?, extraPackages?, env?, shellHook?, passthru? }`
Interactive development shell with `uv`, compiler toolchains, `nix-ld` host GPU bindings, and `UV_TORCH_BACKEND` configured. Dependency resolution is performed interactively via runtime `uv sync`.

#### `p8n.uv.readProject (workspaceRoot | { workspaceRoot, name?, overlays?, missingBuildSystems?, crossWheelLinkingPackages?, extraLibs?, autoTorchBuildInputs?, extraTorchPackages?, excludeTorchPackages? })`
Inspects a UV project workspace once and returns an object exposing metadata, hardware inference, and specialized target builders:

- **`.mkVenv { accelerator?, editable?, python?, extras?, overlays?, missingBuildSystems?, crossWheelLinkingPackages?, extraLibs?, autoTorchBuildInputs?, extraTorchPackages?, excludeTorchPackages? }`**:
  Builds a pure Nix Python virtual environment derivation.
  - `accelerator` (default `"cpu"`): Shorthand string (`"cpu"`, `"cuda"`, `"cuda12_8"`, `"rocm"`), config set, or resolver function (`project.inferAccelerator "torch"`).
  - `editable` (default `false`): When `false`, all packages (workspace members and dependencies) are built into immutable `/nix/store/` paths.
  - `overlays` (`[final: prev: ...] | (final: prev: ...)`, default `[]`): Custom Python scope overlays.
  - `extras` (`[string] | null`, default `null`): Python extras to enable. When `null`, automatically selects the backend extra from `accelerator` (e.g. `["cu129"]`, `["rocm"]`, `["cpu"]`).
  - `autoTorchBuildInputs` (`bool`, default `true`): Automatically detects C++/CUDA PyTorch extension packages built from source (sdists) that depend on `torch` and injects `prev.torch` into their `nativeBuildInputs` and `PYTHONPATH`.
  - `extraTorchPackages` (`[string]`, default `[]`): Additional package names to explicitly treat as requiring `torch` at build time.
  - `excludeTorchPackages` (`[string]`, default `[]`): Package names to exclude from automatic `torch` build input injection (opt-out).

- **`.mkShell { accelerator?, editable?, python?, extras?, packages?, extraPackages?, env?, shellHook?, preCommit?, overlays?, autoTorchBuildInputs?, extraTorchPackages?, excludeTorchPackages? }`**:
  Builds an interactive development shell derivation (`nix develop`).
  - `editable` (default `true`): Automatically installs local workspace packages in PEP 660 editable mode linked to `$REPO_ROOT`, allowing live edits without rebuilds.

- **`.pythonSet { accelerator?, python?, extras?, overlays?, ... }`**:
  Exposes the underlying resolved `pyproject.nix` / `uv2nix` package set for ad-hoc overrides or custom derivations.

- **`.mkOCI { accelerator?, editable?, tag?, packages?, extraPackages?, extraLibs?, env?, cmd?, entrypoint?, maxLayers?, venv? }`**:
  Builds a layered OCI/Docker container image derivation using `dockerTools.buildLayeredImage`.
  - `editable` (default `false`): When `false`, self-contained image ready for distribution. Can be set to `true` for development containers with volume bind mounts.

- **`.mkSIF { accelerator?, editable?, pkgs?, ... }`**:
  Builds an Apptainer / Singularity `.sif` image derivation ready for HPC cluster execution (e.g. on Snellius with `apptainer run --nv`).

- **`.inferAccelerator (package? | { package?, extras? })`**:
  Automatically analyzes the locked dependency graph in `uv.lock` for the target package (defaults to `"torch"`), inspecting `cuda-toolkit`, `cuda-bindings`, `rocm-core`, and wheel tags. Returns a typed accelerator config set.

- **Built-in Auto-Fixups**:
  - **Auto-Torch Build Systems**: Automatically resolves and provides `torch` during build/compilation for any PyPI sdist or workspace dependency that depends on PyTorch (e.g. `torchmatch`, `torch-scatter`, `flash-attn`, `deformable-convolution`).
  - **OpenCV Collisions**: Automatically resolves `site-packages/cv2` conflicts when both GUI (`opencv-python`) and headless (`opencv-python-headless`) packages exist in dependencies.
  - **Missing Build Systems**: Automatically injects missing build dependencies (`setuptools`, `wheel`) for legacy sdists, and handles `torch` in custom `missingBuildSystems`.
  - **Cross-Wheel Dynamic Linking**: Patchelf auto-ignore rules for packages that dynamically link across separate wheels (`torch`, `nvidia-*`, `torchvision`, `triton`, `xformers`, `deformops`, `torchmatch`).
  - **Numba TBB**: Automatically links Intel TBB for multi-core performance.

#### `p8n.uv.mkProject`
Compatibility helper that delegates directly to `(p8n.uv.readProject args).mkShell { }`.

#### `p8n.uv.inferAccelerator (package | { workspaceRoot, package?, extras? })`
Standalone helper that can be called directly or passed as a resolver function to `accelerator = p8n.uv.inferAccelerator "torch"`.

#### `p8n.uv.mkFHS { accelerator?, name?, packages?, extraPackages?, profile?, passthru? }`
FHS container flavor for Python tooling requiring full FHS filesystem emulation.

#### `p8n.uv.mkOCI { name, venv, tag?, accelerator?, packages?, extraPackages?, extraLibs?, env?, cmd?, entrypoint?, maxLayers? }`
Standalone low-level builder that wraps a pre-existing `venv` into a layered OCI/Docker container image derivation using `dockerTools.buildLayeredImage`.

---

### `p8n.mamba` Module

#### `p8n.mamba.mkFHS { name?, file?, accelerator?, packages?, extraPackages?, profile?, passthru? }`
Creates a robust `buildFHSEnv` sandbox for Conda/Micromamba environments. Automatically initializes the environment from `${file}` on first entry and exports accelerator paths (`CUDA_HOME`, `TORCH_EXTENSIONS_DIR`).

---

### `p8n.container` Module

Provides utilities for working with containerized environments, Apptainer/Singularity images, and OCI registries.

#### `p8n.container.mkSIF { name, ociImage, pkgs? }` (Alias: `p8n.container.mkApptainer`)
Converts any OCI/Docker image derivation into an Apptainer / Singularity `.sif` image derivation via `apptainer build`.

#### `p8n.container.get (string)`
```nix
p8n.container.get "pytorch/pytorch:2.8.0-cuda12.9-cudnn9-devel"
```
Returns `dockerTools.pullImage` attribute specification for curated container image digests from the registry.

---

### `p8n.latex` & `p8n.typst` Modules

#### `p8n.latex.readProject (src | { src, ... })`
Inspects a LaTeX repository root (auto-detecting `main.tex` or `paper.tex` and `latexmkrc`) and returns:
- **`.mkDocument { name, main?, ... }`**: Builds the document PDF.
- **`.mkShell { ... }`**: Interactive TeX authoring shell.
- **`.mkWatch { name?, ... }`**: Runnable watch application for `apps.<name>` or `nix run .#<name>`.

#### `p8n.latex.mkShell { texlive?, version?, texpkgs?, packages?, extraPackages?, env?, shellHook? }`
- **`texlive` / `version`** (`string | attrs`, default `"default"`): Selects the TeX Live release baseline (`"default"`, `"2024"` / `"24.05"`, `"2023"` / `"23.11"`) or a custom TeX Live package set. Use `"2023"` for legacy document templates that have package incompatibilities with newer LaTeX kernels.
- **`texpkgs`** (`ps -> attrs`, default `ps: { inherit (ps) scheme-full; }`): Custom TeX Live package set function.

#### `p8n.latex.mkDocument { name, src, texlive?, version?, main?, texpkgs?, packages?, extraPackages?, shellEscape?, latexmkFlags?, env? }`
Builds a PDF derivation using `latexmk`. Accepts `texlive` / `version` to pin older TeX Live release environments (e.g. `"2023"`). Defaults to `main = "main.tex"`.

#### `p8n.latex.mkWatch { name?, src, texlive?, version?, main?, texpkgs?, packages?, extraPackages?, shellEscape?, latexmkFlags? }`
Returns a runnable application derivation (with `type = "app"`) that runs `latexmk -pvc -pdf` in continuous preview/watch mode. Expose directly in `apps.<name>`.

#### `p8n.typst.readProject (src | { src, ... })`
Inspects a Typst document root (auto-detecting `main.typ`) and returns:
- **`.mkDocument { name, main?, ... }`**: Builds the document PDF.
- **`.mkShell { ... }`**: Interactive Typst authoring shell.
- **`.mkWatch { name?, ... }`**: Runnable watch application for `apps.<name>` or `nix run .#<name>`.

#### `p8n.typst.mkShell { packages?, extraPackages?, env?, shellHook? }`
Interactive shell with `typst`, `hayagriva`, and `typstyle`.

#### `p8n.typst.mkDocument { name, src, main?, output?, buildInputs?, extraBuildInputs?, nativeBuildInputs?, extraNativeBuildInputs?, env? }`
Builds a PDF derivation using `typst compile`. Defaults to `main = "main.typ"` and `output = "document.pdf"`.

#### `p8n.typst.mkWatch { name?, src, main?, output?, packages?, extraPackages? }`
Returns a runnable application derivation (with `type = "app"`) that runs `typst watch` in continuous preview mode. Expose directly in `apps.<name>`.

---

### `p8n.composeShells`

Composes multiple `devShells` into a unified, conflict-free development environment while preserving the base shell's accelerator `stdenv` (e.g. GCC/CUDA compatibility) and automatically concatenating all environment variables and `shellHook` activation scripts.

Aliases: `p8n.combineShells`, `p8n.mergeShells`.

#### Toolchain Slot Validation
`composeShells` automatically verifies compatibility across composed shells:
- **Python Slot (`category = "python"`)**: Prevents composing contradictory Python environments (e.g. a locked `uv2nix` pure-Nix virtualenv with an interactive dynamic `uv.mkShell` or `mamba` environment).
- **Accelerator Slot (`category = "accelerator"`)**: Verifies that all non-CPU hardware acceleration targets match (e.g. catches conflicting CUDA versions such as `cu126` vs `cu128`).
- **LaTeX Slot (`category = "latex"`)**: Verifies that TeX Live distributions are compatible.

```nix
# Short syntax (list — first shell acts as base):
p8n.composeShells [ baseShell shellA shellB ... ]

# Extended syntax (attrset):
p8n.composeShells {
  base = config.devShells.cu128;       # Primary shell determining stdenv (optional if `shells` is provided)
  shells = [ config.devShells.paper ]; # Additional shells to merge via inputsFrom
  name = "custom-combined-name";       # Override the derivation name (optional)
  packages = [ pkgs.htop ];            # Extra one-off tools (optional)
  env = { VAR = "value"; };            # Extra environment variables (exported in shellHook) (optional)
  shellHook = ''echo "Ready!"'';        # Extra startup commands (optional)
  preCommit = config.pre-commit;       # Pre-commit hooks (auto-inherited when using formatting module) (optional)
  ignoreConflicts = false;             # Set true to bypass slot conflict checks if desired (optional)
}
```

---

### `p8n.config` Module

The configuration engine evaluates and resolves hardware accelerator targets:
- `p8n.config.resolve (string)`: Parses a shorthand accelerator string into an attribute set.
- `p8n.config.build (pkgs) (string | attrs)`: Evaluates an accelerator specification against `pkgs`.

---

## Use-Case Cookbooks & Examples

### Cookbook 1: Pure-Nix Python Project with SIF & OCI Output

Use `p8n.uv.readProject` when you want a completely reproducible Python project driven by `uv.lock`. `nix develop` drops you straight into an editable environment with zero `uv sync` step, and `nix build` produces both local venvs and HPC containers:

```nix
{
  inputs = {
    tue-p8n.url = "github:tue-p8n/nix";
    nixpkgs.follows = "tue-p8n/nixpkgs";
    flake-parts.follows = "tue-p8n/flake-parts";
  };

  outputs = inputs@{ flake-parts, tue-p8n, ... }:
    flake-parts.lib.mkFlake { inherit inputs; } {
      imports = [ tue-p8n.flakeModule ];
      systems = [ "x86_64-linux" ];

      perSystem = { pkgs, p8n, ... }:
        let
          pyproject = p8n.uv.readProject {
            name = "my-research";
            workspaceRoot = ./.;
          };
        in
        {
          # Interactive shell (editable local install by default)
          devShells.default = pyproject.mkShell {
            accelerator = "cuda12_9";
          };

          # Virtual environment derivation
          packages.default = pyproject.mkVenv {
            accelerator = "cuda12_9";
          };

          # Layered OCI image: `nix build .#docker`
          packages.docker = pyproject.mkOCI {
            accelerator = "cuda12_9";
          };

          # Apptainer SIF container for HPC: `nix build .#sif`
          packages.sif = pyproject.mkSIF {
            accelerator = "cuda12_9";
          };
        };
    };
}
```

---

### Cookbook 2: Interactive Fast Prototyping Shell

Use `p8n.uv.mkShell` when you want a fast, dynamic development workflow where dependencies are managed interactively via `uv add` and `uv sync`:

```nix
perSystem = { pkgs, p8n, ... }: {
  devShells.default = p8n.uv.mkShell {
    name = "fast-experiment";
    accelerator = "cuda12_9";
    extraPackages = [
      pkgs.just
      pkgs.htop
      pkgs.nvtopPackages.nvidia
    ];
    env = {
      WANDB_PROJECT = "vision-research";
    };
    shellHook = ''
      echo "Ready for experiments!"
    '';
  };
};
```

---

### Cookbook 3: Bare CUDA / C++ Development Shell

Use `p8n.accelerator.mkShell` or `p8n.accelerator.mkFHS` when building standalone C++/CUDA tools without Python:

```nix
perSystem = { pkgs, p8n, ... }: {
  # 1. Native Nix-LD shell with nvcc and CUDA toolchain
  devShells.cuda = p8n.accelerator.mkShell {
    accelerator = "cuda12_9";
    extraPackages = [
      pkgs.cmake
      pkgs.ninja
      pkgs.gdb
    ];
  };

  # 2. FHS sandbox for traditional /usr/lib linking
  devShells.cuda-fhs = (p8n.accelerator.mkFHS {
    name = "cuda-fhs";
    accelerator = "cuda12_9";
    extraPackages = [ pkgs.cmake pkgs.ninja ];
  }).env;
};
```

---

### Cookbook 4: Micromamba Conda Environment

Use `p8n.mamba.mkFHS` when working with legacy Conda recipes or packages requiring Conda channels:

```nix
perSystem = { p8n, ... }: {
  devShells.default = (p8n.mamba.mkFHS {
    name = "conda-research";
    file = ./environment.yaml;
    accelerator = "cuda12_9";
    profile = ''
      export PYTHONUNBUFFERED=1
    '';
  }).env;
};
```

---

### Cookbook 5: HPC Cluster Deployment & SLURM Integration

Deploying reproducible Nix builds to Snellius, ALCF, or any SLURM cluster:

#### Step 1: Build the SIF container locally or in CI
```bash
nix build .#sif
# Generates ./result, which is the self-contained .sif file
```

#### Step 2: Submit a SLURM batch script
```bash
#!/bin/bash
#SBATCH --job-name=train-model
#SBATCH --partition=gpu
#SBATCH --gpus=1
#SBATCH --time=04:00:00

# Execute inside the Nix-built Apptainer image with host GPU drivers
apptainer run --nv ./result train.py --epochs 100 --batch-size 64
```

---

### Cookbook 6: Building SIF Containers from Curated Registry Images

Package pinned upstream PyTorch images directly as Apptainer `.sif` files:

```nix
perSystem = { pkgs, p8n, ... }:
let
  ociTarball = pkgs.dockerTools.pullImage (
    p8n.container.get "pytorch/pytorch:2.8.0-cuda12.9-cudnn9-devel"
  );
in
{
  packages.oci = ociTarball;
  packages.sif = p8n.container.mkSIF {
    name = "pytorch-cuda12_9";
    ociImage = ociTarball;
  };
};
```

---

### Cookbook 7: Advanced uv2nix Overrides (C++/CUDA Extensions)

When a Python wheel requires custom C++ build tools, system dependencies, or cross-wheel linking:

```nix
perSystem = { pkgs, p8n, ... }:
let
  project = p8n.uv.mkProject {
    name = "complex-pipeline";
    workspaceRoot = ./.;
    accelerator = "cuda12_9";
    extraLibs = [ pkgs.libGL pkgs.glib ];
    missingBuildSystems = {
      flash-attn = [ "setuptools" "wheel" "ninja" "torch" ];
    };
    crossWheelLinkingPackages = [
      "flash-attn"
      "deformops"
    ];
    overrides = final: prev: {
      deformops = prev.deformops.overrideAttrs (old: {
        buildInputs = (old.buildInputs or [ ]) ++ [ pkgs.cudaPackages.cuda_cudart ];
      });
    };
  };
in
{
  devShells.default = project.shell;
  packages.default = project.venv;
  packages.sif = project.sif;
};
```

---

### Cookbook 8: Writing Academic Papers (LaTeX & Typst)

Manage your research paper submissions alongside your code:

```nix
perSystem = { pkgs, p8n, ... }: {
  # 1. Standard LaTeX paper compilation (modern templates)
  packages.paper = p8n.latex.mkDocument {
    name = "paper";
    src = ./paper;
    main = "main.tex";
    shellEscape = true; # Required for minted / pygments syntax highlighting
  };

  # 2. Legacy document template (pinned to an older TeX Live release for compatibility)
  packages.legacy-paper = p8n.latex.mkDocument {
    name = "legacy-paper";
    src = ./legacy-paper;
    main = "main.tex";
    texlive = "2023"; # Pins TeX Live 2023 baseline from tue-p8n automatically!
  };

  # 3. Typst paper compilation
  packages.typst-paper = p8n.typst.mkDocument {
    name = "typst-paper";
    src = ./paper;
    main = "paper.typ";
    output = "paper.pdf";
  };

  # 4. Interactive LaTeX writing shell (pinned to TeX Live 2023)
  devShells.latex = p8n.latex.mkShell {
    texlive = "2023";
  };

  # 5. Interactive Typst writing shell with formatter and bibliography tools
  devShells.typst = p8n.typst.mkShell { };
};
```

---

### Cookbook 9: Composing Multi-Environment Shells (Python + LaTeX)

Combine a full GPU Python training environment with a TeX Live / Typst paper writing environment into a single `devShells.default`:

```nix
perSystem = { config, p8n, ... }:
let
  pyproject = p8n.uv.readProject ./.;
  paper = p8n.latex.readProject {
    src = ./paper;
    texlive = "2024";
  };
in
{
  devShells = {
    # Standalone environments
    cu128 = pyproject.mkShell {
      accelerator = "cuda12_8";
    };

    paper = paper.mkShell { };

    # Combined master shell:
    # Preserves CUDA stdenv/LD_LIBRARY_PATH from cu128 while pulling in TeX Live from paper!
    default = p8n.composeShells [
      config.devShells.cu128
      config.devShells.paper
    ];
  };
};
```

---

### Cookbook 10: Extending the Library via `p8n.extend`

Add custom lab helpers or wrap default builders:

```nix
perSystem = { pkgs, p8n, ... }:
let
  customP8n = p8n.extend (final: prev: {
    uv = prev.uv // {
      # Opinionated wrapper pre-configured for lab GPU cluster
      mkLabShell = args: prev.uv.mkShell (args // {
        accelerator = "cuda12_9";
        extraPackages = (args.extraPackages or [ ]) ++ [ pkgs.nvtopPackages.nvidia pkgs.just ];
      });
    };
  });
in
{
  devShells.default = customP8n.uv.mkLabShell {
    name = "my-lab-shell";
  };
};
```

---

## `flakeModules` Reference

`tue-p8n` exports three composable `flake-parts` modules under `flake.flakeModules`:

- **`tue-p8n.flakeModules.default`**: Injects `_module.args.p8n` into `perSystem` and configures Cachix binary caches in `flake.nixConfig`. Standard `pkgs` is untouched.
- **`tue-p8n.flakeModules.cuda`**: Imports `default` and automatically configures `_module.args.pkgs` with `cudaSupport = true`, `cudaForwardCompat = true`, and `allowUnfree = true`.
- **`tue-p8n.flakeModules.formatting`**: Provides opinionated formatters (`treefmt-nix`) and pre-commit hooks (`git-hooks.nix`). All tools use `lib.mkDefault` and can be overridden perSystem.

### Options in `flakeModules.cuda`

```nix
perSystem = { ... }: {
  # Optionally specify compute capabilities (e.g. ["8.6" "8.9"])
  p8n.cuda.capabilities = [ "8.6" "8.9" ];
};
```
