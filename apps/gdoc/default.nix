# gdoc — открыть .doc/.docx/.odt/.rtf/.xls/.ppt/.md в zathura: документ
# рендерится в PDF локально, без офисного пакета и без выгрузки куда-либо.
#
# Пакет самостоятельный: все внешние программы объявлены аргументами, так
# что подключается он одним callPackage из любой конфигурации — хоть
# home-manager, хоть nixos. Рядом mimes.nix (типы для .desktop), tests/ и
# README.md.
#
# Ни один из конвертеров не тянет за собой офисный пакет: вместе они
# весят ~90 МБ против 1.6 ГБ у libreoffice.
#
#   pandoc    — .docx/.odt/.rtf/.md, формулы уезжают в MathML
#   wv        — структура старого .doc; картинки из него достаёт сам gdoc
#   gnumeric  — ssconvert для .xls/.xlsx/.ods/.csv
#   catdoc    — остатки текста из бинарного .ppt
#   antiword  — запасной путь для .doc, если wvHtml споткнулся
#   typst     — markdown печатает он: формулы набраны по-настоящему, а не
#               MathML'ем браузера, где радикал наезжает на дробь
#
# Промежуточный HTML печатает в PDF headless-chromium: он умеет MathML,
# так что отдельный html2pdf-движок не нужен. Пути до всего прибиты к
# store — иначе gdoc ломался бы в рантайме, стоит убрать пакет из профиля,
# и nix об этом не сказал бы ни слова.
{ lib
, writeShellScriptBin
, writeTextFile
, symlinkJoin
, python3
, pandoc
, wv
, gnumeric
, catdoc
, antiword
, chromium
, typst
, dejavu_fonts
, zathura
}:

let
  # Только .py верхнего уровня: tests/ и .nix в замыкание не идут. Это не
  # экономия, а корректность — отпечаток кэша считается по исходникам, и
  # правка теста иначе обесценивала бы собранные PDF.
  sources = lib.cleanSourceWith {
    name = "gdoc-src";
    src = ./.;
    filter = path: type: type == "regular" && lib.hasSuffix ".py" path;
  };
  gdoc = writeShellScriptBin "gdoc" ''
    export GDOC_PANDOC=${pandoc}/bin/pandoc
    export GDOC_WVHTML=${wv}/bin/wvHtml
    export GDOC_SSCONVERT=${gnumeric}/bin/ssconvert
    export GDOC_CATPPT=${catdoc}/bin/catppt
    export GDOC_ANTIWORD=${antiword}/bin/antiword
    export GDOC_TYPST=${typst}/bin/typst
    # Шрифты тоже из store: со шрифтами машины один и тот же markdown
    # печатался бы по-разному, а моноширинный без кириллицы молча подменялся
    # засечным. Засечный у typst свой, встроенный, — тут только моно и санс.
    export GDOC_TYPST_FONTS=${dejavu_fonts}/share/fonts
    export GDOC_CHROMIUM=''${GDOC_CHROMIUM:-${chromium}/bin/chromium}
    export GDOC_BROWSER=''${GDOC_BROWSER:-${chromium}/bin/chromium}
    export GDOC_VIEWER=''${GDOC_VIEWER:-${zathura}/bin/zathura}
    exec ${python3}/bin/python3 ${sources}/gdoc.py "$@"
  '';

  # Без .desktop двойной щелчок по документу до gdoc не доходит: ассоциация
  # типов умеет ссылаться только на такую запись, а не на программу. Лежит
  # она в самом пакете, а не в конфигурации home-manager, потому что
  # описывает gdoc, а не машину: из профиля её подхватит любой XDG_DATA_DIRS,
  # хоть через home.packages, хоть через environment.systemPackages.
  #
  # Чего тут нет — какой программой открывать .docx на этой машине: это
  # как раз решение машины, и живёт оно в mime.nix.
  desktop = writeTextFile {
    name = "gdoc-desktop";
    destination = "/share/applications/gdoc.desktop";
    text = ''
      [Desktop Entry]
      Type=Application
      Name=gdoc
      Comment=Открыть документ в zathura
      # %F, а не %f: gdoc принимает список файлов и открывает каждый.
      Exec=${gdoc}/bin/gdoc %F
      Terminal=false
      # Запускать gdoc без файла нечего, в меню приложений он лишний.
      NoDisplay=true
      MimeType=${lib.concatMapStrings (m: m + ";") (import ./mimes.nix)}
    '';
  };
in
symlinkJoin {
  name = "gdoc";
  paths = [ gdoc desktop ];
  meta.mainProgram = "gdoc";
}
