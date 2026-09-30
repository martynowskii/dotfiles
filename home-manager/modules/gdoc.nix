{ pkgs, ... }:

let
  # Ни один из конвертеров не тянет за собой офисный пакет: вместе они
  # весят ~90 МБ против 1.6 ГБ у libreoffice.
  #
  # pandoc    — .docx/.odt/.rtf/.md, формулы уезжают в MathML
  # wv        — структура старого .doc; картинки из него достаёт сам gdoc.py
  # gnumeric  — ssconvert для .xls/.xlsx/.ods/.csv
  # catdoc    — остатки текста из бинарного .ppt
  # antiword  — запасной путь для .doc, если wvHtml споткнулся
  #
  # Промежуточный HTML печатает в PDF headless-chromium: он умеет MathML,
  # так что отдельный html2pdf-движок не нужен. Пути до всего прибиты к
  # store — иначе gdoc ломался бы в рантайме, стоит убрать пакет из профиля,
  # и nix об этом не сказал бы ни слова. Замыкание от этого не растёт:
  # chromium и zathura те же самые, что уже ставят home.nix и docs.nix.
  gdoc = pkgs.writeShellScriptBin "gdoc" ''
    export GDOC_PANDOC=${pkgs.pandoc}/bin/pandoc
    export GDOC_WVHTML=${pkgs.wv}/bin/wvHtml
    export GDOC_SSCONVERT=${pkgs.gnumeric}/bin/ssconvert
    export GDOC_CATPPT=${pkgs.catdoc}/bin/catppt
    export GDOC_ANTIWORD=${pkgs.antiword}/bin/antiword
    export GDOC_CHROMIUM=''${GDOC_CHROMIUM:-${pkgs.chromium}/bin/chromium}
    export GDOC_BROWSER=''${GDOC_BROWSER:-${pkgs.chromium}/bin/chromium}
    export GDOC_VIEWER=''${GDOC_VIEWER:-${pkgs.zathura}/bin/zathura}
    exec ${pkgs.python3}/bin/python3 ${../gdoc/gdoc.py} "$@"
  '';

  documentMimes = import ./gdoc-mimes.nix;
in
{
  home.packages = [ gdoc ];

  xdg.desktopEntries.gdoc = {
    name = "gdoc";
    comment = "Открыть документ в zathura";
    # %F, а не %f: gdoc принимает список файлов и открывает каждый.
    exec = "${gdoc}/bin/gdoc %F";
    terminal = false;
    noDisplay = true;
    mimeType = documentMimes;
  };
}
