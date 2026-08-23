# Micromamba Template

A Python project template using `micromamba` (Conda-compatible) FHS environments.
Suitable for packages that require Conda channels (e.g. `nvidia/label/cuda-*`).

## Initialise a new project

```bash
mkdir my-project && cd my-project
nix flake init -t github:tue-p8n/nix#micromamba
git init && git add .
```

## Enter the development shell

```bash
# Enter the FHS sandbox
nix develop

# Or with direnv
direnv allow
```

## Customise the Conda environment

Edit `environment.yaml` to add Conda packages.  
The environment is created on first shell entry and cached in `.mamba/`.

### Providing a custom environment file

Pass `file` to `p8n.mamba.mkFHS` in `flake.nix`:

```nix
(p8n.mamba.mkFHS {
  name = "my-env";
  accelerator = "cuda";
  file = ./my-environment.yaml;
}).env;
```

## Consume the organisation's pinned nixpkgs

```nix
inputs.nixpkgs.follows = "tue-p8n/nixpkgs";
```
