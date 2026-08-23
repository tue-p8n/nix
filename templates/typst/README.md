# Typst Template

A reproducible Typst document template powered by Nix.

## Initialise a new project

```bash
mkdir my-paper && cd my-paper
nix flake init -t github:tue-p8n/nix#typst
git init && git add .
```

## Enter the development shell

```bash
nix develop
# Or with direnv
direnv allow
```

The shell provides `typst`, `hayagriva` (bibliography), and `typstyle` (formatter).

## Build the PDF

```bash
nix build
# PDF is at result/document.pdf
```

## Customise the document entry point

Override `main` and `output` in `flake.nix`:

```nix
p8n.typst.mkDocument {
  name = "my-paper";
  src = ./.;
  main = "paper.typ";
  output = "paper.pdf";
};
```

## Consume the organisation's pinned nixpkgs

```nix
inputs.nixpkgs.follows = "tue-p8n/nixpkgs";
```
