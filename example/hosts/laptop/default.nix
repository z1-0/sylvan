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
      "networkmanager"
    ];
    hashedPassword = "$6$IzeHoJ5nXOYZWnrY$QoCFph20pxKGS4fbgUbg3DX3ofYeiubuRzRd8viEJ9pQr6lCdEl1EbIXVNmw35TjBuOCBF9mJ4VcaCyS8Ipc8.";
  };

  users.users.bob = {
    isNormalUser = true;
    extraGroups = [ "wheel" ];
  };
}
