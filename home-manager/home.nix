{ config, lib, pkgs, ... }:

let
  dotfiles = "${config.home.homeDirectory}/Documents/dotfiles";

  nvimPkgs = import (builtins.fetchTarball {
    url = "https://github.com/NixOS/nixpkgs/archive/832efc09b4caf6b4569fbf9dc01bec3082a00611.tar.gz";
    sha256 = "1sxhlp1khk9ifh24lcg5qland4pg056l5jhyfw8xq3qmpavf390x";
  }) { system = pkgs.stdenv.hostPlatform.system; };
in
{
  imports = [
    ./zsh.nix
  ];

  home.username = "arthr";
  home.homeDirectory = "/home/arthr";
  home.stateVersion = "26.05";

  programs.home-manager.enable = true;

  home.sessionVariables = {
    EDITOR = "nvim";
    VISUAL = "nvim";
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

  programs.tmux = {
    enable = true;
    keyMode = "vi";
    escapeTime = 10;
  };

  programs.fzf = {
    enable = true;
    enableZshIntegration = true;
  };

  xdg.configFile."nvim".source =
    config.lib.file.mkOutOfStoreSymlink "${dotfiles}/nvim";

  xdg.configFile."niri".source =
    config.lib.file.mkOutOfStoreSymlink "${dotfiles}/niri";

  home.file.".vim/vimrc".source =
    config.lib.file.mkOutOfStoreSymlink "${dotfiles}/vim/vimrc.vim";

  home.packages = with pkgs; [
    bat
    telegram-desktop
    tree
    vim-full
    nvimPkgs.neovim
    lua-language-server
  ];
}
