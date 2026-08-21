{
  inputs,
  lib,
  pkgs,
}:

let
  # Static modules that don't depend on the accelerator configuration.
  staticModules = {
    internal = import ./internal { inherit lib; };
    getContainer = import ./get-container.nix { inherit lib; };
  };
  # Factory to create a new uv environment with a specific accelerator configuration.
  withAccelerator =
    accelerator:
    lib.makeExtensible (
      self:
      let
        config = (import ./accelerators { inherit pkgs lib; }) accelerator;
        context = {
          inherit
            inputs
            lib
            config
            self
            ;
          inherit (config) pkgs;
        };
      in
      staticModules
      // {
        inherit config withAccelerator;

        # Modules
        uv = import ./uv context;
        mamba = import ./mamba context;
        latex = import ./latex.nix context;
        typst = import ./typst.nix context;
      }
    );
in
withAccelerator { }
