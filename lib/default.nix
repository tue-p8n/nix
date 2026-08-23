{
  inputs,
  lib,
}:
let
  config = import ./config { inherit lib; };
  internal = import ./internal { inherit lib; };

  build =
    pkgs:
    lib.makeExtensible (
      self:
      let
        context = {
          inherit
            inputs
            lib
            pkgs
            config
            internal
            self
            ;
        };
      in
      {
        inherit
          config
          internal
          ;
        container = import ./container context;
        accelerator = import ./accelerator context;
        uv = import ./uv context;
        mamba = import ./mamba context;
        latex = import ./latex.nix context;
        typst = import ./typst.nix context;
      }
    );
in
{
  inherit
    build
    config
    internal
    ;
  container = import ./container { inherit lib; };
  __functor = self: pkgs: self.build pkgs;
}
