{ lib, inputs }:
let
  inherit (inputs) uv2nix;

  # Extracts CUDA / ROCm version or returns "none" (CPU)
  inspectPackageBackend =
    pkg:
    let
      deps = pkg.dependencies or [ ];
      version = pkg.version or "";
      registry = (pkg.source.registry or "");

      # --- CUDA Detection ---
      cudaToolkit = lib.findFirst (d: (d.name or "") == "cuda-toolkit") null deps;
      cudaBindings = lib.findFirst (d: (d.name or "") == "cuda-bindings") null deps;
      cudaRuntime = lib.findFirst (d: lib.hasPrefix "nvidia-cuda-runtime" (d.name or "")) null deps;

      cudaWheelMatch = builtins.match ".*[+]?cu([0-9]{2})([0-9]+).*" version;
      cudaRegistryMatch = builtins.match ".*whl/cu([0-9]{2})([0-9]+).*" registry;

      # --- ROCm Detection ---
      rocmCore = lib.findFirst (d: (d.name or "") == "rocm-core" || lib.hasPrefix "hip-" (d.name or "")) null deps;
      rocmWheelMatch = builtins.match ".*[+]?rocm([0-9]+)[.]([0-9]+).*" version;
      rocmRegistryMatch = builtins.match ".*whl/rocm([0-9]+)[.]([0-9]+).*" registry;
    in
    # 1. CUDA: Check explicit toolkit/bindings/runtime dependencies first, then wheel/index tags
    if cudaToolkit != null && (cudaToolkit ? version) then
      {
        acceleration = "cuda";
        cuda = {
          version = lib.versions.majorMinor cudaToolkit.version;
        };
      }
    else if cudaBindings != null && (cudaBindings ? version) then
      {
        acceleration = "cuda";
        cuda = {
          version = lib.versions.majorMinor cudaBindings.version;
        };
      }
    else if cudaRuntime != null && (cudaRuntime ? version) then
      {
        acceleration = "cuda";
        cuda = {
          version = lib.versions.majorMinor cudaRuntime.version;
        };
      }
    else if cudaWheelMatch != null then
      {
        acceleration = "cuda";
        cuda = {
          version = "${builtins.elemAt cudaWheelMatch 0}.${builtins.elemAt cudaWheelMatch 1}";
        };
      }
    else if cudaRegistryMatch != null then
      {
        acceleration = "cuda";
        cuda = {
          version = "${builtins.elemAt cudaRegistryMatch 0}.${builtins.elemAt cudaRegistryMatch 1}";
        };
      }

    # 2. ROCm: Check rocm dependencies or wheel/index tags
    else if rocmCore != null && (rocmCore ? version) then
      {
        acceleration = "rocm";
        rocm = {
          version = lib.versions.majorMinor rocmCore.version;
        };
      }
    else if rocmWheelMatch != null then
      {
        acceleration = "rocm";
        rocm = {
          version = "${builtins.elemAt rocmWheelMatch 0}.${builtins.elemAt rocmWheelMatch 1}";
        };
      }
    else if rocmRegistryMatch != null then
      {
        acceleration = "rocm";
        rocm = {
          version = "${builtins.elemAt rocmRegistryMatch 0}.${builtins.elemAt rocmRegistryMatch 1}";
        };
      }

    # 3. CPU fallback
    else
      {
        acceleration = "none";
      };

  inferAcceleratorDirect =
    {
      workspaceRoot,
      package ? "torch",
      extras ? null,
    }:
    let
      lockFile = workspaceRoot + "/uv.lock";
      rawLock =
        if builtins.pathExists lockFile then
          builtins.fromTOML (builtins.readFile lockFile)
        else
          throw ''
            p8n.uv.inferAccelerator: lockfile not found at ${toString lockFile}.
            Please run `uv lock` in your workspace first.
          '';

      parsedLock = uv2nix.lib.lock1.parseLock rawLock;

      # Find matching packages in the lockfile
      matchingPkgs = builtins.filter (p: (p.name or "") == package) (parsedLock.package or [ ]);

      # If extras are provided, filter matching packages for those matching the extra
      filteredPkgs =
        if extras != null && extras != [ ] then
          let
            matchedByVersionOrRegistry = builtins.filter (
              pkg:
              builtins.any (
                ext:
                lib.hasInfix ext (pkg.version or "")
                || lib.hasInfix ext (pkg.source.registry or "")
              ) extras
            ) matchingPkgs;
          in
          if matchedByVersionOrRegistry != [ ] then
            matchedByVersionOrRegistry
          else
            matchingPkgs
        else
          matchingPkgs;

      # Map matching packages to detected backends
      detectedBackends = map inspectPackageBackend filteredPkgs;

      # Prefer accelerated (CUDA / ROCm) configs over CPU if multiple variants exist
      accelerated = builtins.filter (b: b.acceleration != "none") detectedBackends;
    in
    if accelerated != [ ] then
      builtins.head accelerated
    else if detectedBackends != [ ] then
      builtins.head detectedBackends
    else
      # If the package itself is not in lockfile (or pure CPU workspace), return none
      {
        acceleration = "none";
      };

  inferAccelerator =
    arg:
    if builtins.isString arg then
      # Curried resolver: p8n.uv.inferAccelerator "torch"
      { workspaceRoot, extras ? null, ... }:
      inferAcceleratorDirect { inherit workspaceRoot extras; package = arg; }
    else if builtins.isAttrs arg && arg ? workspaceRoot then
      # Direct call: p8n.uv.inferAccelerator { workspaceRoot = ./.; ... }
      inferAcceleratorDirect arg
    else if builtins.isAttrs arg then
      # Config without workspaceRoot: p8n.uv.inferAccelerator { package = "torch"; }
      { workspaceRoot, extras ? null, ... }:
      inferAcceleratorDirect ({ inherit workspaceRoot extras; } // arg)
    else
      throw "p8n.uv.inferAccelerator: expected package name string or attribute set.";
in
{
  inherit inspectPackageBackend inferAccelerator inferAcceleratorDirect;
}
