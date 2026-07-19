{ ... }:
{
  programs.bash = {
    enable = true;
    shellAliases = {
      ll = "ls -la";
      gs = "git status";
    };
  };
  programs.starship.enable = true;
}
