{ ... }:
{
  _meta = {
    author = "meta-test";
    description = "meta test";
    tags = [ "test" "shared" ];
  };

  environment.variables.META_TEST_SHARED = "shared";
}
