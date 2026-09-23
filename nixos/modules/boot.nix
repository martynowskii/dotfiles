{ config, pkgs, ... }:

let
  # The UEFI text console draws a fixed 8x19 font and this firmware ignores
  # console-mode requests, so on the 2880x1800 panel the boot menu came out
  # unreadable. big-console is a DXE driver (a fork of edk2's
  # GraphicsConsoleDxe) that keeps the native resolution and enlarges the
  # character cells instead. Pinned by revision — bump url and sha256 together.
  bigConsoleSrc = builtins.fetchTarball {
    url = "https://github.com/clhodapp/big-console/archive/067b228438036f465dd3ce500acf9784270109b2.tar.gz";
    sha256 = "14fm28m7qplzsyaqjqib69wq465wacv2rh7hr9anavra8vl6f834";
  };

  # Cells of 16x32 (Terminus), about twice the firmware's 8x19. glyphScale = 2
  # would double that again, which is more than we want here.
  bigConsoleDxe = pkgs.callPackage "${bigConsoleSrc}/pkgs/big-console/big-console-dxe" {
    glyphScale = 1;
  };
in
{
  # Use the systemd-boot EFI boot loader.
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  # Show only the 10 newest generations in the boot menu.
  boot.loader.systemd-boot.configurationLimit = 10;

  # systemd-boot loads every driver under EFI/systemd/drivers whose name ends
  # in the architecture id plus .efi, before it draws the menu.
  boot.loader.systemd-boot.extraFiles."EFI/systemd/drivers/BigGraphicsConsoleDxe.x64.efi" =
    "${bigConsoleDxe}/BigGraphicsConsoleDxe.efi";

  # Spread the enlarged grid over the whole panel; the default would centre an
  # 80x25 block in the middle of it.
  boot.loader.systemd-boot.consoleMode = "max";

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
