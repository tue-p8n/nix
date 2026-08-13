# The per-accelerator activation sequence every uv-based shell (native or
# uv2nix) runs once its own env vars are set: apply `accelConfig.env`,
# detect the repo root, wire up host GPU drivers, then run the
# accelerator's own `shellHook`. Factored out because `mk-shell.nix`,
# `mk-fhs.nix`, and `mk-uv2nix.nix` previously hand-duplicated this exact
# sequence, and `mk-fhs.nix`'s copy had drifted to reimplement only half
# of `shell.hostGpuHook` (the non-NixOS branch).
{
  shell,
  repoRootHook,
}: {
  accelConfig,
  nixglhost,
}: ''
  ${shell.exportEnv accelConfig.env}
  ${repoRootHook}

  ${shell.hostGpuHook nixglhost}
  ${accelConfig.shellHook}
''
