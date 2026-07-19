{ ... }:
{
  _meta.type = "test";

  programs.neovim = {
    enable = true;
    defaultEditor = true;
  };
}
