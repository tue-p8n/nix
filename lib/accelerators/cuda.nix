{
  config,
  pkgs,
  pkgs',
  lib,
  ...
}:

let
  selectCudaPkgs =
    version:
    if version == null then
      pkgs'.cudaPackages.pkgs
    else
      let
        tag = builtins.replaceStrings [ "." ] [ "_" ] version;
        attr = "cudaPackages_${tag}";
      in
      if pkgs' ? ${attr} then
        pkgs'.${attr}.pkgs
      else
        throw ''
          accelerators: requested CUDA version "${version}" is unavailable in nixpkgs (`pkgs.${attr}`).
          Available attributes: ${
            lib.concatStringsSep ", " (
              builtins.filter (n: lib.hasPrefix "cudaPackages_" n) (builtins.attrNames pkgs)
            )
          }
        '';
  this = config.cuda;
in
{
  options.cuda = {
    enable = lib.mkOption {
      type = lib.types.bool;
      readOnly = true;
      description = "Computed flag indicating if CUDA is active.";
    };
    version = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      description = ''
        The CUDA version to use. If not specified, the default CUDA version in nixpkgs will be used.
        Available versions: ${
          lib.concatStringsSep ", " (
            builtins.filter (n: lib.hasPrefix "cudaPackages_" n) (builtins.attrNames pkgs)
          )
        }
      '';
    };
  };
  config = lib.mkIf this.enable (
    let
      pkgs = selectCudaPkgs this.version;
      version' = builtins.replaceStrings [ "." ] [ "" ] this.version;
    in
    {
      inherit pkgs;

      name = lib.mkDefault "cuda${version'}";

      stdenv = pkgs.cudaPackages.backendStdenv;
      packages = [ pkgs.cudaPackages.cudatoolkit ];
      environment.variables = {
        CUDA_VISIBLE_DEVICES = "all";
        CUDA_HOME = "${pkgs.cudaPackages.cudatoolkit}";
        CUDA_PATH = "${pkgs.cudaPackages.cudatoolkit}";
        UV_TORCH_BACKEND = "cu${version'}";
      };
      shellHook = ''
        # Signal CUDA enabled
        echo " >>> CUDA support enabled (version: ${pkgs.cudaPackages.cudatoolkit.version})"

        # Detect NVIDIA GPU architecture and set TORCH_CUDA_ARCH_LIST for PyTorch
        if command -v nvidia-smi &> /dev/null; then
          arch=$(nvidia-smi --query-gpu=compute_cap --format=csv,noheader | sort -u | head -n 1)
          export TORCH_CUDA_ARCH_LIST="$arch"
          echo " >>> Detected NVIDIA GPU architecture: $arch"
        fi
      '';
      libraries.extraPackages = with pkgs.cudaPackages; [
        cudatoolkit
        cudnn
        nccl
        cuda_cudart
        libcufft
        libcurand
        libcusolver
        libcusparse
      ];
    }
  );
}
