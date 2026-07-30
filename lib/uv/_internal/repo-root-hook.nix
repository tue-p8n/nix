# Detects the enclosing git repo's root (falling back to $PWD outside one)
# and exports it as $REPO_ROOT. `uv-base-hook.nix` depends on this having
# run first.
''
  REPO_ROOT=$(git rev-parse --show-toplevel 2>/dev/null) || REPO_ROOT=$(pwd)
  export REPO_ROOT
''
