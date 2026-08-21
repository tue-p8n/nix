{
  pkgs,
  lib ? pkgs.lib,
}:
let
  resolve =
    accel:
    let
      m = builtins.match "(cpu|cuda|rocm)([0-9]+_[0-9]+)?" accel;
    in
    if m == null then
      throw ''
        accelerators.resolve: unrecognised accelerator "${accel}".
        Expected: "cpu" | "cuda" | "cudaX_Y" | "rocm".
      ''
    else
      let
        accelEnum = builtins.elemAt m 0;
        accelVersion = builtins.elemAt m 1;

        parsedConfig =
          if (accelVersion != null) then
            { version = builtins.replaceStrings [ "_" ] [ "." ] accelVersion; }
          else
            { };

        baseConfig = {
          acceleration = if accelEnum == "cpu" then "none" else accelEnum;
        } // (lib.optionalAttrs (accelEnum != "cpu") {
          "${accelEnum}" = parsedConfig;
        });

        # A recursive helper that attaches the functor AND safely merges new config
        makeCallable =
          cfg:
          cfg
          // {
            __functor =
              _self: extraAccelConfig:
              makeCallable (
                lib.recursiveUpdate cfg {
                  "${accelEnum}" = extraAccelConfig;
                }
              );
          };
      in
      makeCallable baseConfig;
  evaluate =
    config:
    let
      eval = lib.evalModules {
        specialArgs = {
          pkgs' = pkgs;
        };
        modules = [
          ./schema.nix
          (builtins.removeAttrs config [ "__functor" ])
        ];
      };
      failedAssertions = builtins.filter (x: !x.assertion) eval.config.assertions;
    in
    if failedAssertions != [ ] then
      throw (lib.concatMapStringsSep "\n" (x: x.message) failedAssertions)
    else
      eval;
in
arg: (evaluate (if builtins.isAttrs arg then arg else resolve arg)).config
