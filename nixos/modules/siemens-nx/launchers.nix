# Два способа поднять вложенный дисплей под NX.
#
# rootful Xwayland — основной: его масштабирует сам niri, поэтому лишнего слоя
# не нужно. gamescope — запасной, ради апскейлера FSR. Почему так, а не иначе,
# разобрано в README.md.
{ lib, pkgs, nx, session }:

let
  # NX просит шрифты интерфейса жёсткими XLFD вида -adobe-helvetica-…; без
  # этих каталогов Motif молча сваливается на "fixed".
  fontPath = lib.concatStringsSep "," [
    "${pkgs.font-adobe-75dpi}/share/fonts/X11/75dpi"
    "${pkgs.font-adobe-100dpi}/share/fonts/X11/100dpi"
    "${pkgs.font-misc-misc}/share/fonts/X11/misc"
  ];

<<<<<<< HEAD
<<<<<<< HEAD
  # Свободный номер дисплея и разовый cookie: -ac открыл бы вложенный сервер
  # любому локальному процессу.
=======
  # Задаёт display, runtime, authfile, server_pid и ставит ловушку уборки.
  # Свой cookie вместо -ac: -ac открыл бы сервер любому локальному процессу.
>>>>>>> worktree-siemens-nx10
=======
  # Задаёт display, runtime, authfile, server_pid и ставит ловушку уборки.
  # Свой cookie вместо -ac: -ac открыл бы сервер любому локальному процессу.
>>>>>>> worktree-siemens-nx10
  startDisplay = ''
    display=""
    for n in $(seq 10 40); do
      if [ ! -e "/tmp/.X11-unix/X$n" ] && [ ! -e "/tmp/.X$n-lock" ]; then
        display="$n"
        break
      fi
    done
    if [ -z "$display" ]; then
      echo "nx: свободного дисплея в диапазоне 10-40 нет" >&2
      exit 1
    fi

    runtime=$(mktemp -d)
    authfile="$runtime/Xauthority"
    xauth -q -f "$authfile" add ":$display" MIT-MAGIC-COOKIE-1 "$(mcookie)"

    server_pid=""
<<<<<<< HEAD
<<<<<<< HEAD
    trap 'kill $server_pid 2>/dev/null || true; rm -rf "$runtime"' EXIT
  '';

=======
=======
>>>>>>> worktree-siemens-nx10
    cleanup() {
      [ -n "$server_pid" ] && kill "$server_pid" 2>/dev/null
      rm -rf "$runtime"
    }
    trap cleanup EXIT INT TERM HUP
  '';

  # Читает server_pid и display, заданные выше.
<<<<<<< HEAD
>>>>>>> worktree-siemens-nx10
=======
>>>>>>> worktree-siemens-nx10
  waitForDisplay = server: ''
    for _ in $(seq 1 100); do
      if ! kill -0 "$server_pid" 2>/dev/null; then
        echo "nx: ${server} завершился, не подняв :$display" >&2
        exit 1
      fi
      [ -e "/tmp/.X11-unix/X$display" ] && break
      sleep 0.1
    done
    if [ ! -e "/tmp/.X11-unix/X$display" ]; then
      echo "nx: ${server} не поднял :$display за 10 секунд" >&2
      exit 1
    fi
  '';

<<<<<<< HEAD
<<<<<<< HEAD
  # Логический размер выхода задаёт масштаб, физический — то, во что gamescope
  # увеличивает. Спрашиваем niri, чтобы не разъезжалось при смене масштаба.
=======
  # Задаёт logical и physical. Логический размер выхода определяет масштаб,
  # физический — то, во что gamescope увеличивает.
>>>>>>> worktree-siemens-nx10
=======
  # Задаёт logical и physical. Логический размер выхода определяет масштаб,
  # физический — то, во что gamescope увеличивает.
>>>>>>> worktree-siemens-nx10
  outputSize = ''
    out=$(niri msg --json focused-output 2>/dev/null || true)
    logical=$(printf '%s' "$out" | jq -r '.logical | "\(.width)x\(.height)"' 2>/dev/null || true)
    physical=$(printf '%s' "$out" | jq -r '.modes[.current_mode] | "\(.width)x\(.height)"' 2>/dev/null || true)
<<<<<<< HEAD
<<<<<<< HEAD
    case "$logical"  in [0-9]*x[0-9]*) ;; *) logical=1645x1028  ;; esac
    case "$physical" in [0-9]*x[0-9]*) ;; *) physical=2880x1800 ;; esac
  '';

=======
=======
>>>>>>> worktree-siemens-nx10
    case "$logical" in
      [0-9]*x[0-9]*) ;;
      *) logical=1645x1028
         echo "nx: niri не ответил, беру размер выхода $logical" >&2 ;;
    esac
    case "$physical" in [0-9]*x[0-9]*) ;; *) physical=2880x1800 ;; esac
  '';

  # Выключает полный экран не только на 0, но и на привычные false/no/off.
  fullscreenFlag = flag: ''
    case "''${NX_FULLSCREEN:-1}" in
      0 | no | false | off) fullscreen=() ;;
      *) fullscreen=(${flag}) ;;
    esac
  '';

<<<<<<< HEAD
>>>>>>> worktree-siemens-nx10
=======
>>>>>>> worktree-siemens-nx10
  rootful = pkgs.writeShellApplication {
    name = "nx";
    runtimeInputs = with pkgs; [ xwayland xauth util-linux coreutils jq ];
    text = ''
      # NX_NESTED=0 — запуск в хозяйском X-сервере, без прослойки.
      if [ "''${NX_NESTED:-1}" = 0 ]; then
        exec ${nx}/bin/nx "$@"
      fi

      ${outputSize}

      # Меньше логического размера — крупнее и мыльнее, больше — мельче и чётче.
      : "''${NX_GEOMETRY:=$logical}"

      # -fullscreen не спорит с -geometry: размер X-экрана остаётся наш.
<<<<<<< HEAD
<<<<<<< HEAD
      fullscreen=()
      [ "''${NX_FULLSCREEN:-1}" = 0 ] || fullscreen=(-fullscreen)
=======
      ${fullscreenFlag "-fullscreen"}
>>>>>>> worktree-siemens-nx10
=======
      ${fullscreenFlag "-fullscreen"}
>>>>>>> worktree-siemens-nx10

      ${startDisplay}

      Xwayland ":$display" \
        -auth "$authfile" \
        -geometry "$NX_GEOMETRY" \
<<<<<<< HEAD
<<<<<<< HEAD
        -fp ${fontPath} \
=======
        -fp "${fontPath}" \
>>>>>>> worktree-siemens-nx10
=======
        -fp "${fontPath}" \
>>>>>>> worktree-siemens-nx10
        "''${fullscreen[@]}" &
      server_pid=$!

      ${waitForDisplay "Xwayland"}

      DISPLAY=":$display" XAUTHORITY="$authfile" ${session} "$@"
    '';
  };

<<<<<<< HEAD
<<<<<<< HEAD
  # Xephyr внутри gamescope обязателен: gamescope показывает только верхнее
  # окно, а у NX их много.
  gamescopeInner = pkgs.writeShellScript "nx-gamescope-inner" ''
    set -euo pipefail
    display="$NX_GS_DISPLAY"
    authfile="$NX_GS_AUTH"

    # -no-host-grab обязателен: NX делает активный grab для меню, иначе ввод
    # всей системы уйдёт ему.
    ${pkgs.xorg-server}/bin/Xephyr ":$display" \
      -auth "$authfile" \
      -screen "''${NX_GS_WIDTH}x''${NX_GS_HEIGHT}" \
      -fp ${fontPath} \
      -resizeable -no-host-grab &
    server_pid=$!
    trap 'kill "$server_pid" 2>/dev/null || true' EXIT

    ${waitForDisplay "Xephyr"}

    DISPLAY=":$display" XAUTHORITY="$authfile" ${session} "$@"
  '';

  gamescopeBin = pkgs.writeShellApplication {
    name = "nx-gamescope";
    runtimeInputs = with pkgs; [ gamescope xorg-server xauth util-linux coreutils jq ];
=======
=======
>>>>>>> worktree-siemens-nx10
  # Вторая половина запуска через gamescope: Xephyr внутри него обязателен,
  # потому что gamescope показывает только верхнее окно, а у NX их много.
  gamescopeInner = pkgs.writeShellApplication {
    name = "nx-gamescope-inner";
    runtimeInputs = with pkgs; [ coreutils ];
    text = ''
      display="$1"
      authfile="$2"
      screen="$3"
      shift 3

      # -no-host-grab обязателен: NX делает активный grab для меню, иначе ввод
      # всей системы уйдёт ему.
      ${pkgs.xorg-server}/bin/Xephyr ":$display" \
        -auth "$authfile" \
        -screen "$screen" \
        -fp "${fontPath}" \
        -resizeable -no-host-grab &
      server_pid=$!
      trap 'kill "$server_pid" 2>/dev/null || true' EXIT INT TERM HUP

      ${waitForDisplay "Xephyr"}

      DISPLAY=":$display" XAUTHORITY="$authfile" ${session} "$@"
    '';
  };

  gamescopeBin = pkgs.writeShellApplication {
    name = "nx-gamescope";
    runtimeInputs = with pkgs; [ gamescope xauth util-linux coreutils jq ];
<<<<<<< HEAD
>>>>>>> worktree-siemens-nx10
=======
>>>>>>> worktree-siemens-nx10
    text = ''
      ${outputSize}

      : "''${NX_GS_WIDTH:=''${logical%x*}}"
      : "''${NX_GS_HEIGHT:=''${logical#*x}}"
      : "''${NX_GS_OUT_WIDTH:=''${physical%x*}}"
      : "''${NX_GS_OUT_HEIGHT:=''${physical#*x}}"

      # Апскейлер: linear, nearest, fsr, nis, pixel.
      : "''${NX_GS_FILTER:=fsr}"

<<<<<<< HEAD
<<<<<<< HEAD
      fullscreen=()
      [ "''${NX_FULLSCREEN:-1}" = 0 ] || fullscreen=(-f)

      ${startDisplay}

      # Внутренний скрипт — отдельный процесс с set -u, поэтому именно export.
      export NX_GS_WIDTH NX_GS_HEIGHT
      export NX_GS_DISPLAY="$display"
      export NX_GS_AUTH="$authfile"

      exec gamescope \
=======
=======
>>>>>>> worktree-siemens-nx10
      ${fullscreenFlag "-f"}

      ${startDisplay}

      # Без exec: он заменил бы процесс и ловушка уборки не сработала бы.
      gamescope \
<<<<<<< HEAD
>>>>>>> worktree-siemens-nx10
=======
>>>>>>> worktree-siemens-nx10
        --backend wayland \
        -w "$NX_GS_WIDTH" -h "$NX_GS_HEIGHT" \
        -W "$NX_GS_OUT_WIDTH" -H "$NX_GS_OUT_HEIGHT" \
        -F "$NX_GS_FILTER" \
        "''${fullscreen[@]}" \
<<<<<<< HEAD
<<<<<<< HEAD
        -- ${gamescopeInner} "$@"
    '';
  };

  # Своя иконка, чтобы два пункта в лаунчере не путались. У gamescope иконки
  # нет, берём монитор из Adwaita.
  gamescopeIcon = pkgs.runCommand "nx-gamescope-icon" { } ''
    install -Dm444 \
      ${pkgs.adwaita-icon-theme}/share/icons/Adwaita/scalable/devices/video-display.svg \
      "$out/share/pixmaps/siemens-nx-gamescope.svg"
  '';

=======
=======
>>>>>>> worktree-siemens-nx10
        -- ${gamescopeInner}/bin/nx-gamescope-inner \
           "$display" "$authfile" "''${NX_GS_WIDTH}x''${NX_GS_HEIGHT}" "$@"
    '';
  };

<<<<<<< HEAD
>>>>>>> worktree-siemens-nx10
=======
>>>>>>> worktree-siemens-nx10
  gamescopeDesktop = pkgs.makeDesktopItem {
    name = "siemens-nx-gamescope";
    desktopName = "Siemens NX 10.0.3 (gamescope)";
    comment = "NX через gamescope: увеличение по FSR вместо растягивания композитором";
    exec = "nx-gamescope %f";
<<<<<<< HEAD
<<<<<<< HEAD
    icon = "siemens-nx-gamescope";
    # Одна основная категория, иначе пункт появится в меню дважды.
=======
=======
>>>>>>> worktree-siemens-nx10
    # Имя из темы значков, чтобы не тащить копию файла из adwaita.
    icon = "video-display";
    # Graphics основная, Engineering дополнительная. Двух основных нельзя:
    # пункт задвоится в меню.
<<<<<<< HEAD
>>>>>>> worktree-siemens-nx10
=======
>>>>>>> worktree-siemens-nx10
    categories = [ "Graphics" "Engineering" ];
    terminal = false;
  };
in
{
  inherit rootful;

  gamescope = pkgs.symlinkJoin {
    name = "nx-gamescope";
<<<<<<< HEAD
<<<<<<< HEAD
    paths = [ gamescopeBin gamescopeDesktop gamescopeIcon ];
=======
    paths = [ gamescopeBin gamescopeDesktop ];
>>>>>>> worktree-siemens-nx10
=======
    paths = [ gamescopeBin gamescopeDesktop ];
>>>>>>> worktree-siemens-nx10
  };
}
