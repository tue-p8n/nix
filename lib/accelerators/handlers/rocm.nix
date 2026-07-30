{
  pkgs,
  version,
}:
if version != null then
  throw ''
    accelerators.resolve: ROCm does not support a version suffix (got "${version}").
    Only one ROCm toolchain is available per nixpkgs revision. Use "rocm".
  ''
else
  let
    rocmPackages = pkgs.rocmPackages;
  in
  {
    inherit pkgs;
    stdenv = pkgs.stdenv;
    packages = [ rocmPackages.clr ];
    env = {
      ROCM_PATH = "${rocmPackages.clr}";
    };
    shellHook = "";
    systemLibs = [
      rocmPackages.clr
      rocmPackages.rocblas
      rocmPackages.hipblas
    ];
  }
