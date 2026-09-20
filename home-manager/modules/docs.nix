{ pkgs, ... }:

# Чтение .doc/.docx. Форматы двух поколений, инструменты для них не
# пересекаются: .docx (OOXML) читает pandoc, .doc (OLE2) — antiword,
# который docx не понимает принципиально. Вёрстку показывает zathura.
# Ассоциации и функция doc — в mime.nix.
{
  home.packages = with pkgs; [
    antiword   # .doc -> текст и PostScript
    pandoc     # .docx -> plain/markdown/latex
    zathura    # pdf, ps, djvu, epub, cbz + картинки
  ];
}
