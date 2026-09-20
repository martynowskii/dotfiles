{ pkgs, ... }:

{
  home.packages = [ pkgs.yazi ];

  programs.tmux = {
    enable = true;
    keyMode = "vi";
    escapeTime = 10;
  };

  programs.fzf = {
    enable = true;
    enableZshIntegration = true;
  };
}
