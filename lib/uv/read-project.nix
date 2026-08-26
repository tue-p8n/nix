{
  self,
  inputs,
  lib,
  pkgs,
  config,
  internal,
  ...
}:
let
  defaultPkgs = pkgs;
  inherit (inputs) uv2nix;
  pyprojectNix = inputs.pyproject-nix;
  pyprojectBuildSystems = inputs.pyproject-build-systems;

  stripCustomArgs =
    fn: args:
    let
      customKeys = builtins.attrNames (builtins.functionArgs fn);
    in
    builtins.removeAttrs args customKeys;

  inferHelper = import ./infer-accelerator.nix { inherit lib inputs; };

  defaultMissingBuildSystems = {
    antlr4-python3-runtime = [
      "setuptools"
      "wheel"
    ];
    calver = [
      "setuptools"
      "wheel"
    ];
    deformops = [
      "setuptools"
      "wheel"
    ];
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
    laco = [
      "setuptools"
      "wheel"
    ];
    laco-torch = [
      "setuptools"
      "wheel"
    ];
    laco-typer = [
      "setuptools"
      "wheel"
    ];
    laco-submitit = [
      "setuptools"
      "wheel"
    ];
    torchmatch = [
      "setuptools"
      "wheel"
    ];
    unipercept = [
      "setuptools"
      "wheel"
    ];
    unimt = [
      "setuptools"
      "wheel"
    ];
    unidata = [
      "setuptools"
      "wheel"
    ];
    evaluators = [
      "setuptools"
      "wheel"
    ];
    vistill = [
      "setuptools"
      "wheel"
    ];
    mpsi = [
      "setuptools"
      "wheel"
    ];
    multiformer = [
      "setuptools"
      "wheel"
    ];
    nulidar = [
      "setuptools"
      "wheel"
    ];
    freezemt = [
      "setuptools"
      "wheel"
    ];
    trove-classifiers = [
      "setuptools"
      "wheel"
      "calver"
    ];
    trove_classifiers = [
      "setuptools"
      "wheel"
      "calver"
    ];
    pyyaml-ft = [
      "setuptools"
      "wheel"
    ];
    pyyaml_ft = [
      "setuptools"
      "wheel"
    ];
    pyyaml = [
      "setuptools"
      "wheel"
    ];
    ruamel-yaml = [
      "setuptools"
      "wheel"
    ];
    ruamel_yaml = [
      "setuptools"
      "wheel"
    ];
  };

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

  normalizeOverlays =
    ov:
    if builtins.isList ov then
      ov
    else if builtins.isFunction ov then
      [ ov ]
    else
      [ ];
in
readProjectArgs:
let
  workspaceRoot =
    if builtins.isPath readProjectArgs || builtins.isString readProjectArgs then
      readProjectArgs
    else if builtins.isAttrs readProjectArgs && readProjectArgs ? workspaceRoot then
      readProjectArgs.workspaceRoot
    else
      throw "p8n.uv.readProject: expected a workspaceRoot path or an attribute set containing `workspaceRoot`.";

  projectArgs = if builtins.isAttrs readProjectArgs then readProjectArgs else { };

  workspace = uv2nix.lib.workspace.loadWorkspace { inherit workspaceRoot; };

  pyprojectPath = workspaceRoot + "/pyproject.toml";
  pyprojectToml =
    if builtins.pathExists pyprojectPath then
      builtins.fromTOML (builtins.readFile pyprojectPath)
    else
      { };

  discoveredPackages = builtins.attrNames (workspace.deps.optionals or { });

  inferredName =
    pyprojectToml.project.name or (
      pyprojectToml.tool.poetry.name or (
        if discoveredPackages != [ ] then
          builtins.head discoveredPackages
        else
          "project"
      )
    );

  projectName = projectArgs.name or inferredName;

  baseOverlays = normalizeOverlays (projectArgs.overlays or [ ]);
  baseMissingBuildSystems = defaultMissingBuildSystems // (projectArgs.missingBuildSystems or { });
  baseCrossWheelLinkingPackages = defaultCrossWheelLinkingPackages ++ (projectArgs.crossWheelLinkingPackages or [ ]);

  inferAccelerator =
    pkgArg:
    let
      package =
        if builtins.isString pkgArg then
          pkgArg
        else if builtins.isAttrs pkgArg then
          pkgArg.package or "torch"
        else
          "torch";
      extras = if builtins.isAttrs pkgArg then pkgArg.extras or null else null;
    in
    inferHelper.inferAccelerator {
      inherit workspaceRoot package extras;
    };

  mkVenv =
    {
      name ? projectName,
      accelerator ? (projectArgs.accelerator or "cpu"),
      editable ? false,
      pkgs ? defaultPkgs,
      python ? (projectArgs.python or null),
      extras ? (projectArgs.extras or null),
      overlays ? [ ],
      missingBuildSystems ? { },
      crossWheelLinkingPackages ? [ ],
      ...
    }@args:
    let
      resolvedAccelerator =
        if builtins.isFunction accelerator then
          accelerator { inherit workspaceRoot workspace inferAccelerator; }
        else
          accelerator;

      accelConfig = config.build pkgs resolvedAccelerator;
      pkgs' = accelConfig.pkgs;
      resolvedPython = if python != null then python else pkgs'.python313;
      tag = accelConfig.name;

      knownPackages = builtins.attrNames (workspace.deps.optionals or { });
      packageFound = builtins.elem name knownPackages;
      availableExtras = if packageFound then (workspace.deps.optionals.${name} or [ ]) else [ ];

      resolvedExtras =
        let
          accelExtra =
            if lib.hasPrefix "rocm" tag then
              "rocm"
            else
              accelConfig.environment.variables.UV_TORCH_BACKEND or "cpu";
          baseExtras =
            if packageFound && builtins.elem accelExtra availableExtras then
              [ accelExtra ]
            else
              [ ];
        in
        if extras != null then
          lib.unique (baseExtras ++ extras)
        else
          baseExtras;

      missingExtras = builtins.filter (ext: !builtins.elem ext availableExtras) resolvedExtras;

      validate =
        if !packageFound && knownPackages != [ ] then
          throw ''
            p8n.uv: package "${name}" was not found in the uv workspace at ${toString workspaceRoot}.
            Available workspace packages: ${lib.concatStringsSep ", " knownPackages}.
            Ensure `name = "${name}"` matches the `name` in pyproject.toml and run `uv lock`.
          ''
        else if packageFound && availableExtras != [ ] && missingExtras != [ ] then
          throw ''
            p8n.uv: requested extra(s) [ ${lib.concatStringsSep ", " (map (e: "\"${e}\"") missingExtras)} ] not found in pyproject.toml [project.optional-dependencies] for package "${name}".
            Available extras for "${name}": ${lib.concatStringsSep ", " (map (e: "\"${e}\"") availableExtras)}.
          ''
        else
          true;

      pyprojectDeps =
        assert validate;
        lib.zipAttrsWith (_: lib.concatLists) [
          workspace.deps.groups
          { ${name} = resolvedExtras; }
        ];

      uvOverlay = workspace.mkPyprojectOverlay {
        sourcePreference = "wheel";
        dependencies = pyprojectDeps;
      };

      editableOverlay = workspace.mkEditablePyprojectOverlay {
        root = "$REPO_ROOT";
      };

      allMissingBuildSystems = baseMissingBuildSystems // missingBuildSystems;
      overrideMissingBuildSystems =
        final: prev:
        lib.mapAttrs (
          pkgName: buildSystems:
          let
            # Filter out "torch" from resolveBuildSystem because pyproject-build-systems does not contain torch;
            # torch is handled via prev.torch.
            standardBuildSystems = builtins.filter (bs: bs != "torch") buildSystems;
            hasTorch = builtins.elem "torch" buildSystems;
          in
          prev.${pkgName}.overrideAttrs (old: {
            nativeBuildInputs =
              (old.nativeBuildInputs or [ ])
              ++ (final.resolveBuildSystem (pkgs'.lib.genAttrs standardBuildSystems (_: [ ])))
              ++ (lib.optional (hasTorch && prev ? torch) prev.torch);
            preConfigure =
              (old.preConfigure or "")
              + lib.optionalString (hasTorch && prev ? torch) ''
                export PYTHONPATH="${prev.torch}/${resolvedPython.sitePackages}:''${PYTHONPATH:-}"
              '';
          })
        ) (lib.filterAttrs (pkgName: _: prev ? ${pkgName}) allMissingBuildSystems);

      allCrossWheelLinkingPackages = baseCrossWheelLinkingPackages ++ crossWheelLinkingPackages;
      overrideCrossWheelLinkingPackages =
        _final: prev:
        lib.mapAttrs (
          pkgName: pkg:
          if (lib.hasPrefix "nvidia-" pkgName) || (lib.elem pkgName allCrossWheelLinkingPackages) then
            pkg.overrideAttrs (_: {
              autoPatchelfIgnoreMissingDeps = true;
            })
          else
            pkg
        ) prev;

      effectiveAutoTorch =
        if projectArgs ? autoTorchBuildInputs then
          projectArgs.autoTorchBuildInputs
        else
          (projectArgs.autoTorch or (args.autoTorchBuildInputs or (args.autoTorch or true)));

      allExtraTorchPackages =
        (projectArgs.extraTorchPackages or [ ])
        ++ (args.extraTorchPackages or [ ]);

      allExcludeTorchPackages =
        (projectArgs.excludeTorchPackages or [ ])
        ++ (args.excludeTorchPackages or [ ]);

      # Automatically detects source distribution (sdist) builds that depend on torch
      # and injects prev.torch and its dependencies (nvidia-*, sympy, triton, etc.) into nativeBuildInputs and PYTHONPATH.
      overrideAutoTorch =
        _final: prev:
        if !effectiveAutoTorch || !(prev ? torch) then
          { }
        else
          let
            torchDeps =
              if prev.torch ? passthru && prev.torch.passthru ? dependencies then
                lib.attrNames prev.torch.passthru.dependencies
              else
                [ ];
            nvidiaPkgs = builtins.filter (
              n: lib.hasPrefix "nvidia-" n && prev ? ${n}
            ) (builtins.attrNames prev);
            relevantDeps = lib.unique (
              [ "torch" ]
              ++ (builtins.filter (n: prev ? ${n}) torchDeps)
              ++ nvidiaPkgs
            );
            torchBuildInputs = map (n: prev.${n}) relevantDeps;
            torchPythonPath = lib.concatStringsSep ":" (
              map (n: "${prev.${n}}/${resolvedPython.sitePackages}") relevantDeps
            );
          in
          lib.mapAttrs (
            pkgName: pkg:
            let
              format = pkg.passthru.format or null;
              isSdist = format == "pyproject";
              isExplicitExtra = lib.elem pkgName allExtraTorchPackages;
              isExplicitExcluded = lib.elem pkgName allExcludeTorchPackages;

              passthruDeps = pkg.passthru.dependencies or { };
              rawDeps = pkg.passthru.package.dependencies or [ ];
              buildSystemDeps = pkg.passthru.project.dependencies.build-systems or [ ];

              dependsOnTorch =
                (passthruDeps ? torch)
                || (builtins.any (d: (d.name or "") == "torch") rawDeps)
                || (builtins.any (d: (d.name or d) == "torch") buildSystemDeps);

              needsTorch = !isExplicitExcluded && (isExplicitExtra || (isSdist && dependsOnTorch));
            in
            if needsTorch then
              pkg.overrideAttrs (old: {
                nativeBuildInputs = (old.nativeBuildInputs or [ ]) ++ torchBuildInputs;
                preConfigure =
                  (old.preConfigure or "")
                  + ''
                    export PYTHONPATH="${torchPythonPath}:''${PYTHONPATH:-}"
                  '';
                autoPatchelfIgnoreMissingDeps = true;
              })
            else
              pkg
          ) prev;

      overrideSpecial =
        _: prev:
        (lib.optionalAttrs (prev ? numba) {
          numba = prev.numba.overrideAttrs (old: {
            buildInputs = (old.buildInputs or [ ]) ++ [ pkgs'.tbb ];
          });
        })
        // (lib.optionalAttrs (prev ? opencv-python && (prev ? opencv-python-headless || prev ? opencv-contrib-python-headless)) {
          # When both GUI and headless OpenCV packages are present in the environment,
          # drop cv2 from opencv-python to avoid mkVirtualEnv collision errors.
          opencv-python = prev.opencv-python.overrideAttrs (old: {
            postInstall =
              (old.postInstall or "")
              + ''
                rm -rf "$out/${resolvedPython.sitePackages}/cv2"
              '';
          });
        })
        // (lib.optionalAttrs (prev ? calver) {
          calver = prev.calver.overrideAttrs (old: {
            postPatch =
              (old.postPatch or "")
              + ''
                sed -i -E 's/^[[:space:]]*license[[:space:]]*=[[:space:]]*["'"'"']([^"'"'"']+)["'"'"']/license = { text = "\1" }/g' pyproject.toml 2>/dev/null || true
              '';
          });
        })
        // (lib.optionalAttrs (prev ? trove-classifiers) {
          trove-classifiers = prev.trove-classifiers.overrideAttrs (old: {
            postPatch =
              (old.postPatch or "")
              + ''
                sed -i -E 's/^[[:space:]]*license[[:space:]]*=[[:space:]]*["'"'"']([^"'"'"']+)["'"'"']/license = { text = "\1" }/g' pyproject.toml 2>/dev/null || true
              '';
          });
        })
        // (lib.optionalAttrs (prev ? opencv-contrib-python && prev ? opencv-contrib-python-headless) {
          opencv-contrib-python = prev.opencv-contrib-python.overrideAttrs (old: {
            postInstall =
              (old.postInstall or "")
              + ''
                rm -rf "$out/${resolvedPython.sitePackages}/cv2"
              '';
          });
        });

      userOverlays = baseOverlays ++ (normalizeOverlays overlays);

      pythonSet =
        (pkgs'.callPackage pyprojectNix.build.packages {
          python = resolvedPython;
          inherit (accelConfig) stdenv;
        }).overrideScope
          (
            lib.composeManyExtensions (
              [
                pyprojectBuildSystems.overlays.default
                uvOverlay
              ]
              ++ lib.optionals editable [ editableOverlay ]
              ++ [
                overrideMissingBuildSystems
                overrideCrossWheelLinkingPackages
                overrideAutoTorch
                overrideSpecial
              ]
              ++ userOverlays
            )
          );

      venvName = "${name}-${if editable then "editable-" else ""}venv";
      venvDrv = pythonSet.mkVirtualEnv venvName pyprojectDeps;
    in
    venvDrv
    // {
      inherit
        pythonSet
        pyprojectDeps
        accelConfig
        pkgs'
        tag
        ;
    };

  mkShell =
    {
      name ? projectName,
      accelerator ? (projectArgs.accelerator or "cpu"),
      editable ? true,
      pkgs ? defaultPkgs,
      packages ? (_ps: [ ]),
      extraPackages ? (_ps: [ ]),
      env ? { },
      shellHook ? "",
      preCommit ? (args.self.preCommit or null),
      passthru ? { },
      extraLibs ? (projectArgs.extraLibs or [ ]),
      ...
    }@args:
    let
      venv = mkVenv (
        projectArgs
        // args
        // {
          inherit
            name
            accelerator
            editable
            pkgs
            extraLibs
            ;
        }
      );

      accelConfig = venv.accelConfig;
      pkgs' = venv.pkgs';
      tag = venv.tag;
      resolvePkgs = p: if builtins.isFunction p then p pkgs' else p;

      nixglhost = pkgs'.nixglhost or null;
      nixglPkg = if nixglhost != null then [ nixglhost ] else [ ];
      libPath = pkgs'.lib.makeLibraryPath (accelConfig.libraries.packages ++ extraLibs);
      passThroughAttrs = stripCustomArgs mkShell args;
    in
    (pkgs'.mkShell.override { inherit (accelConfig) stdenv; }) (
      passThroughAttrs
      // {
        name =
          if accelConfig.acceleration != "none" && tag != "none" && tag != "cpu" then
            "${name}+${tag}"
          else
            name;

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
          ++ (resolvePkgs extraPackages)
          ++ (internal.preCommit.packages preCommit);

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

          ${internal.exportEnv (accelConfig.environment.variables // env)}
          ${internal.repoRootHook}
          ${internal.hostGpuHook nixglhost}
          ${accelConfig.shellHook}

          export TORCH_EXTENSIONS_DIR="''${TORCH_EXTENSIONS_DIR:-$REPO_ROOT/.torch-extensions/${name}-${tag}}"

          echo " >>> UV shell activated: $(uv --version) [${tag}]"
          ${internal.preCommit.hook preCommit}
          ${shellHook}
        '';

        passthru = passthru // {
          config = accelConfig;
          inherit venv;
          pythonSet = venv.pythonSet;
          inherit workspace;
          p8n = {
            category = "python";
            flavor = "uv2nix";
            accelerator = tag;
            name = name;
            inherit venv;
          };
        };
      }
    );

  mkOCI =
    {
      name ? projectName,
      accelerator ? (projectArgs.accelerator or "cuda"),
      editable ? false,
      pkgs ? defaultPkgs,
      tag ? "latest",
      packages ? [ ],
      extraPackages ? [ ],
      extraLibs ? (projectArgs.extraLibs or [ ]),
      env ? { },
      cmd ? null,
      entrypoint ? null,
      maxLayers ? 120,
      passthru ? { },
      ...
    }@args:
    let
      venv =
        if args ? venv then
          args.venv
        else
          mkVenv (
            projectArgs
            // args
            // {
              inherit
                name
                accelerator
                editable
                pkgs
                extraLibs
                ;
            }
          );

      accelConfig = venv.accelConfig or (config.build pkgs accelerator);
      pkgs' = venv.pkgs' or accelConfig.pkgs;
      libPath = pkgs'.lib.makeLibraryPath (accelConfig.libraries.packages ++ extraLibs);
      passThroughAttrs = stripCustomArgs mkOCI args;

      resolvedCmd = if cmd != null then cmd else [ "${venv}/bin/python" ];

      baseContents =
        with pkgs';
        [
          dockerTools.binSh
          dockerTools.caCertificates
          coreutils
          bashInteractive
        ]
        ++ accelConfig.packages
        ++ [ venv ]
        ++ packages
        ++ extraPackages;
    in
    pkgs'.dockerTools.buildLayeredImage (
      passThroughAttrs
      // {
        inherit name tag maxLayers;
        contents = baseContents;

        fakeRootCommands = ''
          mkdir -m 1777 tmp
        '';

        config = {
          Cmd = resolvedCmd;
          Entrypoint = entrypoint;
          Env = [
            "PATH=${lib.makeBinPath baseContents}:/bin:/usr/bin"
            "LD_LIBRARY_PATH=${libPath}"
            "SSL_CERT_FILE=${pkgs'.cacert}/etc/ssl/certs/ca-bundle.crt"
            "NIX_SSL_CERT_FILE=${pkgs'.cacert}/etc/ssl/certs/ca-bundle.crt"
            "TORCH_EXTENSIONS_DIR=/tmp/.torch-extensions"
            "NVIDIA_VISIBLE_DEVICES=all"
            "NVIDIA_DRIVER_CAPABILITIES=compute,utility"
            "VIRTUAL_ENV=${venv}"
            "UV_PYTHON=${venv}/bin/python"
          ] ++ (lib.mapAttrsToList (k: v: "${k}=${v}") (accelConfig.environment.variables // env));
        };

        passthru = passthru // {
          inherit venv;
          config = accelConfig;
        };
      }
    );

  mkSIF =
    {
      name ? projectName,
      accelerator ? (projectArgs.accelerator or "cuda"),
      editable ? false,
      pkgs ? defaultPkgs,
      ...
    }@args:
    let
      oci = mkOCI (
        projectArgs
        // args
        // {
          inherit
            name
            accelerator
            editable
            pkgs
            ;
        }
      );
    in
    self.container.mkSIF {
      inherit name pkgs;
      ociImage = oci;
    };
in
{
  inherit
    workspace
    workspaceRoot
    inferAccelerator
    mkVenv
    mkShell
    mkOCI
    mkSIF
    ;

  name = projectName;

  pythonSet =
    args:
    (mkVenv (
      projectArgs
      // (if builtins.isAttrs args then args else { })
    )).pythonSet;

  # Compatibility helpers
  build = mkVenv;
  mkProject = mkShell;
}
