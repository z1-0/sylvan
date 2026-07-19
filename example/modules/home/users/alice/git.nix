{ ... }:
{
  programs.git = {
    enable = true;
    settings = {
      user.name = "Alice";
      user.email = "alice@example.com";
      core.editor = "vim";
    };
  };
}
