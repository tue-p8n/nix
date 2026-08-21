{
  lib,
}:
let
  # Resolve an accelerator string to a config attrset.
  resolve =
    accel:
    let
      m = builtins.match "(none|cpu|cuda|rocm)([0-9]+_[0-9]+)?" accel;
    in
    if m == null then
      throw ''
        accelerators.resolve: unrecognised accelerator "${accel}".
        Expected: "none" | "cpu" | "cuda" | "cudaX_Y" | "rocm".
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

        baseConfig =
          let
            acceleration = if accelEnum == "cpu" then "none" else accelEnum;
          in
          {
            inherit acceleration;
          }
          // (lib.optionalAttrs (accelEnum != "none") {
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

  # Evaluate the accelerator module.
  evaluate =
    pkgs: config:
    let
      eval = lib.evalModules {
        specialArgs = {
          pkgs' = pkgs;
        };
        modules = [
          ./modules
          (builtins.removeAttrs config [ "__functor" ])
        ];
      };
      failedAssertions = builtins.filter (x: !x.assertion) eval.config.assertions;
    in
    if failedAssertions != [ ] then
      throw (lib.concatMapStringsSep "\n" (x: x.message) failedAssertions)
    else
      eval;

  # A helper that evaluates a config, resolving the `args` to an attrset if needed.
  build = pkgs: arg: (evaluate pkgs (if builtins.isAttrs arg then arg else resolve arg)).config;
in
{
  inherit resolve build;
}
