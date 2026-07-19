{ self, inputs, config, lib, ... }:
{
  imports = [
    (import (inputs.nixpkgs + "/nixos/modules/misc/nixpkgs.nix"))
  ];

  options.example = lib.mkOption {
    type = lib.types.str;
    default = "hello from flake-parts";
    description = "An example flake option";
  };

  config = {
    flake.exampleOut = config.example;
  };
}