{
  inputs,
  lib,
  self,
  pkgs,
  config,
  ...
}:
let
  inherit (inputs) uv2nix;
  pyprojectNix = inputs.pyproject-nix;
  pyprojectBuildSystems = inputs.pyproject-build-systems;
  accelerators = import ../accelerators;

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
      python ? pkgs.python313,
      extras ? [ ],
      overrides ? (_final: prev: prev),
      packages ? (_ps: [ ]),
      extraPackages ? (_ps: [ ]),
      env ? { },
      shellHook ? "",
      passthru ? { },
      accelerator ? null,
      missingBuildSystems ? { },
      crossWheelLinkingPackages ? [ ],
      extraLibs ? [ ],
      ...
    }@args:
    let
      config' =
        if accelerator != null && accelerator != config.name then
          (accelerators { inherit pkgs lib; }) accelerator
        else
          config;
      resolvePkgs = p: if builtins.isFunction p then p pkgs else p;

      nixglhost = pkgs.nixglhost or null;
      nixglPkg = if nixglhost != null then [ nixglhost ] else [ ];

      tag = config'.name;

      # Select torch extra backend (ROCm special cased)
      torchExtra = if lib.hasPrefix "rocm" tag then "rocm" else config'.environment.variables.UV_TORCH_BACKEND or "cpu";

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
                  ++ (final.resolveBuildSystem (pkgs.lib.genAttrs buildSystems (_: [ ])));
              })
            ) (default // missingBuildSystems);

          # Default set of special cases
          overrideSpecial = _: prev: {
            numba = prev.numba.overrideAttrs (old: {
              buildInputs = (old.buildInputs or [ ]) ++ [ pkgs.tbb ];
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
        (pkgs.callPackage pyprojectNix.build.packages {
          inherit python;
          inherit (config') stdenv;
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

      libPath = pkgs.lib.makeLibraryPath (config'.libraries.packages ++ extraLibs);
      passThroughAttrs = stripCustomArgs mkProject args;
    in
    {
      inherit workspace pythonSet venv;

      shell = (pkgs.mkShell.override { inherit (config') stdenv; }) (
        passThroughAttrs
        // {
          name = "${name}-uv2nix-${tag}";

          packages =
            config'.packages
            ++ (with pkgs; [
              uv
              git
              just
            ])
            ++ [ venv ]
            ++ nixglPkg
            ++ (resolvePkgs packages)
            ++ (resolvePkgs extraPackages);

          env = config'.environment.variables // env;

          shellHook = ''
            ${self.internal.nixLdHook pkgs libPath}

            # Listing `venv` in `packages` makes nixpkgs Python setup hook
            # export PYTHONPATH pointing at its site-packages. PYTHONPATH
            # outranks a venv's own site-packages, so it silently shadows any
            # *other* environment the user works in: activating a uv-managed
            # .venv, or even invoking that venv's interpreter by absolute
            # path, still imports this venv's packages. Symptom is a wrong-
            # library import with no error, which is worse than a failure.
            # It is also redundant here: `venv` is already the interpreter, so
            # its packages are on sys.path natively. Both uv2nix devShell
            # idioms unset it for exactly this reason.
            unset PYTHONPATH

            export UV_PYTHON_DOWNLOADS=never
            export UV_PYTHON="${venv}/bin/python"
            export UV_NO_SYNC=1
            export VIRTUAL_ENV="${venv}"
            export LD_LIBRARY_PATH="${libPath}:$LD_LIBRARY_PATH"

            # The nvidia-* wheels depend on each other's shared objects, and
            # `baseOverrides` sets autoPatchelfIgnoreMissingDeps on them so the
            # build can finish without resolving those cross-wheel links. That
            # leaves the sibling lib directories out of every RPATH, and unlike
            # a plain pip install torch does not recover: its
            # `_preload_cuda_deps` fallback only runs when loading
            # libtorch_global_deps.so *fails*, and auto-patchelf fixed that one
            # up, so the fallback never fires. The first bare-name dlopen of a
            # sibling (libcudnn_graph.so.9, reached via libtorch_cuda) then
            # aborts the process with SIGABRT in cudnnGetVersion, which is not
            # a catchable exception. Putting the sibling dirs on the loader
            # path is what the preload would otherwise have done.
            for _nvlib in "${venv}"/lib/python*/site-packages/nvidia/*/lib; do
              [ -d "$_nvlib" ] && LD_LIBRARY_PATH="$_nvlib:$LD_LIBRARY_PATH"
            done
            unset _nvlib
            export LD_LIBRARY_PATH

            ${self.uv.hooks.accelActivationHook {
              inherit nixglhost;
            }}

            # Set after the activation hook, which is what defines REPO_ROOT.
            # Without this torch caches JIT-built extensions in a shared
            # per-user directory keyed only loosely on the environment, so two
            # projects on different torch or CUDA versions collide; torch warns
            # about precisely that on every build. Keyed by project and
            # accelerator so the variants cannot share a cache entry.
            export TORCH_EXTENSIONS_DIR="''${TORCH_EXTENSIONS_DIR:-$REPO_ROOT/.torch-extensions/${name}-${tag}}"

            echo " >>> UV (uv2nix) shell activated: $(uv --version) [${tag}]"
            ${shellHook}
          '';

          passthru = passthru // {
            config = config';
            venv = venv;
            pythonSet = pythonSet;
            workspace = workspace;
          };
        }
      );
    };
}
