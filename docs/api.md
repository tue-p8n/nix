# Library API Reference

This page documents the public API exported by `flake.lib` in `github:tue-p8n/nix`.

## Accessing the library

```nix
{
  inputs = {
    tue-p8n.url = "github:tue-p8n/nix";
    nixpkgs.follows = "tue-p8n/nixpkgs";
  };

  outputs = { tue-p8n, nixpkgs, ... }:
    let
      system = builtins.currentSystem;
      pkgs = import nixpkgs {
        inherit system;
        config = { cudaSupport = true; cudaForwardCompat = true; allowUnfree = true; };
        overlays = [ ]; # explicit -- avoids nixpkgs reading local overlay files impurely
      };
      lib = tue-p8n.lib;
    in { ... };
}
```

---

## Accelerator selectors

Every `mk-*` function with an `accelerator` argument takes one of:

| Selector                        | Meaning                                                |
| ------------------------------- | ------------------------------------------------------ |
| `"cpu"`                         | CPU-only                                               |
| `"cuda"`                        | NVIDIA CUDA, **default** version of the pinned nixpkgs |
| `"cudaX_Y"` (e.g. `"cuda12_9"`) | NVIDIA CUDA pinned to a specific major.minor           |
| `"rocm"`                        | AMD ROCm — one toolchain per nixpkgs pin, see below    |

### CPU-only / Unmodified `pkgs`

`accelerator = "cpu"` (the default across `lib.resolve` and all builders) uses the provided `pkgs` instance **as-is**, without re-importing nixpkgs, overriding CUDA/ROCm configuration flags, or injecting hardware-specific environment variables or driver hooks.

### Why pinning the CUDA version matters


`accelerator = "cuda12_6"` doesn't just rename the toolkit — it switches the
shell to a `pkgs` instance where `cudaPackages` defaults to 12.6, using
nixpkgs' canonical `cudaPackages_X_Y.pkgs` rescoping. Per-version shells
therefore produce distinct closures: cuda-aware packages (cudnn, nccl,
libcublas, …) are rebuilt against the chosen CUDA, while non-cuda packages
(zlib, glib, stdenv, git, …) are reused from the outer pkgs.

### ROCm version selection

ROCm does not support version pinning. Unlike CUDA, nixpkgs ships no
`rocmPackages_X_Y.pkgs` rescoping — only one ROCm toolchain exists per
nixpkgs revision. `accelerators.resolve` rejects a `"rocmX_Y"` selector
with an error rather than silently ignoring the version; pass `"rocm"`.

---

## `lib.resolve { pkgs, accelerator? }`

Returns `{ config, uv, mamba, micromamba, latex, typst }`.

Main entry point for resolving hardware accelerators and scoping module builders for a target environment:

- `pkgs`: mandatory nixpkgs package set.
- `accelerator`: selector string (`"cpu"`, `"cuda"`, `"cuda12_9"`, `"rocm"`) or pre-resolved `accelConfig`. Defaults to `"cpu"`.

The returned attrset contains:

- `config`: the resolved `accelConfig`.
- `uv`: `{ mkShell, mkFHS, mkProject, mkUv2nix }`
- `mamba` / `micromamba`: `{ mkShell, mkFHS }`
- `latex`: `{ mkShell, mkDocument }`
- `typst`: `{ mkShell, mkDocument }`

---

## `lib.accelerators { pkgs, lib? }`

Returns `{ resolve = string -> accelConfig; }`. Most consumers don't need
this directly — higher-level builders (`lib.resolve` or `lib.uv`, `lib.micromamba`) accept an accelerator selector and resolve it internally.

---

## `lib.uv { pkgs, accelerator? }`

Returns `{ mkShell, mkFHS, mkProject, mkUv2nix }`.


### `.mkShell { name?, accelerator? }`

Plain `pkgs.mkShell` derivation provisioning a UV-capable environment:
`uv`, build tooling, NIX_LD/NIX_LD_LIBRARY_PATH, host GPU drivers,
`UV_PROJECT_ENVIRONMENT` → `$REPO_ROOT/.venv`, and (for CUDA)
`UV_TORCH_BACKEND`. Does **not** create a venv or run `uv sync` — that's
the consumer's responsibility.

| Parameter     | Type             | Default                                        |
| ------------- | ---------------- | ---------------------------------------------- |
| `name`        | `string \| null` | `null` (auto-derived as `"uv-${accelerator}"`) |
| `accelerator` | selector         | `"cpu"`                                        |

To add packages or shell hooks, compose with `pkgs.mkShell`:

```nix
let
  base = lib.uv { inherit pkgs; }.mkShell { accelerator = "cuda12_9"; };
in
  pkgs.mkShell {
    inputsFrom = [ base ];
    packages   = [ pkgs.clang-tools ];
    shellHook  = ''
      export UV_NO_BUILD_ISOLATION=true
      export TEXINPUTS=".:$REPO_ROOT/packages//:"
    '';
  }
```

`inputsFrom` inherits the base shell's `buildInputs` and concatenates its
`shellHook`. The base sets all of its env vars via `export …` in the hook
because mkShell's `env` attrset is **not** inherited by `inputsFrom`.

### `.mkFHS { name, accelerator? }`

`buildFHSEnv` flavor for tooling that genuinely cannot work with `nix-ld`.
`name` is required; `accelerator` defaults to `"cpu"`.

### `.mkProject { name, workspaceRoot, python?, accelerator?, extras?, overrides?, packages? }` (or `.mkUv2nix`)

Builds the project's **entire** Python environment as ordinary Nix
derivations via [uv2nix] — no runtime `uv sync`. `workspaceRoot`'s
`pyproject.toml` + `uv.lock` drive the build directly; every wheel is
resolved and fetched through the lockfile at build time.

[uv2nix]: https://pyproject-nix.github.io/uv2nix/introduction.html

| Parameter       | Type                 | Default                                                                            |
| --------------- | -------------------- | ---------------------------------------------------------------------------------- |
| `name`          | `string`             | **required** — must match `[project].name` in `pyproject.toml`                     |
| `workspaceRoot` | `path`               | **required** — directory containing `pyproject.toml` + `uv.lock`                   |
| `python`        | `derivation`         | `pkgs.python313`                                                                   |
| `accelerator`   | selector             | `"cpu"`                                                                            |
| `extras`        | `[string]`           | `[]` — extra `[project.optional-dependencies]` groups beyond the accelerator's own |
| `overrides`     | `final: prev: {...}` | identity — composed _after_ the built-in autoPatchelf relaxation                   |
| `packages`      | `pkgs -> [drv]`      | `[]` — extra Nix packages (tools) added to the dev shell's `PATH`                  |

Returns `{shell, venv, pythonSet, workspace}`:

- `shell` — the dev shell derivation (`nix develop`).
- `venv` — the built virtualenv itself, usable as a `packages` output
  (`nix build`).
- `pythonSet`, `workspace` — the underlying uv2nix package set and loaded
  workspace, for consumers who need to build further derivations on top.

`accelerator` selects a `[project.optional-dependencies]` group the same way
`UV_TORCH_BACKEND` does for `mkShell`/`mkFHS` (`cpu` / `cuXYZ` / `rocm`) —
**that group must exist and be non-empty** in `pyproject.toml` (uv itself
doesn't record an extra with zero dependencies in `uv.lock`, so uv2nix has
nothing to resolve for it).

Wheels that dlopen `.so`s living in sibling wheels (`torch`, `torchvision`,
`torchaudio`, `triton`, `xformers`, `bitsandbytes`, every `nvidia-*` package)
get `autoPatchelfIgnoreMissingDeps = true` by default — this is what makes
CUDA wheels buildable at all; `overrides` composes on top of it, it doesn't
replace it.

```nix
let
  project = lib.uv { inherit pkgs; }.mkProject {
    name = "my-project";
    workspaceRoot = ./.;
    accelerator = "cuda12_9";
  };
in {
  devShells.default = project.shell;
  packages.default = project.venv;
}
```

Unlike `mkShell`/`mkFHS`, this strategy needs `uv.lock` to exist and be
**committed** — there's no deferred "run `uv sync` at shell-entry time"
step, since the whole point is that Nix already did the resolving and
building before you ever entered the shell.

---

## `lib.micromamba { pkgs }`

Returns `{ mkShell, mkFHS }` for Conda-compatible environments via
Micromamba. Both variants create the env from `${file}` on first entry,
patch it via `mm-patch.sh`, and `micromamba activate` it.

| Parameter     | Type     | Default                              |
| ------------- | -------- | ------------------------------------ |
| `name`        | `string` | **required**; also the YAML basename |
| `file`        | `path`   | `./${name}.yaml`                     |
| `accelerator` | selector | `"cpu"`                              |

---

## `lib.cuda { pkgs }`

Returns `{ mkShell }`. Bare CUDA dev shell — toolkit, host GPU drivers, no
UV/Python.

| Parameter     | Type     | Default                             |
| ------------- | -------- | ----------------------------------- |
| `name`        | `string` | `"cuda-shell"`                      |
| `accelerator` | selector | `"cuda"` (pass `"cuda12_6"` to pin) |

---

## `lib.latex { pkgs }`

Returns `{ mkShell, mkDocument }`.

- `mkShell { texpkgs? }` — `pkgs.mkShell` with `texlive.combine (texpkgs pkgs.texlive)` (defaults to `scheme-full`). Override `texpkgs` for a smaller scheme.
- `mkDocument { name, src, main?, texpkgs?, shellEscape? }` — builds a PDF derivation with `latexmk`. Extra `mkDerivation` attrs pass through.

---

## `lib.typst { pkgs }`

Returns `{ mkShell, mkDocument }`.

- `mkShell {}` — `pkgs.mkShell` with `typst`, `hayagriva`, `typstyle`.
- `mkDocument { name, src, main?, output? }` — builds a PDF derivation. Extra `mkDerivation` attrs pass through.

---

## `flakeModule` (flake-parts integration)

For consumers using [flake-parts], `tue-p8n` exposes a flake-parts module
that lets you declare dev shells declaratively:

```nix
{
  inputs = {
    tue-p8n.url = "github:tue-p8n/nix";
    nixpkgs.follows = "tue-p8n/nixpkgs";
    flake-parts.follows = "tue-p8n/flake-parts";
  };

  outputs = inputs @ { flake-parts, tue-p8n, ... }:
    flake-parts.lib.mkFlake { inherit inputs; } {
      imports = [ tue-p8n.flakeModule ];
      systems = [ "x86_64-linux" ];

      perSystem = { system, ... }: {
        # Required for any CUDA shell.
        _module.args.pkgs = import inputs.nixpkgs {
          inherit system;
          config = { cudaSupport = true; cudaForwardCompat = true; allowUnfree = true; };
          overlays = [ ]; # explicit -- avoids nixpkgs reading local overlay files impurely
        };

        tue-p8n = {
          uv.shells.dev   = { accelerator = "cuda12_9"; };
          uv.fhs.dev-fhs  = { accelerator = "cuda12_9"; };
          uv.uv2nix.native = { workspaceRoot = ./.; accelerator = "cuda12_9"; };
          cuda.shells.bare = {};
          micromamba.shells.mm = { name = "mm"; file = ./environment.yaml; accelerator = "cuda12_9"; };
          latex.shells.tex = {};
          typst.shells.tp = {};
        };
      };
    };
}
```

Each entry under `tue-p8n.<builder>.{shells,fhs}.<key>` materialises as
`devShells.<key>` (`uv.uv2nix` also materialises `packages.<key>`, the built
venv). Options per entry:

| Builder                       | Options                                                                 |
| ----------------------------- | ----------------------------------------------------------------------- |
| `uv.shells.<k>`               | `accelerator`, `name?`                                                  |
| `uv.fhs.<k>`                  | `accelerator`, `name?` (defaults to `<k>`)                              |
| `uv.uv2nix.<k>`               | `workspaceRoot`, `accelerator?`, `name?` (defaults to `<k>`), `python?` |
| `cuda.shells.<k>`             | `accelerator`, `name?`                                                  |
| `micromamba.{shells,fhs}.<k>` | `accelerator`, `name?`, `file?`                                         |
| `latex.shells.<k>`            | `texpkgs?`                                                              |
| `typst.shells.<k>`            | (none)                                                                  |

`uv.uv2nix.<k>` is deliberately narrower than the direct-lib `mkProject` API —
no `overrides`/`extras`/`packages` passthrough (function-typed flake-parts
options are awkward). Call `tue-p8n.lib.resolve { inherit pkgs; }.uv.mkProject { ... }`
directly if you need those.

The module does **not** configure `_module.args.pkgs` — set it yourself
with `cudaSupport = true; cudaForwardCompat = true; allowUnfree = true;`
if any of your shells use CUDA.

[flake-parts]: https://flake.parts

---

## `lib.getContainer`

```nix
lib.getContainer "pytorch/pytorch:2.8.0-cuda12.9-cudnn9-devel"
```

Returns `dockerTools.pullImage` args for the given OCI image tag.

---

## `accelConfig` schema

`accelerators.resolve` (and every `mk-*` builder via `accelerator`) returns:

```nix
{
  tag        : string                # the original selector ("cuda12_9", "cpu", …)
  pkgs       : <nixpkgs scope>       # rescoped pkgs (versioned CUDA) or the outer pkgs.
  stdenv     : <stdenv drv>          # CUDA: cudaPackages.backendStdenv. Else: pkgs.stdenv.
  packages   : [drv]                 # Nix packages added to the shell PATH
  env        : { name: str }         # CUDA_HOME, UV_TORCH_BACKEND, ROCM_PATH, …
  shellHook  : str                   # Per-accelerator bash (CUDA arch sniff, …)
  systemLibs : [drv]                 # Added to LD_LIBRARY_PATH / NIX_LD_LIBRARY_PATH
}
```

Builders should use `accelConfig.pkgs` (not the outer `pkgs`) so cuda-aware
references resolve against the user-selected version.
