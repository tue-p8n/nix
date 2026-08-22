{
  pkgs ? import <nixpkgs> { },
  lib ? pkgs.lib,
}:
let
  cudaComponents = [
    "cudnn"
    "nccl"
    "cuda_cudart"
    "libcufft"
    "libcurand"
    "libcusolver"
    "libcusparse"
  ];

  mkMockCudaPackages =
    ver: storePath:
    {
      cudatoolkit = {
        version = "${builtins.replaceStrings [ "_" ] [ "." ] ver}.0";
        outPath = storePath;
      };
    }
    // lib.genAttrs cudaComponents (n: {
      outPath = "${storePath}-${n}";
    });

  mockRocmPackages = lib.genAttrs [ "clr" "rocblas" "hipblas" ] (n: {
    outPath = "/nix/store/mock-${n}";
  });

  rootLibs = [
    "libGL"
    "libGLU"
    "libglvnd"
    "libxkbcommon"
    "glib"
    "zlib"
    "bzip2"
    "xz"
    "zstd"
    "openssl"
    "libffi"
    "ncurses"
    "libxml2"
    "expat"
    "dbus"
    "libjpeg"
    "libpng"
    "libtiff"
    "libwebp"
    "giflib"
    "openjpeg"
    "freetype"
    "fontconfig"
    "harfbuzz"
    "ffmpeg"
  ];

  xorgLibs = [
    "libX11"
    "libXext"
    "libXrender"
    "libSM"
    "libICE"
    "libXrandr"
    "libXcursor"
    "libXi"
    "libXinerama"
    "libXfixes"
    "libXxf86vm"
    "libxcb"
  ];

  mkMockLib = n: { outPath = "/nix/store/mock-${n}"; };

  mockPkgs =
    let
      mkScope = ver: storePath: rec {
        cudaPackages = mkMockCudaPackages ver storePath // {
          backendStdenv = {
            outPath = "/nix/store/mock-cuda-${ver}-stdenv";
          };
          pkgs = self;
        };
        pkgs = self;
        self = {
          inherit cudaPackages;
          rocmPackages = mockRocmPackages;
          stdenv = {
            outPath = "/nix/store/mock-default-stdenv";
            cc = {
              cc = {
                lib = {
                  outPath = "/nix/store/mock-libstdcxx";
                };
              };
            };
          };
          xorg = lib.genAttrs xorgLibs mkMockLib;
        }
        // (lib.genAttrs rootLibs mkMockLib)
        // (lib.mapAttrs'
          (
            v: _:
            lib.nameValuePair "cudaPackages_${builtins.replaceStrings [ "." ] [ "_" ] v}" (
              mkScope v "/nix/store/mock-cuda-${builtins.replaceStrings [ "." ] [ "-" ] v}"
            )
          )
          {
            "12_6" = null;
            "12_8" = null;
            "12_9" = null;
          }
        );
      };
    in
    (mkScope "12_9" "/nix/store/mock-cuda-default").self;

  # Mock nixpkgs import function — mirrors the signature used in cuda.nix/default.nix.
  mockNixpkgs =
    { config ? { }, ... }:
    if config.cudaSupport or false then
      # Return CUDA-enabled mockPkgs (already has cudaPackages_* attrs)
      mockPkgs
    else
      mockPkgs;

  mockSystem = "x86_64-linux";

  accelerators =
    accel:
    (import ../lib/accelerators {
      inherit lib;
      nixpkgs = mockNixpkgs;
    }).build mockSystem accel;

  tests = {
    testCudaDefaultBackend = {
      expr = (accelerators "cuda").environment.variables.UV_TORCH_BACKEND;
      expected = "cu129";
    };
    testCudaVersioned126 = {
      expr = (accelerators "cuda12_6").environment.variables.UV_TORCH_BACKEND;
      expected = "cu126";
    };
    testCudaVersioned128 = {
      expr = (accelerators "cuda12_8").environment.variables.UV_TORCH_BACKEND;
      expected = "cu128";
    };
    testCudaVersionedHomePath = {
      expr = (accelerators "cuda12_6").environment.variables.CUDA_HOME;
      expected = "/nix/store/mock-cuda-12_6";
    };
    testCudaPkgsRescoped = {
      expr = (accelerators "cuda12_6").pkgs.cudaPackages.cudatoolkit.version;
      expected = "12.6.0";
    };
    testCudaPkgsDefaultIsOuter = {
      expr = (accelerators "cuda").pkgs.cudaPackages.cudatoolkit.version;
      expected = "12.9.0";
    };
    testCudaStdenvIsBackend = {
      expr = (accelerators "cuda12_6").stdenv.outPath;
      expected = "/nix/store/mock-cuda-12_6-stdenv";
    };

    testRocmEnvHasRocmPath = {
      expr = (accelerators "rocm").environment.variables.ROCM_PATH;
      expected = "/nix/store/mock-clr";
    };
    testRocmVersionSuffixThrows = {
      expr = (builtins.tryEval (accelerators "rocm6_4")).success;
      expected = false;
    };

    testCpuPackagesEmpty = {
      expr = (accelerators "cpu").packages;
      expected = [ ];
    };
    testCpuStdenvIsDefault = {
      expr = (accelerators "cpu").stdenv.outPath;
      expected = "/nix/store/mock-default-stdenv";
    };
    testCpuPkgsIsOuter = {
      expr = (accelerators "cpu").pkgs == mockPkgs;
      expected = true;
    };

    testTagPreserved = {
      expr = (accelerators "cuda12_6").name;
      expected = "cuda126";
    };
  };

  runTests = lib.runTests tests;
in
if runTests == [ ] then
  pkgs.writeText "unit-tests-passed" "OK"
else
  throw (builtins.toJSON runTests)
