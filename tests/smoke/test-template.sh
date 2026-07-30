#!/usr/bin/env bash
set -e

echo " >>> Running Template Smoke Test..."

# Use the absolute path to the flake
FLAKE_ROOT=$1

# Collect all temp dirs so we can clean them all up on exit
TEMP_DIRS=()
cleanup() {
    for d in "${TEMP_DIRS[@]}"; do
        rm -rf "$d"
    done
}
trap cleanup EXIT

for template in uv latex typst micromamba; do
    echo " >>> Verifying template: $template"
    TEMP_DIR=$(mktemp -d)
    TEMP_DIRS+=("$TEMP_DIR")

    # Copy template files into a scratch directory
    cp -r "$FLAKE_ROOT/templates/$template/"* "$TEMP_DIR/"
    chmod -R +w "$TEMP_DIR"

    # Verify essential file exists
    if [ ! -f "$TEMP_DIR/flake.nix" ]; then
        echo "ERROR: flake.nix not found for $template"
        exit 1
    fi

    # Check that the flake.nix can be parsed by Nix (no syntax errors).
    nix-instantiate --parse "$TEMP_DIR/flake.nix" > /dev/null || {
        echo "ERROR: nix parse failed for template $template"
        exit 1
    }

    echo " >>> Template $template: OK"
done

echo " >>> All Template Smoke Tests PASSED"

