# Checks for `nix flake check`.
args@{ inputs, pkgs }:
let
  devShells = inputs.self.devShells.${pkgs.stdenv.hostPlatform.system};
  smokeTests = import ./smoke args;
  shellChecks = pkgs.lib.mapAttrs' (name: shell: {
    name = "shell-${name}";
    value = shell.inputDerivation;
  }) devShells;
in
{
  unit = import ./unit.nix { inherit pkgs inputs; };
  uv2nix = import ./uv2nix.nix {
    inherit pkgs;
    inherit (inputs.self) lib;
  };
}
// smokeTests
// shellChecks
