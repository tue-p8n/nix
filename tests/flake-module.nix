{
  pkgs,
  self,
}: let
  # `mkFlake` resolves `self.outputs.flakeModule`, so we need to tie a
  # recursive knot — Nix lazy eval terminates because the test only forces
  # `result.devShells`.
  result =
    self.inputs.flake-parts.lib.mkFlake {
      inputs = {
        inherit (self.inputs) nixpkgs flake-parts;
        self = result;
      };
    } {
      imports = [self.outputs.flakeModule];
      systems = ["x86_64-linux"];
      perSystem = _: {
        _module.args.pkgs = pkgs;
        tue-p8n = {
          uv.shells.uv-native = {accelerator = "cpu";};
          uv.fhs.uv-fhs = {accelerator = "cpu";};
          uv.uv2nix.uv2nix-native = {
            name = "fixture";
            workspaceRoot = ../tests/fixtures/uv2nix-fixture;
            accelerator = "cpu";
          };
          cuda.shells.cuda-bare = {};
          latex.shells.tex = {};
          typst.shells.tp = {};
        };
      };
    };

  shells = result.devShells.x86_64-linux;
  packages = result.packages.x86_64-linux;
  expectedShells = ["cuda-bare" "tex" "tp" "uv-fhs" "uv-native" "uv2nix-native"];
  expectedPackages = ["uv2nix-native"];
  actualShells = builtins.attrNames shells;
  actualPackages = builtins.attrNames packages;

  fail = what: expected: actual:
    throw "tests/flake-module.nix: ${what} attribute set mismatch (expected: ${
      builtins.toJSON expected
    }, got: ${builtins.toJSON actual})";
in
  if actualShells != expectedShells
  then fail "devShells" expectedShells actualShells
  else if actualPackages != expectedPackages
  then fail "packages" expectedPackages actualPackages
  else pkgs.writeText "flake-module-eval-passed" "OK"
