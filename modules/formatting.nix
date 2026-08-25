# Formatting and Pre-commit Flake-parts module
# ============================================
{
  inputs,
  lib,
  ...
}:
{
  imports = [
    inputs.git-hooks.flakeModule
    inputs.treefmt.flakeModule
  ];

  perSystem =
    {
      config,
      pkgs,
      ...
    }:
    {
      # Treefmt enables formatting of multiple languages through `nix fmt`.
      # This configuration enables multiple formatters and linters as opinionated defaults.
      treefmt = {
        programs = {
          clang-format.enable = lib.mkDefault true;
          clang-tidy.enable = lib.mkDefault true;
          deadnix.enable = lib.mkDefault true;
          ruff.check = lib.mkDefault true;
          ruff.format = lib.mkDefault true;
          shellcheck.enable = lib.mkDefault true;
          shfmt.enable = lib.mkDefault true;
        };
        settings = {
          formatter = {
            shellcheck.options = lib.mkDefault [
              "-s"
              "bash"
            ];
            ruff-check.priority = lib.mkDefault 1;
            ruff-check.options = lib.mkDefault [ "--fix-only" ];
            ruff-format.priority = lib.mkDefault 2;
          };
        };
      };

      # Pre-commit git hooks wrapping treefmt and standard hygiene checks.
      pre-commit.settings = {
        package = lib.mkDefault pkgs.prek;
        hooks = {
          treefmt = {
            enable = lib.mkDefault true;
            package = lib.mkDefault config.treefmt.build.wrapper;
          };
          check-toml.enable = lib.mkDefault true;
          check-yaml.enable = lib.mkDefault true;
          check-json.enable = lib.mkDefault true;
          check-merge-conflicts.enable = lib.mkDefault true;
          check-added-large-files.enable = lib.mkDefault true;
          end-of-file-fixer.enable = lib.mkDefault true;
          trim-trailing-whitespace = {
            enable = lib.mkDefault true;
            args = lib.mkDefault [ "--markdown-linebreak-ext=md" ];
          };
        };
      };
    };
}
