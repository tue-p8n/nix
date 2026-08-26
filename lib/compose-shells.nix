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
  resolveShell =
    s:
    if builtins.isAttrs s && (s ? mkShell && builtins.isFunction s.mkShell) && !(s ? type && s.type == "derivation") then
      s.mkShell { }
    else
      s;

  rawShells =
    if isList then
      map resolveShell args
    else
      (if args ? base && args.base != null then [ (resolveShell args.base) ] else [ ])
      ++ (map resolveShell (args.shells or [ ]));
  validShells = lib.filter (s: s != null && s != false) rawShells;

  customArgs = if builtins.isAttrs args && !isList then args else { };

  base =
    if validShells == [ ] then
      throw "p8n.composeShells: expected at least one shell to compose."
    else
      builtins.head validShells;
  rest = builtins.tail validShells;

  ignoreConflicts = customArgs.ignoreConflicts or (customArgs.allowIncompatible or false);

  getMeta =
    s:
    let
      pt = if (builtins.isAttrs s && s ? passthru && builtins.isAttrs s.passthru) then s.passthru else { };
    in
    {
      p8n = pt.p8n or (if builtins.isAttrs s then s.p8n or { } else { });
      config = pt.config or (if builtins.isAttrs s then s.config or null else null);
      venv = pt.venv or (if builtins.isAttrs s then s.venv or null else null);
      pythonSet = pt.pythonSet or (if builtins.isAttrs s then s.pythonSet or null else null);
      tex = pt.tex or (if builtins.isAttrs s then s.tex or null else null);
      name = if builtins.isAttrs s then s.name or "anonymous" else "anonymous";
    };

  # 1. Accelerator Compatibility Validation
  accelShells = lib.filter (
    s:
    let
      meta = getMeta s;
      cfg = meta.config;
      accelName = meta.p8n.accelerator or (if cfg != null then cfg.name else null);
    in
    cfg != null && cfg.acceleration != "none" && accelName != null && accelName != "cpu"
  ) validShells;

  accelTags = lib.unique (
    map (
      s:
      let
        meta = getMeta s;
      in
      meta.p8n.accelerator or (if meta.config != null then meta.config.name else null)
    ) accelShells
  );

  checkAccelerators =
    if (!ignoreConflicts && builtins.length accelTags > 1) then
      let
        details = map (
          s:
          let
            meta = getMeta s;
          in
          "  - Shell '${meta.name}': accelerator '${meta.p8n.accelerator or meta.config.name}'"
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
    let
      meta = getMeta s;
    in
    (meta.p8n.category or null) == "python"
    || meta.venv != null
    || meta.pythonSet != null
  ) validShells;

  distinctPythonEnvironments = lib.unique (
    map (
      s:
      let
        meta = getMeta s;
        flavor = meta.p8n.flavor or "custom";
        venvPath =
          if meta.venv != null then
            (toString meta.venv)
          else
            (meta.p8n.name or meta.name);
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
            meta = getMeta s;
            flavor =
              meta.p8n.flavor or (
                if meta.venv != null then "uv2nix (pure-Nix venv)" else "dynamic Python"
              );
            name = meta.p8n.name or meta.name;
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
    let
      meta = getMeta s;
    in
    (meta.p8n.category or null) == "latex" || meta.tex != null
  ) validShells;

  distinctTex = lib.unique (
    map (
      s:
      let
        meta = getMeta s;
      in
      if meta.tex != null then
        (toString meta.tex)
      else
        (meta.p8n.texlive or "custom")
    ) latexShells
  );

  checkLatex =
    if (!ignoreConflicts && builtins.length distinctTex > 1) then
      let
        descriptions = map (
          s:
          let
            meta = getMeta s;
            ver = meta.p8n.texlive or "custom";
            name = meta.name;
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

  accelTag =
    if builtins.length accelTags > 0 then
      builtins.head accelTags
    else
      null;

  cleanSegment =
    s:
    let
      meta = getMeta s;
      p8nName = meta.p8n.name or null;
      rawName = if p8nName != null then p8nName else (s.name or "shell");
      withoutShell = lib.removeSuffix "-shell" rawName;
      withoutTag =
        if accelTag != null then
          lib.removeSuffix "+${accelTag}" (lib.removeSuffix "-${accelTag}" withoutShell)
        else
          withoutShell;
    in
    withoutTag;

  segments = lib.unique (map cleanSegment validShells);
  joinedSegments = lib.concatStringsSep "-" segments;

  synthesizedName =
    if customName != null then
      customName
    else if builtins.length validShells <= 1 then
      base.name or "composed"
    else if accelTag != null && accelTag != "none" && accelTag != "cpu" then
      "${joinedSegments}+${accelTag}"
    else
      joinedSegments;

  mergedPassthru =
    lib.foldl' (acc: s: acc // (if s ? passthru && builtins.isAttrs s.passthru then s.passthru else { })) (if base ? passthru && builtins.isAttrs base.passthru then base.passthru else { }) rest
    // extraPassthru;

  composedShell =
    assert checkAccelerators;
    assert checkPython;
    assert checkLatex;
    if base ? overrideAttrs then
      base.overrideAttrs (old: {
        name = synthesizedName;
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
