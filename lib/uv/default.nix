context@{ lib, inputs, ... }:
let
  inferHelper = import ./infer-accelerator.nix { inherit lib inputs; };
in
(import ./mk-shell.nix context)
// (import ./mk-fhs.nix context)
// (import ./mk-project.nix context)
// (import ./mk-oci.nix context)
// {
  readProject = import ./read-project.nix context;
  loadProject = import ./read-project.nix context;
  inferAccelerator = inferHelper.inferAccelerator;
}
