{
  pkgs,
  lib ? pkgs.lib,
}:
let
  commonLibs = import ./libs.nix { inherit pkgs; };

  # Contract Assertion Validator
  requiredContractKeys = [
    "pkgs"
    "stdenv"
    "packages"
    "env"
    "shellHook"
    "systemLibs"
  ];

  validateContract =
    accel:
    let
      missing = lib.subtractLists (builtins.attrNames accel) requiredContractKeys;
    in
    if missing != [ ] then
      throw "accelerators: target implementation is missing required contract key(s): ${builtins.toJSON missing}"
    else if !lib.isAttrs accel.pkgs then
      throw "accelerators contract violation: `pkgs` must be an attribute set"
    else if !lib.isList accel.packages then
      throw "accelerators contract violation: `packages` must be a list"
    else if !lib.isAttrs accel.env then
      throw "accelerators contract violation: `env` must be an attribute set"
    else if !lib.isString accel.shellHook then
      throw "accelerators contract violation: `shellHook` must be a string"
    else if !lib.isList accel.systemLibs then
      throw "accelerators contract violation: `systemLibs` must be a list"
    else
      accel;

  handlers = {
    cpu = _: import ./handlers/cpu.nix { inherit pkgs; };
    cuda =
      version:
      import ./handlers/cuda.nix {
        inherit
          pkgs
          lib
          version
          ;
      };
    rocm = version: import ./handlers/rocm.nix { inherit pkgs version; };
  };
in
{
  resolve =
    s:
    let
      m = builtins.match "(cpu|cuda|rocm)([0-9]+_[0-9]+)?" s;
    in
    if m == null then
      throw ''
        accelerators.resolve: unrecognised accelerator "${s}".
        Expected: "cpu" | "cuda" | "cudaX_Y" | "rocm".
      ''
    else
      let
        kind = builtins.elemAt m 0;
        version = builtins.elemAt m 1;
        handler = handlers.${kind} version;
        result = validateContract (handler // { systemLibs = commonLibs.all ++ handler.systemLibs; });
      in
      result // { tag = s; };
}
