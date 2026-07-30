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

  accelerators = import ../lib/accelerators {
    inherit lib;
    pkgs = mockPkgs;
  };


  tests = {
    testCudaDefaultBackend = {
      expr = (accelerators.resolve "cuda").env.UV_TORCH_BACKEND;
      expected = "cu129";
    };
    testCudaVersioned126 = {
      expr = (accelerators.resolve "cuda12_6").env.UV_TORCH_BACKEND;
      expected = "cu126";
    };
    testCudaVersioned128 = {
      expr = (accelerators.resolve "cuda12_8").env.UV_TORCH_BACKEND;
      expected = "cu128";
    };
    testCudaVersionedHomePath = {
      expr = (accelerators.resolve "cuda12_6").env.CUDA_HOME;
      expected = "/nix/store/mock-cuda-12_6";
    };
    testCudaPkgsRescoped = {
      expr = (accelerators.resolve "cuda12_6").pkgs.cudaPackages.cudatoolkit.version;
      expected = "12.6.0";
    };
    testCudaPkgsDefaultIsOuter = {
      expr = (accelerators.resolve "cuda").pkgs.cudaPackages.cudatoolkit.version;
      expected = "12.9.0";
    };
    testCudaStdenvIsBackend = {
      expr = (accelerators.resolve "cuda12_6").stdenv.outPath;
      expected = "/nix/store/mock-cuda-12_6-stdenv";
    };

    testRocmEnvHasRocmPath = {
      expr = (accelerators.resolve "rocm").env.ROCM_PATH;
      expected = "/nix/store/mock-clr";
    };
    testRocmVersionSuffixThrows = {
      expr = (builtins.tryEval (accelerators.resolve "rocm6_4")).success;
      expected = false;
    };

    testCpuPackagesEmpty = {
      expr = (accelerators.resolve "cpu").packages;
      expected = [ ];
    };
    testCpuStdenvIsDefault = {
      expr = (accelerators.resolve "cpu").stdenv.outPath;
      expected = "/nix/store/mock-default-stdenv";
    };
    testCpuPkgsIsOuter = {
      expr = (accelerators.resolve "cpu").pkgs == mockPkgs;
      expected = true;
    };

    testTagPreserved = {
      expr = (accelerators.resolve "cuda12_6").tag;
      expected = "cuda12_6";
    };
  };

  runTests = lib.runTests tests;
in
if runTests == [ ] then
  pkgs.writeText "unit-tests-passed" "OK"
else
  throw (builtins.toJSON runTests)
