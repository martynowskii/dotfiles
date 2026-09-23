# Разблокировка по лицу — аналог Windows Hello. Работает на входе в систему
# (greetd), на блокировке экрана (swaylock), в sudo и polkit: howdy по
# умолчанию встраивается во все PAM-сервисы сразу.
#
# Конкретные пути к камере лежат в ./machine.nix.
{ config, lib, pkgs, ... }:

let
  irCamera = config.machine.irCamera;
in
{
  # Одной howdy мало. ИК-сенсор без включённой подсветки отдаёт не шум, а
  # ровно нули: подсветка висит на vendor-специфичном UVC extension unit
  # control, до которого ядро само не дотрагивается.
  #
  # Модуль ставит пакет и systemd-юнит, но не саму настройку — её нужно
  # один раз подобрать вручную:
  #
  #   sudo linux-enable-ir-emitter -d /dev/<node> configure -g
  #
  # Результат ложится в /var/lib/linux-enable-ir-emitter и применяется юнитом
  # при загрузке и после каждого выхода из сна.
  services.linux-enable-ir-emitter = {
    enable = true;
    device = irCamera.node;
  };

  services.howdy = {
    enable = true;

    # Дефолт модуля — "required", то есть лицо становится ОБЯЗАТЕЛЬНЫМ
    # фактором сразу для всех PAM-сервисов: стоит камере оказаться занятой
    # или комнате тёмной, и перестают работать вход, sudo и разблокировка
    # разом. "sufficient" даёт поведение Windows Hello: узнали лицо —
    # пускаем, не узнали — обычный ввод пароля.
    control = "sufficient";

    settings = {
      video = {
        device_path = irCamera.path;

        # У ИК-потока ровно один формат, так что незачем заставлять OpenCV
        # перебирать разрешения на каждой попытке аутентификации.
        frame_width = irCamera.width;
        frame_height = irCamera.height;
      };

      core = {
        # Лицо перед ноутбуком не должно пускать того, кто пришёл по сети,
        # и не должно срабатывать с закрытой крышкой.
        abort_if_ssh = true;
        abort_if_lid_closed = true;
      };
    };
  };
}
