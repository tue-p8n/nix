# Aggregates the cross-builder shell fragments -- each a single-export file
# below -- into the `shell` attrset `lib/default.nix` injects into every
# `mk-*.nix` builder (uv, cuda, micromamba). A fragment used by only one
# builder family belongs under that family's own `_internal/` instead
# (see `lib/uv/_internal/`), not here.
{lib}: {
  exportEnv = import ./export-env.nix {inherit lib;};
  nixLdHook = import ./nix-ld-hook.nix {inherit lib;};
  hostGpuHook = import ./host-gpu-hook.nix;
  repoRootHook = import ./repo-root-hook.nix;
}
