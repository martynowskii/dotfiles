# Шрифты вложенного X-сервера. Возвращает кусок шелла, задающий $nx_fp.
#
# NX просит шрифты жёсткими XLFD и знает всего два семейства, поэтому вместо
# правки его файла ресурсов мы объявляем современные TTF под теми же именами
# и ставим каталог первым в пути шрифтов. Разбор — в siemens-nx-display.md.
{ lib, pkgs }:

let
  bitmaps = lib.concatStringsSep "," [
    "${pkgs.font-adobe-75dpi}/share/fonts/X11/75dpi"
    "${pkgs.font-adobe-100dpi}/share/fonts/X11/100dpi"
    "${pkgs.font-misc-misc}/share/fonts/X11/misc"
  ];

  # Нули в числовых полях XLFD — признак масштабируемого шрифта.
  fontsDir = pkgs.writeText "fonts.dir" ''
    4
    mono-bold.ttf -adobe-courier-bold-r-normal--0-0-0-0-m-0-iso8859-1
    mono.ttf -adobe-courier-medium-r-normal--0-0-0-0-m-0-iso8859-1
    sans-bold.ttf -adobe-helvetica-bold-r-normal--0-0-0-0-p-0-iso8859-1
    sans.ttf -adobe-helvetica-medium-r-normal--0-0-0-0-p-0-iso8859-1
  '';

  mkSet = name: { sans, sansBold, mono, monoBold }:
    pkgs.runCommand "nx-fonts-${name}" { } ''
      dir="$out/share/fonts/nx"
      install -Dm444 ${fontsDir} "$dir/fonts.dir"
      ln -s ${sans}     "$dir/sans.ttf"
      ln -s ${sansBold} "$dir/sans-bold.ttf"
      ln -s ${mono}     "$dir/mono.ttf"
      ln -s ${monoBold} "$dir/mono-bold.ttf"
    '';

  liberation = "${pkgs.liberation_ttf}/share/fonts/truetype";
  dejavu = "${pkgs.dejavu_fonts}/share/fonts/truetype";
  noto = "${pkgs.noto-fonts}/share/fonts/noto";

  sets = {
    # По умолчанию: метрически совместим с Helvetica, которую NX и просит.
    liberation = mkSet "liberation" {
      sans = "${liberation}/LiberationSans-Regular.ttf";
      sansBold = "${liberation}/LiberationSans-Bold.ttf";
      mono = "${liberation}/LiberationMono-Regular.ttf";
      monoBold = "${liberation}/LiberationMono-Bold.ttf";
    };

    # Заметно отличается от Helvetica — годится как проверка, что подмена
    # вообще доходит до NX.
    dejavu = mkSet "dejavu" {
      sans = "${dejavu}/DejaVuSans.ttf";
      sansBold = "${dejavu}/DejaVuSans-Bold.ttf";
      mono = "${dejavu}/DejaVuSansMono.ttf";
      monoBold = "${dejavu}/DejaVuSansMono-Bold.ttf";
    };

    # Системный по умолчанию. Файл вариативный, и жирный из него X-сервер не
    # достаёт — начертания совпадут.
    noto = mkSet "noto" {
      sans = "${noto}/NotoSans.ttf";
      sansBold = "${noto}/NotoSans.ttf";
      mono = "${noto}/NotoSansMono.ttf";
      monoBold = "${noto}/NotoSansMono.ttf";
    };
  };

  path = set: "${set}/share/fonts/nx,${bitmaps}";
in
''
  case "''${NX_FONTS:-liberation}" in
    original) nx_fp=${bitmaps} ;;
    dejavu)   nx_fp=${path sets.dejavu} ;;
    noto)     nx_fp=${path sets.noto} ;;
    *)        nx_fp=${path sets.liberation} ;;
  esac
''
