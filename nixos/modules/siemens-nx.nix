{ lib, pkgs, ... }:

# Всё, что относится к Siemens NX 10: сервер лицензий, сам NX и запуск его во
# вложенном Weston.
#
# Пакеты живут отдельно, в ~/Documents/univer/Siemens — здесь только их
# подключение к системе. Каталог вне git и вне /nix/store намеренно: рядом с
# исходниками лежит ~13 ГБ носителя, которому в репозитории делать нечего.

let
  # Путь именно как path, а не строка. "${siemensDir}" скопировал бы весь
  # каталог вместе с носителем в /nix/store — те самые 13 ГБ.
  siemensDir = /home/arthr/Documents/univer/Siemens;

  nx = pkgs.callPackage (siemensDir + "/nix-nx") {
    licenseServer = "28000@localhost";   # тот же хост, где включён splmLicenseServer ниже
  };

  # Обёртка запуска. Живёт здесь, а не в пакете, сознательно: NX сам по себе
  # к Weston отношения не имеет, это потребность конкретно этой машины — niri
  # поверх Wayland с дробным масштабом. На другой системе пакет ставится как
  # есть, без композитора-прослойки.
  #
  # Чем мешает хостовый XWayland (xwayland-satellite, который niri поднимает
  # сам на :0):
  #
  #   1. Меню. NX рисует их как Motif-приложения девяностых — отдельным окном
  #      override-redirect по абсолютным координатам, в обход оконного
  #      менеджера, плюс активный grab указателя и клавиатуры. Без настоящего
  #      X-оконного менеджера они не разворачиваются. У Weston XWayland
  #      встроенный, с полноценным WM.
  #
  #   2. Масштаб. NX родом из 2014 года и про HiDPI не знает: рисует в
  #      физических пикселях, и при scale 1.75 интерфейс выходит примерно
  #      вдвое мельче нужного. Своего масштабирования у него нет, но картинку
  #      увеличивает сам Weston.
  #
  #   3. Окна. Каждый диалог NX — отдельный X11-toplevel, и в тайловом niri
  #      они разъезжаются по плиткам. Внутри Weston это одно окно.
  #
  # Имя намеренно то же, что у пакета, — nx. Ниже обёртка помечена hiPrio и
  # перекрывает bin/nx из пакета, так что команда и пункт в лаунчере остаются
  # в единственном экземпляре.
  nx-weston = pkgs.writeShellApplication {
    name = "nx";
    # xkbcomp — им XWayland внутри Weston компилирует раскладку; без него в
    # выводе появляется "Errors from xkbcomp are not fatal to the X server".
    runtimeInputs = [ pkgs.weston pkgs.xorg.xkbcomp ];
    text = ''
      # libxkbcommon ищет описания раскладок по вшитому пути
      # /usr/share/X11/xkb, которого на NixOS нет, и Weston встречает запуск
      # парой строк "failed to add default include path". Указываем каталог
      # явно — niri своим процессам это передаёт сам, а Weston мы запускаем
      # в обход сессии, поэтому переменную приходится ставить здесь.
      export XKB_CONFIG_ROOT=${pkgs.xkeyboard_config}/share/X11/xkb

      # NX_WESTON=0 — запуск напрямую, без вложенного композитора: X-сервер
      # тогда берётся снаружи (XWayland самого niri, DISPLAY из окружения).
      # Нужно, если Weston не поднимается или надо сравнить поведение.
      : "''${NX_WESTON:=1}"

      # scale в wl_output — целое (int32), дробное масштабирование живёт в
      # отдельном протоколе, которого здесь нет. Доступны 1, 2, 3; к 1.75
      # ближе всего 2 — чуть крупнее родного и слегка мягче по краям.
      : "''${NX_WESTON_SCALE:=2}"

      # На весь экран, чтобы не получилось окно в окне.
      : "''${NX_WESTON_ARGS:=--fullscreen}"

      if [ "$NX_WESTON" = 0 ]; then
        exec ${nx}/bin/nx "$@"
      fi

      # Форма `weston ... -- программа` делает всю работу сама: запускает
      # программу, когда композитор готов; выставляет ей DISPLAY своего
      # XWayland, выбрав свободный номер (хостовый :0 не трогается);
      # завершается, когда программа вышла. Поэтому ни ожидания сокета в
      # /tmp/.X11-unix, ни отдельного kill по выходу тут не нужно.
      #
      # NX_WESTON_ARGS без кавычек намеренно — это список аргументов.
      # shellcheck disable=SC2086
      exec weston \
        --backend=wayland \
        --xwayland \
        --scale="$NX_WESTON_SCALE" \
        $NX_WESTON_ARGS \
        -- ${nx}/bin/nx "$@"
    '';
  };
in
{
  imports = [ /home/arthr/Documents/univer/Siemens/nix-license-server/license-server-module.nix ];

  nixpkgs.config.allowUnfree = true;

  # Сервер лицензий — локально, на этой же машине. Если он крутится где-то ещё
  # в сети, этот блок не нужен: тогда достаточно указать NX его port@host
  # выше, в licenseServer.
  services.splmLicenseServer = {
    enable = true;
    licenseFile = "/var/lib/splm/license.lic";   # настоящий .lic, получить — см. nix-license-server/README.md
  };

  # lmutil (lmstat -a, lmdown) и getcid сюда не добавляем: пакет сервера
  # лицензий выставляет себя в systemPackages сам, из license-server-module.nix.
  environment.systemPackages = [
    # Пакет целиком: дерево NX, ярлык в лаунчере, иконка.
    nx

    # Только bin/nx, зато с приоритетом — перекрывает одноимённый файл из
    # пакета. Всё остальное (share/applications, share/pixmaps) берётся
    # оттуда, поэтому пункт в меню по-прежнему один и зовёт просто `nx`.
    (lib.hiPrio nx-weston)
  ];
}
