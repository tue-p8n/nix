# mamba/default.nix
# Stage 1: Static context & internal helper encapsulation
{ inputs, lib }:
let
  shellModule = import ./mk-shell.nix { inherit inputs lib; };
  fhsModule = import ./mk-fhs.nix { inherit inputs lib; };
in
# Stage 2: Target environment evaluation
accelConfig: {
  inherit ((shellModule accelConfig)) mkShell;
  inherit ((fhsModule accelConfig)) mkFHS;
}

