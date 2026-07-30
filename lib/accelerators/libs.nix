# Curated set of system libraries for accelerators.
{ pkgs }:
let
  runtime = with pkgs; [
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

  graphics = with pkgs; [
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

  media = with pkgs; [
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
in
{
  inherit runtime;
  inherit graphics;
  inherit media;
  all = runtime ++ graphics ++ media;
}
