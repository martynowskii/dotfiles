{ ... }:

{
  # Шаблон yazi в noctalia должен оставаться выключенным: он правит theme.toml
  # через sed -i и заменил бы симлинк из стора обычным файлом
  programs.yazi = {
    enable = true;

    # Цвета — встроенные в yazi. Ниже только то, что гасит скругления:
    # по умолчанию во всех этих ключах U+E0B6/U+E0B4
    theme = {
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
