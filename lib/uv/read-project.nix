{
  self,
  inputs,
  lib,
  ...
}:
args:
let
  workspaceRoot =
    if builtins.isPath args || builtins.isString args then
      args
    else if builtins.isAttrs args && args ? workspaceRoot then
      args.workspaceRoot
    else
      throw "p8n.uv.readProject: expected a workspaceRoot path or an attribute set containing `workspaceRoot`.";

  customArgs = if builtins.isAttrs args then args else { };
  workspace = inputs.uv2nix.lib.workspace.loadWorkspace { inherit workspaceRoot; };
  inferHelper = import ./infer-accelerator.nix { inherit lib inputs; };
in
rec {
  inherit workspace workspaceRoot;

  # Query & Inference helpers
  inferAccelerator =
    pkgArg:
    let
      package =
        if builtins.isString pkgArg then
          pkgArg
        else if builtins.isAttrs pkgArg then
          pkgArg.package or "torch"
        else
          "torch";
      extras = if builtins.isAttrs pkgArg then pkgArg.extras or null else null;
    in
    inferHelper.inferAccelerator {
      inherit workspaceRoot package extras;
    };

  # Target builders bound to this workspace
  build =
    buildArgs:
    let
      # If accelerator is a resolver function, evaluate it
      accelInput = buildArgs.accelerator or (customArgs.accelerator or "cpu");
      resolvedAccel =
        if builtins.isFunction accelInput then
          accelInput { inherit workspaceRoot workspace inferAccelerator; }
        else
          accelInput;
    in
    self.uv.mkProject (
      customArgs
      // buildArgs
      // {
        inherit workspaceRoot;
        accelerator = resolvedAccel;
      }
    );

  shell = buildArgs: (build buildArgs).shell;
  oci = buildArgs: (build buildArgs).oci;
  sif = buildArgs: (build buildArgs).sif;
}
