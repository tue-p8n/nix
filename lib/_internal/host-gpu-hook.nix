# NixOS picks up host GPU drivers via `/run/opengl-driver/lib`; elsewhere
# `nixglhost -p` reports the same. `TRITON_LIBCUDA_PATH` is needed because
# Triton dlopens libcuda.so by name and won't find it in the Nix store.
# Triton reads it as a *directory* (passed straight to `-L` when JIT-
# compiling a kernel launcher) -- pointing it at the `.so` file itself
# produces an invalid `-L/.../libcuda.so` linker flag.
nixglhost: ''
  if [ -f "/etc/NIXOS" ]; then
    if [ -d "/run/opengl-driver/lib" ]; then
      export LD_LIBRARY_PATH="/run/opengl-driver/lib:$LD_LIBRARY_PATH"
      export TRITON_LIBCUDA_PATH="/run/opengl-driver/lib"
    fi
  else
    if host_libs=$(${nixglhost}/bin/nixglhost -p 2>/dev/null); then
      export LD_LIBRARY_PATH="$host_libs:$LD_LIBRARY_PATH"
    fi
  fi
''
