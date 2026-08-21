# mamba/default.nix
# Stage 1: Static context & internal helper encapsulation
context: {
  mkShell = (import ./mk-shell.nix context).mkShell;
  mkFHS = (import ./mk-fhs.nix context).mkFHS;
}
