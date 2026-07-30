#!/usr/bin/env bash

# Check that a Micromamba/Conda environment is active
if [ -z "$CONDA_PREFIX" ]; then
    echo "No Micromamba/Conda environment is active. Please activate an environment first."
    exit 1
fi

# Path to the state file
STATE_FILE="$CONDA_PREFIX/conda-meta/state"

# Create an empty state file if it doesn't exist
if [ ! -f "$STATE_FILE" ]; then
    echo "No state file found. Creating an empty state file..." >&2
    echo "{}" > "$STATE_FILE"
fi

# Updating environment
export CUDA_HOME=$CONDA_PREFIX
export CUDA_PATH=$CONDA_PREFIX
export TORCH_EXTENSIONS_DIR="$CONDA_PREFIX/torch_extensions"

mkdir -p "$TORCH_EXTENSIONS_DIR"

# Update the state file to include CUDA_HOME and CUDA_PATH
echo "Patching state file..." >&2
STATE_PATCHED=$(jq ".env_vars += {\
  \"TORCH_EXTENSIONS_DIR\": \"$TORCH_EXTENSIONS_DIR\", \
  \"FORCE_CUDA\": \"1\",\
  \"CUDA_HOME\": \"$CONDA_PREFIX\", \
  \"CUDA_PATH\": \"$CONDA_PREFIX\"\
}" "$STATE_FILE")

echo "${STATE_PATCHED}" > "$STATE_FILE"
echo "${STATE_PATCHED}" >&2
echo "Success! If you are currently in a shell, please restart it to apply the changes." >&2
