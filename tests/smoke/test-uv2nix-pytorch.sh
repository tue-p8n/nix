#!/usr/bin/env bash
# End-to-end smoke test for the uv2nix-native CUDA template: enters the
# template's real dev shell (torch + triton via uv2nix, resolved through its
# committed uv.lock, with the host GPU driver hooked up the same way
# mk-uv2nix.nix's other consumers get it) and runs the same PyTorch+Triton
# kernel check used by test-uv-pytorch.sh inside it.
#   bash tests/smoke/test-uv2nix-pytorch.sh
# Requires network access (uv2nix fetches every wheel as a fixed-output
# derivation) and, for the kernel-run path, a CUDA-capable GPU. Runs `python`
# through `nix develop` rather than invoking the built venv's binary
# directly -- the raw venv alone has no host libcuda.so on its search path,
# only the dev shell's shellHook sets that up (see hostGpuHook/nixLdHook in
# lib/_internal/shell.nix).
set -euo pipefail

here=$(dirname "$(readlink -f "$0")")
repo_root=$(git -C "$here" rev-parse --show-toplevel)
template="$repo_root/templates/uv-cuda-native"

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

cp -r "$template"/* "$tmp"/
chmod -R +w "$tmp"

echo " >>> nix develop --command python $here/pytorch_triton.py"
nix develop \
  --extra-experimental-features 'nix-command flakes' \
  --override-input tue-p8n "path:$repo_root" \
  --no-write-lock-file \
  "path:$tmp#default" \
  --command python "$here/pytorch_triton.py"
echo " >>> uv2nix PyTorch+Triton smoke: PASSED"
