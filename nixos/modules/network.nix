{ ... }:
{
  # Configure network connections interactively with nmcli or nmtui.
  networking.networkmanager.enable = true;

  hardware.bluetooth.enable = true;
  # services.blueman.enable = true; # опционально, GUI для BT

  # Configure network proxy if necessary
  # networking.proxy.default = "http://user:password@proxy:port/";
  # networking.proxy.noProxy = "127.0.0.1,localhost,internal.domain";

  # Open ports in the firewall.
  # networking.firewall.allowedTCPPorts = [ ... ];
  # networking.firewall.allowedUDPPorts = [ ... ];
  # Or disable the firewall altogether.
  # networking.firewall.enable = false;

  # Нужны права на systemd и /etc
  # programs.amnezia-vpn.enable = true;

  # You can generate config via link2mihomo.py
  services.mihomo = {
    enable = true;
    tunMode = true;
    configFile = "/etc/mihomo/config.yaml";
  };
  networking.firewall.trustedInterfaces = [ "mihomo0" ];

  services.resolved = {
    enable = true;
    settings.Resolve = {
      Domains = [ "~." ];
      DNSStubListener = true;
    };
  };

  networking.nameservers = [ "1.1.1.1" "8.8.8.8" ];
}

