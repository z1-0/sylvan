{ ... }:
{
  _meta = {
    author = "meta-test";
    description = "meta test";
    tags = [ "test" "nixos" ];
  };

  environment.variables.META_TEST_NIXOS = "nixos";
}
