# Utilities for composing multiple devShells into a unified shell environment.
{
  lib,
  internal,
  self,
  ...
}:
args:
let
  isList = builtins.isList args;
  rawShells =
    if isList then
      args
    else
      (if args ? base && args.base != null then [ args.base ] else [ ])
      ++ (args.shells or [ ]);
  validShells = lib.filter (s: s != null && s != false) rawShells;

  customArgs = if builtins.isAttrs args && !isList then args else { };

  base =
    if validShells == [ ] then
      throw "p8n.composeShells: expected at least one shell to compose."
    else
      builtins.head validShells;
  rest = builtins.tail validShells;

  extraPackages = customArgs.packages or (customArgs.extraPackages or [ ]);
  extraShellHook = customArgs.shellHook or "";
  extraEnv = customArgs.env or { };
  preCommit = customArgs.preCommit or (self.preCommit or null);
  customName = customArgs.name or null;
  extraPassthru = customArgs.passthru or { };

  mergedPassthru =
    lib.foldl' (acc: s: acc // (s.passthru or { })) (base.passthru or { }) rest
    // extraPassthru;

  composedShell =
    if base ? overrideAttrs then
      base.overrideAttrs (old: {
        name = if customName != null then customName else (old.name or "composed-shell");
        inputsFrom = (old.inputsFrom or [ ]) ++ rest;
        nativeBuildInputs =
          (old.nativeBuildInputs or [ ])
          ++ extraPackages
          ++ (internal.preCommit.packages preCommit);
        shellHook =
          (old.shellHook or "")
          + (lib.optionalString (extraEnv != { }) "\n${internal.exportEnv extraEnv}")
          + (lib.optionalString (preCommit != null) "\n${internal.preCommit.hook preCommit}")
          + (lib.optionalString (extraShellHook != "") "\n${extraShellHook}");
        passthru = (old.passthru or { }) // mergedPassthru;
      })
    else
      throw "p8n.composeShells: the base shell does not support `overrideAttrs`. Ensure all elements in the list are devShell derivations.";
in
composedShell // { passthru = mergedPassthru; }
