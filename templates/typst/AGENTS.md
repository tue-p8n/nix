# Agent Notes

This project was scaffolded from `github:tue-p8n/nix#typst`.

## What this template provides

- A Nix dev shell with `typst`, `hayagriva` (bibliography), and `typstyle`
  (formatter) — see `tue-p8n.lib.typst.mkShell`.
- A `nix build` target that compiles `main.typ` to a PDF under `result/`.

## Conventions

- Override `main` and `output` in `flake.nix` to compile a different entry point.
- `nixpkgs` is followed from `tue-p8n/nixpkgs`. **Do not** add a separate
  `nixpkgs.url` input.
- Run `direnv allow` once after cloning.

## Not committed

- `result*`, `.direnv/`, `.env*`, and the build PDF — see `.gitignore`.
