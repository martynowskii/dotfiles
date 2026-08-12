{ config, lib, pkgs, ... }:

let
  dotfiles = "${config.home.homeDirectory}/Documents/dotfiles";
in
{
  home.pointerCursor = {
    name = "Simp1e-Breeze-Dark";
    package = pkgs.simp1e-cursors;
    size = 24;
    gtk.enable = true;
    x11.enable = true;
  };

  xdg.configFile."niri".source =
    config.lib.file.mkOutOfStoreSymlink "${dotfiles}/niri";
}
