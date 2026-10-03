# Чтение документов: gdoc рендерит их в PDF и открывает в zathura,
# плюс те же конвертеры доступны как обычные команды в терминале.
{ pkgs, ... }:

let
  # Приложение живёт в apps/gdoc — там исходники, тесты и объявление
  # окружения. Здесь только подключение, как у pa9 и siemens-nx.
  gdoc = pkgs.callPackage ../../apps/gdoc { };
  gdocMimes = import ../../apps/gdoc/mimes.nix;
in
{
  home.packages = [ gdoc ] ++ (with pkgs; [
    antiword   # .doc  -> текст
    pandoc     # .docx -> plain/markdown/latex
    zathura    # pdf, ps, djvu, epub, cbz + картинки
  ]);

  xdg.desktopEntries.gdoc = {
    name = "gdoc";
    comment = "Открыть документ в zathura";
    # %F, а не %f: gdoc принимает список файлов и открывает каждый.
    exec = "${gdoc}/bin/gdoc %F";
    terminal = false;
    noDisplay = true;
    mimeType = gdocMimes;
  };
}
