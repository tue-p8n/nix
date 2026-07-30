# Agent Notes

This project was scaffolded from `github:tue-p8n/nix#latex`.

## What this template provides

- A Nix dev shell with TeX Live `scheme-full` (`tue-p8n.lib.latex.mkShell`).
- A `nix build` target that compiles `main.tex` to a PDF under `result/`.

## Conventions

- Override `texpkgs` in `flake.nix` to use a smaller scheme if `scheme-full` is
  overkill (it commonly is).
- `nixpkgs` is followed from `tue-p8n/nixpkgs`. **Do not** add a separate
  `nixpkgs.url` input.
- Run `direnv allow` once after cloning.

## Not committed

- `result*`, `.direnv/`, `.env*`, and the usual LaTeX aux files — see `.gitignore`.
