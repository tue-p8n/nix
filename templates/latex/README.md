# LaTeX Template

A reproducible LaTeX document template powered by Nix.

## Initialise a new project

```bash
mkdir my-paper && cd my-paper
nix flake init -t github:tue-p8n/nix#latex
git init && git add .
```

## Enter the development shell

```bash
nix develop
# Or with direnv
direnv allow
```

The shell provides a full TeX Live installation (`scheme-full`).

## Build the PDF

```bash
nix build
# PDF is at result/*.pdf
```

## Customise TeX packages

Override `texpkgs` in `flake.nix` to use a smaller scheme:

```nix
lib.latex { inherit pkgs; }.mkDocument {
  name = "my-paper";
  src = ./.;
  texpkgs = ps: { inherit (ps) scheme-small latexmk; };
};
```

## Consume the organisation's pinned nixpkgs

```nix
inputs.nixpkgs.follows = "tue-p8n/nixpkgs";
```
