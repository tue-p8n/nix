# `escapeShellArg` is load-bearing: values come from accelConfig.env which
# is interpolated from Nix store paths and version strings. A naive
# "export ${n}=\"${v}\"" would break on values containing quotes or `$`,
# and worse, would be a shell-injection seam if values ever became
# consumer-controlled.
{lib}: env:
lib.concatStringsSep "\n" (lib.mapAttrsToList (n: v: "export ${n}=${lib.escapeShellArg v}") env)
