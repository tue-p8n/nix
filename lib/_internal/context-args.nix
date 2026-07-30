# Names of the context arguments `lib/default.nix`'s `mkBuilder` injects
# into every `mk-*.nix` builder (`pkgs`, `lib`, the resolved `accelerators`,
# etc. -- see `ctx` there). Shared with `lib/flake-module.nix`'s builder
# coverage check so both files agree on what counts as "context" versus
# "consumer-facing" when deciding a builder's real option surface.
[
  "pkgs"
  "lib"
  "shell"
  "uvShell"
  "path"
  "uv2nix"
  "pyprojectNix"
  "pyprojectBuildSystems"
  "accelerators"
  "nixglhost"
]
