# Curated set of system libraries for accelerators.
{
  lib,
  config,
  pkgs,
  ...
}:
let
  this = config.libraries;
in
{
  options.libraries = {
    runtime = lib.mkEnableOption "Include runtime libraries.";
    graphics = lib.mkEnableOption "Include graphics libraries.";
    media = lib.mkEnableOption "Include media libraries.";
    extraPackages = lib.mkOption {
      type = lib.types.listOf lib.types.package;
      default = [ ];
      description = "A list of extra packages to include in the environment.";
    };
    packages = lib.mkOption {
      type = lib.types.listOf lib.types.package;
      description = "A list of packages to include in the environment.";
    };
  };
  config = lib.mkMerge [
    # Default runtime libraries
    (lib.mkIf this.runtime {
      libraries.packages = with pkgs; [
        stdenv.cc.cc.lib
        zlib
        bzip2
        xz
        zstd
        openssl
        libffi
        ncurses
        libxml2
        expat
      ];
    })

    # Default graphics libraries
    (lib.mkIf this.graphics {
      libraries.packages = with pkgs; [
        libGL
        libGLU
        libglvnd
        libxkbcommon
        glib
        libx11
        libxext
        libxrender
        libsm
        libice
        libxrandr
        libxcursor
        libxi
        libxinerama
        libxfixes
        libxxf86vm
        libxcb
        dbus
      ];
    })

    # Default media libraries
    (lib.mkIf this.media {
      libraries.packages = with pkgs; [
        libjpeg
        libpng
        libtiff
        libwebp
        giflib
        openjpeg
        freetype
        fontconfig
        harfbuzz
        ffmpeg
      ];
    })

    # Extra packages
    (lib.mkIf (this.extraPackages != [ ]) {
      libraries.packages = this.extraPackages;
    })
  ];
}
