# mamba/default.nix
# Stage 1: Static context & internal helper encapsulation
context: {
  hooks = import ./hooks.nix context;
  mkShell = import ./mk-shell.nix context;
  mkFHS = import ./mk-fhs.nix context;
}
