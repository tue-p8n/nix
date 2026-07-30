#!/usr/bin/env bash
# End-to-end smoke test for the micromamba dev shells: verify the active env
# can import PyTorch and run a Triton kernel. Must be invoked from inside an
# active micromamba shell, e.g.
#   nix develop .#mm-shell-py313cu129 --command bash tests/smoke/test-mm-pytorch.sh
# `pytorch-gpu` is in the YAML; `triton` is pip-installed on first run if
# missing. Requires network on first run; needs a CUDA GPU for the kernel.
set -euo pipefail

here=$(dirname "$(readlink -f "$0")")

if [[ -z "${CONDA_PREFIX:-}" ]] || ! command -v python >/dev/null; then
    echo "ERROR: no active conda env (are you inside a mm-* dev shell?)" >&2
    exit 1
fi

if ! python -c "import triton" 2>/dev/null; then
    echo " >>> triton not in env; installing via pip..."
    python -m pip install --quiet triton
fi

python "$here/pytorch_triton.py"
echo " >>> Micromamba PyTorch+Triton smoke: PASSED"
