context@{ lib, ... }:
lib.mkMerge builtins.map (path: import path context) [
  ./mk-shell.nix
  ./mk-fhs.nix
]
