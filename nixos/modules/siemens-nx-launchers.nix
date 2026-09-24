# Два способа поднять вложенный дисплей под NX.
#
# rootful Xwayland — основной: его масштабирует сам niri, поэтому лишнего слоя
# не нужно. gamescope — запасной, ради апскейлера FSR. Почему так, а не иначе,
# разобрано в siemens-nx-display.md.
{ pkgs, nx, session, fontPath }:

let
  # Свободный номер дисплея и разовый cookie: -ac открыл бы вложенный сервер
  # любому локальному процессу.
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
    trap 'kill $server_pid 2>/dev/null || true; rm -rf "$runtime"' EXIT
  '';

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

  # Логический размер выхода задаёт масштаб, физический — то, во что gamescope
  # увеличивает. Спрашиваем niri, чтобы не разъезжалось при смене масштаба.
  outputSize = ''
    out=$(niri msg --json focused-output 2>/dev/null || true)
    logical=$(printf '%s' "$out" | jq -r '.logical | "\(.width)x\(.height)"' 2>/dev/null || true)
    physical=$(printf '%s' "$out" | jq -r '.modes[.current_mode] | "\(.width)x\(.height)"' 2>/dev/null || true)
    case "$logical"  in [0-9]*x[0-9]*) ;; *) logical=1645x1028  ;; esac
    case "$physical" in [0-9]*x[0-9]*) ;; *) physical=2880x1800 ;; esac
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
      ${fontPath}

      # Меньше логического размера — крупнее и мыльнее, больше — мельче и чётче.
      : "''${NX_GEOMETRY:=$logical}"

      # -fullscreen не спорит с -geometry: размер X-экрана остаётся наш.
      fullscreen=()
      [ "''${NX_FULLSCREEN:-1}" = 0 ] || fullscreen=(-fullscreen)

      ${startDisplay}

      Xwayland ":$display" \
        -auth "$authfile" \
        -geometry "$NX_GEOMETRY" \
        -fp "$nx_fp" \
        "''${fullscreen[@]}" &
      server_pid=$!

      ${waitForDisplay "Xwayland"}

      DISPLAY=":$display" XAUTHORITY="$authfile" ${session} "$@"
    '';
  };

  # Xephyr внутри gamescope обязателен: gamescope показывает только верхнее
  # окно, а у NX их много.
  gamescopeInner = pkgs.writeShellScript "nx-gamescope-inner" ''
    set -euo pipefail
    display="$NX_GS_DISPLAY"
    authfile="$NX_GS_AUTH"

    ${fontPath}

    # -no-host-grab обязателен: NX делает активный grab для меню, иначе ввод
    # всей системы уйдёт ему.
    ${pkgs.xorg-server}/bin/Xephyr ":$display" \
      -auth "$authfile" \
      -screen "''${NX_GS_WIDTH}x''${NX_GS_HEIGHT}" \
      -fp "$nx_fp" \
      -resizeable -no-host-grab &
    server_pid=$!
    trap 'kill "$server_pid" 2>/dev/null || true' EXIT

    ${waitForDisplay "Xephyr"}

    DISPLAY=":$display" XAUTHORITY="$authfile" ${session} "$@"
  '';

  gamescopeBin = pkgs.writeShellApplication {
    name = "nx-gamescope";
    runtimeInputs = with pkgs; [ gamescope xorg-server xauth util-linux coreutils jq ];
    text = ''
      ${outputSize}

      : "''${NX_GS_WIDTH:=''${logical%x*}}"
      : "''${NX_GS_HEIGHT:=''${logical#*x}}"
      : "''${NX_GS_OUT_WIDTH:=''${physical%x*}}"
      : "''${NX_GS_OUT_HEIGHT:=''${physical#*x}}"

      # Апскейлер: linear, nearest, fsr, nis, pixel.
      : "''${NX_GS_FILTER:=fsr}"

      fullscreen=()
      [ "''${NX_FULLSCREEN:-1}" = 0 ] || fullscreen=(-f)

      ${startDisplay}

      # Внутренний скрипт — отдельный процесс с set -u, поэтому именно export.
      export NX_GS_WIDTH NX_GS_HEIGHT
      export NX_GS_DISPLAY="$display"
      export NX_GS_AUTH="$authfile"

      exec gamescope \
        --backend wayland \
        -w "$NX_GS_WIDTH" -h "$NX_GS_HEIGHT" \
        -W "$NX_GS_OUT_WIDTH" -H "$NX_GS_OUT_HEIGHT" \
        -F "$NX_GS_FILTER" \
        "''${fullscreen[@]}" \
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

  gamescopeDesktop = pkgs.makeDesktopItem {
    name = "siemens-nx-gamescope";
    desktopName = "Siemens NX 10.0.3 (gamescope)";
    comment = "NX через gamescope: увеличение по FSR вместо растягивания композитором";
    exec = "nx-gamescope %f";
    icon = "siemens-nx-gamescope";
    # Одна основная категория, иначе пункт появится в меню дважды.
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
