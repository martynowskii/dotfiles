{ lib, ... }:

# Чем и как открываются файлы: ассоциации для xdg-open (за ним же
# закреплён alias open из zsh.nix) и функция doc для форматов, у
# которых GUI-обработчика нет.
#
# mimeapps.list становится симлинком в стор, поэтому прежние записи,
# которые раньше правились вручную и приложениями, перенесены сюда —
# иначе они потерялись бы при первом переключении. Следствие: файл
# read-only и приложения больше не пропишут себя сами.
{
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

  # doc file     — текст в пейджер (docx через pandoc, doc через antiword)
  # doc -v file  — вёрстка .doc в zathura через PostScript.
  # Кодировка у antiword задаётся отдельно для каждого режима вывода:
  # UTF-8.txt для текста, 8859-5.txt для PostScript — комбинацию PS+UTF-8
  # он отвергает явной ошибкой, а PDF с кириллицей не умеет вовсе,
  # поэтому путь к вёрстке идёт через .ps, который zathura открывает сама.
  # Сами pandoc, antiword и zathura ставит docs.nix.
  programs.zsh.initContent = lib.mkAfter ''
    doc() {
      emulate -L zsh
      local visual=0
      [[ $1 == -v ]] && { visual=1; shift; }
      local f=$1
      [[ -r $f ]] || { print -u2 "doc: не читается: $f"; return 1 }

      if (( visual )); then
        case $f in
          *.doc)
            local ps=$(mktemp --suffix=.ps)
            antiword -p a4 -m 8859-5.txt -- "$f" > $ps && zathura $ps
            rm -f $ps ;;
          *.pdf|*.ps|*.djvu|*.epub) zathura "$f" ;;
          *) print -u2 "doc -v: только .doc (docx — конвертируй в pdf)"; return 1 ;;
        esac
      else
        case $f in
          *.docx) pandoc -t plain -- "$f" | ''${=PAGER:-less} ;;
          *.doc)  antiword -m UTF-8.txt -- "$f" | ''${=PAGER:-less} ;;
          *) print -u2 "doc: не .doc/.docx: $f"; return 1 ;;
        esac
      fi
    }
  '';
}
