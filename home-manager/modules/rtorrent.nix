{ config, lib, pkgs, ... }:

let
  home = config.home.homeDirectory;

  # Пути относительно $HOME — в таком виде их ждёт home.file
  downloadRel = "Downloads";
  watchRel = "Downloads/watch";
  sessionRel = ".local/share/rtorrent/session";
in
{
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

      # Лимиты. 0 = без ограничения; правь под свой канал
      throttle.global_down.max_rate.set_kb = 0
      throttle.global_up.max_rate.set_kb = 0
      throttle.max_uploads.set = 50
      throttle.min_peers.normal.set = 20
      throttle.max_peers.normal.set = 60

      # Локальный SCGI-сокет — пригодится для rtxmlrpc/flood
      network.scgi.open_local = (cat, (session.path), "rpc.socket")
      schedule2 = scgi_permission, 0, 0, ((execute.nothrow, chmod, "0600", (cat, (session.path), "rpc.socket")))
    '';
  };

  # rtorrent не создаёт эти каталоги сам и отказывается стартовать без них
  home.file."${sessionRel}/.keep".text = "";
  home.file."${watchRel}/.keep".text = "";
}
