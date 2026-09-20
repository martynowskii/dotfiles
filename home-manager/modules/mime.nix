{ lib, pkgs, ... }:

# Всё про открытие файлов: чем открывать, что с чем связано и как
# читать форматы, которым графического обработчика не нашлось.
#
# mimeapps.list становится симлинком в стор, поэтому прежние записи,
# которые раньше правились вручную и приложениями, перенесены сюда —
# иначе они потерялись бы при первом переключении. Следствие: файл
# read-only и приложения больше не пропишут себя сами.
{
  # .doc (OLE2) и .docx (OOXML) — форматы двух поколений, инструменты
  # для них не пересекаются: docx читает pandoc, doc — antiword,
  # который docx не понимает принципиально.
  home.packages = with pkgs; [
    antiword   # .doc  -> текст
    pandoc     # .docx -> plain/markdown/latex
    zathura    # pdf, ps, djvu, epub, cbz + картинки
  ];

  xdg.mimeApps = {
    enable = true;

    defaultApplications = {
      # Документы — всё, что умеет zathura с текущим набором плагинов.
      # .doc и .docx сюда не попадают: GUI-приложения для них в системе
      # нет, zathura эти форматы не открывает. Для них — функция doc.
      "application/pdf" = "org.pwmt.zathura.desktop";
      "application/postscript" = "org.pwmt.zathura.desktop";
      "application/epub+zip" = "org.pwmt.zathura.desktop";
      "image/vnd.djvu" = "org.pwmt.zathura.desktop";

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

  # doc file — прочитать .doc/.docx в пейджере. Кодировку antiword сам
  # не угадывает, без -m UTF-8.txt выдаёт кракозябры. Для pdf и прочего,
  # что открывается графически, есть alias open и ассоциации выше.
  programs.zsh.initContent = lib.mkAfter ''
    doc() {
      emulate -L zsh
      local f=$1
      [[ -r $f ]] || { print -u2 "doc: не читается: $f"; return 1 }

      case $f in
        *.docx) pandoc -t plain -- "$f" | ''${=PAGER:-less} ;;
        *.doc)  antiword -m UTF-8.txt -- "$f" | ''${=PAGER:-less} ;;
        *) print -u2 "doc: не .doc/.docx: $f"; return 1 ;;
      esac
    }
  '';
}
