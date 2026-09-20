{ pkgs, ... }:

{
  home.packages = with pkgs; [
    antiword   # .doc  -> текст
    pandoc     # .docx -> plain/markdown/latex
    zathura    # pdf, ps, djvu, epub, cbz + картинки
  ];
}
