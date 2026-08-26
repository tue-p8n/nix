# UV + CUDA Native Template

A Python project template with `uv` package management and CUDA/ROCm
acceleration, with its Python environment built **natively in Nix via
[uv2nix]** — resolved and built entirely as Nix derivations instead of via a runtime `uv sync`.

[uv2nix]: https://pyproject-nix.github.io/uv2nix/introduction.html

## Initialise a new project

```bash
mkdir my-project && cd my-project
nix flake init -t github:tue-p8n/nix#uv
git init && git add .
```

## Enter the development shell

```bash
nix develop                   # uses the `default` devShell from this flake
direnv allow                  # or run once for automatic activation on cd
```

## Pick an accelerator

`flake.nix` configures `p8n.uv.readProject` with `pyproject.mkShell`, `pyproject.mkVenv`, and `pyproject.mkSIF`.
Change `accelerator` in `flake.nix` to one of:

| Selector                                   | Meaning                                    |
| ------------------------------------------- | ------------------------------------------- |
| `"cpu"`                                    | CPU-only                                   |
| `"cuda"`                                   | NVIDIA, default CUDA of the pinned nixpkgs |
| `"cuda12_6"`, `"cuda12_8"`, `"cuda12_9"`  | NVIDIA, version-pinned                     |
| `"rocm"`                                   | AMD ROCm                                   |

This selects which `[project.optional-dependencies]` group (`cpu`/`cuXYZ`)
uv2nix resolves for `torch`, matching the `[[tool.uv.index]]` /
`[tool.uv.sources]` entries already in `pyproject.toml`.

## Adding dependencies

```bash
uv add some-package
just lock                     # equivalent to `uv lock`; re-resolves uv.lock
git add pyproject.toml uv.lock
```

Then re-enter the shell (`nix develop`, or let direnv reload) to pick up the
change — Nix rebuilds only the parts of the environment that changed.

## Build the venv as a package

```bash
nix build                     # produces ./result, the venv itself
./result/bin/python -c "import torch; print(torch.__version__)"
```

## Consume the organisation's pinned nixpkgs

The template already follows the central `nixpkgs` pin via:

```nix
inputs.nixpkgs.follows = "tue-p8n/nixpkgs";
```

Do **not** override `nixpkgs.url` — doing so defeats reproducibility.

## Project layout

```
my-project/
├── flake.nix        # Nix environment definition
├── pyproject.toml   # Python project + UV deps + CUDA wheel indices
├── uv.lock          # committed -- drives the Nix build
├── justfile         # `just lock` / `just build`
├── .envrc           # direnv integration (run `direnv allow` once)
└── sources/         # Your Python source
```
