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
        # How a consumer actually wires this module up. Without it the module
        # falls back to `inputs.self.lib`, which on the fixture flake above
        # resolves to the fixture itself and has no `lib`.
        tue-p8n = self;
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

  # Comparing attribute names only proves the module wired something up, not
  # that what it wired up is well-formed. `buildFHSEnv` and uv2nix both emit
  # real derivations (a root filesystem, a profile script, an init script, a
  # bwrap wrapper, a virtual environment) generated from this repository's
  # code, and a malformed one instantiates fine and fails at build time.
  #
  # Only the CPU entries are realized. The CUDA, LaTeX, and Typst shells above
  # stay evaluation-only on purpose: building them drags a multi-gigabyte
  # toolchain in without covering any code this repository owns, and whether
  # they build is a property of the pinned nixpkgs rather than of the change
  # under review. The environments workflow covers those separately.
  realized = [
    shells.uv-fhs
    shells.uv-native.inputDerivation
    shells.uv2nix-native.inputDerivation
    packages.uv2nix-native
  ];
in
  if actualShells != expectedShells
  then fail "devShells" expectedShells actualShells
  else if actualPackages != expectedPackages
  then fail "packages" expectedPackages actualPackages
  else
    # Passed as an environment variable rather than via `buildInputs`: an
    # `inputDerivation` output is a text dump of a build environment, and
    # stdenv would try to source it as a setup hook. Naming the paths is
    # enough to make them dependencies, so building this check builds them.
    pkgs.runCommand "flake-module-check" {inherit realized;} ''
      echo "$realized" > $out
    ''
