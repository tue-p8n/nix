{ inputs, pkgs }:
let
  test-uv =
    pkgs.runCommand "test-uv-cpu"
      (
        let
          system = pkgs.stdenv.hostPlatform.system;
          shell = inputs.self.devShells.${system}.uv-cpu;
        in
        {
          buildInputs = shell.buildInputs ++ shell.nativeBuildInputs;
          env = {
            ACCELERATOR = "cpu";
            UV_PYTHON_PREFERENCE = "only-managed";
            UV_PYTHON_DOWNLOADS = "auto";
          };
        }
      )
      ''
        # Mock some things that might fail in sandbox
        export REPO_ROOT=$(pwd)
        export HOME=$(pwd)

        # We don't want to actually run 'uv sync' in the sandbox because it needs internet
        # So we'll mock pyproject.toml to not exist or be empty

        bash ${./test-uv.sh}

        touch $out
      '';

  test-template =
    pkgs.runCommand "test-template"
      {
        nativeBuildInputs = [
          pkgs.nix
          pkgs.git
        ];
      }
      ''
        export HOME=$(pwd)
        # We need a dummy git config for some nix commands
        git config --global user.email "test@example.com"
        git config --global user.name "Test User"

        bash ${./test-template.sh} ${inputs.self}

        touch $out
      '';


in
{
  inherit test-uv test-template;
}
