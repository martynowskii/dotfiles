{ pkgs, ... }:

# Всё, что относится к Siemens NX 10: сервер лицензий, сам NX и обёртка для
# запуска во вложенном Weston.
#
# Сами пакеты живут отдельно, в ~/Documents/univer/Siemens — здесь только их
# подключение к системе. Каталог вне git и вне /nix/store намеренно: рядом с
# исходниками лежит ~13 ГБ носителя, которому в репозитории делать нечего.

let
  # Путь именно как path, а не строка. "${siemensDir}" скопировал бы весь
  # каталог вместе с носителем в /nix/store — те самые 13 ГБ.
  siemensDir = /home/arthr/Documents/univer/Siemens;

  nx = pkgs.callPackage (siemensDir + "/nix-nx") {
    licenseServer = "28000@localhost";   # тот же хост, где включён splmLicenseServer ниже
  };

  # NX рисует меню так же, как Motif-приложения девяностых: отдельным окном
  # override-redirect по абсолютным координатам, в обход оконного менеджера,
  # плюс активный grab указателя и клавиатуры. xwayland-satellite на этом
  # спотыкается — меню не разворачиваются (ровно как было с AWT в ПА9).
  # У Weston XWayland встроенный и полноценный, с настоящим X-оконным
  # менеджером, поэтому проблемные случаи запускаем во вложенном Weston.
  # Обычный `nx` при этом никуда не девается.
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
      # Weston тут нет. Доступны только 1, 2, 3; 2 ближе всего. Чуть крупнее
      # родного и слегка мягче по краям — плата за то, что приложение
      # масштабироваться само не умеет.
      #
      # NX_WESTON_SCALE=1 возвращает поведение «пиксель в пиксель».
      : "''${NX_WESTON_SCALE:=2}"
      : "''${NX_WESTON_ARGS:=--fullscreen}"

      if ! command -v nx >/dev/null 2>&1; then
        echo "nx-weston: команда nx не найдена в PATH." >&2
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

  # Отдельный пункт в лаунчере. Свой — "Siemens NX 10.0.3" — ставит сам пакет
  # NX, он зовёт голый nx через XWayland самого niri. В списке будут оба, и по
  # названию видно, что берёшь. Иконка общая: здесь имя, а не путь; файл
  # кладёт пакет NX в share/pixmaps.
  nx-weston-desktop = pkgs.makeDesktopItem {
    name = "nx-weston";
    desktopName = "Siemens NX (Weston)";
    comment = "NX во вложенном Weston — корректно работают меню";
    exec = "nx-weston %f";
    icon = "siemens-nx";
    categories = [ "Graphics" "Science" "Engineering" ];
    terminal = false;
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
    nx
    nx-weston
    nx-weston-desktop
  ];
}
