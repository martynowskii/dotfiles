# Что происходит внутри вложенного дисплея: оконный менеджер и сам NX.
#
# Metacity не вкусовщина — NX сверяет _NET_WM_NAME со списком из трёх имён,
# зашитым в libugii.so. Настройки его рамок подобраны замерами, см.
# siemens-nx-display.md.
{ pkgs, nx }:

let
  dumpWindows = pkgs.writeShellApplication {
    name = "nx-dump-windows";
    runtimeInputs = with pkgs; [ xwininfo xprop xdpyinfo coreutils gnugrep ];
    text = ''
      out="''${1:-$HOME/nx-windows.txt}"
      session="''${XDG_RUNTIME_DIR:-/tmp}/nx-session.env"

      # Позвали снаружи — берём дисплей и cookie из записки, которую оставил
      # nx-session.
      if [ -z "''${DISPLAY:-}" ] && [ -r "$session" ]; then
        # shellcheck source=/dev/null
        . "$session"
        export DISPLAY XAUTHORITY
      fi

      if [ -z "''${DISPLAY:-}" ]; then
        echo "nx-dump-windows: NX не запущен, нет $session" >&2
        exit 1
      fi

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
          echo
        done
      } > "$out" 2>&1

      echo "nx-dump-windows: записано в $out" >&2
    '';
  };

  # Композитор включён, но его тень убрана: без композитора окна мелькают при
  # изменении размера, а тень добавляла к рамке 26 пикселей и разносила
  # раскладку NX. Борт по бокам и снизу — чтобы окно было за что ухватить.
  gtkCss = border: ''
    decoration, decoration:backdrop {
      margin: 0 ${border}px ${border}px ${border}px;
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

  settings = pkgs.writeText "metacity-keyfile" ''
    [org/gnome/metacity]
    compositor='xrender'
    placement-mode='center'
  '';

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
