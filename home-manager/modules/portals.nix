{ pkgs, ... }:

let
  # Урезанная версия yazi-wrapper.sh из пакета портала: пути абсолютные,
  # потому что PATH у systemd-сервиса портала может не содержать профиль.
  # Аргументы задаёт портал, порядок фиксирован (см. man 5).
  chooser = pkgs.writeShellScript "yazi-chooser" ''
    multiple="$1"; directory="$2"; save="$3"; path="$4"; out="$5"

    if [ "$directory" = "1" ]; then
      ${pkgs.foot}/bin/foot --app-id=termfilechooser --title=termfilechooser \
        ${pkgs.yazi}/bin/yazi --chooser-file="$out" --cwd-file="$out.1" "$path"
      if [ ! -s "$out" ] && [ -s "$out.1" ]; then
        cat "$out.1" > "$out"
      fi
      rm -f "$out.1"
    else
      ${pkgs.foot}/bin/foot --app-id=termfilechooser --title=termfilechooser \
        ${pkgs.yazi}/bin/yazi --chooser-file="$out" "$path"
    fi
  '';
in
{
  xdg.configFile."xdg-desktop-portal-termfilechooser/config".text = ''
    [filechooser]
    cmd=${chooser}
    default_dir=$HOME
    open_mode=suggested
    save_mode=suggested
  '';
}
