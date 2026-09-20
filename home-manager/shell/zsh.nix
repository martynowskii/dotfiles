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

      # Привычка из macOS. Ассоциации — в xdg.mimeApps: схемы в home.nix,
      # документы в tools/docs.nix.
      open = "xdg-open";
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

        # --- vi-режим + навигация в стиле macOS ---
        # Идёт после oh-my-zsh (он ставит bindkey -e), поэтому vi побеждает.
        # Индикатор режима рисует p10k: сегмент vi_mode у него уже включён,
        # в command-режиме справа появляется NORMAL.
        bindkey -v
        KEYTIMEOUT=1   # без этого Esc срабатывает с задержкой ~0.4 с

        # Alt-клавиши должны работать в обоих режимах.
        # Последовательности сверены с terminfo foot (kLFT3/kRIT3/kDC3).
        for _km in viins vicmd; do
          bindkey -M $_km '^[[1;3D' backward-word       # Alt+←
          bindkey -M $_km '^[[1;3C' forward-word        # Alt+→
          bindkey -M $_km '^[[3;3~' kill-word           # Alt+Delete
          bindkey -M $_km '^H'      backward-kill-word  # Ctrl+Backspace (foot шлёт ^H)
        done
        unset _km

        # Это vi-раскладка теряет — в viins они становятся self-insert
        # или undefined-key, поэтому возвращаем явно.
        bindkey -M viins '^A'   beginning-of-line
        bindkey -M viins '^E'   end-of-line
        bindkey -M viins '^K'   kill-line
        bindkey -M viins '^Y'   yank
        bindkey -M viins '^[b'  backward-word
        bindkey -M viins '^[f'  forward-word
        bindkey -M viins '^[d'  kill-word
        bindkey -M viins '^[^?' backward-kill-word      # Alt+Backspace

        # Открыть текущую команду в $EDITOR (nvim) и вернуть отредактированной.
        # `v` в command-режиме намеренно оставлен за visual-mode, как в vim.
        autoload -Uz edit-command-line
        zle -N edit-command-line
        bindkey -M viins '^X^E' edit-command-line
        bindkey -M vicmd '^X^E' edit-command-line

        # Форма курсора: линия в insert, блок в command.
        # add-zle-hook-widget, а не zle -N zle-keymap-select — иначе
        # перетрём хук p10k и сломаем индикатор NORMAL.
        autoload -Uz add-zle-hook-widget
        _cursor_for_keymap() {
          case ''${KEYMAP:-viins} in
            vicmd) print -n '\e[2 q' ;;
            *)     print -n '\e[6 q' ;;
          esac
        }
        zle -N _cursor_for_keymap
        add-zle-hook-widget zle-keymap-select _cursor_for_keymap
        add-zle-hook-widget zle-line-init     _cursor_for_keymap
      ''
    ];
  };
}

