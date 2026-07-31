#!/usr/bin/env bash
# End-to-end smoke test for the UV dev shells: download torch+triton via uv
# and run a Triton kernel. Must be invoked from inside an active UV shell, e.g.
#   nix develop .#uv-cuda12_9 --command bash tests/smoke/test-uv-pytorch.sh
# Requires network access (for `uv sync`) and, for the kernel-run path, a
# CUDA-capable GPU.
set -euo pipefail

here=$(dirname "$(readlink -f "$0")")
fixture="$here/uv-fixture"

if ! command -v uv >/dev/null; then
  echo "ERROR: uv not found on PATH (are you inside a uv-* dev shell?)" >&2
  exit 1
fi

if [[ -z ${UV_TORCH_BACKEND:-} ]]; then
  echo "WARNING: UV_TORCH_BACKEND unset — wheel selection will fall back to UV's default."
fi

cd "$fixture"
echo " >>> uv sync   (downloads torch + triton from PyPI)"
uv sync
echo " >>> uv run python pytorch_triton.py"
uv run python "$here/pytorch_triton.py"
echo " >>> UV PyTorch+Triton smoke: PASSED"
