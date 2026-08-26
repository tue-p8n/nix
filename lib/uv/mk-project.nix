context@{ ... }:
let
  readProjectFn = import ./read-project.nix context;
in
{
  mkProject = args: (readProjectFn args).mkShell { };
}
