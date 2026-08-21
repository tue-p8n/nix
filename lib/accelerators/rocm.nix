{
  pkgs,
  lib,
  config,
  ...
}:
let
  this = config.rocm;
in
{
  options = {
    rocm = {
      enable = lib.mkOption {
        type = lib.types.bool;
        readOnly = true;
        description = "Computed flag indicating if ROCm is active.";
      };
    };
  };
  config = lib.mkIf this.enable {
    name = lib.mkDefault "rocm";
    packages = [ pkgs.rocmPackages.clr ];
    environment.variables = {
      ROCM_PATH = "${pkgs.rocmPackages.clr}";
    };
    shellHook = ''
      echo " >>> ROCm support enabled"
    '';
    libraries.extraPackages = [
      pkgs.rocmPackages.clr
      pkgs.rocmPackages.rocblas
      pkgs.rocmPackages.hipblas
    ];
  };
}
