{ ... }:

# Мелочь для оболочки: настройки в несколько строк, отдельного файла
# на каждую не заслуживают, но и в home.packages им не место —
# они настраиваются, а не просто ставятся.
{
  programs.tmux = {
    enable = true;
    keyMode = "vi";
    escapeTime = 10;
  };

  programs.fzf = {
    enable = true;
    enableZshIntegration = true;
  };
}
