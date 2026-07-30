# Aggregates the uv-only shell fragments -- each a single-export file below
# -- into the `uvShell` attrset `lib/default.nix` injects into `uv/mk-*.nix`.
# Fragments used by cuda/micromamba too live in `lib/_internal/shell.nix`
# instead; promote a fragment here back to that file if a second builder
# family ever needs it.
{ shell, ... }: let

  repoRootHook = import ./repo-root-hook.nix;
in {
  inherit repoRootHook;
  uvBaseHook = import ./uv-base-hook.nix;
  accelActivationHook = import ./accel-activation-hook.nix {inherit shell repoRootHook;};
}
