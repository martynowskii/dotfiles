{ config, lib, pkgs, ... }:

let
  dotfiles = "${config.home.homeDirectory}/Documents/dotfiles";
in
{
  imports = [
    ./modules
  ];

  home.username = "arthr";
  home.homeDirectory = "/home/arthr";
  home.stateVersion = "26.05";

  programs.home-manager.enable = true;

  home.sessionVariables = {
    EDITOR = "nvim";
    VISUAL = "nvim";
    PAGER = "less -R";
  };

  home.sessionPath = [
    "$HOME/.local/bin"
    "$HOME/bin"
  ];

  programs.chromium = {
    enable = true;
    commandLineArgs = [
      "--ozone-platform=wayland"
    ];
  };

  home.file.".vim/vimrc".source =
    config.lib.file.mkOutOfStoreSymlink "${dotfiles}/vim/vimrc.vim";

  # claude-code and its unfree predicate live in ./modules/claude.nix.

  # Утилиты без собственной конфигурации. Всё, что требует настройки,
  # живёт в modules/.
  home.packages = with pkgs; [
    bat
    gcc
    gnumake
    python314
    telegram-desktop
    tree
    unzip
    vim-full
  ];
}
