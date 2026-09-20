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
  # Or disable the firewall altogether.
  # networking.firewall.enable = false;

  # Порты торрент-клиентов. Без них мы «пассивны»: соединиться можно только
  # с теми пирами, кто сам принимает входящие. Пиры за NAT, а их большинство,
  # умеют лишь звонить нам — и упираются в закрытый фаервол. Роутер порт
  # qBittorrent уже пробрасывает через NAT-PMP, дело было только в хосте.
  #
  # 12991 — qBittorrent (Session\Port в его конфиге)
  # 50000 — rtorrent (network.port_range в home-manager/modules/torrent.nix)
  networking.firewall.allowedTCPPorts = [ 12991 50000 ];
  networking.firewall.allowedUDPPorts = [ 12991 50000 ];

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

