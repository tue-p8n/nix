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
    "libx11"
    "libxext"
    "libxrender"
    "libsm"
    "libice"
    "libxrandr"
    "libxcursor"
    "libxi"
    "libxinerama"
    "libxfixes"
    "libxxf86vm"
    "libxcb"
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
          cacert = { outPath = "/nix/store/mock-cacert"; };
          mkShell =
            let
              mkSh =
                args:
                rec {
                  name = args.name or "mock-shell";
                  passthru = args.passthru or { };
                  inputsFrom = args.inputsFrom or [ ];
                  packages = args.packages or [ ];
                  nativeBuildInputs = args.nativeBuildInputs or [ ];
                  shellHook = args.shellHook or "";
                  overrideAttrs = f: mkSh (args // f (args // { inherit name passthru inputsFrom packages nativeBuildInputs shellHook; }));
                };
            in
            {
              __functor = _self: args: mkSh args;
              override = _: args: mkSh args;
            };
          stdenv = {
            mkDerivation = args: args // { outPath = "/nix/store/mock-${args.name or "drv"}"; };
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
      expected = "cu126";
    };

    # Config module
    testConfigResolveCuda = {
      expr = (p8nInstance.config.resolve "cuda12_9").cuda.version;
      expected = "12.9";
    };
    testConfigResolveCuShorthand = {
      expr = (p8nInstance.config.resolve "cu128").cuda.version;
      expected = "12.8";
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
        builtins.isFunction proj.mkDocument
        && builtins.isFunction proj.mkShell
        && builtins.isFunction proj.mkWatch;
      expected = true;
    };
    testTypstReadProjectExists = {
      expr =
        let
          proj = p8nInstance.typst.readProject ./.;
        in
        builtins.isFunction proj.mkDocument
        && builtins.isFunction proj.mkShell
        && builtins.isFunction proj.mkWatch;
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
    testLatexMkDocumentOptionalName = {
      expr = (p8nInstance.latex.mkDocument { src = ./.; }).name;
      expected = "document";
    };
    testLatexReadProjectInfersName = {
      expr = (p8nInstance.latex.readProject ./fixtures/uv2nix-fixture).name;
      expected = "uv2nix-fixture";
    };
    testTypstMkDocumentOptionalName = {
      expr = (p8nInstance.typst.mkDocument { src = ./.; }).name;
      expected = "document";
    };
    testTypstReadProjectInfersName = {
      expr = (p8nInstance.typst.readProject ./fixtures/uv2nix-fixture).name;
      expected = "uv2nix-fixture";
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

    testPreCommitInjectionInUvShell = {
      expr =
        let
          mockPreCommit = {
            settings = {
              package = { outPath = "/nix/store/mock-prek"; };
              enabledPackages = [ { outPath = "/nix/store/mock-treefmt"; } ];
            };
            installationScript = "echo 'mock-install-hook'";
          };
          p8nWithPreCommit = p8nInstance.extend (_final: _prev: {
            preCommit = mockPreCommit;
          });
          shell = p8nWithPreCommit.uv.mkShell { };
        in
        builtins.isAttrs shell;
      expected = true;
    };

    testPreCommitInjectionInAcceleratorShell = {
      expr =
        let
          mockPreCommit = {
            settings = {
              package = { outPath = "/nix/store/mock-prek"; };
              enabledPackages = [ { outPath = "/nix/store/mock-treefmt"; } ];
            };
            installationScript = "echo 'mock-install-hook'";
          };
          p8nWithPreCommit = p8nInstance.extend (_final: _prev: {
            preCommit = mockPreCommit;
          });
          shell = p8nWithPreCommit.accelerator.mkShell { };
        in
        builtins.isAttrs shell;
      expected = true;
    };

    # composeShells tests
    testComposeShellsExists = {
      expr = builtins.isFunction p8nInstance.composeShells;
      expected = true;
    };
    testCombineShellsAliasExists = {
      expr = builtins.isFunction p8nInstance.combineShells;
      expected = true;
    };
    testMergeShellsAliasExists = {
      expr = builtins.isFunction p8nInstance.mergeShells;
      expected = true;
    };
    testComposeShellsList = {
      expr =
        let
          shell1 = p8nInstance.uv.mkShell { name = "shell-1"; };
          shell2 = p8nInstance.latex.mkShell { };
          composed = p8nInstance.composeShells [ shell1 shell2 ];
        in
        (builtins.length composed.inputsFrom == 1)
        && (composed.name == "shell-1-latex")
        && (composed.passthru ? config)
        && (composed.passthru ? tex);
      expected = true;
    };
    testComposeShellsAttrSet = {
      expr =
        let
          shell1 = p8nInstance.uv.mkShell { };
          shell2 = p8nInstance.latex.mkShell { };
          composed = p8nInstance.composeShells {
            name = "custom-combined";
            base = shell1;
            shells = [ shell2 ];
            env = {
              TEST_VAR = "hello";
            };
          };
        in
        (composed.name == "custom-combined")
        && (builtins.length composed.inputsFrom == 1)
        && (composed.passthru ? config)
        && (composed.passthru ? tex);
      expected = true;
    };
    testComposeShellsFiltersNull = {
      expr =
        let
          shell1 = p8nInstance.uv.mkShell { };
          shell2 = p8nInstance.latex.mkShell { };
          composed = p8nInstance.composeShells [ shell1 null false shell2 ];
        in
        builtins.length composed.inputsFrom == 1;
      expected = true;
    };
    testComposeShellsConflictAcceleratorThrows = {
      expr =
        let
          cu126 = p8nInstance.uv.mkShell { accelerator = "cuda12_6"; };
          cu128 = p8nInstance.uv.mkShell { accelerator = "cuda12_8"; };
        in
        (builtins.tryEval (p8nInstance.composeShells [ cu126 cu128 ])).success;
      expected = false;
    };
    testComposeShellsConflictAcceleratorBypass = {
      expr =
        let
          cu126 = p8nInstance.uv.mkShell { accelerator = "cuda12_6"; };
          cu128 = p8nInstance.uv.mkShell { accelerator = "cuda12_8"; };
        in
        (builtins.tryEval (p8nInstance.composeShells {
          base = cu126;
          shells = [ cu128 ];
          ignoreConflicts = true;
        })).success;
      expected = true;
    };
    testComposeShellsConflictPythonThrows = {
      expr =
        let
          uvDynamic = p8nInstance.uv.mkShell { name = "dynamic"; };
          uvProject = (p8nInstance.uv.mkShell { name = "project"; }).overrideAttrs (_: {
            passthru = {
              p8n = {
                category = "python";
                flavor = "uv2nix";
                name = "project";
                venv = { outPath = "/nix/store/mock-venv"; };
              };
            };
          });
        in
        (builtins.tryEval (p8nInstance.composeShells [ uvDynamic uvProject ])).success;
      expected = false;
    };
    testComposeShellsConflictLatexThrows = {
      expr =
        let
          latex24 = p8nInstance.latex.mkShell { texlive = "2024"; };
          latex23 = p8nInstance.latex.mkShell { texlive = "2023"; };
        in
        (builtins.tryEval (p8nInstance.composeShells [ latex24 latex23 ])).success;
      expected = false;
    };
    testComposeShellsCompatibleMultiDomain = {
      expr =
        let
          cu128 = p8nInstance.uv.mkShell { accelerator = "cuda12_8"; };
          bare128 = p8nInstance.accelerator.mkShell { accelerator = "cuda12_8"; };
          paper = p8nInstance.latex.mkShell { texlive = "2024"; };
          typst = p8nInstance.typst.mkShell { };
          composed = p8nInstance.composeShells [ cu128 bare128 paper typst ];
        in
        (composed.passthru ? config)
        && (composed.passthru ? tex)
        && (composed.passthru ? typst)
        && (builtins.length composed.inputsFrom == 3);
      expected = true;
    };
    testComposeShellsSynthesizesMultiDomainName = {
      expr =
        let
          cu128 = p8nInstance.uv.mkShell { name = "myproj"; accelerator = "cuda12_8"; };
          paper = p8nInstance.latex.mkShell { name = "paper"; };
          composed = p8nInstance.composeShells [ cu128 paper ];
        in
        composed.name;
      expected = "myproj-paper+cu128";
    };
    testComposeShellsWithoutPassthruWorks = {
      expr =
        let
          plainBase = mockPkgs.mkShell { name = "plain-base"; };
          plainOther = mockPkgs.mkShell { name = "plain-other"; };
          composed = p8nInstance.composeShells [ plainBase plainOther ];
        in
        (composed.name == "plain-base-plain-other")
        && (builtins.length composed.inputsFrom == 1);
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
