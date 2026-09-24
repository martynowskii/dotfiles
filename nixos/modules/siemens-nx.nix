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

  # Снимок дерева окон вложенного сервера. Нужен, чтобы разбираться с
  # панелями NX по фактам: видно, чем окно себя объявило (WM_CLASS,
  # _NET_WM_WINDOW_TYPE, _MOTIF_WM_HINTS, WM_TRANSIENT_FOR) и что с ним
  # сделал менеджер.
  #
  # Запускается двумя способами: сам, когда NX стартовал с NX_DEBUG=1, или
  # руками из другого терминала — тогда дисплей и cookie берутся из файла,
  # который пишет nx-session.
  nx-dump-windows = pkgs.writeShellApplication {
    name = "nx-dump-windows";
    runtimeInputs = with pkgs; [
      xwininfo
      xprop
      xdpyinfo
      coreutils
      gnugrep
    ];
    text = ''
      out="''${1:-$HOME/nx-windows.txt}"
      session_file="''${XDG_RUNTIME_DIR:-/tmp}/nx-session.env"

      # NX_IN_SESSION выставлен, когда нас позвал сам nx-session: там DISPLAY
      # и XAUTHORITY уже верные, читать файл незачем.
      if [ -z "''${NX_IN_SESSION:-}" ] && [ -r "$session_file" ]; then
        # shellcheck source=/dev/null
        . "$session_file"
        export DISPLAY XAUTHORITY
      fi

      if [ -z "''${DISPLAY:-}" ]; then
        echo "nx-dump-windows: не знаю, какой дисплей смотреть." >&2
        echo "  Похоже, NX сейчас не запущен: нет $session_file." >&2
        exit 1
      fi

      {
        echo "=== дисплей $DISPLAY ==="
        xdpyinfo | grep -E 'name of display|version number|dimensions|resolution|depth of root'

        echo
        echo "=== менеджер окон ==="
        xprop -root _NET_SUPPORTING_WM_CHECK _NET_SUPPORTED
        wm=$(xprop -root _NET_SUPPORTING_WM_CHECK | grep -o '0x[0-9a-f]*' | head -1)
        if [ -n "$wm" ]; then
          xprop -id "$wm" _NET_WM_NAME
        fi

        echo
        echo "=== дерево окон ==="
        xwininfo -root -tree

        echo
        echo "=== окна верхнего уровня ==="
        for w in $(xprop -root _NET_CLIENT_LIST | grep -o '0x[0-9a-f]*'); do
          echo "--- $w ---"
          xwininfo -id "$w" | grep -E 'Absolute|Width:|Height:|Map State|Override'
          xprop -id "$w" \
            WM_NAME WM_CLASS WM_TRANSIENT_FOR WM_NORMAL_HINTS \
            _MOTIF_WM_HINTS _NET_WM_WINDOW_TYPE _NET_WM_STATE
          echo
        done
      } > "$out" 2>&1

      echo "nx-dump-windows: записано в $out" >&2
    '';
  };

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

    # Композитор. Без него окна мелькают при изменении размера — перерисовка
    # идёт без двойной буферизации. С ним metacity по умолчанию добавляет
    # вокруг каждого окна невидимую область тени в 26 пикселей, и вот это уже
    # ломает раскладку: NX расставляет свои окна (окно детали, панели Resource
    # Bar) внутри прямоугольника главного, как MDI-детей на Windows, и поправки
    # на рамку не делает — код писан под тонкие рамки 2010 года.
    #
    # Оказалось, выбирать не нужно: тень убирается из gtk.css ниже, и тогда
    # включённый композитор даёт рамку тоньше, чем выключенный. Замеры на
    # xclock 300x200, сдвиг клиента внутри рамки:
    #
    #   композитор, тень как из коробки      +26 +60
    #   без композитора, заголовок сжат        +5 +21
    #   композитор, тень убрана полностью      +0 +16
    #   композитор, тень убрана, борт 4px      +4 +16   ← это
    #
    # Совсем нулевой борт не берём: за него нечем ухватить окно мышью, а
    # запасной способ metacity — Super с перетаскиванием — до вложенной сессии
    # не доходит, Super перехватывает niri. Борт стоит только по бокам и
    # снизу: верхний отступ просто прибавляется к заголовку и ничего не даёт.
    #
    # NX_COMPOSITOR=none — выключить обратно. Может пригодиться на тяжёлых
    # сценах: композитор докладывает лишнее копирование кадра поверх OpenGL.
    # Значения: xrender (по умолчанию), xpresent, none.
    : "''${NX_COMPOSITOR:=xrender}"
    # Где открывать окна, которые сами себе места не выбрали — диалоги вроде
    # настроек. center ставит их по центру экрана вместо ступенек от левого
    # верхнего угла.
    #
    # Раскладке NX это не мешает, и вот почему. В place.c metacity при
    # включённых обходах (значение по умолчанию) делает так:
    #
    #   if ((flags & PPosition) || (flags & USPosition))
    #     goto done_no_constraints;   /* позиция от приложения — не трогаем */
    #
    # то есть окно, задавшее себе координаты, алгоритм размещения вообще
    # обходит стороной. Панели NX их задают, и замер это подтвердил: при
    # center окно без позиции переехало в центр, окно с позицией осталось на
    # месте до пикселя.
    #
    # Оговорка: если NX задаёт позицию и своим диалогам, центрировать их
    # нечем — перебить это можно только через disable-workarounds, а он
    # заодно развалит расстановку панелей.
    #
    # Значения: center, smart, cascade, origin, random.
    : "''${NX_PLACEMENT:=center}"

    metacity_cfg=$(mktemp -d)
    mkdir -p "$metacity_cfg/glib-2.0/settings" "$metacity_cfg/gtk-3.0"
    cat > "$metacity_cfg/glib-2.0/settings/keyfile" <<EOF
[org/gnome/metacity]
compositor='$NX_COMPOSITOR'
placement-mode='$NX_PLACEMENT'
EOF

    # Заголовок окна metacity 3.x рисует темой GTK, поэтому его высота
    # правится обычным пользовательским gtk.css — и, раз XDG_CONFIG_HOME у
    # нас подменён только для metacity, файл увидит тоже только он.
    #
    # Смысл тот же, что у настройки тени: NX кладёт свои окна внутрь
    # главного, не делая поправки на рамку, так что каждый лишний пиксель
    # рамки — это пиксель, на который окно уезжает. Замер на xclock 300x200
    # при выключенном композиторе, чтобы видеть вклад одного заголовка:
    #
    #   как есть           заголовок 42
    #   этот gtk.css       заголовок 21
    #
    # 21 — жёсткий пол: обнуление шрифта, кнопок и отступов ниже не опускает,
    # у темы GTK внутри свой минимум. Совсем без заголовка можно только через
    # старую тему metacity-theme-3.xml с has_title="false", но тогда у
    # плавающих панелей пропадут крестик и возможность двигать их мышью.
    # На RHEL у NX заголовки были примерно такие же, около 20.
    #
    # NX_TITLEBARS=normal — вернуть штатные 42, если правка когда-нибудь
    # разойдётся с очередной версией GTK.
    if [ "''${NX_TITLEBARS:-thin}" != normal ]; then
      cat > "$metacity_cfg/gtk-3.0/gtk.css" <<'EOF'
/* Невидимая область тени вокруг рамки. Из-за неё окна NX уезжали на 26
   пикселей вбок; оставляем 4 по бокам и снизу — чтобы окно можно было
   ухватить мышью за край. Сверху ноль: верхний отступ просто добавляется
   к заголовку (замер: margin 4px по кругу даёт +4+20, а так +4+16). */
decoration, decoration:backdrop {
  margin: 0 4px 4px 4px;
  box-shadow: none;
  border-radius: 0;
}

.titlebar, headerbar,
.titlebar.default-decoration, headerbar.default-decoration {
  min-height: 0;
  padding: 0 2px;
  border-width: 0;
}

.titlebar label.title, headerbar label.title {
  font-size: 9px;
  padding: 0;
  margin: 0;
}

.titlebar button.titlebutton, headerbar button.titlebutton {
  min-height: 0;
  min-width: 0;
  padding: 0;
  margin: 0;
  border-width: 0;
}

.titlebar button.titlebutton image, headerbar button.titlebutton image {
  -gtk-icon-size: 12px;
  min-height: 0;
  min-width: 0;
  padding: 0;
  margin: 0;
}
EOF
    fi

    # Корневое окно вложенного сервера по умолчанию чёрное с мусором. Его
    # видно по краям, вокруг окон NX, и оно же вспыхивает в щелях при
    # изменении размеров. Заливаем серым под цвет интерфейса Motif — щели
    # никуда не денутся, но перестанут бросаться в глаза.
    ${pkgs.xsetroot}/bin/xsetroot -solid "''${NX_ROOT_COLOR:-#b3b3b3}" || true

    # Куда смотреть снаружи. Дисплей у нас каждый раз новый, а cookie лежит
    # во временном каталоге, так что без этой записки к вложенному серверу из
    # другого терминала не подключиться — ни nx-dump-windows, ни чем-то ещё.
    session_file="''${XDG_RUNTIME_DIR:-/tmp}/nx-session.env"
    printf 'DISPLAY=%s\nXAUTHORITY=%s\n' "$DISPLAY" "''${XAUTHORITY:-}" > "$session_file"

    # Настройки подсовываем только metacity, а не всей сессии: XDG_CONFIG_HOME
    # задан на одну команду, чтобы не сбить с толку NX и не тронуть настоящий
    # dconf твоего рабочего стола.
    GSETTINGS_BACKEND=keyfile XDG_CONFIG_HOME="$metacity_cfg" \
      ${pkgs.metacity}/bin/metacity &
    metacity_pid=$!

    # NX_DEBUG=1 — снять дерево окон, когда интерфейс уже сложился. Задержка
    # по умолчанию с запасом: NX стартует долго, а снимок в середине запуска
    # показывает недостроенный интерфейс и только путает.
    debug_pid=""
    if [ -n "''${NX_DEBUG:-}" ]; then
      (
        sleep "''${NX_DEBUG_DELAY:-90}"
        NX_IN_SESSION=1 ${nx-dump-windows}/bin/nx-dump-windows \
          "''${NX_DEBUG_FILE:-$HOME/nx-windows.txt}"
      ) &
      debug_pid=$!
    fi

    # Ждущий снимок убиваем тоже: если закрыть NX раньше срока, он проснётся
    # над уже мёртвым дисплеем и запишет вместо дерева окон ошибку.
    trap 'kill "$metacity_pid" ''${debug_pid:+"$debug_pid"} 2>/dev/null || true; rm -f "$session_file"; rm -rf "$metacity_cfg"' EXIT

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

  # Размеры активного выхода. Нужны обоим вариантам, и по-разному: логический
  # задаёт масштаб (в нём рисует NX), физический — то, во что картинку
  # увеличивают.
  #
  # Спрашиваем niri, а не вбиваем числа: иначе при смене масштаба или
  # подключении монитора полноэкранное окно перестанет совпадать с экраном и
  # по краям появятся поля. Запасные значения — под текущий ноутбук, на
  # случай если niri нет или он промолчал.
  outputQuery = ''
    nx_logical=""
    nx_physical=""
    if command -v niri >/dev/null 2>&1; then
      nx_out=$(niri msg --json focused-output 2>/dev/null || true)
      if [ -n "$nx_out" ]; then
        nx_logical=$(printf '%s' "$nx_out" | jq -r '.logical | "\(.width)x\(.height)"' 2>/dev/null || true)
        nx_physical=$(printf '%s' "$nx_out" | jq -r '.modes[.current_mode] | "\(.width)x\(.height)"' 2>/dev/null || true)
      fi
    fi
    case "$nx_logical" in [0-9]*x[0-9]*) ;; *) nx_logical=1645x1028 ;; esac
    case "$nx_physical" in [0-9]*x[0-9]*) ;; *) nx_physical=2880x1800 ;; esac
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
    runtimeInputs = with pkgs; [ xwayland xauth util-linux coreutils jq ];
    text = ''
      # NX_NESTED=0 — запуск напрямую, в X-сервере хозяйской сессии. Панели
      # при этом разъедутся, зато видно поведение без прослойки.
      : "''${NX_NESTED:=1}"

      ${outputQuery}

      # Логический размер выхода. Уменьшить это число — картинка станет
      # крупнее и мыльнее, увеличить — мельче и чётче; поставить физический
      # размер экрана значит отказаться от увеличения вовсе.
      #
      # По умолчанию берём ровно логический размер выхода: тогда развёрнутое
      # на полный экран окно совпадает с экраном пиксель в пиксель, без полей
      # и без повторного растягивания.
      : "''${NX_GEOMETRY:=$nx_logical}"

      # Полный экран. Проверено, что -fullscreen не спорит с -geometry:
      # размер X-экрана остаётся наш, а композитор лишь разворачивает окно.
      #   только -geometry 800x600         → X-экран 800x600
      #   только -fullscreen               → X-экран 640x480 (размер по умолчанию)
      #   -fullscreen + -geometry 800x600  → X-экран 800x600
      # NX_FULLSCREEN=0 — оставить обычным окном.
      : "''${NX_FULLSCREEN:=1}"
      if [ "$NX_FULLSCREEN" = 0 ]; then
        fullscreen_arg=""
      else
        fullscreen_arg="-fullscreen"
      fi

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
        $fullscreen_arg \
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
  nx-gamescope-bin = pkgs.writeShellApplication {
    name = "nx-gamescope";
    runtimeInputs = with pkgs; [ gamescope xorg-server xauth util-linux coreutils jq ];
    text = ''
      ${outputQuery}

      # Внутреннее разрешение — в нём рисует NX. По умолчанию логический
      # размер выхода.
      : "''${NX_GS_WIDTH:=''${nx_logical%x*}}"
      : "''${NX_GS_HEIGHT:=''${nx_logical#*x}}"

      # Выходное — физическое разрешение панели.
      : "''${NX_GS_OUT_WIDTH:=''${nx_physical%x*}}"
      : "''${NX_GS_OUT_HEIGHT:=''${nx_physical#*x}}"

      # Полный экран — как и у варианта 1. NX_FULLSCREEN=0 оставит окном.
      : "''${NX_FULLSCREEN:=1}"
      if [ "$NX_FULLSCREEN" = 0 ]; then
        fullscreen_arg=""
      else
        fullscreen_arg="-f"
      fi

      # Апскейлер: linear, nearest, fsr, nis, pixel. FSR заточен ровно под
      # этот случай — увеличить готовую картинку и не размылить её.
      : "''${NX_GS_FILTER:=fsr}"

      # Внутренний скрипт — отдельный процесс, и живёт он с set -u. Без
      # export он падает на первой же строке с unbound variable, а не
      # запускает Xephyr.
      export NX_GS_WIDTH NX_GS_HEIGHT

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

      # shellcheck disable=SC2086
      exec gamescope \
        --backend wayland \
        -w "$NX_GS_WIDTH" -h "$NX_GS_HEIGHT" \
        -W "$NX_GS_OUT_WIDTH" -H "$NX_GS_OUT_HEIGHT" \
        -F "$NX_GS_FILTER" \
        $fullscreen_arg \
        -- ${nx-gamescope-inner} "$@"
    '';
  };

  # Своя иконка, чтобы пункт в лаунчере не путался с основным. У gamescope
  # иконки нет вовсе, так что берём монитор из Adwaita — по смыслу это как
  # раз про вывод и масштаб.
  nx-gamescope-icon = pkgs.runCommand "nx-gamescope-icon" { } ''
    install -Dm644 \
      ${pkgs.adwaita-icon-theme}/share/icons/Adwaita/scalable/devices/video-display.svg \
      "$out/share/pixmaps/siemens-nx-gamescope.svg"
  '';

  nx-gamescope-desktop = pkgs.makeDesktopItem {
    name = "siemens-nx-gamescope";
    desktopName = "Siemens NX 10.0.3 (gamescope)";
    comment = "NX через gamescope: увеличение по FSR вместо растягивания композитором";
    exec = "nx-gamescope %f";
    icon = "siemens-nx-gamescope";
    # Ровно одна основная категория: с двумя (Graphics и Science, как у
    # пункта самого пакета) меню показало бы запуск дважды.
    categories = [ "Graphics" "Engineering" ];
    terminal = false;
  };

  nx-gamescope = pkgs.symlinkJoin {
    name = "nx-gamescope";
    paths = [ nx-gamescope-bin nx-gamescope-desktop nx-gamescope-icon ];
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

    # Вариант 3 — отдельная команда со своим пунктом в лаунчере и своей
    # иконкой, чтобы два запуска не путались.
    nx-gamescope

    # Снимок дерева окон запущенного NX — для разбирательств с панелями.
    nx-dump-windows
  ];
}
