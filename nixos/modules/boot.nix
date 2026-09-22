{ config, pkgs, ... }:

{
  # Use the systemd-boot EFI boot loader.
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  # Show only the 10 newest generations in the boot menu.
  boot.loader.systemd-boot.configurationLimit = 10;

  # Standard UEFI 80x25 mode. The panel is 2880x1800, so the mode the firmware
  # picks on its own leaves the menu font unreadably small; 80x25 roughly
  # doubles the glyphs. systemd-boot has no font size of its own — the console
  # mode is the only lever.
  boot.loader.systemd-boot.consoleMode = "0";

  # Use latest kernel.
  boot.kernelPackages = pkgs.linuxPackages_latest;

  # configurationLimit only trims the menu; the generations themselves stay in
  # the store until something deletes them. Keep the 10 newest, weekly.
  systemd.services.nix-prune-generations = {
    description = "Keep only the 10 newest NixOS system generations";
    startAt = "weekly";
    path = [ config.nix.package ];
    serviceConfig.Type = "oneshot";
    script = ''
      nix-env --profile /nix/var/nix/profiles/system --delete-generations +10
      nix-collect-garbage
    '';
  };

  # Hardlink identical files in the store, saves space after the pruning.
  nix.optimise.automatic = true;
}
