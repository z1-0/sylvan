{ pkgs, ... }:
pkgs.stdenv.mkDerivation {
  pname = "hello";
  version = "0.1";
  buildPhase = ''
    mkdir -p $out/bin
    printf '#!/bin/sh\nprintf "hello\\n"\n' > $out/bin/hello
    chmod +x $out/bin/hello
  '';
  doInstallCheck = false;
}