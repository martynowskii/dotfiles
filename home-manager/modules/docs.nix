{ pkgs, ... }:

# Чтение .doc/.docx. Форматы двух поколений, инструменты для них не
# пересекаются: .docx (OOXML) читает pandoc, .doc (OLE2) — antiword,
# который docx не понимает принципиально.
# Ассоциации и обработчик — в mime.nix.
{
  home.packages = with pkgs; [
    antiword   # .doc  -> текст
    pandoc     # .docx -> plain/markdown/latex
    zathura    # pdf, ps, djvu, epub, cbz + картинки
  ];
}
