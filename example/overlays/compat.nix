final: prev: {
  # Example: add a custom overlay
  myTools = prev.stdenv.mkDerivation {
    pname = "my-tools";
    version = "0.1";
    src = ./.;
  };
}
