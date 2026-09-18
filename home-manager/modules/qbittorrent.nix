{ config, lib, pkgs, ... }:

{
  # Модуля home-manager для qbittorrent нет и быть не может: клиент сам
  # перезаписывает свой qBittorrent.conf при каждом изменении настроек,
  # поэтому симлинк из /nix/store он бы сломал. Настройки живут в
  # ~/.config/qBittorrent и в dotfiles не попадают — в отличие от rtorrent.
  home.packages = with pkgs; [
    qbittorrent
  ];
}
