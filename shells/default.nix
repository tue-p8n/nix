# Opinionated set of development shells.
{
  inputs,
  pkgs,
}:
let
  uv = inputs.self.lib.uv { inherit pkgs; };
  micromamba = inputs.self.lib.micromamba { inherit pkgs; };
  cuda = inputs.self.lib.cuda { inherit pkgs; };
  latex = inputs.self.lib.latex { inherit pkgs; };
  typst = inputs.self.lib.typst { inherit pkgs; };

in
{
  mamba-py313cu129 = micromamba.mkShell {
    name = "mamba-py313cu129";
    accelerator = "cuda12_9";
  };
  cuda = cuda.mkShell { };
  latex = latex.mkShell { };
  typst = typst.mkShell { };
}

# Python shells using UV.
// builtins.listToAttrs (
  map
    (a: {
      name = "uv-${a}";
      value = uv.mkShell { accelerator = a; };
    })
    [
      "cpu"
      "cuda12_6"
      "cuda13_0"
      "rocm"
    ]
)

# Python environments using `micromamba` and FHS.
// pkgs.lib.mapAttrs (name: accelerator: (micromamba.mkFHS { inherit name accelerator; }).env) {
  mamba-fhs-py313cu128 = "cuda12_8";
  mamba-fhs-py313cu129 = "cuda12_9";
}
