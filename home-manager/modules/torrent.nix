{ config, pkgs, ... }:

# Порты 50000 и 12991 открыты в nixos/modules/network.nix.
let
  home = config.home.homeDirectory;

  # Пути относительно $HOME — в таком виде их ждёт home.file
  downloadRel = "Downloads";
  watchRel = "Downloads/watch";
  sessionRel = ".local/share/rtorrent/session";
in
{
  # Модуля home-manager для qbittorrent нет и быть не может: клиент сам
  # перезаписывает свой qBittorrent.conf при каждом изменении настроек,
  # поэтому симлинк из /nix/store он бы сломал. Настройки живут в
  # ~/.config/qBittorrent и в dotfiles не попадают — в отличие от rtorrent.
  home.packages = with pkgs; [
    qbittorrent
  ];

  programs.rtorrent = {
    enable = true;

    # Синтаксис 0.9.6+ (command.set), не старый rtorrent.rc
    extraConfig = ''
      # Куда качать и где хранить состояние сессии
      directory.default.set = ${home}/${downloadRel}
      session.path.set = ${home}/${sessionRel}

      # Автоподхват .torrent-файлов, брошенных в ~/${watchRel}
      schedule2 = watch_directory, 10, 10, ((load.start, "${home}/${watchRel}/*.torrent"))

      # Не перехешировать торрент после завершения закачки
      pieces.hash.on_completion.set = no

      # Сеть: один фиксированный порт, удобно пробрасывать на роутере
      network.port_range.set = 50000-50000
      network.port_random.set = no

      # Шифрование протокола: принимаем любое, исходящее пробуем шифровать
      protocol.encryption.set = allow_incoming,try_outgoing,enable_retry

      # DHT и обмен пирами — нужны для публичных раздач.
      # Порт для DHT отдельно не задаём: берётся из network.port_range,
      # значит пробросить на роутере достаточно один 50000/udp+tcp
      dht.mode.set = auto
      protocol.pex.set = yes
      trackers.use_udp.set = yes

      # Bootstrap-узлы DHT. В libtorrent-rakshasa они НЕ зашиты: без этих
      # строк на чистой установке DHT не с чего стартовать, и при молчащем
      # трекере торрент не найдёт ни одного пира.
      #
      # Форма именно "dht.add_node=host:port" — одной строкой. Вики rtorrent
      # описывает вариант ((dht.add_node, "host", port)), но он падает с
      # "Wrong object type: expected: string actual: list"; см.
      # https://github.com/rakshasa/rtorrent/issues/1155
      # Проверено ping-запросами KRPC: router.bittorrent.com,
      # router.utorrent.com, router.bitcomet.com и dht.aelitis.com не
      # отвечают — держать их бессмысленно. Отвечают только эти два.
      schedule2 = dht_node_1, 5, 0, "dht.add_node=dht.transmissionbt.com:6881"
      schedule2 = dht_node_2, 6, 0, "dht.add_node=dht.libtorrent.org:25401"

      # Лимиты. 0 = без ограничения; правь под свой канал
      throttle.global_down.max_rate.set_kb = 0
      throttle.global_up.max_rate.set_kb = 0
      throttle.max_uploads.set = 50
      throttle.min_peers.normal.set = 20
      throttle.max_peers.normal.set = 60

      # Лог: без него не видно ответов трекеров и причин зависших анонсов
      log.open_file = "log", ${home}/.local/share/rtorrent/rtorrent.log
      log.add_output = "info", "log"

      # Локальный SCGI-сокет — пригодится для rtxmlrpc/flood
      network.scgi.open_local = (cat, (session.path), "rpc.socket")
      schedule2 = scgi_permission, 0, 0, ((execute.nothrow, chmod, "0600", (cat, (session.path), "rpc.socket")))
    '';
  };

  # rtorrent не создаёт эти каталоги сам и отказывается стартовать без них
  home.file."${sessionRel}/.keep".text = "";
  home.file."${watchRel}/.keep".text = "";
}
