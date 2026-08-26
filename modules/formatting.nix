# Formatting and Pre-commit Flake-parts module
# ============================================
{
  inputs,
  lib,
  ...
}:
let
  tueP8n = inputs.tue-p8n or inputs.self or { };

  treefmtModule =
    if inputs ? treefmt then
      inputs.treefmt.flakeModule
    else if tueP8n ? inputs && tueP8n.inputs ? treefmt then
      tueP8n.inputs.treefmt.flakeModule
    else
      throw "modules/formatting.nix: could not find treefmt in inputs or tue-p8n.inputs";

  gitHooksModule =
    if inputs ? git-hooks then
      inputs.git-hooks.flakeModule
    else if tueP8n ? inputs && tueP8n.inputs ? git-hooks then
      tueP8n.inputs.git-hooks.flakeModule
    else
      throw "modules/formatting.nix: could not find git-hooks in inputs or tue-p8n.inputs";
in
{
  imports = [
    gitHooksModule
    treefmtModule
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
        package = lib.mkOverride 900 pkgs.prek;
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

      # Provide a fallback default devShell with pre-commit if no shell is defined
      devShells.default = lib.mkDefault (
        pkgs.mkShell {
          name = "formatting-devshell";
          packages = [
            config.pre-commit.settings.package
          ] ++ config.pre-commit.settings.enabledPackages;
          shellHook = config.pre-commit.installationScript;
        }
      );
    };
}
