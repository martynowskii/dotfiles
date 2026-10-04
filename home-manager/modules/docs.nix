# Чтение документов: gdoc рендерит их в PDF и открывает в zathura,
# плюс те же конвертеры доступны как обычные команды в терминале.
{ pkgs, ... }:

{
  # Сами приложения собираются в apps/, здесь только подключение — как у
  # pa9 и siemens-nx. Чем открывать .docx по двойному щелчку, решает
  # mime.nix: это свойство машины, а не программы.
  home.packages = with pkgs; [
    (callPackage ../../apps/gdoc { })
    (callPackage ../../apps/zaread { })
    antiword   # .doc  -> текст
    pandoc     # .docx -> plain/markdown/latex
    zathura    # pdf, ps, djvu, epub, cbz + картинки
  ];
}
