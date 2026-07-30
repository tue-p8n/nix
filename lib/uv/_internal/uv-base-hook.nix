# Assumes `repo-root-hook.nix` has run.
''
  export UV_LINK_MODE=copy
  export UV_NO_SYNC=1
  export UV_LOCKED=1
  export UV_PYTHON_PREFERENCE=only-managed
  export UV_PYTHON_DOWNLOADS=auto
  export UV_PROJECT_ENVIRONMENT="$REPO_ROOT/.venv"
  export VIRTUAL_ENV="$UV_PROJECT_ENVIRONMENT"
''
