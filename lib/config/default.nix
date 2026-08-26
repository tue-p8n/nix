{
  lib,
}:
let
  # Resolve an accelerator string to a config attrset.
  resolve =
    accel:
    let
      m = builtins.match "(none|cpu|cuda|cu|rocm)(_?[0-9]+[._]?[0-9]*)?" accel;
    in
    if m == null then
      throw ''
        accelerators.resolve: unrecognised accelerator "${accel}".
        Expected: "none" | "cpu" | "cuda" | "cu" | "cu128" | "cuda12_8" | "rocm".
      ''
    else
      let
        rawEnum = builtins.elemAt m 0;
        rawVersion = builtins.elemAt m 1;
        accelEnum = if rawEnum == "cu" then "cuda" else rawEnum;

        cleanVersion =
          if rawVersion == null then
            null
          else
            let
              v = lib.removePrefix "_" rawVersion;
            in
            if builtins.match "[0-9]+_[0-9]+" v != null then
              builtins.replaceStrings [ "_" ] [ "." ] v
            else if builtins.match "[0-9]+[.][0-9]+" v != null then
              v
            else if builtins.stringLength v == 3 then
              "${builtins.substring 0 2 v}.${builtins.substring 2 1 v}"
            else
              v;

        parsedConfig =
          if (cleanVersion != null) then
            { version = cleanVersion; }
          else
            { };

        baseConfig =
          let
            acceleration = if accelEnum == "cpu" then "none" else accelEnum;
          in
          {
            inherit acceleration;
          }
          // (lib.optionalAttrs (accelEnum != "none" && accelEnum != "cpu") {
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
                if accelEnum != "none" && accelEnum != "cpu" then
                  lib.recursiveUpdate cfg {
                    "${accelEnum}" = extraAccelConfig;
                  }
                else
                  cfg
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
