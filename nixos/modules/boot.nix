{ config, pkgs, ... }:

{
  # Limine draws its own graphical terminal instead of writing through the
  # firmware's text console, so the menu font is ours to size. systemd-boot
  # could not do this: it has no font setting, and this firmware ignored the
  # console-mode requests that were the only lever it offered, leaving the
  # menu at 8x19 glyphs on a 2880x1800 panel.
  boot.loader.limine = {
    enable = true;
    efiSupport = true;

    # Same job as systemd-boot's configurationLimit: keep the menu (and the
    # ESP) down to the 10 newest generations.
    maxGenerations = 10;

    # Double the built-in font in both directions.
    style.graphicalTerminal.font.scale = "2x2";
  };
  boot.loader.efi.canTouchEfiVariables = true;

  # Use latest kernel.
  boot.kernelPackages = pkgs.linuxPackages_latest;

  # maxGenerations only trims the menu; the generations themselves stay in the
  # store until something deletes them. Keep the 10 newest, weekly.
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
