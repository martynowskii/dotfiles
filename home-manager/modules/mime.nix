{ pkgs, ... }:

let
  # Для .doc/.docx нет GUI-приложения, а xdg-open требует .desktop.
  # Пути абсолютные: в окружении xdg-open может не быть ~/.nix-profile/bin.
  # antiword без -m UTF-8.txt выдаёт кракозябры.
  docReader = pkgs.writeShellScriptBin "doc-reader" ''
    f=''${1:-}
    if [ ! -r "$f" ]; then
      printf 'не читается: %s\n' "$f" >&2
      read -r _
      exit 1
    fi
    case "$f" in
      *.docx) ${pkgs.pandoc}/bin/pandoc -t plain -- "$f" ;;
      *.doc)  ${pkgs.antiword}/bin/antiword -m UTF-8.txt -- "$f" ;;
      *)      printf 'не .doc/.docx: %s\n' "$f" >&2; read -r _; exit 1 ;;
    esac | ${pkgs.less}/bin/less
  '';
in
{
  home.packages = [ docReader ];

  xdg.desktopEntries.doc-reader = {
    name = "Doc reader";
    comment = "Читать .doc и .docx в пейджере";
    exec = "${pkgs.foot}/bin/foot ${docReader}/bin/doc-reader %f";
    terminal = false;
    noDisplay = true;
    mimeType = [
      "application/msword"
      "application/vnd.openxmlformats-officedocument.wordprocessingml.document"
    ];
  };

  # enable делает mimeapps.list симлинком в стор: прежние записи
  # перенесены сюда, сами приложения себя больше не пропишут.
  xdg.mimeApps = {
    enable = true;

    defaultApplications = {
      "application/pdf" = "org.pwmt.zathura.desktop";
      "application/postscript" = "org.pwmt.zathura.desktop";
      "application/epub+zip" = "org.pwmt.zathura.desktop";
      "image/vnd.djvu" = "org.pwmt.zathura.desktop";

      "application/msword" = "doc-reader.desktop";
      "application/vnd.openxmlformats-officedocument.wordprocessingml.document" =
        "doc-reader.desktop";

      "x-scheme-handler/tg" = "org.telegram.desktop.desktop";
      "x-scheme-handler/tonsite" = "org.telegram.desktop.desktop";
      "x-scheme-handler/mailto" = "chromium-browser.desktop";
      "x-scheme-handler/claude-cli" = "claude-code-url-handler.desktop";
    };

    associations.added = {
      "x-scheme-handler/tg" = "org.telegram.desktop.desktop";
      "x-scheme-handler/tonsite" = "org.telegram.desktop.desktop";
    };
  };
}
