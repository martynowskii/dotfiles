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
      effect-blur = "10x5";
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
