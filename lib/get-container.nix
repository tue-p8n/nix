# This function returns a container spec from the registry by name.
# The registry is a lost of container specs.
_:
let
  registry = builtins.listToAttrs (
    builtins.map
      (spec: {
        name = "${spec.finalImageName}:${spec.finalImageTag}";
        value = spec;
      })
      [
        {
          imageName = "pytorch/pytorch";
          imageDigest = "sha256:cf5aa3f7045a68c10d80f546746591c5ccae6a33729e5e32625ff76bd2c036fe";
          hash = "sha256-qiwnTb4G7IN45IDiiCgeEeqLJmNPrJxfL0RWZVJpkGQ=";
          finalImageName = "pytorch/pytorch";
          finalImageTag = "2.8.0-cuda12.9-cudnn9-devel";
        }
      ]
  );
in
name: builtins.getAttr name registry
