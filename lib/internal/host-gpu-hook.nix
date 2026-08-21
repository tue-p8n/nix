# NixOS picks up host GPU drivers via `/run/opengl-driver/lib`; elsewhere
# `nixglhost -p` reports the same. `TRITON_LIBCUDA_PATH` is needed because
# Triton dlopens libcuda.so by name and won't find it in the Nix store.
# Triton reads it as a *directory* (passed straight to `-L` when JIT-
# compiling a kernel launcher) -- pointing it at the `.so` file itself
# produces an invalid `-L/.../libcuda.so` linker flag.
#
# `nixglhost` may be null: it is absent from some nixpkgs revisions, and
# `mk-*.nix` resolve it with `pkgs.nixglhost or null`. Only the non-NixOS
# branch needs it, so the NixOS branch must not be gated on it -- doing so
# left NixOS hosts with no driver on the loader path at all, and torch then
# reports "Found no NVIDIA driver on your system" despite a working
# nvidia-smi.
nixglhost: ''
  if [ -f "/etc/NIXOS" ]; then
    if [ -d "/run/opengl-driver/lib" ]; then
      export LD_LIBRARY_PATH="/run/opengl-driver/lib:$LD_LIBRARY_PATH"
      export TRITON_LIBCUDA_PATH="/run/opengl-driver/lib"
    fi
  ${
    if nixglhost != null
    then ''
      else
        if host_libs=$(${nixglhost}/bin/nixglhost -p 2>/dev/null); then
          export LD_LIBRARY_PATH="$host_libs:$LD_LIBRARY_PATH"
        fi
    ''
    else ''
      else
        echo "warning: not NixOS and nixglhost is unavailable in this nixpkgs;" >&2
        echo "         host GPU drivers are not on LD_LIBRARY_PATH." >&2
    ''
  }
  fi
''
