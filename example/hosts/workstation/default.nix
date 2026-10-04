{
  config,
  pkgs,
  lib,
  ...
}:
{
  nixpkgs.hostPlatform = "x86_64-linux";

  users.users.alice = {
    isNormalUser = true;
    extraGroups = [
      "wheel"
      "docker"
    ];
  };

  system.stateVersion = lib.versions.majorMinor lib.version;
}
