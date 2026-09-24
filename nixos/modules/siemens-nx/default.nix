# Siemens NX 10: сервер лицензий, сам NX и две команды запуска.
#
<<<<<<< HEAD
# Пакеты лежат вне репозитория, в ~/Documents/univer/Siemens — рядом с ними
# ~13 ГБ носителя. Зачем NX вообще нужна прослойка — README.md.
{ lib, pkgs, ... }:
=======
# Пакеты лежат вне репозитория, в ~/Documents/univer/Siemens-tmp — рядом с ними
# ~13 ГБ носителя. Зачем NX вообще нужна прослойка — README.md.
{ config, lib, pkgs, ... }:
>>>>>>> worktree-siemens-nx10

let
  # Именно path, а не строка: "${siemensDir}" утащил бы носитель в /nix/store.
  siemensDir = /home/arthr/Documents/univer/Siemens-tmp;

  nx = pkgs.callPackage (siemensDir + "/nix-nx") {
<<<<<<< HEAD
    licenseServer = "28000@localhost";
=======
    licenseServer = "${toString config.services.splmLicenseServer.port}@localhost";
>>>>>>> worktree-siemens-nx10
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
<<<<<<< HEAD
    # Дерево NX, ярлык и иконка. Команду nx из него перекрываем обёрткой.
    nx
    (lib.hiPrio launchers.rootful)
=======
    # Из пакета берём только ярлык и иконку: команду nx даёт обёртка, а два
    # bin/nx в одном профиле пришлось бы разводить приоритетами.
    (pkgs.buildEnv {
      name = "siemens-nx-share";
      paths = [ nx ];
      pathsToLink = [ "/share" ];
    })

    launchers.rootful
>>>>>>> worktree-siemens-nx10
    launchers.gamescope
    dumpWindows
  ];
}
