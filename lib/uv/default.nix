# uv/default.nix
context@{ lib, ... }:
lib.mkMerge builtins.map (path: import path context) [
  ./build.nix
  ./mk-shell.nix
  ./mk-fhs.nix
  ./mk-project.nix
]
