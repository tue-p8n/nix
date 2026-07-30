# Agent Notes

This project was scaffolded from `github:tue-p8n/nix#micromamba`.

## What this template provides

- Two Nix dev shells: `default` (native, requires `nix-ld` on NixOS) and `fhs`
  (full FHS sandbox; recommended for complex CUDA build steps).
- A Conda environment specified in `environment.yaml`, materialised under `.mamba/`
  on first shell entry and reused thereafter.
- An optional `pyproject.toml` skeleton for pure-Python deps you want installed
  with `pip` inside the env (run `pip install -e .[…]` yourself once the env is
  active).

## Conventions

- `environment.yaml` is the source of truth for system / native / CUDA / Conda
  packages. Pure-Python dependencies belong in `pyproject.toml`.
- Delete `.mamba/` to force the env to be recreated on next shell entry.
- `nixpkgs` is followed from `tue-p8n/nixpkgs`. **Do not** add a separate
  `nixpkgs.url` input.
- Run `direnv allow` once after cloning.

## Not committed

- `.mamba/`, `result*`, `.direnv/`, `.env*` — see `.gitignore`.
