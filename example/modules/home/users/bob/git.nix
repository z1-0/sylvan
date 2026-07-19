{ ... }:
{
  programs.git = {
    enable = true;
    settings = {
      user.name = "Bob";
      user.email = "bob@example.com";
    };
  };
}
