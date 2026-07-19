{
  inputs = {
    flake-parts.url = "github:hercules-ci/flake-parts";
    metatree.url = "github:z1-0/metatree-nix";
    srctree.url = "github:z1-0/srctree-nix";
  };

  outputs = inputs: {
    __functor =
      _: userInputs: root:
      import ./lib { inherit inputs userInputs root; };
  };
}
