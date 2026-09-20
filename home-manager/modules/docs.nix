{ lib, pkgs, ... }:

# Чтение .doc/.docx из ~/Documents/univer/practice/docs.
# Форматы двух поколений, инструменты для них не пересекаются:
# .docx (OOXML) читает pandoc, .doc (OLE2) — antiword, который docx
# не понимает принципиально. Вёрстку показывает zathura.
{
  home.packages = with pkgs; [
    antiword   # .doc -> текст и PostScript
    pandoc     # .docx -> plain/markdown/latex
    zathura    # pdf, ps, djvu, epub, cbz + картинки
  ];

  # .doc/.docx здесь намеренно нет: GUI-приложения для них в системе
  # не стоит, а zathura эти форматы не открывает. Для них — функция doc.
  xdg.mimeApps.defaultApplications = {
    "application/pdf" = "org.pwmt.zathura.desktop";
    "application/postscript" = "org.pwmt.zathura.desktop";
    "application/epub+zip" = "org.pwmt.zathura.desktop";
    "image/vnd.djvu" = "org.pwmt.zathura.desktop";
  };

  # doc file     — текст в пейджер (docx через pandoc, doc через antiword)
  # doc -v file  — вёрстка .doc в zathura через PostScript.
  # Кодировка у antiword задаётся отдельно для каждого режима вывода:
  # UTF-8.txt для текста, 8859-5.txt для PostScript — комбинацию PS+UTF-8
  # он отвергает явной ошибкой, а PDF с кириллицей не умеет вовсе,
  # поэтому путь к вёрстке идёт через .ps, который zathura открывает сама.
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
