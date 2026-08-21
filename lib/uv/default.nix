# uv/default.nix
# Stage 1: Static context & internal helper encapsulation
context: {
  hooks = import ./hooks.nix context;
  mkShell = (import ./mk-shell.nix context).mkShell;
  mkFHS = (import ./mk-fhs.nix context).mkFHS;
  mkProject = (import ./mk-project.nix context).mkProject;
  mkUv2nix = (import ./mk-project.nix context).mkProject;
}
