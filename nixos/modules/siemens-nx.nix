{ lib, pkgs, ... }:

# Всё, что относится к Siemens NX 10: сервер лицензий, сам NX и два способа
# его запустить.
#
# Пакеты живут отдельно, в ~/Documents/univer/Siemens — здесь только их
# подключение к системе. Каталог вне git и вне /nix/store намеренно: рядом с
# исходниками лежит ~13 ГБ носителя, которому в репозитории делать нечего.
#
# Почему запуск вообще требует прослойки и какие ещё варианты разобраны —
# siemens-nx-display.md в этом же каталоге.

let
  # Путь именно как path, а не строка. "${siemensDir}" скопировал бы весь
  # каталог вместе с носителем в /nix/store — те самые 13 ГБ.
  siemensDir = /home/arthr/Documents/univer/Siemens;

  nx = pkgs.callPackage (siemensDir + "/nix-nx") {
    licenseServer = "28000@localhost";   # тот же хост, где включён splmLicenseServer ниже
  };

  # Каталоги растровых шрифтов X. NX задаёт шрифты интерфейса жёсткими XLFD
  # вида -adobe-helvetica-medium-r-normal--12-120-75-75-p-*-iso8859-1, то есть
  # требует именно эти наборы. В пути шрифтов современного X-сервера их уже
  # нет, и Motif молча сваливается на "fixed".
  fontPath = lib.concatStringsSep "," [
    "${pkgs.font-adobe-75dpi}/share/fonts/X11/75dpi"
    "${pkgs.font-adobe-100dpi}/share/fonts/X11/100dpi"
    "${pkgs.font-misc-misc}/share/fonts/X11/misc"
  ];

  # Общая часть обоих вариантов: на уже поднятом DISPLAY запустить оконный
  # менеджер и отдать ему NX.
  #
  # Metacity здесь не вкусовщина. NX опознаёт менеджер так: читает
  # root._NET_SUPPORTING_WM_CHECK, по нему находит окно-маркер и сверяет
  # _NET_WM_NAME со списком, зашитым в libugui.so — Metacity, KWin,
  # GNOME Shell, больше никого. Под незнакомым менеджером (а это и niri, и
  # Weston) панели вроде Истории перестают стыковаться и разъезжаются
  # отдельными окнами. Одного лишь имени мало: панели расставляются через
  # _NET_MOVERESIZE_WINDOW, который есть у настоящего metacity и которого нет
  # у встроенного XWM Weston.
  nx-session = pkgs.writeShellScript "nx-session" ''
    # Metacity читает настройки через GSettings и без каталога схем не
    # стартует вовсе.
    export XDG_DATA_DIRS="${pkgs.metacity}/share:${pkgs.gsettings-desktop-schemas}/share''${XDG_DATA_DIRS:+:$XDG_DATA_DIRS}"

    ${pkgs.metacity}/bin/metacity &
    metacity_pid=$!
    trap 'kill "$metacity_pid" 2>/dev/null || true' EXIT

    # Без exec: иначе потеряется trap и metacity останется висеть.
    ${nx}/bin/nx "$@"
  '';

  # Выбор свободного номера дисплея и разовый cookie. Вынесено отдельно,
  # потому что нужно обоим вариантам.
  #
  # Своя авторизация вместо -ac: -ac открыл бы вложенный сервер любому
  # локальному процессу, а нужен ровно этот NX.
  displaySetup = ''
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

    runtime=$(mktemp -d)
    authfile="$runtime/Xauthority"
    xauth -f "$authfile" add ":$display" MIT-MAGIC-COOKIE-1 "$(mcookie)"
  '';

  # Ожидание сокета: оконный менеджер, запущенный раньше сервера, просто не
  # подключится.
  waitForDisplay = serverName: ''
    for _ in $(seq 1 100); do
      if ! kill -0 "$server_pid" 2>/dev/null; then
        echo "nx: ${serverName} завершился, не подняв дисплей :$display." >&2
        exit 1
      fi
      [ -e "/tmp/.X11-unix/X$display" ] && break
      sleep 0.1
    done
    if [ ! -e "/tmp/.X11-unix/X$display" ]; then
      echo "nx: ${serverName} не поднял дисплей :$display за 10 секунд." >&2
      exit 1
    fi
  '';


  # ── Вариант 1: rootful Xwayland ────────────────────────────────────────────
  # Основной. Масштабирует сам niri, и это единственный вариант, которому для
  # этого не нужен отдельный слой.
  #
  # Суть: rootful Xwayland — обычный клиент Wayland, и дробный масштаб он себе
  # не выторговывает. Замер под композитором со scale=2: просили окно 800x600,
  # внутри оказалось ровно 800x600 при 96 dpi. То есть он рисует в логических
  # пикселях, а растягивает его композитор. Xephyr так не умеет — он X-клиент
  # хозяйского xwayland-satellite, и niri до него не дотягивается.
  #
  # Поэтому масштаб здесь задаётся размером экрана: NX_GEOMETRY — это
  # логический размер выхода, niri растянет его до физического.
  nx-rootful = pkgs.writeShellApplication {
    name = "nx";
    runtimeInputs = with pkgs; [ xwayland xauth util-linux coreutils ];
    text = ''
      # NX_NESTED=0 — запуск напрямую, в X-сервере хозяйской сессии. Панели
      # при этом разъедутся, зато видно поведение без прослойки.
      : "''${NX_NESTED:=1}"

      # Логический размер выхода niri (2880x1800 при масштабе 1.75).
      # Уменьшить это число — картинка станет крупнее и мыльнее, увеличить —
      # мельче и чётче. 2880x1800 даст масштаб 1:1 без увеличения.
      : "''${NX_GEOMETRY:=1645x1028}"

      # -host-grab здесь намеренно НЕ передаётся: он отключил бы горячие
      # клавиши хозяйской сессии. NX делает активный grab для меню, и отдавать
      # ему ввод всей системы не нужно.
      : "''${NX_XWAYLAND_ARGS:=}"

      if [ "$NX_NESTED" = 0 ]; then
        exec ${nx}/bin/nx "$@"
      fi

      ${displaySetup}

      cleanup() {
        [ -n "''${server_pid:-}" ] && kill "$server_pid" 2>/dev/null
        rm -rf "$runtime"
      }
      trap cleanup EXIT

      # shellcheck disable=SC2086
      Xwayland ":$display" \
        -auth "$authfile" \
        -geometry "$NX_GEOMETRY" \
        -fp ${fontPath} \
        $NX_XWAYLAND_ARGS &
      server_pid=$!

      ${waitForDisplay "Xwayland"}

      export DISPLAY=":$display"
      export XAUTHORITY="$authfile"
      ${nx-session} "$@"
    '';
  };


  # Вторая половина варианта 3: запускается уже внутри gamescope, на его
  # XWayland. Номер дисплея и файл авторизации приходят из NX_GS_DISPLAY и
  # NX_GS_AUTH, размер экрана — из тех же переменных, что у обёртки.
  nx-gamescope-inner = pkgs.writeShellScript "nx-gamescope-inner" ''
    set -euo pipefail
    display="$NX_GS_DISPLAY"
    authfile="$NX_GS_AUTH"

    # -no-host-grab обязателен: NX делает активный grab клавиатуры и мыши для
    # меню, и без флага захват ушёл бы наружу, забрав ввод у всей системы.
    ${pkgs.xorg-server}/bin/Xephyr ":$display" \
      -auth "$authfile" \
      -screen "''${NX_GS_WIDTH}x''${NX_GS_HEIGHT}" \
      -fp ${fontPath} \
      -resizeable -no-host-grab &
    server_pid=$!
    trap 'kill "$server_pid" 2>/dev/null || true' EXIT

    ${waitForDisplay "Xephyr"}

    export DISPLAY=":$display"
    export XAUTHORITY="$authfile"
    ${nx-session} "$@"
  '';


  # ── Вариант 3: gamescope + Xephyr ──────────────────────────────────────────
  # Запасной, на случай если мыльность от растягивания в варианте 1 будет
  # раздражать. Единственный вариант с умным апскейлером: FSR и NIS заметно
  # чётче обычного билинейного растягивания.
  #
  # Xephyr внутри обязателен, а не по недосмотру: gamescope показывает только
  # верхнее окно, а у NX их много. Xephyr сворачивает всё это в одно окно.
  # Отсюда два вложенных сервера — плата за апскейлер.
  #
  # Требует Vulkan.
  nx-gamescope = pkgs.writeShellApplication {
    name = "nx-gamescope";
    runtimeInputs = with pkgs; [ gamescope xorg-server xauth util-linux coreutils ];
    text = ''
      # Внутреннее разрешение — в нём рисует NX.
      : "''${NX_GS_WIDTH:=1645}"
      : "''${NX_GS_HEIGHT:=1028}"

      # Выходное — физическое разрешение панели.
      : "''${NX_GS_OUT_WIDTH:=2880}"
      : "''${NX_GS_OUT_HEIGHT:=1800}"

      # Апскейлер: linear, nearest, fsr, nis, pixel. FSR заточен ровно под
      # этот случай — увеличить готовую картинку и не размылить её.
      : "''${NX_GS_FILTER:=fsr}"

      ${displaySetup}

      cleanup() {
        [ -n "''${server_pid:-}" ] && kill "$server_pid" 2>/dev/null
        rm -rf "$runtime"
      }
      trap cleanup EXIT

      # Дальше работает отдельный скрипт, уже внутри gamescope: поднимает
      # Xephyr на его XWayland и отдаёт NX. Номер дисплея и файл авторизации
      # передаются переменными окружения — так надёжнее, чем тащить через
      # gamescope шелловскую функцию.
      export NX_GS_DISPLAY="$display"
      export NX_GS_AUTH="$authfile"

      exec gamescope \
        --backend wayland \
        -w "$NX_GS_WIDTH" -h "$NX_GS_HEIGHT" \
        -W "$NX_GS_OUT_WIDTH" -H "$NX_GS_OUT_HEIGHT" \
        -F "$NX_GS_FILTER" \
        -f \
        -- ${nx-gamescope-inner} "$@"
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

    # Вариант 1 — только bin/nx, зато с приоритетом: перекрывает одноимённый
    # файл из пакета. Всё остальное (share/applications, share/pixmaps)
    # берётся оттуда, поэтому пункт в меню по-прежнему один и зовёт `nx`.
    (lib.hiPrio nx-rootful)

    # Вариант 3 — отдельная команда, своего ярлыка намеренно нет: два
    # одинаковых пункта в лаунчере только путают.
    nx-gamescope
  ];
}
