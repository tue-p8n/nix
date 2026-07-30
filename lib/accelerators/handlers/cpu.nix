{ pkgs }:
{
  inherit pkgs;
  stdenv = pkgs.stdenv;
  packages = [ ];
  env = { };
  shellHook = "";
  systemLibs = [ ];
}
