# UV + CUDA Native Template

A Python project template with `uv` package management and CUDA/ROCm
acceleration, with its Python environment built **natively in Nix via
[uv2nix]** — the same dependency set as the `uv-cuda` template, resolved and
built entirely as Nix derivations instead of via a runtime `uv sync`.

[uv2nix]: https://pyproject-nix.github.io/uv2nix/introduction.html

## The key difference from the `uv-cuda`/`uv-cpu` templates

Those templates provision `uv` and system libraries, then defer dependency
resolution to a runtime `uv sync`. This template resolves and builds the
**entire** Python environment (including torch's CUDA wheels) as Nix
derivations: `uv.lock` drives the build directly, and `nix develop` drops you
straight into a fully-populated environment — there is no `uv sync` step,
ever.

The practical consequence: **`uv.lock` must exist and be committed**, and
whenever you change `pyproject.toml`'s dependencies you must re-run `uv lock`
(or `just lock`) and commit the updated lockfile before `nix develop`/`nix
build` will see the change.

## Initialise a new project

```bash
mkdir my-project && cd my-project
nix flake init -t github:tue-p8n/nix#uv-cuda-native
git init && git add .
```

## Enter the development shell

```bash
nix develop                   # uses the `default` shell from this flake
direnv allow                  # or run once for automatic activation on cd
```

## Pick an accelerator

`flake.nix` calls `tue-p8n.uv.uv2nix.default = { accelerator = "cuda"; ... };`.
Change `accelerator` to one of:

| Selector                                   | Meaning                                    |
| ------------------------------------------- | ------------------------------------------- |
| `"cpu"`                                    | CPU-only                                   |
| `"cuda"`                                   | NVIDIA, default CUDA of the pinned nixpkgs |
| `"cuda12_6"` `"cuda12_8"` `"cuda12_9"` | NVIDIA, version-pinned                     |

This selects which `[project.optional-dependencies]` group (`cpu`/`cuXYZ`)
uv2nix resolves for `torch`, matching the `[[tool.uv.index]]` /
`[tool.uv.sources]` entries already in `pyproject.toml`. Add more `cuXYZ`
groups/indices if you need a version not listed.

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
├── flake.nix        # Nix environment definition (tue-p8n.uv.uv2nix.default)
├── pyproject.toml   # Python project + UV deps + CUDA wheel indices
├── uv.lock          # committed -- drives the Nix build
├── justfile         # `just lock` / `just build`
├── .envrc           # direnv integration (run `direnv allow` once)
└── sources/         # Your Python source
```
