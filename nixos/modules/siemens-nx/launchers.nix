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

  # Задаёт display, runtime, authfile, server_pid и ставит ловушку уборки.
  # Свой cookie вместо -ac: -ac открыл бы сервер любому локальному процессу.
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
    cleanup() {
      [ -n "$server_pid" ] && kill "$server_pid" 2>/dev/null
      rm -rf "$runtime"
    }
    trap cleanup EXIT INT TERM HUP
  '';

  # Читает server_pid и display, заданные выше.
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

  # Задаёт logical и physical. Логический размер выхода определяет масштаб,
  # физический — то, во что gamescope увеличивает.
  outputSize = ''
    out=$(niri msg --json focused-output 2>/dev/null || true)
    logical=$(printf '%s' "$out" | jq -r '.logical | "\(.width)x\(.height)"' 2>/dev/null || true)
    physical=$(printf '%s' "$out" | jq -r '.modes[.current_mode] | "\(.width)x\(.height)"' 2>/dev/null || true)
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
      ${fullscreenFlag "-fullscreen"}

      ${startDisplay}

      Xwayland ":$display" \
        -auth "$authfile" \
        -geometry "$NX_GEOMETRY" \
        -fp "${fontPath}" \
        "''${fullscreen[@]}" &
      server_pid=$!

      ${waitForDisplay "Xwayland"}

      DISPLAY=":$display" XAUTHORITY="$authfile" ${session} "$@"
    '';
  };

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
    text = ''
      ${outputSize}

      : "''${NX_GS_WIDTH:=''${logical%x*}}"
      : "''${NX_GS_HEIGHT:=''${logical#*x}}"
      : "''${NX_GS_OUT_WIDTH:=''${physical%x*}}"
      : "''${NX_GS_OUT_HEIGHT:=''${physical#*x}}"

      # Апскейлер: linear, nearest, fsr, nis, pixel.
      : "''${NX_GS_FILTER:=fsr}"

      ${fullscreenFlag "-f"}

      ${startDisplay}

      # Без exec: он заменил бы процесс и ловушка уборки не сработала бы.
      gamescope \
        --backend wayland \
        -w "$NX_GS_WIDTH" -h "$NX_GS_HEIGHT" \
        -W "$NX_GS_OUT_WIDTH" -H "$NX_GS_OUT_HEIGHT" \
        -F "$NX_GS_FILTER" \
        "''${fullscreen[@]}" \
        -- ${gamescopeInner}/bin/nx-gamescope-inner \
           "$display" "$authfile" "''${NX_GS_WIDTH}x''${NX_GS_HEIGHT}" "$@"
    '';
  };

  # Своя копия, а не имя из темы: имя лаунчер не всегда разрешает, а два
  # пункта меню надо различать наверняка. У gamescope иконки нет, берём
  # монитор из adwaita.
  gamescopeIcon = pkgs.runCommand "nx-gamescope-icon" { } ''
    install -Dm444 \
      ${pkgs.adwaita-icon-theme}/share/icons/Adwaita/scalable/devices/video-display.svg \
      "$out/share/pixmaps/siemens-nx-gamescope.svg"
  '';

  gamescopeDesktop = pkgs.makeDesktopItem {
    name = "siemens-nx-gamescope";
    desktopName = "Siemens NX 10.0.3 (gamescope)";
    comment = "NX через gamescope: увеличение по FSR вместо растягивания композитором";
    exec = "nx-gamescope %f";
    icon = "siemens-nx-gamescope";
    # Graphics основная, Engineering дополнительная. Двух основных нельзя:
    # пункт задвоится в меню.
    categories = [ "Graphics" "Engineering" ];
    terminal = false;
  };
in
{
  inherit rootful;

  gamescope = pkgs.symlinkJoin {
    name = "nx-gamescope";
    paths = [ gamescopeBin gamescopeDesktop gamescopeIcon ];
  };
}
