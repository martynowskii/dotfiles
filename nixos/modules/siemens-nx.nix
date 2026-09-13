{ config, lib, pkgs, ... }:

# Siemens NX 10.0 (2014) — проприетарный CAD, собран под RHEL 6 / SLES 11.
# В nixpkgs его нет и быть не может, поэтому ставим "как на обычном Linux"
# в /opt, а недостающий FHS (/usr/lib, /lib64, ...) подкладываем через
# buildFHSEnv. NX ничего не знает про nix store и продолжает работать.
#
# Порядок действий после nixos-rebuild описан в README-nx.md.

let cfg = config.programs.siemens-nx; in
{
  options.programs.siemens-nx = {
    enable = lib.mkEnableOption "Siemens NX 10.0 в FHS-окружении";

    baseDir = lib.mkOption {
      type = lib.types.str;
      default = "/opt/siemens/nx10";
      description = ''
        UGII_BASE_DIR — куда установлен NX. Обязательно вне nix store:
        установщик пишет в эту директорию, а store неизменяем.
      '';
    };

    licenseServer = lib.mkOption {
      type = lib.types.str;
      default = "28000@localhost";
      example = "28000@license.example.com";
      description = "Лицензионный сервер Siemens в формате port@host.";
    };

    extraPkgs = lib.mkOption {
      type = lib.types.functionTo (lib.types.listOf lib.types.package);
      default = _: [ ];
      example = lib.literalExpression "pkgs: [ pkgs.libpng12 ]";
      description = ''
        Ещё библиотеки в FHS-окружение, если ldd ругается на что-то
        специфичное для твоей сборки NX.
      '';
    };
  };

  config =
    let
      # Всё, на что линкуется NX 10: ядро Motif-GUI, встроенные Qt 4.8 и JRE,
      # плюс шеллы, которые дёргают ugii_env.sh / install-скрипты.
      nxLibs = pkgs: (with pkgs; [
        # C/C++ runtime. libxcrypt-legacy даёт libcrypt.so.1, выброшенный из
        # современного glibc, — без него бинарники NX не стартуют.
        stdenv.cc.cc.lib
        libxcrypt-legacy
        ncurses5
        zlib
        bzip2
        xz
        expat
        libxml2
        openssl

        # OpenGL. /run/opengl-driver/lib добавляется в profile ниже.
        libGL
        libGLU
        libglvnd
        mesa

        # Шрифты и растр
        freetype
        fontconfig
        libpng
        libjpeg
        libtiff

        # Motif — на нём построен классический UI NX (libXm.so.4)
        motif

        # Встроенная JRE тянет alsa, встроенный Qt — glib/dbus/nss
        alsa-lib
        glib
        dbus
        nss
        nspr
        cups

        # Шеллы и утилиты, которые вызывают скрипты запуска NX
        bash
        tcsh
        ksh
        coreutils
        gnused
        gawk
        gnugrep
        findutils
        gnutar
        gzip
        which
        file
        procps
        util-linux
        e2fsprogs
      ]) ++ (with pkgs.xorg; [
        libX11
        libXext
        libXt
        libXmu
        libXi
        libXrender
        libXrandr
        libXcursor
        libXinerama
        libXfixes
        libXdamage
        libXcomposite
        libXScrnSaver
        libXtst
        libXpm
        libXaw
        libXft
        # libXp — X Print Extension, выпилен из современных дистрибутивов,
        # но Motif 2.x приложения этой эпохи всё ещё его требуют.
        libXp
        libICE
        libSM
        libxcb
      ]);

      nxEnv = pkgs.buildFHSEnv {
        name = "nx10-env";
        targetPkgs = p: nxLibs p ++ cfg.extraPkgs p;
        runScript = "bash";

        profile = ''
          export UGII_BASE_DIR=${cfg.baseDir}
          export UGII_ROOT_DIR=${cfg.baseDir}/ugii
          export UGII_LANG=english

          export UGS_LICENSE_SERVER=${cfg.licenseServer}
          export SPLM_LICENSE_SERVER=${cfg.licenseServer}

          # NX парсит числа только с десятичной ТОЧКОЙ. При ru_RU.UTF-8
          # (LC_NUMERIC=ru_RU) он молча ломает ввод размеров и импорт STEP.
          export LC_ALL=C
          export LANG=C

          export PATH=$UGII_ROOT_DIR:$PATH
          export LD_LIBRARY_PATH=/run/opengl-driver/lib:$UGII_ROOT_DIR:''${LD_LIBRARY_PATH-}
        '';
      };

      # runScript=bash, поэтому в окружение можно просто передать скрипт с аргументами.
      nxStart = pkgs.writeShellScript "nx10-start" ''
        if [ ! -x "$UGII_ROOT_DIR/ugraf" ]; then
          echo "NX не найден в $UGII_ROOT_DIR." >&2
          echo "Установи его туда (см. README-nx.md) или поправь" >&2
          echo "programs.siemens-nx.baseDir." >&2
          exit 1
        fi
        exec "$UGII_ROOT_DIR/ugraf" "$@"
      '';

      nx = pkgs.writeShellScriptBin "nx10" ''
        exec ${nxEnv}/bin/nx10-env ${nxStart} "$@"
      '';

      desktopItem = pkgs.makeDesktopItem {
        name = "siemens-nx10";
        desktopName = "Siemens NX 10.0";
        exec = "nx10 %f";
        categories = [ "Graphics" "Engineering" "Science" ];
      };
    in
    lib.mkIf cfg.enable {
      # NX — это OpenGL-приложение, драйвер обязателен.
      hardware.graphics.enable = true;

      # NX 10 — X11/Motif, нативного Wayland у него нет. Под niri XWayland
      # поднимается отдельным процессом (см. niri/config.kdl).
      environment.systemPackages = [ nxEnv nx desktopItem pkgs.xwayland-satellite ];

      # Каталог под установку: установщик запускается из-под root.
      systemd.tmpfiles.rules = [ "d ${cfg.baseDir} 0755 root root -" ];
    };
}
