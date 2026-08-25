# Aggregates the cross-builder shell fragments into the internal attrset.
{ lib }:
{
  exportEnv = import ./export-env.nix { inherit lib; };
  nixLdHook = import ./nix-ld-hook.nix { inherit lib; };
  hostGpuHook = import ./host-gpu-hook.nix;
  repoRootHook = import ./repo-root-hook.nix;
  preCommit = import ./pre-commit-hook.nix;
}
