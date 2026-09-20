{ pkgs, ... }:

# Чем открываются файлы. mimeapps.list становится симлинком в стор,
# поэтому прежние записи, которые раньше правились вручную и
# приложениями, перенесены сюда — иначе они потерялись бы при первом
# переключении. Следствие: файл read-only и приложения больше не
# пропишут себя сами.

let
  # Обработчик для .doc/.docx: графического приложения для них нет,
  # но xdg-open требует .desktop, поэтому читалка оформлена как
  # приложение. Пути к pandoc и antiword абсолютные: окружение при
  # запуске через xdg-open может не содержать ~/.nix-profile/bin.
  # Кодировку antiword сам не угадывает, без -m UTF-8.txt выдаёт
  # кракозябры.
  docReader = pkgs.writeShellScriptBin "doc-reader" ''
    f=''${1:-}
    if [ ! -r "$f" ]; then
      printf 'не читается: %s\n' "$f" >&2
      read -r _
      exit 1
    fi
    case "$f" in
      *.docx) ${pkgs.pandoc}/bin/pandoc -t plain -- "$f" ;;
      *.doc)  ${pkgs.antiword}/bin/antiword -m UTF-8.txt -- "$f" ;;
      *)      printf 'не .doc/.docx: %s\n' "$f" >&2; read -r _; exit 1 ;;
    esac | ${pkgs.less}/bin/less
  '';
in
{
  home.packages = [ docReader ];

  # Открывается в отдельном окне foot: xdg-open не умеет отдавать
  # вывод в текущий терминал.
  xdg.desktopEntries.doc-reader = {
    name = "Doc reader";
    comment = "Читать .doc и .docx в пейджере";
    exec = "${pkgs.foot}/bin/foot ${docReader}/bin/doc-reader %f";
    terminal = false;
    noDisplay = true;
    mimeType = [
      "application/msword"
      "application/vnd.openxmlformats-officedocument.wordprocessingml.document"
    ];
  };

  xdg.mimeApps = {
    enable = true;

    defaultApplications = {
      # Документы — всё, что умеет zathura с текущим набором плагинов.
      "application/pdf" = "org.pwmt.zathura.desktop";
      "application/postscript" = "org.pwmt.zathura.desktop";
      "application/epub+zip" = "org.pwmt.zathura.desktop";
      "image/vnd.djvu" = "org.pwmt.zathura.desktop";

      # zathura эти два формата не открывает — отдаём читалке выше.
      "application/msword" = "doc-reader.desktop";
      "application/vnd.openxmlformats-officedocument.wordprocessingml.document" =
        "doc-reader.desktop";

      "x-scheme-handler/tg" = "org.telegram.desktop.desktop";
      "x-scheme-handler/tonsite" = "org.telegram.desktop.desktop";
      "x-scheme-handler/mailto" = "chromium-browser.desktop";
      "x-scheme-handler/claude-cli" = "claude-code-url-handler.desktop";
    };

    associations.added = {
      "x-scheme-handler/tg" = "org.telegram.desktop.desktop";
      "x-scheme-handler/tonsite" = "org.telegram.desktop.desktop";
    };
  };
}
