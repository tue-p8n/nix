# uv/default.nix
# Stage 1: Static context & internal helper encapsulation
{ inputs, lib }:
let
  # Private internal helpers encapsulated strictly inside ./uv
  shell = import ../_internal { inherit lib; };
  uvShell = import ./_internal { inherit shell lib; };

  # Stage 1: Pass static context to builders
  moduleArgs = { inherit inputs lib shell uvShell; };
  shellModule = import ./mk-shell.nix moduleArgs;
  fhsModule = import ./mk-fhs.nix moduleArgs;
  projectModule = import ./mk-project.nix moduleArgs;
in
# Stage 2: Target environment evaluation
accelConfig: {
  inherit ((shellModule accelConfig)) mkShell;
  inherit ((fhsModule accelConfig)) mkFHS;
  inherit ((projectModule accelConfig)) mkProject;
  mkUv2nix = (projectModule accelConfig).mkProject;
}
