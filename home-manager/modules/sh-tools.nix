{ config, pkgs, ... }:

let
  dotfiles = "${config.home.homeDirectory}/Documents/dotfiles";
in
{
  home.packages = [ pkgs.yazi ];

  xdg.configFile."yazi".source =
    config.lib.file.mkOutOfStoreSymlink "${dotfiles}/yazi";

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
