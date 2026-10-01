{ config, lib, ... }:

let
  swaylock = lib.getExe config.programs.swaylock.package;
in
{
  programs.swaylock = {
    enable = true;
    settings = {
      color = "000000";
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
