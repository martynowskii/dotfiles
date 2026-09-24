{ config, pkgs, ... }:

{
  # Limine instead of systemd-boot: the latter has no font setting, and this
  # firmware ignores console-mode. Font scale is panel-specific, see machine.nix.
  boot.loader.limine = {
    enable = true;
    efiSupport = true;
    maxGenerations = 10;
  };
  boot.loader.efi.canTouchEfiVariables = true;

  boot.kernelPackages = pkgs.linuxPackages_latest;

  # maxGenerations trims the menu only; generations stay in the store.
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

  nix.optimise.automatic = true;
}
