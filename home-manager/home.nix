{ config, lib, pkgs, ... }:

let
  dotfiles = "${config.home.homeDirectory}/Documents/dotfiles";
in
{
  imports = [
    ./modules/claude.nix
    ./modules/foot.nix
    ./modules/niri.nix
    ./modules/nvim.nix
    ./modules/qbittorrent.nix
    ./modules/rtorrent.nix
    ./modules/zsh.nix
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

  # Ассоциации: до этого mimeapps.list правился вручную и приложениями,
  # поэтому старые x-scheme-handler перенесены сюда — иначе home-manager
  # заменит файл симлинком и они потеряются.
  xdg.mimeApps = {
    enable = true;

    defaultApplications = {
      # Документы — всё, что умеет zathura с текущим набором плагинов.
      "application/pdf" = "org.pwmt.zathura.desktop";
      "application/postscript" = "org.pwmt.zathura.desktop";
      "application/epub+zip" = "org.pwmt.zathura.desktop";
      "image/vnd.djvu" = "org.pwmt.zathura.desktop";

      # Было в ~/.config/mimeapps.list до перехода на декларативный конфиг.
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

  home.packages = with pkgs; [
    antiword      # .doc: текст (-m UTF-8.txt) и PostScript (-p, -m 8859-5.txt)
    bat
    gcc
    gnumake
    pandoc        # .docx -> plain/markdown/latex
    python314
    telegram-desktop
    tree
    unzip
    vim-full
    zathura       # pdf, ps, djvu, epub, cbz + картинки
  ];
}
