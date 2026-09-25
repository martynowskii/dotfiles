# Значения, верные только для этого ноутбука: Lenovo XiaoXin Pro 14 AHP9.
{ config, lib, ... }:

{
  options.machine.irCamera = {
    path = lib.mkOption {
      type = lib.types.str;
      description = "ИК-нода камеры. by-path, потому что номер /dev/videoN между загрузками не гарантирован.";
    };

    node = lib.mkOption {
      type = lib.types.str;
      description = "Та же нода без пути: из неё строится имя systemd-юнита устройства.";
    };

    width = lib.mkOption {
      type = lib.types.int;
      description = "Ширина кадра ИК-потока.";
    };

    height = lib.mkOption {
      type = lib.types.int;
      description = "Высота кадра ИК-потока.";
    };
  };

  config = {
    machine.irCamera = {
      path = "/dev/v4l/by-path/pci-0000:63:00.4-usb-0:1:1.2-video-index0";
      node = "video2";
      width = 640;
      height = 360;
    };

    # Панель 2880x1800: шрифт Limine нужно удвоить, иначе не читается.
    boot.loader.limine.style.graphicalTerminal.font.scale = "2x2";
  };
}
