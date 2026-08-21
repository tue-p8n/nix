{ self, config, ... }: rec {
  repoRootHook = ''
    REPO_ROOT=$(git rev-parse --show-toplevel 2>/dev/null) || REPO_ROOT=$(pwd)
    export REPO_ROOT
  '';
  uvBaseHook = ''
    export UV_LINK_MODE=copy
    export UV_NO_SYNC=1
    export UV_LOCKED=1
    export UV_PYTHON_PREFERENCE=only-managed
    export UV_PYTHON_DOWNLOADS=auto
    export UV_PROJECT_ENVIRONMENT="$REPO_ROOT/.venv"
    export VIRTUAL_ENV="$UV_PROJECT_ENVIRONMENT"
  '';
  accelActivationHook =
    {
      nixglhost,
    }:
    ''
      ${self.internal.exportEnv config.env}
      ${repoRootHook}

      ${self.internal.hostGpuHook nixglhost}
      ${config.shellHook}
    '';
}
