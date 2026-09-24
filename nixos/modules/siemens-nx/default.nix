# Siemens NX 10: сервер лицензий, сам NX и две команды запуска.
#
# Пакеты лежат вне репозитория, в ~/Documents/univer/Siemens — рядом с ними
# ~13 ГБ носителя. Зачем NX вообще нужна прослойка — README.md.
{ config, lib, pkgs, ... }:

let
  # Именно path, а не строка: "${siemensDir}" утащил бы носитель в /nix/store.
  siemensDir = /home/arthr/Documents/univer/Siemens;

  nx = pkgs.callPackage (siemensDir + "/nix-nx") {
    licenseServer = "${toString config.services.splmLicenseServer.port}@localhost";
  };

  inherit (import ./session.nix { inherit pkgs nx; }) session dumpWindows;
  launchers = import ./launchers.nix { inherit lib pkgs nx session; };
in
{
  imports = [ (siemensDir + "/nix-license-server/license-server-module.nix") ];

  nixpkgs.config.allowUnfree = true;

  services.splmLicenseServer = {
    enable = true;
    licenseFile = "/var/lib/splm/license.lic";
  };

  environment.systemPackages = [
    # Из пакета берём только ярлык и иконку: команду nx даёт обёртка, а два
    # bin/nx в одном профиле пришлось бы разводить приоритетами.
    (pkgs.buildEnv {
      name = "siemens-nx-share";
      paths = [ nx ];
      pathsToLink = [ "/share" ];
    })

    launchers.rootful
    launchers.gamescope
    dumpWindows
  ];
}
