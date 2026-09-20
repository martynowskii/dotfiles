{ config, lib, pkgs, ... }:

{
  programs.foot = {
    enable = true;
    server.enable = true;
    settings = {
      main = {
        font = "JetBrainsMono Nerd Font:size=10";
        pad = "8x8";
      };
      colors-dark.alpha = 0.95;
    };
  };

  home.packages = with pkgs; [
    chafa       # универсальный вьюер
    libsixel    # img2sixel, эталонный кодировщик
  ];
}
