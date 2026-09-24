# Всё, что верно только для этой железки: Lenovo XiaoXin Pro 14 AHP9
# (DMI: LENOVO / 83D3 / LNVNB161216). Остальные модули читают отсюда
# config.machine.*, чтобы у них внутри не заводились PCI-адреса, номера
# /dev/videoN и прочие значения, которые на другом ноутбуке окажутся
# просто неверными.
#
# hardware-configuration.nix сюда не переезжает: его генерирует и
# перезаписывает nixos-generate-config.
{ config, lib, ... }:

{
  options.machine = {
    irCamera = {
      path = lib.mkOption {
        type = lib.types.str;
        example = "/dev/v4l/by-path/pci-0000:00:14.0-usb-0:8:1.0-video-index0";
        description = ''
          Путь к ИК-ноде веб-камеры.

          Намеренно by-path, а не /dev/videoN: номер зависит от порядка,
          в котором uvcvideo разбирает интерфейсы устройства, и не
          гарантирован между загрузками. by-path собран из PCI-адреса
          контроллера и номера USB-порта — у распаянной камеры они
          постоянны.
        '';
      };

      node = lib.mkOption {
        type = lib.types.str;
        example = "video2";
        description = ''
          Имя той же ноды в /dev, без пути. Нужно отдельно, потому что из
          него строится имя systemd-юнита устройства (dev-video2.device),
          а symlink'у by-path соответствует юнит с другим, экранированным
          именем. Должно указывать на то же устройство, что и path.
        '';
      };

      width = lib.mkOption {
        type = lib.types.int;
        example = 640;
        description = "Ширина кадра ИК-потока.";
      };

      height = lib.mkOption {
        type = lib.types.int;
        example = 360;
        description = "Высота кадра ИК-потока.";
      };
    };
  };

  config = {
    # Камера Luxvisions 30c9:00c2 — одно USB-устройство с двумя UVC-функциями:
    # интерфейс 1.0 это RGB (video0), интерфейс 1.2 — ИК, единственный формат
    # GREY 640x360@30.
    machine.irCamera = {
      path = "/dev/v4l/by-path/pci-0000:63:00.4-usb-0:1:1.2-video-index0";
      node = "video2";
      width = 640;
      height = 360;
    };

    # Штатный UEFI-режим 80x25. Панель тут 2880x1800, и режим, который
    # прошивка выбирает сама, оставляет шрифт меню нечитаемо мелким;
    # 80x25 примерно вдвое укрупняет глифы. Своего размера шрифта у
    # systemd-boot нет, режим консоли — единственный рычаг.
    boot.loader.systemd-boot.consoleMode = "0";
  };
}
