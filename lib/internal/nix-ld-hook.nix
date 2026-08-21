# `pkgs` must be the (possibly rescoped) scope owning `stdenv.cc`.
{lib}: pkgs: libPath: ''
  export NIX_LD_LIBRARY_PATH="${libPath}"
  export NIX_LD="${lib.fileContents "${pkgs.stdenv.cc}/nix-support/dynamic-linker"}"
  if [ -f "/etc/NIXOS" ] && [ -z "$NIX_LD" ]; then
    echo " >>> WARNING: Nix-LD not detected but required for native shells on NixOS."
    echo "     Please add 'programs.nix-ld.enable = true;' to your system configuration."
  fi
''
