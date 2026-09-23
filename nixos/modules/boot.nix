{ config, pkgs, ... }:

{
  # Use the systemd-boot EFI boot loader.
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  # Show only the 10 newest generations in the boot menu.
  boot.loader.systemd-boot.configurationLimit = 10;

  # Режим консоли systemd-boot зависит от разрешения панели — см. ./machine.nix

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
