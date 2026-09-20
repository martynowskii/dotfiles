{ config, lib, pkgs, ... }:

let
  dotfiles = "${config.home.homeDirectory}/Documents/dotfiles";
in
{
  imports = [
    ./modules/claude.nix
    ./modules/foot.nix
    ./modules/niri.nix
    ./modules/zsh.nix
    ./tools
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

  programs.tmux = {
    enable = true;
    keyMode = "vi";
    escapeTime = 10;
  };

  programs.fzf = {
    enable = true;
    enableZshIntegration = true;
  };

  home.file.".vim/vimrc".source =
    config.lib.file.mkOutOfStoreSymlink "${dotfiles}/vim/vimrc.vim";

  # claude-code and its unfree predicate live in ./modules/claude.nix.

  # Включает декларативные ассоциации: mimeapps.list становится симлинком
  # в стор, поэтому прежние записи перенесены сюда — иначе они потерялись
  # бы при первом переключении. Следствие: файл read-only и приложения
  # больше не пропишут себя сами.
  # Ассоциации на документы добавляет tools/docs.nix.
  xdg.mimeApps = {
    enable = true;

    defaultApplications = {
      "x-scheme-handler/tg" = "org.telegram.desktop.desktop";
      "x-scheme-handler/tonsite" = "org.telegram.desktop.desktop";
      "x-scheme-handler/mailto" = "chromium-browser.desktop";
      "x-scheme-handler/claude-cli" = "claude-code-url-handler.desktop";
    };

    associations.added = {
      "x-scheme-handler/tg" = "org.telegram.desktop.desktop";
      "x-scheme-handler/tonsite" = "org.telegram.desktop.desktop";
    };
  };

  # Утилиты без собственной конфигурации. Всё, что требует настройки,
  # живёт в modules/ или tools/.
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
