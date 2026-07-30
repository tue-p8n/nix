{
  pkgs,
  lib,
  version ? null,
}:

let
  selectCudaPkgs =
    v:
    if v == null then
      pkgs
    else
      let
        attr = "cudaPackages_${v}";
      in
      if pkgs ? ${attr} then
        pkgs.${attr}.pkgs
      else
        throw ''
          accelerators: requested CUDA version "${v}" is unavailable in nixpkgs (`pkgs.${attr}`).
          Available attributes: ${
            lib.concatStringsSep ", " (
              builtins.filter (n: lib.hasPrefix "cudaPackages_" n) (builtins.attrNames pkgs)
            )
          }
        '';

  cudaPkgs = selectCudaPkgs version;
  cudaPackages = cudaPkgs.cudaPackages;
  mmVersion = lib.versions.majorMinor cudaPackages.cudatoolkit.version;
  backend = "cu${builtins.replaceStrings [ "." ] [ "" ] mmVersion}";
in
{
  pkgs = cudaPkgs;
  stdenv = cudaPackages.backendStdenv;
  packages = [ cudaPackages.cudatoolkit ];
  env = {
    CUDA_HOME = "${cudaPackages.cudatoolkit}";
    CUDA_PATH = "${cudaPackages.cudatoolkit}";
    UV_TORCH_BACKEND = backend;
  };
  shellHook = ''
    if command -v nvidia-smi &> /dev/null; then
      arch=$(nvidia-smi --query-gpu=compute_cap --format=csv,noheader | sort -u | head -n 1)
      export TORCH_CUDA_ARCH_LIST="$arch"
      echo " >>> Detected NVIDIA GPU architecture: $arch"
    fi
  '';
  systemLibs = (
    with cudaPackages;
    [
      cudatoolkit
      cudnn
      nccl
      cuda_cudart
      libcufft
      libcurand
      libcusolver
      libcusparse
    ]
  );
}
