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

## Pinning TeX Live Version (for Legacy Document Templates)

If your document template suffers from line-numbering bugs or package incompatibilities on newer TeX Live, pass `texlive = "2023"`:

```nix
p8n.latex.mkDocument {
  name = "my-paper";
  src = ./.;
  texlive = "2023"; # Pins TeX Live 2023 baseline from tue-p8n
};
```

## Customise TeX packages

Override `texpkgs` in `flake.nix` to use a smaller scheme:

```nix
p8n.latex.mkDocument {
  name = "my-paper";
  src = ./.;
  texpkgs = ps: { inherit (ps) scheme-small latexmk; };
};
```

## Consume the organisation's pinned nixpkgs

```nix
inputs.nixpkgs.follows = "tue-p8n/nixpkgs";
```
