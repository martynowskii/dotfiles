{ pkgs, ... }:

let
  # Ни один из конвертеров не тянет за собой офисный пакет: вместе они
  # весят ~90 МБ против 1.6 ГБ у libreoffice.
  #
  # pandoc    — .docx/.odt/.rtf, формулы уезжают в MathML
  # wv        — структура старого .doc; картинки из него достаёт сам gdoc.py
  # gnumeric  — ssconvert для .xls/.xlsx/.ods/.csv
  # catdoc    — остатки текста из бинарного .ppt
  # antiword  — запасной путь для .doc, если wvHtml споткнулся
  #
  # Промежуточный HTML печатается в PDF headless-хромиумом: он уже стоит
  # системным пакетом и умеет MathML, так что отдельный движок не нужен.
  gdoc = pkgs.writeShellScriptBin "gdoc" ''
    export GDOC_PANDOC=${pkgs.pandoc}/bin/pandoc
    export GDOC_WVHTML=${pkgs.wv}/bin/wvHtml
    export GDOC_SSCONVERT=${pkgs.gnumeric}/bin/ssconvert
    export GDOC_CATPPT=${pkgs.catdoc}/bin/catppt
    export GDOC_ANTIWORD=${pkgs.antiword}/bin/antiword
    export GDOC_VIEWER=''${GDOC_VIEWER:-${pkgs.zathura}/bin/zathura}
    # Запуск из .desktop идёт с урезанным PATH, а chromium берётся из профиля.
    export PATH="$HOME/.nix-profile/bin:/run/current-system/sw/bin:$PATH"
    exec ${pkgs.python3}/bin/python3 ${../gdoc/gdoc.py} "$@"
  '';

  documentMimes = [
    "application/msword"
    "application/vnd.openxmlformats-officedocument.wordprocessingml.document"
    "application/vnd.oasis.opendocument.text"
    "application/rtf"
    "application/vnd.ms-excel"
    "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"
    "application/vnd.oasis.opendocument.spreadsheet"
    "application/vnd.ms-powerpoint"
    "application/vnd.openxmlformats-officedocument.presentationml.presentation"
    "text/csv"
  ];
in
{
  home.packages = [ gdoc ];

  # Сами соответствия mime -> gdoc.desktop живут в mime.nix, чтобы вся
  # маршрутизация открытия файлов оставалась в одном месте.
  xdg.desktopEntries.gdoc = {
    name = "gdoc";
    comment = "Открыть документ в zathura";
    exec = "${gdoc}/bin/gdoc %f";
    terminal = false;
    noDisplay = true;
    mimeType = documentMimes;
  };
}
