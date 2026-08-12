{ config, lib, pkgs, ... }:

let
  dotfiles = "${config.home.homeDirectory}/Documents/dotfiles";
in
{
  programs.zsh = {
    enable = true;
    autocd = true;
    dotDir = "${config.home.homeDirectory}/.config/zsh";

    enableCompletion = true;
    autosuggestion.enable = true;
    syntaxHighlighting.enable = true;

    oh-my-zsh = {
      enable = true;
      theme = "";                    # тему рисует p10k
      plugins = [
        "git"
        # "sudo"                       # ESC ESC — префикс sudo к последней команде
        # "extract"                    # x archive.tar.gz — любой формат
        "colored-man-pages"
        "command-not-found"
      ];
    };

    history = {
      path = "${config.xdg.dataHome}/zsh/history";
      size = 10000;
      ignoreDups = true;
    };

    shellAliases = {
      hms = "home-manager switch -b backup";
      nrs = "nixos-rebuild switch";
    };

    plugins = [
      {
        name = "powerlevel10k";
        src = pkgs.zsh-powerlevel10k;
        file = "share/zsh-powerlevel10k/powerlevel10k.zsh-theme";
      }
    ];

    initContent = lib.mkMerge [
      (lib.mkBefore ''
        if [[ -r "${config.xdg.cacheHome}/p10k-instant-prompt-''${(%):-%n}.zsh" ]]; then
          source "${config.xdg.cacheHome}/p10k-instant-prompt-''${(%):-%n}.zsh"
        fi
      '')
      ''
        HISTFILE="${config.xdg.dataHome}/zsh/history"

        source ${dotfiles}/zsh/p10k.zsh
        source ${dotfiles}/zsh/yandex.zsh

        if [ -S "$HOME/.ssh/ssh_auth_sock" ]; then
          export SSH_AUTH_SOCK="$HOME/.ssh/ssh_auth_sock"
        fi
      ''
    ];
  };
}

