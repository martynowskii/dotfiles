{ config, lib, pkgs, ... }:

{
  environment.sessionVariables = {
    NIXOS_OZONE_WL = "1";
    QT_QPA_PLATFORM = "wayland;xcb";
    QT_QPA_PLATFORMTHEME = "gtk3";
  };

  # List packages installed in system profile.
  # You can use https://search.nixos.org/ to find more packages (and options).
  environment.systemPackages = with pkgs; [
    chromium
    git
    fastfetch
    ffmpeg
    jq
    libimobiledevice
    noctalia-shell
    swaylock
    wget
    wl-clipboard
    wtype

    # niri сам поднимает его по требованию, когда приложению нужен X11
    xwayland-satellite

    linux-enable-ir-emitter
    pciutils
    usbutils
    v4l-utils

    # Needed for appicons in noctalia
    tela-icon-theme
    kora-icon-theme
    papirus-icon-theme
    adwaita-icon-theme  # fallback
    hicolor-icon-theme  # required
    nwg-look            # theme switcher
  ];

  # Some programs need SUID wrappers, can be configured further or are
  # started in user sessions.
  # programs.mtr.enable = true;
  # programs.gnupg.agent = {
  #   enable = true;
  #   enableSSHSupport = true;
  # };

  programs = {
    # Чтобы zsh был доступен как login shell
    zsh.enable = true;

    # Регистрирует сессию и настраивает что-то системное
    niri.enable = true;

    # Нужен для всех пользователей
    vim.enable = true;
  };

  users.users.arthr.shell = pkgs.zsh;

  # List services that you want to enable:

  services.greetd = {
    enable = true;
    settings.default_session = {
      command = "${pkgs.tuigreet}/bin/tuigreet --time --cmd niri-session";
      user = "greeter";
    };
  };

  # For "talking" with iphone
  services.usbmuxd.enable = true;

  # Enable the OpenSSH daemon.
  # services.openssh.enable = true;

  # For howdy
  services.linux-enable-ir-emitter.enable = true;
}
