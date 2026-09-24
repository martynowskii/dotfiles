# Что происходит внутри вложенного дисплея: оконный менеджер и сам NX.
#
<<<<<<< HEAD
# Metacity не вкусовщина — NX сверяет _NET_WM_NAME со списком из трёх имён,
# зашитым в libugii.so. Настройки его рамок подобраны замерами, см.
=======
# NX опознаёт три WM по _NET_WM_NAME (Metacity, KWin, GNOME Shell). На
# раскладку панелей это, как выяснилось, не влияет, но metacity — единственный
# протестированный Siemens вариант. Настройки рамок подобраны замерами, см.
>>>>>>> worktree-siemens-nx10
# README.md.
{ pkgs, nx }:

let
  dumpWindows = pkgs.writeShellApplication {
    name = "nx-dump-windows";
<<<<<<< HEAD
    runtimeInputs = with pkgs; [ xwininfo xprop xdpyinfo coreutils gnugrep ];
    text = ''
      out="''${1:-$HOME/nx-windows.txt}"
      session="''${XDG_RUNTIME_DIR:-/tmp}/nx-session.env"

      # Позвали снаружи — берём дисплей и cookie из записки, которую оставил
      # nx-session.
      if [ -z "''${DISPLAY:-}" ] && [ -r "$session" ]; then
        # shellcheck source=/dev/null
        . "$session"
=======
    runtimeInputs = with pkgs; [ xwininfo xprop xdpyinfo coreutils gnugrep gnused ];
    text = ''
      out="''${1:-''${XDG_RUNTIME_DIR:-/tmp}/nx-windows.txt}"
      session="''${XDG_RUNTIME_DIR:-/tmp}/nx-session.env"

      # Позвали снаружи — берём дисплей и cookie из записки nx-session.
      # Читаем, а не исполняем: файл может лежать в общедоступном /tmp.
      if [ -z "''${DISPLAY:-}" ] && [ -r "$session" ]; then
        DISPLAY=$(sed -n 's/^DISPLAY=//p' "$session")
        XAUTHORITY=$(sed -n 's/^XAUTHORITY=//p' "$session")
>>>>>>> worktree-siemens-nx10
        export DISPLAY XAUTHORITY
      fi

      if [ -z "''${DISPLAY:-}" ]; then
        echo "nx-dump-windows: NX не запущен, нет $session" >&2
        exit 1
      fi

<<<<<<< HEAD
      {
        echo "=== дисплей $DISPLAY ==="
        xdpyinfo | grep -E 'name of display|dimensions|resolution|depth of root'

        echo
        echo "=== менеджер окон ==="
        xprop -root _NET_SUPPORTING_WM_CHECK _NET_SUPPORTED
        wm=$(xprop -root _NET_SUPPORTING_WM_CHECK | grep -o '0x[0-9a-f]*' | head -1)
        [ -n "$wm" ] && xprop -id "$wm" _NET_WM_NAME

        echo
        echo "=== дерево окон ==="
        xwininfo -root -tree

        echo
        echo "=== окна верхнего уровня ==="
        for w in $(xprop -root _NET_CLIENT_LIST | grep -o '0x[0-9a-f]*'); do
          echo "--- $w ---"
          xwininfo -all -id "$w" \
            | grep -E 'Absolute|Width:|Height:|Map State|Override|Gravity|Backing'
          xprop -id "$w" WM_NAME WM_CLASS WM_TRANSIENT_FOR WM_NORMAL_HINTS \
            _MOTIF_WM_HINTS _NET_WM_WINDOW_TYPE _NET_WM_STATE
=======
      # Каждый фильтр с || true: пустой grep под errexit оборвал бы снимок на
      # середине — ровно в том случае, ради которого он и снимается.
      {
        echo "=== дисплей $DISPLAY ==="
        xdpyinfo | grep -E 'name of display|dimensions|resolution|depth of root' || true

        echo
        echo "=== менеджер окон ==="
        xprop -root _NET_SUPPORTING_WM_CHECK _NET_SUPPORTED || true
        wm=$(xprop -root _NET_SUPPORTING_WM_CHECK 2>/dev/null | grep -o '0x[0-9a-f]*' | head -1 || true)
        if [ -n "$wm" ]; then
          xprop -id "$wm" _NET_WM_NAME || true
        fi

        echo
        echo "=== дерево окон ==="
        xwininfo -root -tree || true

        echo
        echo "=== окна верхнего уровня ==="
        for w in $(xprop -root _NET_CLIENT_LIST 2>/dev/null | grep -o '0x[0-9a-f]*' || true); do
          echo "--- $w ---"
          xwininfo -all -id "$w" \
            | grep -E 'Absolute|Width:|Height:|Map State|Override|Gravity|Backing' || true
          xprop -id "$w" WM_NAME WM_CLASS WM_TRANSIENT_FOR WM_NORMAL_HINTS \
            _MOTIF_WM_HINTS _NET_WM_WINDOW_TYPE _NET_WM_STATE || true
>>>>>>> worktree-siemens-nx10
          echo
        done
      } > "$out" 2>&1

      echo "nx-dump-windows: записано в $out" >&2
    '';
  };

  # Композитор включён, но его тень убрана: без композитора окна мелькают при
  # изменении размера, а тень добавляла к рамке 26 пикселей и разносила
  # раскладку NX. Борт по бокам и снизу — чтобы окно было за что ухватить.
<<<<<<< HEAD
  gtkCss = border: ''
    decoration, decoration:backdrop {
      margin: 0 ${border}px ${border}px ${border}px;
=======
  gtkCss = pkgs.writeText "nx-metacity.css" ''
    decoration, decoration:backdrop {
      margin: 0 @border@px @border@px @border@px;
>>>>>>> worktree-siemens-nx10
      box-shadow: none;
      border-radius: 0;
    }
    .titlebar, headerbar,
    .titlebar.default-decoration, headerbar.default-decoration {
      min-height: 0; padding: 0 2px; border-width: 0;
    }
    .titlebar label.title, headerbar label.title {
      font-size: 9px; padding: 0; margin: 0;
    }
    .titlebar button.titlebutton, headerbar button.titlebutton,
    .titlebar button.titlebutton image, headerbar button.titlebutton image {
      min-height: 0; min-width: 0; padding: 0; margin: 0; border-width: 0;
    }
  '';

<<<<<<< HEAD
  settings = pkgs.writeText "metacity-keyfile" ''
=======
  settings = pkgs.writeText "nx-metacity-keyfile" ''
>>>>>>> worktree-siemens-nx10
    [org/gnome/metacity]
    compositor='xrender'
    placement-mode='center'
  '';

<<<<<<< HEAD
  session = pkgs.writeShellScript "nx-session" ''
    export XDG_DATA_DIRS="${pkgs.metacity}/share:${pkgs.gsettings-desktop-schemas}/share''${XDG_DATA_DIRS:+:$XDG_DATA_DIRS}"

    # NX_FRAME_BORDER — ширина борта, за который окно тянут мышью.
    cfg=$(mktemp -d)
    mkdir -p "$cfg/glib-2.0/settings" "$cfg/gtk-3.0"
    cp ${settings} "$cfg/glib-2.0/settings/keyfile"
    cat > "$cfg/gtk-3.0/gtk.css" <<EOF
    ${gtkCss "\${NX_FRAME_BORDER:-8}"}
    EOF

    # Корневое окно иначе чёрное с мусором, и оно вспыхивает в щелях между
    # окнами при изменении размеров.
    ${pkgs.xsetroot}/bin/xsetroot -solid '#b3b3b3' || true

    # Записка наружу: дисплей каждый раз новый, а cookie во временном каталоге.
    session_file="''${XDG_RUNTIME_DIR:-/tmp}/nx-session.env"
    printf 'DISPLAY=%s\nXAUTHORITY=%s\n' "$DISPLAY" "''${XAUTHORITY:-}" > "$session_file"

    # Настройки видит только metacity, настоящий dconf не трогаем.
    GSETTINGS_BACKEND=keyfile XDG_CONFIG_HOME="$cfg" ${pkgs.metacity}/bin/metacity &
    wm_pid=$!

    # NX_DEBUG=1 — снять дерево окон, когда интерфейс уже сложится.
    dump_pid=""
    if [ -n "''${NX_DEBUG:-}" ]; then
      ( sleep 90; ${dumpWindows}/bin/nx-dump-windows ) &
      dump_pid=$!
    fi

    trap 'kill "$wm_pid" ''${dump_pid:+"$dump_pid"} 2>/dev/null || true
          rm -rf "$cfg"; rm -f "$session_file"' EXIT

    # Без exec: иначе потеряется trap и metacity останется висеть.
    ${nx}/bin/nx "$@"
  '';
in
{ inherit session dumpWindows; }
=======
  session = pkgs.writeShellApplication {
    name = "nx-session";
    runtimeInputs = with pkgs; [ coreutils gnused gnugrep xprop xsetroot metacity ];
    text = ''
      export XDG_DATA_DIRS="${pkgs.metacity}/share:${pkgs.gsettings-desktop-schemas}/share''${XDG_DATA_DIRS:+:$XDG_DATA_DIRS}"

      # NX_FRAME_BORDER — ширина борта, за который окно тянут мышью.
      border="''${NX_FRAME_BORDER:-8}"
      case "$border" in "" | *[!0-9]*) border=8 ;; esac

      # Подменный XDG_CONFIG_HOME на одну команду: настройки увидит только
      # metacity, настоящий dconf не трогаем.
      cfg=$(mktemp -d)
      mkdir -p "$cfg/glib-2.0/settings" "$cfg/gtk-3.0"
      cp ${settings} "$cfg/glib-2.0/settings/keyfile"
      sed "s/@border@/$border/g" ${gtkCss} > "$cfg/gtk-3.0/gtk.css"

      # Корневое окно иначе чёрное с мусором, и оно вспыхивает в щелях между
      # окнами при изменении размеров.
      xsetroot -solid '#b3b3b3' || true

      # Записка наружу: дисплей каждый раз новый, а cookie во временном каталоге.
      session_file="''${XDG_RUNTIME_DIR:-/tmp}/nx-session.env"
      printf 'DISPLAY=%s\nXAUTHORITY=%s\n' "$DISPLAY" "''${XAUTHORITY:-}" > "$session_file"

      GSETTINGS_BACKEND=keyfile XDG_CONFIG_HOME="$cfg" metacity &
      wm_pid=$!

      # NX_DEBUG=1 — снять дерево окон, когда интерфейс уже сложится.
      dump_pid=""
      if [ -n "''${NX_DEBUG:-}" ]; then
        ( sleep 90; ${dumpWindows}/bin/nx-dump-windows ) &
        dump_pid=$!
      fi

      # INT/TERM/HUP наравне с EXIT: по Ctrl-C bash не выполняет EXIT-ловушку,
      # и каталоги остались бы висеть.
      cleanup() {
        kill "$wm_pid" ''${dump_pid:+"$dump_pid"} 2>/dev/null || true
        rm -rf "$cfg"
        rm -f "$session_file"
      }
      trap cleanup EXIT INT TERM HUP

      # Ради metacity всё и затевалось, поэтому ждём, пока он объявит себя.
      for _ in $(seq 1 50); do
        xprop -root _NET_SUPPORTING_WM_CHECK 2>/dev/null | grep -q '0x' && break
        if ! kill -0 "$wm_pid" 2>/dev/null; then
          echo "nx-session: metacity не поднялся" >&2
          exit 1
        fi
        sleep 0.1
      done

      # Без exec: иначе потеряется ловушка и metacity останется висеть.
      ${nx}/bin/nx "$@"
    '';
  };
in
{
  inherit dumpWindows;
  session = "${session}/bin/nx-session";
}
>>>>>>> worktree-siemens-nx10
