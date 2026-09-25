{ config, lib, pkgs, ... }:

let
  irCamera = config.machine.irCamera;
in
{
  # Без эмиттера ИК-сенсор отдаёт ровно нули. Его настройку нужно один раз
  # подобрать руками: sudo linux-enable-ir-emitter -d /dev/<node> configure
  services.linux-enable-ir-emitter = {
    enable = true;
    device = irCamera.node;
  };

  services.howdy = {
    enable = true;

    # Дефолт модуля — "required": лицо становится обязательным сразу для всех
    # PAM-сервисов, то есть в тёмной комнате это лок-аут.
    control = "sufficient";

    settings.video = {
      device_path = irCamera.path;
      frame_width = irCamera.width;
      frame_height = irCamera.height;

      # У ИК-камеры лицо снято на почти чёрном фоне, и дефолтные 60% режут
      # годные кадры: замеренные медиана 39%, максимум 65%.
      dark_threshold = 80;
    };
  };
}
