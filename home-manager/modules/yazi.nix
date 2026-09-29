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

      # Везде ниже по умолчанию U+E0B6/U+E0B4 — они и рисуют скругления
      indicator.padding = {
        open = "";
        close = "";
      };

      status = {
        sep_left = {
          open = "";
          close = "";
        };
        sep_right = {
          open = "";
          close = "";
        };
      };

      tabs = {
        sep_inner = {
          open = "";
          close = "";
        };
        sep_outer = {
          open = "";
          close = "";
        };
      };
    };

    enableZshIntegration = false;
  };
}
