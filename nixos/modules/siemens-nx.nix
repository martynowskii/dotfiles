{ lib, pkgs, ... }:

# Всё, что относится к Siemens NX 10: сервер лицензий, сам NX и запуск его во
# вложенном X-сервере с настоящим оконным менеджером.
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

  # Каталоги растровых шрифтов X. NX задаёт шрифты интерфейса жёсткими XLFD
  # вида -adobe-helvetica-medium-r-normal--12-120-75-75-p-*-iso8859-1, то есть
  # требует именно эти растровые наборы. В пути шрифтов современного X-сервера
  # их обычно нет, и Motif молча сваливается на "fixed".
  fontPath = lib.concatStringsSep "," [
    "${pkgs.font-adobe-75dpi}/share/fonts/X11/75dpi"
    "${pkgs.font-adobe-100dpi}/share/fonts/X11/100dpi"
    "${pkgs.font-misc-misc}/share/fonts/X11/misc"
  ];

  # Запуск NX во вложенном X-сервере.
  #
  # Живёт здесь, а не в пакете, сознательно: NX сам по себе ни к Xephyr, ни к
  # metacity отношения не имеет — это потребность конкретно этой машины, niri
  # поверх Wayland. На другой системе пакет ставится как есть.
  #
  # Зачем вообще прослойка. NX опознаёт оконный менеджер так: читает
  # root._NET_SUPPORTING_WM_CHECK, по нему находит окно-маркер и сверяет его
  # _NET_WM_NAME со списком, зашитым в libugui.so. Список целиком:
  #
  #     Metacity, KWin, GNOME Shell
  #
  # Больше NX не знает никого — Siemens поддерживал его на Linux только под
  # RHEL и SLES с GNOME, а после NX 12 свернул Linux совсем. И niri, и Weston
  # для него чужие: в журнале появляется "ugUIidentifyWindowManager:
  # Unrecognized Window Manager", после чего панели, которые должны
  # пристыковываться (История, Навигатор детали и прочие), разъезжаются
  # отдельными окнами и не закрываются.
  #
  # Подменять одно лишь имя через wmname недостаточно: панели NX расставляет
  # через _NET_MOVERESIZE_WINDOW, а XWM внутри Weston этот атом не
  # реализует — у него есть только _NET_FRAME_EXTENTS, _NET_SUPPORTED,
  # _NET_WM_MOVERESIZE, _NET_WM_STATE и _NET_WM_WINDOW_TYPE. Поэтому здесь
  # поднимается настоящий Metacity во вложенном Xephyr: NX получает ровно тот
  # менеджер, под который писался, со всем протоколом целиком.
  #
  # Заодно снимается и проблема с меню: NX рисует их отдельными окнами
  # override-redirect с активным grab, и полноценному X-менеджеру это
  # привычно, в отличие от xwayland-satellite.
  nx-nested = pkgs.writeShellApplication {
    name = "nx";
    runtimeInputs = with pkgs; [
      xorg-server      # Xephyr
      metacity
      xauth
      util-linux       # mcookie
      coreutils
    ];
    text = ''
      # NX_NESTED=0 — запуск напрямую, в X-сервере хозяйской сессии. Панели
      # при этом разъедутся, зато видно поведение без прослойки.
      : "''${NX_NESTED:=1}"

      # Размер вложенного экрана. По умолчанию — физическое разрешение
      # панели: X-клиенты под niri рисуются в физических пикселях, логический
      # размер 1645x1028 тут ни при чём.
      : "''${NX_SCREEN:=2880x1800}"

      # Прочие аргументы Xephyr. -resizeable позволяет тянуть окно и менять
      # размер вложенного экрана за ним; -no-host-grab обязателен, иначе
      # активный grab внутри NX заберёт клавиатуру и мышь у всей системы и
      # вернуть их будет нечем.
      : "''${NX_XEPHYR_ARGS:=-resizeable -no-host-grab}"

      if [ "$NX_NESTED" = 0 ]; then
        exec ${nx}/bin/nx "$@"
      fi

      # Свободный номер дисплея. Начинаем с 10, чтобы заведомо разойтись с
      # хозяйским :0 от xwayland-satellite.
      display=""
      for n in $(seq 10 40); do
        if [ ! -e "/tmp/.X11-unix/X$n" ] && [ ! -e "/tmp/.X$n-lock" ]; then
          display="$n"
          break
        fi
      done
      if [ -z "$display" ]; then
        echo "nx: не нашёл свободного номера дисплея в диапазоне 10-40." >&2
        exit 1
      fi

      # Своя авторизация вместо -ac: -ac открыл бы вложенный сервер любому
      # локальному процессу, а нам нужен ровно этот NX.
      runtime=$(mktemp -d)
      authfile="$runtime/Xauthority"
      xauth -f "$authfile" add ":$display" MIT-MAGIC-COOKIE-1 "$(mcookie)"

      cleanup() {
        [ -n "''${metacity_pid:-}" ] && kill "$metacity_pid" 2>/dev/null
        [ -n "''${xephyr_pid:-}" ] && kill "$xephyr_pid" 2>/dev/null
        rm -rf "$runtime"
      }
      trap cleanup EXIT

      # shellcheck disable=SC2086
      Xephyr ":$display" \
        -auth "$authfile" \
        -screen "$NX_SCREEN" \
        -fp ${fontPath} \
        $NX_XEPHYR_ARGS &
      xephyr_pid=$!

      # Ждём, пока сокет появится: metacity, запущенный раньше сервера,
      # просто не подключится.
      for _ in $(seq 1 100); do
        if ! kill -0 "$xephyr_pid" 2>/dev/null; then
          echo "nx: Xephyr завершился, не успев поднять дисплей :$display." >&2
          exit 1
        fi
        [ -e "/tmp/.X11-unix/X$display" ] && break
        sleep 0.1
      done
      if [ ! -e "/tmp/.X11-unix/X$display" ]; then
        echo "nx: Xephyr не поднял дисплей :$display за 10 секунд." >&2
        exit 1
      fi

      export DISPLAY=":$display"
      export XAUTHORITY="$authfile"

      # Схемы GSettings: metacity читает свои настройки через них и без
      # каталога схем падает ещё до появления окон.
      export XDG_DATA_DIRS="${pkgs.metacity}/share:${pkgs.gsettings-desktop-schemas}/share''${XDG_DATA_DIRS:+:$XDG_DATA_DIRS}"

      metacity &
      metacity_pid=$!

      # Без exec: иначе потеряется trap, и Xephyr с metacity останутся
      # висеть после выхода из NX.
      ${nx}/bin/nx "$@"
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
    (lib.hiPrio nx-nested)
  ];
}
