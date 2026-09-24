# Siemens NX 10: сервер лицензий, сам NX и две команды запуска.
#
# Пакеты лежат вне репозитория, в ~/Documents/univer/Siemens — рядом с ними
# ~13 ГБ носителя. Зачем NX вообще нужна прослойка — siemens-nx-display.md.
{ lib, pkgs, ... }:

let
  # Именно path, а не строка: "${siemensDir}" утащил бы носитель в /nix/store.
  siemensDir = /home/arthr/Documents/univer/Siemens;

  nx = pkgs.callPackage (siemensDir + "/nix-nx") {
    licenseServer = "28000@localhost";
  };

  fontPath = import ./siemens-nx-fonts.nix { inherit lib pkgs; };
  inherit (import ./siemens-nx-session.nix { inherit pkgs nx; }) session dumpWindows;
  launchers = import ./siemens-nx-launchers.nix {
    inherit pkgs nx session fontPath;
  };
in
{
  imports = [ (siemensDir + "/nix-license-server/license-server-module.nix") ];

  nixpkgs.config.allowUnfree = true;

  services.splmLicenseServer = {
    enable = true;
    licenseFile = "/var/lib/splm/license.lic";
  };

  environment.systemPackages = [
    # Дерево NX, ярлык и иконка. Команду nx из него перекрываем обёрткой.
    nx
    (lib.hiPrio launchers.rootful)
    launchers.gamescope
    dumpWindows
  ];
}
