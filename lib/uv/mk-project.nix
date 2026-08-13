{
  inputs,
  lib,
  shell,
  uvShell,
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
accelConfig@{ pkgs, ... }:
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
      ...
    }@args:
    let
      accelConfig' =
        if accelerator != null && accelerator != (accelConfig.tag or "") then
          (accelerators { inherit pkgs lib; }).resolve accelerator
        else
          accelConfig;
      pkgs' = accelConfig'.pkgs;
      resolvePkgs = p: if builtins.isFunction p then p pkgs' else p;

      nixglhost = pkgs'.nixglhost or null;
      nixglPkg = if nixglhost != null then [ nixglhost ] else [ ];

      tag = accelConfig'.tag or "cpu";

      # Select torch extra backend (ROCm special cased)
      torchExtra = if lib.hasPrefix "rocm" tag then "rocm" else accelConfig'.env.UV_TORCH_BACKEND or "cpu";

      crossWheelLinkingPackages = [
        "torch"
        "torchvision"
        "torchaudio"
        "triton"
        "xformers"
        "bitsandbytes"
      ];

      baseOverrides =
        _final: prev:
        lib.mapAttrs (
          pname: pkg:
          if lib.hasPrefix "nvidia-" pname || lib.elem pname crossWheelLinkingPackages then
            pkg.overrideAttrs (_: {
              autoPatchelfIgnoreMissingDeps = true;
            })
          else
            pkg
        ) prev;

      workspace = uv2nix.lib.workspace.loadWorkspace { inherit workspaceRoot; };

      pyprojectDeps = lib.zipAttrsWith (_: lib.concatLists) [
        workspace.deps.groups
        { ${name} = [ torchExtra ] ++ extras; }
      ];

      uvOverlay = workspace.mkPyprojectOverlay {
        sourcePreference = "wheel";
        dependencies = pyprojectDeps;
      };

      pythonSet = (pkgs'.callPackage pyprojectNix.build.packages {
        inherit python;
        stdenv = accelConfig'.stdenv;
      }).overrideScope (
        lib.composeManyExtensions [
          pyprojectBuildSystems.overlays.default
          uvOverlay
          baseOverrides
          overrides
        ]
      );

      venv = pythonSet.mkVirtualEnv "${name}-venv" pyprojectDeps;

      libPath = pkgs'.lib.makeLibraryPath accelConfig'.systemLibs;
      passThroughAttrs = stripCustomArgs mkProject args;
    in
    {
      inherit workspace pythonSet venv;

      shell = (pkgs'.mkShell.override { inherit (accelConfig') stdenv; }) (
        passThroughAttrs
        // {
          name = "${name}-uv2nix-${tag}";

          packages =
            accelConfig'.packages
            ++ (with pkgs'; [
              uv
              git
              just
            ])
            ++ [ venv ]
            ++ nixglPkg
            ++ (resolvePkgs packages)
            ++ (resolvePkgs extraPackages);

          env = (accelConfig'.env or { }) // env;

          shellHook = ''
            ${shell.nixLdHook pkgs' libPath}

            # Listing `venv` in `packages` makes nixpkgs' Python setup hook
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

            ${uvShell.accelActivationHook { accelConfig = accelConfig'; inherit nixglhost; }}

            echo " >>> UV (uv2nix) shell activated: $(uv --version) [${tag}]"
            ${shellHook}
          '';

          passthru = passthru // {
            accelConfig = accelConfig';
            venv = venv;
            pythonSet = pythonSet;
            workspace = workspace;
          };
        }
      );
    };
}
