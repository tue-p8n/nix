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
      readOnly = true;
      description = "A list of packages to include in the environment.";
    };
  };
  config = lib.mkMerge [
    # Default runtime libraries
    (lib.mkIf this.runtime.enable {
      packages = with pkgs; [
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
    (lib.mkIf this.graphics.enable {
      packages = with pkgs; [
        libGL
        libGLU
        libglvnd
        libxkbcommon
        glib
        libX11
        libXext
        libXrender
        libSM
        libICE
        libXrandr
        libXcursor
        libXi
        libXinerama
        libXfixes
        libXxf86vm
        libxcb
        dbus
      ];
    })

    # Default media libraries
    (lib.mkIf this.media.enable {
      packages = with pkgs; [
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
    (lib.mkIf (this.extras or [ ]) {
      packages = this.extraPackages;
    })
  ];
}
