{
  inputs,
  lib,
}:

let

  staticModules = {
    accelerators = import ./accelerators { inherit lib; };
    internal = import ./internal { inherit lib; };
    getContainer = import ./get-container.nix { inherit lib; };
  };

  buildModule =
    pkgs: accelerator:
    lib.makeExtensible (
      self:
      let
        config = staticModules.accelerators.build pkgs accelerator;
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
        withAccelerator = buildModule pkgs;

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
  # Initialize the module with a given `pkgs` and `accelerator`.
  build = pkgs: accelerator: (buildModule pkgs accelerator);

  # Some modules depend on `pkgs`, so we must provide a way to initialize these.
  # To this end, a functor is used.
  __functor = self: pkgs: (self.build pkgs { });
}
