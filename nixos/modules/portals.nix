{ pkgs, ... }:

{
  # niri нет в UseIn у termfilechooser, поэтому обработчик FileChooser
  # задан явно — иначе портал не подхватится.
  xdg.portal = {
    enable = true;
    extraPortals = with pkgs; [
      xdg-desktop-portal-gtk
      xdg-desktop-portal-termfilechooser
    ];
    # default не трогаем: его задаёт модуль niri в nixpkgs.
    config.niri."org.freedesktop.impl.portal.FileChooser" = [ "termfilechooser" ];
  };
}
