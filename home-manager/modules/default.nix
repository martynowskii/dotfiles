{ ... }:

# Плоский список: один настраиваемый компонент — один файл. Утилиты
# без настроек (bat, gcc, gnumake, python314, tree, unzip) остаются
# списком в home.packages, отдельный модуль им ничего не добавит.
{
  imports = [
    ./claude.nix
    ./foot.nix
    ./mime.nix
    ./niri.nix
    ./nvim.nix
    ./sh-tools.nix
    ./torrent.nix
    ./zsh.nix
  ];
}
