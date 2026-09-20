{ ... }:

# Инструменты — то, что несёт собственную конфигурацию, а не просто
# лежит списком в home.packages. Утилиты без настроек (bat, tree, gcc,
# gnumake, python, unzip) остаются в home.nix.
{
  imports = [
    ./docs.nix
    ./nvim.nix
  ];
}
