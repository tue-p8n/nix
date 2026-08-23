# Builds a minimal fixture's venv through the full uv2nix pipeline (workspace
# load -> overlay -> pythonSet -> mkVirtualEnv) and checks that both the
# fixture package and its one tiny pure-Python dependency actually import.
# Kept deliberately light (no torch/CUDA) so it stays fast and doesn't depend
# on PyPI-index reachability beyond a single small wheel (contrast with the
# `test-uv-pytorch.sh`/`test-uv2nix-pytorch.sh` manual smoke tests, which need
# real torch downloads and, for the kernel-run path, a GPU).
{
  pkgs,
  lib,
}: let
  venv =
    ((lib pkgs).uv.mkProject {
      name = "fixture";
      workspaceRoot = ./fixtures/uv2nix-fixture;
    })
    .venv;
in
  pkgs.runCommand "uv2nix-check" {} ''
    ${venv}/bin/python -c "import fixture, iniconfig"
    touch $out
  ''
