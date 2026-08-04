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

            export UV_PYTHON_DOWNLOADS=never
            export UV_PYTHON="${venv}/bin/python"
            export UV_NO_SYNC=1
            export VIRTUAL_ENV="${venv}"
            export LD_LIBRARY_PATH="${libPath}:$LD_LIBRARY_PATH"

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
