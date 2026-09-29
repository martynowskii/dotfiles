{ ... }:

{
  programs.yazi = {
    enable = true;

    # Шаблон yazi в noctalia выключен: он правит theme.toml через sed -i и заменил
    # бы симлинк из стора обычным файлом
    flavors."noctalia" = ../../yazi/flavors/noctalia.yazi;

    theme = {
      flavor = {
        dark = "noctalia";
        light = "noctalia";
      };

      # По умолчанию тут U+E0B6/U+E0B4 — они и рисуют скругление у выбранной строки
      indicator.padding = {
        open = "";
        close = "";
      };
    };

    enableZshIntegration = false;
  };
}
