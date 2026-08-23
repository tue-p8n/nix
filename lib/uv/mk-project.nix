{
  inputs,
  lib,
  pkgs,
  config,
  internal,
  self,
  ...
}:
let
  defaultPkgs = pkgs;
  inherit (inputs) uv2nix;
  pyprojectNix = inputs.pyproject-nix;
  pyprojectBuildSystems = inputs.pyproject-build-systems;
  hooks = import ./hooks.nix { inherit internal; };

  stripCustomArgs =
    fn: args:
    let
      customKeys = builtins.attrNames (builtins.functionArgs fn);
    in
    builtins.removeAttrs args customKeys;
in
rec {
  mkProject =
    {
      name,
      workspaceRoot,
      accelerator ? "cpu",
      pkgs ? defaultPkgs,
      python ? null,
      extras ? [ ],
      overrides ? (_final: prev: prev),
      packages ? (_ps: [ ]),
      extraPackages ? (_ps: [ ]),
      env ? { },
      shellHook ? "",
      passthru ? { },
      missingBuildSystems ? { },
      crossWheelLinkingPackages ? [ ],
      extraLibs ? [ ],
      ...
    }@args:
    let
      accelConfig = config.build pkgs accelerator;
      pkgs' = accelConfig.pkgs;
      resolvedPython = if python != null then python else pkgs'.python313;
      resolvePkgs = p: if builtins.isFunction p then p pkgs' else p;

      nixglhost = pkgs'.nixglhost or null;
      nixglPkg = if nixglhost != null then [ nixglhost ] else [ ];

      tag = accelConfig.name;

      # Select torch extra backend (ROCm special cased)
      torchExtra =
        if lib.hasPrefix "rocm" tag then "rocm" else accelConfig.environment.variables.UV_TORCH_BACKEND or "cpu";

      # Missing build systems. Default configuration includes some popular packages
      # as a default.
      overrideMissingBuildSystems =
        let
          default = {
            antlr4-python3-runtime = [ "setuptools" ];
            deformops = [ "setuptools" ];
            semantic-version = [
              "setuptools"
              "wheel"
            ];
            setuptools-scm = [
              "setuptools"
              "wheel"
            ];
            setuptools-rust = [
              "setuptools"
              "wheel"
            ];
            libcst = [
              "setuptools"
              "wheel"
            ];
            nvidia-pipecat = [
              "setuptools"
              "wheel"
            ];
          };
          overrideResolved =
            final: prev:
            lib.mapAttrs (
              pkgName: buildSystems:
              prev.${pkgName}.overrideAttrs (old: {
                nativeBuildInputs =
                  (old.nativeBuildInputs or [ ])
                  ++ (final.resolveBuildSystem (pkgs'.lib.genAttrs buildSystems (_: [ ])));
              })
            ) (default // missingBuildSystems);

          # Default set of special cases
          overrideSpecial = _: prev: {
            numba = prev.numba.overrideAttrs (old: {
              buildInputs = (old.buildInputs or [ ]) ++ [ pkgs'.tbb ];
            });
          };
        in
        final: prev: (overrideResolved final prev) // (overrideSpecial final prev);

      # Packages that are known to have cross-wheel linking issues.
      # These packages are linked against each other.
      # The list below includes some common packages.
      overrideCrossWheelLinkingPackages =
        let
          defaultCrossWheelLinkingPackages = [
            "torch"
            "torchvision"
            "torchaudio"
            "triton"
            "xformers"
            "bitsandbytes"
            "deformops"
            "torchmatch"
          ];
          resolvedCrossWheelLinkingPackages = defaultCrossWheelLinkingPackages ++ crossWheelLinkingPackages;
        in
        _final: prev:
        lib.mapAttrs (
          pkgName: pkg:
          # check if starts with "nvidia-"
          if (lib.hasPrefix "nvidia-" pkgName) || (lib.elem pkgName resolvedCrossWheelLinkingPackages) then
            pkg.overrideAttrs (_: {
              autoPatchelfIgnoreMissingDeps = true;
            })
          else
            pkg
        ) prev;

      # UV workspace
      workspace = uv2nix.lib.workspace.loadWorkspace { inherit workspaceRoot; };

      # PyProject dependencies
      pyprojectDeps = lib.zipAttrsWith (_: lib.concatLists) [
        workspace.deps.groups
        { ${name} = [ torchExtra ] ++ extras; }
      ];

      # UV overlay
      uvOverlay = workspace.mkPyprojectOverlay {
        sourcePreference = "wheel";
        dependencies = pyprojectDeps;
      };

      # Python set
      pythonSet =
        (pkgs'.callPackage pyprojectNix.build.packages {
          python = resolvedPython;
          inherit (accelConfig) stdenv;
        }).overrideScope
          (
            lib.composeManyExtensions [
              pyprojectBuildSystems.overlays.default
              uvOverlay
              overrideMissingBuildSystems
              overrideCrossWheelLinkingPackages
              overrides
            ]
          );

      venv = pythonSet.mkVirtualEnv "${name}-venv" pyprojectDeps;

      libPath = pkgs'.lib.makeLibraryPath (accelConfig.libraries.packages ++ extraLibs);
      passThroughAttrs = stripCustomArgs mkProject args;

      oci = self.uv.mkOCI {
        inherit name venv accelerator pkgs extraLibs;
      };

      sif = self.container.mkSIF {
        inherit name pkgs;
        ociImage = oci;
      };
    in
    {
      inherit
        workspace
        pythonSet
        venv
        oci
        sif
        ;

      shell = (pkgs'.mkShell.override { inherit (accelConfig) stdenv; }) (
        passThroughAttrs
        // {
          name = "${name}-uv2nix-${tag}";

          packages =
            accelConfig.packages
            ++ (with pkgs'; [
              uv
              git
              just
            ])
            ++ [ venv ]
            ++ nixglPkg
            ++ (resolvePkgs packages)
            ++ (resolvePkgs extraPackages);

          env = accelConfig.environment.variables // env;

          shellHook = ''
            ${internal.nixLdHook pkgs' libPath}

            unset PYTHONPATH

            export UV_PYTHON_DOWNLOADS=never
            export UV_PYTHON="${venv}/bin/python"
            export UV_NO_SYNC=1
            export VIRTUAL_ENV="${venv}"
            export LD_LIBRARY_PATH="${libPath}:$LD_LIBRARY_PATH"

            for _nvlib in "${venv}"/lib/python*/site-packages/nvidia/*/lib; do
              [ -d "$_nvlib" ] && LD_LIBRARY_PATH="$_nvlib:$LD_LIBRARY_PATH"
            done
            unset _nvlib
            export LD_LIBRARY_PATH

            ${hooks.accelActivationHook {
              config = accelConfig;
              inherit nixglhost;
            }}

            export TORCH_EXTENSIONS_DIR="''${TORCH_EXTENSIONS_DIR:-$REPO_ROOT/.torch-extensions/${name}-${tag}}"

            echo " >>> UV (uv2nix) shell activated: $(uv --version) [${tag}]"
            ${shellHook}
          '';

          passthru = passthru // {
            config = accelConfig;
            inherit venv;
            inherit pythonSet;
            inherit workspace;
            inherit oci;
            inherit sif;
          };
        }
      );
    };

  mkUv2nix = mkProject;
}
