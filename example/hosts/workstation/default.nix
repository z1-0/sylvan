{
  config,
  pkgs,
  lib,
  ...
}:
{
  # platform attribute set with an ABI suffix; sylvan normalizes it to `x86_64-linux'
  nixpkgs.hostPlatform = {
    config = "x86_64-unknown-linux-gnu";
  };

  users.users.alice = {
    isNormalUser = true;
    extraGroups = [
      "wheel"
      "docker"
    ];
  };
}
