# uv/default.nix
context@{ ... }:
builtins.foldl' (acc: path: acc // (import path context)) { } [
  ./mk-shell.nix
  ./mk-fhs.nix
  ./mk-project.nix
]
// {
  hooks = import ./hooks.nix context;
}
