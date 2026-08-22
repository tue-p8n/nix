{
  inputs,
  lib,
}:

let

  staticModules = {
    accelerators = import ./accelerators { inherit lib; nixpkgs = args: import inputs.nixpkgs args; };
    internal = import ./internal { inherit lib; };
    getContainer = import ./get-container.nix { inherit lib; };
  };

  buildModule =
    system: accelerator:
    lib.makeExtensible (
      self:
      let
        config = staticModules.accelerators.build system accelerator;
        context = {
          inherit
            inputs
            lib
            self
            ;
        };
      in
      staticModules
      // {
        inherit config;

        # Rebuild with another accelerator
        withAccelerator = buildModule system;

        # Modules
        uv = import ./uv context;
        mamba = import ./mamba context;
        latex = import ./latex.nix context;
        typst = import ./typst.nix context;
      }
    );
in
staticModules
// {
  # Initialize the module for a given system string and accelerator config.
  build = system: accelerator: (buildModule system accelerator);

  # Convenience functor: `tueLib system` initializes with the default (cpu) accelerator.
  __functor = self: system: (self.build system { });
}
