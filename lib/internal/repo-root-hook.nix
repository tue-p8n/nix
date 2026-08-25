# Resolves the root of the repository or falls back to pwd.
''
  REPO_ROOT=$(git rev-parse --show-toplevel 2>/dev/null) || REPO_ROOT=$(pwd)
  export REPO_ROOT
''
