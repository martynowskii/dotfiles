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
      hms = "HOME_MANAGER_BACKUP_EXT=backup HOME_MANAGER_BACKUP_OVERWRITE=1 home-manager switch";
      nrs = "sudo nixos-rebuild switch";
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

        # --- Навигация по строке в стиле macOS (Alt = Option) ---
        # Уже работает без настройки: Alt+B / Alt+F (по словам), Alt+D (удалить
        # слово вперёд), Alt+Backspace (удалить слово назад), Home/End (начало и
        # конец строки — аналог Cmd+←/→), Ctrl+←/→ и пустой WORDCHARS от oh-my-zsh.
        # Ниже — только то, что zsh не биндит сам.

        # Alt+←/→ — перемещение по словам (foot: \e[1;3D / \e[1;3C)
        bindkey '^[[1;3D' backward-word
        bindkey '^[[1;3C' forward-word

        # Alt+Delete — удалить слово вперёд (foot: \e[3;3~, terminfo kDC3)
        bindkey '^[[3;3~' kill-word

        # Ctrl+Backspace — удалить слово назад.
        # foot шлёт для него ^H, а обычный Backspace — ^?, так что конфликта нет.
        bindkey '^H' backward-kill-word
      ''
    ];
  };
}

