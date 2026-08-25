# Pre-commit hook and package extractor for p8n devShells
# ========================================================
{
  packages =
    preCommit:
    if preCommit != null && preCommit != false && (preCommit ? settings) then
      [ preCommit.settings.package ] ++ (preCommit.settings.enabledPackages or [ ])
    else
      [ ];

  hook =
    preCommit:
    if preCommit != null && preCommit != false && (preCommit ? installationScript) then
      preCommit.installationScript
    else
      "";
}
