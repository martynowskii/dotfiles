{ ... }:

# Плоский список: один настраиваемый компонент — один файл. Утилиты
# без настроек (bat, gcc, gnumake, python314, tree, unzip) остаются
# списком в home.packages, отдельный модуль им ничего не добавит.
{
  imports = [
    ./claude.nix
    ./docs.nix
    ./foot.nix
    ./fzf.nix
    ./niri.nix
    ./nvim.nix
    ./tmux.nix
    ./torrents.nix
    ./zsh.nix
  ];
}
