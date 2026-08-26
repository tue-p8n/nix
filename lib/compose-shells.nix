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

  ignoreConflicts = customArgs.ignoreConflicts or (customArgs.allowIncompatible or false);

  # 1. Accelerator Compatibility Validation
  accelShells = lib.filter (
    s:
    let
      cfg = s.passthru.config or null;
      accelName = s.passthru.p8n.accelerator or (if cfg != null then cfg.name else null);
    in
    cfg != null && cfg.acceleration != "none" && accelName != null && accelName != "cpu"
  ) validShells;

  accelTags = lib.unique (
    map (s: s.passthru.p8n.accelerator or s.passthru.config.name) accelShells
  );

  checkAccelerators =
    if (!ignoreConflicts && builtins.length accelTags > 1) then
      let
        details = map (
          s: "  - Shell '${s.name or "anonymous"}': accelerator '${s.passthru.p8n.accelerator or s.passthru.config.name}'"
        ) accelShells;
      in
      throw ''
        p8n.composeShells: conflicting accelerator configurations detected:
        ${lib.concatStringsSep "\n" details}
        Cannot compose shells with different hardware accelerator targets (e.g. different CUDA versions or CUDA vs ROCm).
        To bypass this check, pass `{ ignoreConflicts = true; ... }`.
      ''
    else
      true;

  # 2. Python Environment Invariance Validation
  pythonShells = lib.filter (
    s:
    (s.passthru.p8n.category or null) == "python"
    || (s.passthru ? venv)
    || (s.passthru ? pythonSet)
  ) validShells;

  distinctPythonEnvironments = lib.unique (
    map (
      s:
      let
        p8nMeta = s.passthru.p8n or { };
        flavor = p8nMeta.flavor or "custom";
        venvPath = if s.passthru ? venv then (toString s.passthru.venv) else (s.passthru.p8n.name or (s.name or "dynamic-uv"));
      in
      "${flavor}:${venvPath}"
    ) pythonShells
  );

  checkPython =
    if (!ignoreConflicts && builtins.length distinctPythonEnvironments > 1) then
      let
        descriptions = map (
          s:
          let
            flavor = s.passthru.p8n.flavor or (if s.passthru ? venv then "uv2nix (pure-Nix venv)" else "dynamic Python");
            name = s.passthru.p8n.name or (s.name or "anonymous");
          in
          "  - '${name}': flavor '${flavor}'"
        ) pythonShells;
      in
      throw ''
        p8n.composeShells: conflicting Python environments detected:
        ${lib.concatStringsSep "\n" descriptions}
        Cannot compose multiple distinct Python virtual environments (e.g. locked uv2nix virtualenv with dynamic uv shell, or two different uv projects).
        Choose one primary Python environment for the shell, or pass `{ ignoreConflicts = true; ... }` to bypass.
      ''
    else
      true;

  # 3. LaTeX Version Invariance Validation
  latexShells = lib.filter (
    s:
    (s.passthru.p8n.category or null) == "latex"
    || (s.passthru ? tex)
  ) validShells;

  distinctTex = lib.unique (
    map (
      s:
      if s.passthru ? tex then
        (toString s.passthru.tex)
      else
        (s.passthru.p8n.texlive or "custom")
    ) latexShells
  );

  checkLatex =
    if (!ignoreConflicts && builtins.length distinctTex > 1) then
      let
        descriptions = map (
          s:
          let
            ver = s.passthru.p8n.texlive or "custom";
            name = s.name or "latex-shell";
          in
          "  - '${name}': texlive '${ver}'"
        ) latexShells;
      in
      throw ''
        p8n.composeShells: conflicting LaTeX / TeX Live versions detected:
        ${lib.concatStringsSep "\n" descriptions}
        Cannot compose shells with different TeX Live package sets.
        To bypass this check, pass `{ ignoreConflicts = true; ... }`.
      ''
    else
      true;

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
    assert checkAccelerators;
    assert checkPython;
    assert checkLatex;
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
