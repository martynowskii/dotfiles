{ pkgs, ... }:

let
  # footclient, а не foot: сервер уже запущен (programs.foot.server).
  # Без --no-wait клиент ждёт закрытия окна — чузеру это обязательно.
  term = "${pkgs.foot}/bin/footclient";
  yazi = "${pkgs.yazi}/bin/yazi";

  # Урезанная версия yazi-wrapper.sh из пакета портала: пути абсолютные,
  # потому что PATH у systemd-сервиса портала может не содержать профиль.
  # Аргументы задаёт портал, порядок фиксирован (см. man 5).
  chooser = pkgs.writeShellScript "yazi-chooser" ''
    multiple="$1"; directory="$2"; save="$3"; path="$4"; out="$5"

    if [ "$directory" = "1" ]; then
      ${term} --title=termfilechooser \
        ${yazi} --chooser-file="$out" --cwd-file="$out.1" "$path"
      if [ ! -s "$out" ] && [ -s "$out.1" ]; then
        cat "$out.1" > "$out"
      fi
      rm -f "$out.1"
    else
      ${term} --title=termfilechooser \
        ${yazi} --chooser-file="$out" "$path"
    fi
  '';

  # "Показать в папке" приложения зовут через этот интерфейс. Реализации
  # в системе нет (файлового менеджера с D-Bus тоже), поэтому своя.
  # E501 отключён: пути в /nix/store длиннее лимита flake8.
  showInFolder = pkgs.writers.writePython3Bin "yazi-filemanager1"
    {
      libraries = with pkgs.python3Packages; [ pydbus pygobject3 ];
      flakeIgnore = [ "E501" ];
    } ''
    import subprocess
    from urllib.parse import unquote, urlparse

    from gi.repository import GLib
    from pydbus import SessionBus


    def to_path(uri):
        parsed = urlparse(uri)
        if parsed.scheme in ("", "file"):
            return unquote(parsed.path)
        return None


    def show(uris):
        targets = [p for p in (to_path(u) for u in uris) if p]
        if targets:
            subprocess.Popen(["${term}", "--title=yazi", "${yazi}", targets[0]])


    class FileManager1:
        """
        <node>
          <interface name="org.freedesktop.FileManager1">
            <method name="ShowFolders">
              <arg type="as" name="URIs" direction="in"/>
              <arg type="s" name="StartupId" direction="in"/>
            </method>
            <method name="ShowItems">
              <arg type="as" name="URIs" direction="in"/>
              <arg type="s" name="StartupId" direction="in"/>
            </method>
            <method name="ShowItemProperties">
              <arg type="as" name="URIs" direction="in"/>
              <arg type="s" name="StartupId" direction="in"/>
            </method>
          </interface>
        </node>
        """

        def ShowFolders(self, uris, startup_id):
            show(uris)

        def ShowItems(self, uris, startup_id):
            show(uris)

        def ShowItemProperties(self, uris, startup_id):
            show(uris)


    SessionBus().publish("org.freedesktop.FileManager1", FileManager1())
    GLib.MainLoop().run()
  '';
in
{
  home.packages = [ showInFolder ];

  xdg.configFile."xdg-desktop-portal-termfilechooser/config".text = ''
    [filechooser]
    cmd=${chooser}
    default_dir=$HOME
    open_mode=suggested
    save_mode=suggested
  '';

  # Это же имя регистрирует nautilus (его .service лежит внутри пакета,
  # а пакет приходит в систему транзитивно). Файл в XDG_DATA_HOME имеет
  # приоритет над системным, поэтому активируется yazi. Отобрать имя у
  # уже запущенного nautilus нельзя — он берёт его без права замены.
  xdg.dataFile."dbus-1/services/org.freedesktop.FileManager1.service".text = ''
    [D-BUS Service]
    Name=org.freedesktop.FileManager1
    Exec=${showInFolder}/bin/yazi-filemanager1
  '';
}
