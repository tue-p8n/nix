context@{ ... }:
builtins.foldl' (acc: path: acc // (import path context)) { } [
  ./mk-shell.nix
  ./mk-fhs.nix
]
