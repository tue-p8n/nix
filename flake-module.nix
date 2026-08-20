# Flake-parts module
# ==================
# Consumers must arrange `_module.args.pkgs` with `cudaSupport`/`cudaForwardCompat`/
# `allowUnfree` themselves if they declare any CUDA shell.
{
  inputs,
  lib,
  flake-parts-lib,
  ...
}:
let
  tueLib = inputs.tue-p8n.lib or inputs.self.lib;

  shellOpts = _: {
    options = {
      accelerator = lib.mkOption {
        type = lib.types.str;
        default = "cpu";
        example = "cuda12_9";
        description = ''
          Accelerator selector: `"cpu"` | `"cuda"` | `"cudaX_Y"` | `"rocm"`.
          ROCm has no version-pinned form -- only one toolchain exists per
          nixpkgs revision.
        '';
      };
      name = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = ''
          Override the underlying derivation's `name`. If `null`, the builder
          auto-derives one from the accelerator (or, where required by the
          builder, the attribute key is used).
        '';
      };
    };
  };

  micromambaOpts = { name, ... }: {
    options = {
      accelerator = lib.mkOption {
        type = lib.types.str;
        default = "cpu";
        example = "cuda12_9";
      };
      name = lib.mkOption {
        type = lib.types.str;
        default = name;
        description = "Environment name; defaults to the attribute key.";
      };
      file = lib.mkOption {
        type = lib.types.nullOr lib.types.path;
        default = null;
        description = "Path to the conda environment YAML.";
      };
    };
  };

  latexOpts = _: {
    options.texpkgs = lib.mkOption {
      type = lib.types.functionTo lib.types.attrs;
      default = ps: { inherit (ps) scheme-full; };
      description = "Function from `pkgs.texlive` to a selected scheme attrset.";
    };
  };

  # Deliberately narrower than the direct-lib `mkProject` API: no
  # `overrides`/`extras`/`packages` passthrough (function-typed flake-parts
  # options are awkward). Reach for `tueLib.resolve { inherit pkgs; }.uv.mkProject`
  # directly if you need those.
  uv2nixOpts = { name, ... }: {
    options = {
      name = lib.mkOption {
        type = lib.types.str;
        default = name;
        description = "Project name; must match `[project].name` in pyproject.toml.";
      };
      workspaceRoot = lib.mkOption {
        type = lib.types.path;
        description = "Path to the uv workspace root (containing pyproject.toml + uv.lock).";
      };
      env = lib.mkOption {
        type = lib.types.attrsOf lib.types.str;
        default = { };
        description = "Extra environment variables to set in the build environment.";
      };
      # shellHook = lib.mkOption {
      #   type = lib.types.str;
      #   default = "";
      #   description = "Extra shell hook.";
      # };
      # overrides = lib.mkOption {
      #   # Using `anything` or `unspecified` prevents the module system from
      #   # trying to deeply merge the returned derivations.
      #   type = lib.types.nullOr (lib.types.functionTo lib.types.anything);
      #   default = null;
      #   description = "Python set overlay function, typically `final: prev: { ... }`.";
      # };
      accelerator = lib.mkOption {
        type = lib.types.str;
        default = "cpu";
        example = "cuda12_9";
      };
      python = lib.mkOption {
        type = lib.types.nullOr lib.types.package;
        default = null;
        description = "Override the Nix-built Python interpreter (defaults to pkgs.python313).";
      };
      extras = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ ];
        description = "Extras passed to `uv sync` via `--extra <name>`.";
      };
      crossWheelLinkingPackages = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = { };
        description = "Extra packages to link into the cross-wheel build environment.";
      };
      extraLibs = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ ];
        description = "Extra libraries to link into the build environment.";
      };
      missingBuildSystems = lib.mkOption {
        type = lib.types.attrsOf (lib.types.listOf lib.types.str);
        default = { };
        description = "Extra build systems to add to the build environment.";
      };
    };
  };

  dropNull = attrs: lib.filterAttrs (_: v: v != null) attrs;

  # Coverage check: every consumer-facing argument a `mk-*.nix` builder
  # accepts must be either exposed as an option above or explicitly listed
  # here as `omitted` (usually because it's function-typed --
  # `overrides`/`extras`/`packages` -- and flake-parts option lib.types can't
  # express that cleanly). `exposed` is read directly off each builder's
  # real submodule (`shellOpts`/`mmOpts`/`uv2nixOpts`) rather than retyped,
  # so this can't itself drift from the options it's meant to verify.
  # Forced via the `assert` on `config` below, since an unreferenced `let`
  # binding would otherwise never fire in lazy Nix.
  contextArgs = import ./lib/_internal/context-args.nix;
  consumerArgs = fn: builtins.attrNames (removeAttrs (builtins.functionArgs fn) contextArgs);

  shellExposed = builtins.attrNames (shellOpts { }).options;
  mmExposed = builtins.attrNames (micromambaOpts { name = "_"; }).options;
  uv2nixExposed = builtins.attrNames (uv2nixOpts { name = "_"; }).options;

  dummyAccel = {
    tag = "cpu";
    pkgs = { };
    stdenv = { };
    packages = [ ];
    env = { };
    shellHook = "";
    systemLibs = [ ];
  };

  moduleArgs = { inherit inputs lib; };
  uvModule = import ./lib/uv moduleArgs;
  mambaModule = import ./lib/mamba moduleArgs;

  builderCoverage = {
    "uv.shells" = {
      fn = (uvModule dummyAccel).mkShell;
      exposed = shellExposed;
      omitted = [
        "packages"
        "extraPackages"
        "env"
        "shellHook"
        "passthru"
      ];
    };
    "uv.fhs" = {
      fn = (uvModule dummyAccel).mkFHS;
      exposed = shellExposed;
      omitted = [
        "packages"
        "extraPackages"
        "profile"
        "passthru"
      ];
    };
    "uv.uv2nix" = {
      fn = (uvModule dummyAccel).mkProject;
      exposed = uv2nixExposed;
      omitted = [
        "overrides"
        "packages"
        "extraPackages"
        "shellHook"
        "overrides"
        "passthru"
      ];
    };
    "cuda.shells" = {
      fn = (uvModule dummyAccel).mkShell;
      exposed = shellExposed;
      omitted = [
        "packages"
        "extraPackages"
        "env"
        "shellHook"
        "passthru"
      ];
    };
    "micromamba.shells" = {
      fn = (mambaModule dummyAccel).mkShell;
      exposed = mmExposed;
      omitted = [
        "packages"
        "extraPackages"
        "env"
        "shellHook"
        "passthru"
      ];
    };
    "micromamba.fhs" = {
      fn = (mambaModule dummyAccel).mkFHS;
      exposed = mmExposed;
      omitted = [
        "packages"
        "extraPackages"
        "profile"
        "passthru"
      ];
    };
  };

  checkBuilderCoverage =
    name:
    {
      fn,
      exposed,
      omitted,
    }:
    let
      actual = consumerArgs fn;
      accounted = exposed ++ omitted;
      missing = lib.subtractLists accounted actual;
      stale = lib.subtractLists actual accounted;
    in
    if missing != [ ] then
      throw ''
        flake-module.nix: the "${name}" builder gained argument(s)
        ${builtins.toJSON missing} that are neither a declared option nor
        listed in `builderCoverage."${name}".omitted`. Add an option above,
        or add the argument to `omitted` with a reason.
      ''
    else if stale != [ ] then
      throw ''
        flake-module.nix: `builderCoverage."${name}"` lists
        ${builtins.toJSON stale}, which that builder no longer accepts.
        Remove the stale entry.
      ''
    else
      true;

  p8nOptions = {
    uv = {
      shells = lib.mkOption {
        type = lib.types.attrsOf (lib.types.submodule shellOpts);
        default = { };
        description = "UV native dev shells. Each entry → devShells.<key>.";
      };
      fhs = lib.mkOption {
        type = lib.types.attrsOf (lib.types.submodule shellOpts);
        default = { };
        description = "UV FHS dev shells. Each entry → devShells.<key>.";
      };
      uv2nix = lib.mkOption {
        type = lib.types.attrsOf (lib.types.submodule uv2nixOpts);
        default = { };
        description = ''
          UV projects built natively via uv2nix (no runtime `uv sync`).
          Each entry → devShells.<key> + packages.<key>.
        '';
      };
    };
    cuda = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = ''
          Whether to automatically re-import `pkgs` for this system target with
          `cudaSupport = true`, `cudaForwardCompat = true`, and `allowUnfree = true`.
        '';
      };
      capabilities = lib.mkOption {
        type = lib.types.nullOr (lib.types.listOf lib.types.str);
        default = null;
        example = [
          "8.6"
          "8.9"
        ];
        description = ''
          Optionally specify target CUDA compute capabilities (e.g., `["8.6" "8.9"]`)
          to restrict builds to specific GPU architectures and speed up compilation.
          If `null`, nixpkgs builds for all standard supported capabilities.
        '';
      };
      shells = lib.mkOption {
        type = lib.types.attrsOf (lib.types.submodule shellOpts);
        default = { };
        description = "Bare CUDA dev shells. Each entry → devShells.<key>.";
      };
    };
    micromamba = {
      shells = lib.mkOption {
        type = lib.types.attrsOf (lib.types.submodule micromambaOpts);
        default = { };
        description = "Micromamba native dev shells.";
      };
      fhs = lib.mkOption {
        type = lib.types.attrsOf (lib.types.submodule micromambaOpts);
        default = { };
        description = "Micromamba FHS dev shells.";
      };
    };
    latex.shells = lib.mkOption {
      type = lib.types.attrsOf (lib.types.submodule latexOpts);
      default = { };
      description = "LaTeX dev shells with TeX Live.";
    };
    typst.shells = lib.mkOption {
      type = lib.types.attrsOf (
        lib.types.submodule (_: {
          options = { };
        })
      );
      default = { };
      description = "Typst dev shells.";
    };
  };

  _coverageChecked = lib.all (name: checkBuilderCoverage name builderCoverage.${name}) (
    builtins.attrNames builderCoverage
  );
in
{
  options.perSystem = flake-parts-lib.mkPerSystemOption (
    {
      config,
      pkgs,
      system,
      ...
    }:
    {
      options.tue-p8n = p8nOptions;
      options.p8n = p8nOptions;

      config =
        assert _coverageChecked;
        let
          cfg = lib.recursiveUpdate config.p8n config.tue-p8n;
          resOf =
            accel:
            tueLib.resolve {
              inherit pkgs;
              accelerator = accel;
            };

          shellArgs = c: dropNull { inherit (c) accelerator name; };
          # buildFHSEnv requires a non-null `name`; fall back to the attribute key.
          fhsArgs =
            key: c:
            (shellArgs c)
            // {
              name = if c.name != null then c.name else key;
            };
          mmArgs = c: dropNull { inherit (c) accelerator name file; };
          uv2nixArgs =
            c:
            dropNull {
              inherit (c)
                name
                workspaceRoot
                accelerator
                python
                ;
            };
        in
        {
          # CUDA support requires unfree packages and forward-compat.
          _module.args.pkgs = lib.mkIf cfg.cuda.enable (
            import inputs.nixpkgs {
              inherit system;
              config = {
                cudaSupport = true;
                cudaForwardCompat = true;
                allowUnfree = true;
              }
              // (lib.optionalAttrs (cfg.cuda.capabilities != null) {
                cudaCapabilities = cfg.cuda.capabilities;
              });

              overlays = [ ];
            }
          );

          # Development shells
          devShells = lib.mkMerge [
            (lib.mapAttrs (_: c: (resOf c.accelerator).uv.mkShell (shellArgs c)) cfg.uv.shells)
            (lib.mapAttrs (k: c: ((resOf c.accelerator).uv.mkFHS (fhsArgs k c)).env) cfg.uv.fhs)
            (lib.mapAttrs (_: c: ((resOf c.accelerator).uv.mkProject (uv2nixArgs c)).shell) cfg.uv.uv2nix)
            (lib.mapAttrs (
              _: c: (resOf (if c.accelerator != "cpu" then c.accelerator else "cuda")).uv.mkShell (shellArgs c)
            ) cfg.cuda.shells)
            (lib.mapAttrs (_: c: (resOf c.accelerator).mamba.mkShell (mmArgs c)) cfg.micromamba.shells)
            (lib.mapAttrs (_: c: ((resOf c.accelerator).mamba.mkFHS (mmArgs c)).env) cfg.micromamba.fhs)
            (lib.mapAttrs (_: c: (resOf "cpu").latex.mkShell { inherit (c) texpkgs; }) cfg.latex.shells)
            (lib.mapAttrs (_: _: (resOf "cpu").typst.mkShell { }) cfg.typst.shells)
          ];
          packages = lib.mkMerge [
            (lib.mapAttrs (_: c: ((resOf c.accelerator).uv.mkProject (uv2nixArgs c)).venv) cfg.uv.uv2nix)
          ];
        };
    }
  );
}
