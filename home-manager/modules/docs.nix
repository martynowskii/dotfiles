# Чтение документов: gdoc рендерит их в PDF и открывает в zathura,
# плюс те же конвертеры доступны как обычные команды в терминале.
{ pkgs, ... }:

{
  # Приложение живёт в apps/gdoc — там исходники, тесты, объявление
  # окружения и своя .desktop-запись. Здесь только подключение, как у
  # pa9 и siemens-nx. Какой программой открывать .docx на этой машине
  # решает mime.nix: это уже не свойство gdoc.
  home.packages = with pkgs; [
    (callPackage ../../apps/gdoc { })
    antiword   # .doc  -> текст
    pandoc     # .docx -> plain/markdown/latex
    zathura    # pdf, ps, djvu, epub, cbz + картинки
  ];
}
