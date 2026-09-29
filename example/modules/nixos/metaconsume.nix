{ inputs, ... }:
{
  _meta = { note = "consumes lib.metaModules"; };
  environment.etc."meta-probe".text =
    inputs.self.lib.metaModules.nixos.meta-test.meta.description;
}
