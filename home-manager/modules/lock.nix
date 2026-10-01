{ config, lib, pkgs, ... }:

let
  swaylock = lib.getExe config.programs.swaylock.package;
in
{
  programs.swaylock = {
    enable = true;
    package = pkgs.swaylock-effects;
    settings = {
      screenshots = true;
      effect-blur = "30x8";
      effect-vignette = "0.5:0.2";
      # swayidle ждёт выхода команды: сон начнётся, когда экран уже заблокирован.
      daemonize = true;
    };
  };

  services.swayidle = {
    enable = true;
    events = {
      before-sleep = swaylock;
      lock = swaylock;
    };
  };
}
