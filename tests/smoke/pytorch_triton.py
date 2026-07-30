"""Smoke test: import PyTorch, run a tiny Triton kernel, compare against torch.add."""

from __future__ import annotations

import sys


def main() -> int:
    import torch

    print(f" >>> torch        = {torch.__version__}")
    print(f" >>> torch.cuda   = {torch.version.cuda}")
    print(f" >>> CUDA visible = {torch.cuda.is_available()}")

    if not torch.cuda.is_available():
        print(" >>> No CUDA device; verified imports only.")
        return 0

    import triton
    import triton.language as tl

    print(f" >>> triton       = {triton.__version__}")
    print(f" >>> device       = {torch.cuda.get_device_name(0)}")

    @triton.jit
    def add_kernel(x_ptr, y_ptr, out_ptr, n, BLOCK: tl.constexpr):
        pid = tl.program_id(0)
        offsets = pid * BLOCK + tl.arange(0, BLOCK)
        mask = offsets < n
        x = tl.load(x_ptr + offsets, mask=mask)
        y = tl.load(y_ptr + offsets, mask=mask)
        tl.store(out_ptr + offsets, x + y, mask=mask)

    n = 4096
    block = 256
    x = torch.randn(n, device="cuda")
    y = torch.randn(n, device="cuda")
    out = torch.empty_like(x)
    add_kernel[(triton.cdiv(n, block),)](x, y, out, n, BLOCK=block)
    torch.cuda.synchronize()

    expected = x + y
    if not torch.allclose(out, expected, atol=1e-5):
        max_err = (out - expected).abs().max().item()
        print(f" >>> FAIL: triton kernel result diverges (max abs err = {max_err})")
        return 1

    print(" >>> PyTorch + Triton kernel: OK")
    return 0


if __name__ == "__main__":
    sys.exit(main())
