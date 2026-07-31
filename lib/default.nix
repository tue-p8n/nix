# Main import path for the library.
{ inputs }:
let
  lib = inputs.nixpkgs.lib;
  accelerators = import ./accelerators;

  # Scope module constructors cleanly at load time
  moduleArgs = { inherit inputs lib; };
  uvModule = import ./uv moduleArgs;
  mambaModule = import ./mamba moduleArgs;
  latexModule = import ./latex.nix moduleArgs;
  typstModule = import ./typst.nix moduleArgs;


  resolve =
    {
      pkgs,
      accelerator ? "cpu",
      lib ? pkgs.lib,
    }:
    let
      config =
        if builtins.isAttrs accelerator then
          accelerator
        else
          (accelerators { inherit pkgs lib; }).resolve accelerator;
    in
    {
      inherit config;

      uv = uvModule config;
      mamba = mambaModule config;
      micromamba = mambaModule config;
      latex = latexModule config;
      typst = typstModule config;
    };
in
{
  inherit resolve accelerators;
  getContainer = import ./get-container.nix;

  # Module constructors taking { pkgs, accelerator? } directly
  uv = { ... }@args: (resolve args).uv;
  mamba = { ... }@args: (resolve args).mamba;
  micromamba = { ... }@args: (resolve args).mamba;
  latex = { ... }@args: (resolve args).latex;
  typst = { ... }@args: (resolve args).typst;
  cuda =
    { pkgs, accelerator ? "cuda", ... }@args:
    (resolve ({ inherit pkgs accelerator; } // (builtins.removeAttrs args [ "pkgs" "accelerator" ]))).uv;
}
