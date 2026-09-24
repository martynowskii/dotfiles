{ config, lib, pkgs, ... }:

# Siemens NX 10 во вложенном Weston.
#
# NX рисует меню так же, как это делали Motif-приложения девяностых: отдельным
# окном типа override-redirect, выставленным по абсолютным координатам в обход
# оконного менеджера, плюс активный grab указателя и клавиатуры. На этом пути
# xwayland-satellite спотыкается — меню не разворачиваются. Ровно та же беда
# была с AWT в ПА9.
#
# У Weston XWayland встроенный и полноценный, с настоящим X-оконным менеджером,
# поэтому NX запускаем внутри вложенного Weston, а не в XWayland самого niri.
# Обычный `nx` при этом никуда не девается — если меню вдруг заработают под
# xwayland-satellite, обёртка просто перестанет быть нужной.

let
  nx-weston = pkgs.writeShellApplication {
    name = "nx-weston";
    runtimeInputs = with pkgs; [ weston coreutils findutils ];
    text = ''
      # NX родом из 2014 года и про HiDPI не знает: он рисует в физических
      # пикселях, и на экране с масштабом 1.75 интерфейс выходит примерно
      # вдвое мельче нужного. Лечится масштабом вложенного Weston — он
      # увеличивает уже готовую картинку.
      #
      # Почему 2, а не 1.75: scale в wl_output — целое число (int32),
      # дробное масштабирование живёт в отдельном протоколе, которого у
      # Weston тут нет. Так что доступны только 1, 2, 3; 2 ближе всего.
      # Чуть крупнее родного и слегка мягче по краям — это плата за то,
      # что приложение масштабироваться само не умеет.
      #
      # NX_WESTON_SCALE=1 возвращает прежнее поведение (пиксель в пиксель).
      : "''${NX_WESTON_SCALE:=2}"
      : "''${NX_WESTON_ARGS:=--fullscreen}"

      if ! command -v nx >/dev/null 2>&1; then
        echo "nx-weston: команда nx не найдена в PATH." >&2
        echo "Собери и установи пакет из ~/Documents/univer/Siemens/nix-nx" >&2
        echo "(см. README.md в том каталоге)." >&2
        exit 1
      fi

      x_sockets() {
        find /tmp/.X11-unix -maxdepth 1 -name 'X*' -printf '%f\n' 2>/dev/null | sort
      }

      before=$(x_sockets)

      # shellcheck disable=SC2086
      weston --backend=wayland --xwayland --scale="$NX_WESTON_SCALE" $NX_WESTON_ARGS &
      weston_pid=$!
      trap 'kill "$weston_pid" 2>/dev/null || true' EXIT

      # Weston поднимает собственный XWayland и создаёт новый сокет в
      # /tmp/.X11-unix. Полагаться на то, что DISPLAY унаследуется, нельзя —
      # там гонка, поэтому просто ждём появления нового сокета.
      display=""
      for _ in $(seq 1 100); do
        if ! kill -0 "$weston_pid" 2>/dev/null; then
          echo "nx-weston: Weston завершился, не дождавшись XWayland." >&2
          exit 1
        fi
        new=$(comm -13 <(printf '%s\n' "$before") <(x_sockets) | head -n1)
        if [ -n "$new" ]; then
          display=":''${new#X}"
          break
        fi
        sleep 0.1
      done

      if [ -z "$display" ]; then
        echo "nx-weston: XWayland внутри Weston не появился за 10 секунд." >&2
        exit 1
      fi

      export DISPLAY="$display"
      nx "$@"
    '';
  };

  # Пункт в лаунчере. Сам пакет NX ставит свой — "Siemens NX 10.0.3",
  # который зовёт голый nx через xwayland-satellite. Этот запускает через
  # Weston, поэтому назван отдельно: в списке будут оба, и видно, что берёшь.
  nx-weston-desktop = pkgs.makeDesktopItem {
    name = "nx-weston";
    desktopName = "Siemens NX (Weston)";
    comment = "NX во вложенном Weston — корректно работают меню";
    exec = "nx-weston %f";
    # Имя иконки, а не путь: файл ставит сам пакет NX в share/pixmaps,
    # оба ярлыка ссылаются на одно и то же изображение.
    icon = "siemens-nx";
    categories = [ "Graphics" "Science" "Engineering" ];
    terminal = false;
  };
in
{
  home.packages = [ nx-weston nx-weston-desktop ];
}
