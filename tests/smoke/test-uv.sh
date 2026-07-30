#!/usr/bin/env bash
set -e

echo " >>> Running UV Smoke Test..."

# Verify UV is in PATH
if ! command -v uv &> /dev/null; then
    echo "ERROR: uv not found in PATH"
    exit 1
fi

uv_version=$(uv --version)
echo "Found UV version: $uv_version"

# Verify environment variables
if [ "$ACCELERATOR" != "cpu" ]; then
    if [ -z "$UV_TORCH_BACKEND" ]; then
        echo "ERROR: UV_TORCH_BACKEND not set for accelerator: $ACCELERATOR"
        exit 1
    fi
    echo "UV_TORCH_BACKEND is set to: $UV_TORCH_BACKEND"
else
    echo "Skipping UV_TORCH_BACKEND check for CPU"
fi

echo " >>> UV Smoke Test PASSED"
