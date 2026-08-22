{
  config,
  lib,
  nixpkgs,
  system,
  ...
}:
{
  imports = [
    ./libraries.nix
    ./cuda.nix
    ./rocm.nix
  ];
  options = {
    assertions = lib.mkOption {
      type = lib.types.listOf lib.types.unspecified;
      default = [ ];
      description = "A list of assertions to check.";
    };
    name = lib.mkOption {
      type = lib.types.str;
      default = "cpu";
      description = "The name of the environment.";
    };
    acceleration = lib.mkOption {
      type = lib.types.enum [
        "none"
        "cuda"
        "rocm"
      ];
      default = "none";
      description = "The type of acceleration to use.";
    };
    pkgs = lib.mkOption {
      type = lib.types.raw;
      description = "The Nixpkgs package set with platform-specific overrides applied.";
    };
    stdenv = lib.mkOption {
      type = lib.types.raw;
      description = "The Nixpkgs stdenv with platform-specific overrides applied.";
    };
    packages = lib.mkOption {
      type = lib.types.listOf lib.types.unspecified;
      default = [ ];
      description = "A list of packages to include in the environment.";
    };
    environment.variables = lib.mkOption {
      type = lib.types.attrs;
      default = { };
      description = "An attribute set of environment variables to set in the shell.";
    };
    shellHook = lib.mkOption {
      type = lib.types.lines;
      default = "";
      description = "A shell hook to run when the shell is started.";
    };
  };

  config = {
    assertions = [
      {
        assertion = !(config.cuda.enable && config.rocm.enable);
        message = "You cannot enable both CUDA and ROCm at the same time.";
      }
    ];

    # Override module `pkgs` argument according to the configured `pkgs` option.
    _module.args.pkgs = config.pkgs;

    # Default pkgs: plain nixpkgs import for cpu/none.
    # CUDA and ROCm modules override this with their own re-import.
    pkgs = lib.mkDefault (
      nixpkgs {
        inherit system;
        overlays = [ ];
      }
    );
    stdenv = lib.mkDefault config.pkgs.stdenv;

    # Select the accelerator module based on the `acceleration` option.
    cuda.enable = config.acceleration == "cuda";
    rocm.enable = config.acceleration == "rocm";

    libraries.runtime = lib.mkDefault true;
    libraries.graphics = lib.mkDefault true;
    libraries.media = lib.mkDefault true;
  };

}
