{
  pkgs ? import <nixpkgs> { },
  lib ? pkgs.lib,
  inputs ? { },
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
          mkShell = args: { inherit (args) passthru; };
          cacert = { outPath = "/nix/store/mock-cacert"; };
          stdenv = {
            hostPlatform = {
              system = "x86_64-linux";
            };
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

  accelerators =
    accel:
    (import ../lib/config {
      inherit lib;
    }).build mockPkgs accel;

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

    # Config module
    testConfigResolveCuda = {
      expr = (p8nInstance.config.resolve "cuda12_9").cuda.version;
      expected = "12.9";
    };
    testConfigResolveRocm = {
      expr = (p8nInstance.config.resolve "rocm").acceleration;
      expected = "rocm";
    };
    testConfigResolveCpu = {
      expr = (p8nInstance.config.resolve "cpu").acceleration;
      expected = "none";
    };

    # Accelerator module builders
    testAcceleratorMkShellExists = {
      expr = builtins.isFunction p8nInstance.accelerator.mkShell;
      expected = true;
    };
    testAcceleratorMkFHSExists = {
      expr = builtins.isFunction p8nInstance.accelerator.mkFHS;
      expected = true;
    };

    # UV module builders
    testUvMkShellExists = {
      expr = builtins.isFunction p8nInstance.uv.mkShell;
      expected = true;
    };
    testUvMkFHSExists = {
      expr = builtins.isFunction p8nInstance.uv.mkFHS;
      expected = true;
    };
    testUvMkProjectExists = {
      expr = builtins.isFunction p8nInstance.uv.mkProject;
      expected = true;
    };
    testUvReadProjectExists = {
      expr = builtins.isFunction p8nInstance.uv.readProject;
      expected = true;
    };
    testUvInferAcceleratorExists = {
      expr = builtins.isFunction p8nInstance.uv.inferAccelerator;
      expected = true;
    };
    testUvReadProjectFixture = {
      expr =
        let
          proj = p8nInstance.uv.readProject ./fixtures/uv2nix-fixture;
        in
        builtins.isFunction proj.build
        && builtins.isFunction proj.mkShell
        && builtins.isFunction proj.mkOCI
        && builtins.isFunction proj.mkSIF;
      expected = true;
    };
    testUvInferAcceleratorFixture = {
      expr =
        let
          proj = p8nInstance.uv.readProject ./fixtures/uv2nix-fixture;
        in
        proj.inferAccelerator "fixture";
      expected = {
        acceleration = "none";
      };
    };
    testUvInspectPackageBackendCudaToolkit = {
      expr =
        let
          inferHelper = import ../lib/uv/infer-accelerator.nix {
            inherit lib inputs;
          };
          mockPkg = {
            name = "torch";
            version = "2.11.0";
            dependencies = [
              { name = "cuda-toolkit"; version = "12.8.1"; }
            ];
          };
        in
        inferHelper.inspectPackageBackend mockPkg;
      expected = {
        acceleration = "cuda";
        cuda = { version = "12.8"; };
      };
    };
    testUvInspectPackageBackendCudaBindings = {
      expr =
        let
          inferHelper = import ../lib/uv/infer-accelerator.nix {
            inherit lib inputs;
          };
          mockPkg = {
            name = "torch";
            version = "2.13.0";
            dependencies = [
              { name = "cuda-bindings"; version = "13.3.1"; }
            ];
          };
        in
        inferHelper.inspectPackageBackend mockPkg;
      expected = {
        acceleration = "cuda";
        cuda = { version = "13.3"; };
      };
    };
    testUvInspectPackageBackendCudaWheel = {
      expr =
        let
          inferHelper = import ../lib/uv/infer-accelerator.nix {
            inherit lib inputs;
          };
          mockPkg = {
            name = "torch";
            version = "2.5.1+cu124";
          };
        in
        inferHelper.inspectPackageBackend mockPkg;
      expected = {
        acceleration = "cuda";
        cuda = { version = "12.4"; };
      };
    };
    testUvInspectPackageBackendRocm = {
      expr =
        let
          inferHelper = import ../lib/uv/infer-accelerator.nix {
            inherit lib inputs;
          };
          mockPkg = {
            name = "torch";
            version = "2.6.0+rocm6.2";
          };
        in
        inferHelper.inspectPackageBackend mockPkg;
      expected = {
        acceleration = "rocm";
        rocm = { version = "6.2"; };
      };
    };
    testUvInspectPackageBackendCpu = {
      expr =
        let
          inferHelper = import ../lib/uv/infer-accelerator.nix {
            inherit lib inputs;
          };
          mockPkg = {
            name = "torch";
            version = "2.6.0";
          };
        in
        inferHelper.inspectPackageBackend mockPkg;
      expected = {
        acceleration = "none";
      };
    };
    testUvMkOCIExists = {
      expr = builtins.isFunction p8nInstance.uv.mkOCI;
      expected = true;
    };
    testUvMkDockerAliasExists = {
      expr = builtins.isFunction p8nInstance.uv.mkDocker;
      expected = true;
    };

    # Document module readProject
    testLatexReadProjectExists = {
      expr =
        let
          proj = p8nInstance.latex.readProject ./.;
        in
        builtins.isFunction proj.mkDocument && builtins.isFunction proj.mkShell;
      expected = true;
    };
    testTypstReadProjectExists = {
      expr =
        let
          proj = p8nInstance.typst.readProject ./.;
        in
        builtins.isFunction proj.mkDocument && builtins.isFunction proj.mkShell;
      expected = true;
    };

    # Mamba module builders
    testMambaMkFHSExists = {
      expr = builtins.isFunction p8nInstance.mamba.mkFHS;
      expected = true;
    };

    # Container module
    testContainerGetValid = {
      expr = (p8nInstance.container.get "pytorch/pytorch:2.8.0-cuda12.9-cudnn9-devel").imageName;
      expected = "pytorch/pytorch";
    };
    testContainerGetTag = {
      expr = (p8nInstance.container.get "pytorch/pytorch:2.8.0-cuda12.9-cudnn9-devel").finalImageTag;
      expected = "2.8.0-cuda12.9-cudnn9-devel";
    };
    testContainerGetMissingThrows = {
      expr = (builtins.tryEval (p8nInstance.container.get "nonexistent")).success;
      expected = false;
    };
    testContainerMkSIFExists = {
      expr = builtins.isFunction p8nInstance.container.mkSIF;
      expected = true;
    };
    testContainerMkApptainerAliasExists = {
      expr = builtins.isFunction p8nInstance.container.mkApptainer;
      expected = true;
    };

    # Document module builders
    testLatexMkShellExists = {
      expr = builtins.isFunction p8nInstance.latex.mkShell;
      expected = true;
    };
    testLatexMkDocumentExists = {
      expr = builtins.isFunction p8nInstance.latex.mkDocument;
      expected = true;
    };
    testLatexVersionDefault = {
      expr = (p8nInstance.latex.mkShell { }).passthru.tex.outPath;
      expected = "/nix/store/mock-tex-default";
    };
    testLatexVersion2024 = {
      expr = (p8nInstance.latex.mkShell { texlive = "2024"; }).passthru.tex.outPath;
      expected = "/nix/store/mock-tex-2024";
    };
    testLatexVersion2023 = {
      expr = (p8nInstance.latex.mkShell { version = "2023"; }).passthru.tex.outPath;
      expected = "/nix/store/mock-tex-2023";
    };
    testLatexInvalidVersionThrows = {
      expr = (builtins.tryEval (p8nInstance.latex.mkShell { texlive = "1999"; }).passthru.tex).success;
      expected = false;
    };
    testTypstMkShellExists = {
      expr = builtins.isFunction p8nInstance.typst.mkShell;
      expected = true;
    };
    testTypstMkDocumentExists = {
      expr = builtins.isFunction p8nInstance.typst.mkDocument;
      expected = true;
    };

    # Extend mechanism
    testP8nExtendTopLevel = {
      expr = extendedP8n.customValue;
      expected = "hello-p8n";
    };
    testP8nExtendSubmodule = {
      expr = extendedP8n.uv.customTool;
      expected = "custom-uv-tool";
    };
    testP8nExtendPreservesExisting = {
      expr = builtins.isFunction extendedP8n.uv.mkShell;
      expected = true;
    };

    # Downstream flake module consumption (simulates downstream flake without tue-p8n internal inputs)
    testDownstreamFlakeModuleResolution = {
      expr =
        let
          downstreamInputs = {
            nixpkgs = mockPkgs;
            self = { };
          };
          module = (import ../modules/default.nix { p8nLib = (_pkgs: p8nInstance); });
          evaluated = module {
            inputs = downstreamInputs;
            inherit lib;
            flake-parts-lib = {
              mkPerSystemOption = f: {
                options = { };
                config = (f {
                  config = { };
                  pkgs = mockPkgs;
                  system = "x86_64-linux";
                }).config;
              };
            };
          };
        in
        builtins.isFunction evaluated.options.perSystem.config._module.args.p8n.uv.mkProject;
      expected = true;
    };

    testFlakeModuleCudaStructure = {
      expr =
        let
          module = import ../modules/cuda.nix;
        in
        builtins.isFunction module;
      expected = true;
    };

    testFlakeModuleFormattingStructure = {
      expr =
        let
          module = import ../modules/formatting.nix;
        in
        builtins.isFunction module;
      expected = true;
    };
  };

  mockTexlive = name: {
    combine = _: { outPath = "/nix/store/mock-tex-${name}"; };
    scheme-full = { };
  };

  mockNixpkgs = name: {
    legacyPackages.${mockPkgs.stdenv.hostPlatform.system} = {
      texlive = mockTexlive name;
    };
  };

  p8nInstance =
    (import ../lib {
      inherit lib;
      inputs = inputs // {
        nixpkgs-24-05 = mockNixpkgs "2024";
        nixpkgs-23-11 = mockNixpkgs "2023";
      };
    }) (
      mockPkgs
      // {
        texlive = mockTexlive "default";
      }
    );

  extendedP8n = p8nInstance.extend (
    _final: prev: {
      customValue = "hello-p8n";
      uv = prev.uv // {
        customTool = "custom-uv-tool";
      };
    }
  );

  runTests = lib.runTests tests;
in
if runTests == [ ] then
  pkgs.writeText "unit-tests-passed" "OK"
else
  throw (builtins.toJSON runTests)
