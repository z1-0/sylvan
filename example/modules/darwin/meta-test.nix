{ ... }:
{
  _meta = {
    author = "meta-test";
    description = "meta test";
    tags = [ "test" "darwin" ];
  };

  system.defaults.NSGlobalDomain.InitialKeyRepeat = 15;
}
