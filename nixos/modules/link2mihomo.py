#!/usr/bin/env python3
"""
link2mihomo — превращает share-ссылку прокси в готовый config.yaml для mihomo.

Поддержка: vmess://, vless:// (в т.ч. Reality), trojan://, ss://,
           vpn:// (формат AmneziaVPN: base64url от qCompress(JSON))

Примеры:
    echo 'vmess://...' | python3 link2mihomo.py > config.yaml
    python3 link2mihomo.py 'vmess://...' | sudo tee /etc/mihomo/config.yaml
    xclip -o | python3 link2mihomo.py --nix        # выдать блок для configuration.nix

Ключи:
    --name NAME         имя прокси в конфиге (по умолчанию из ссылки)
    --device DEV        имя tun-устройства (по умолчанию mihomo0)
    --stack S           mixed | system | gvisor (по умолчанию mixed)
    --dns-mode M        fake-ip | redir-host (по умолчанию fake-ip)
    --dns SERVER        основной резолвер (по умолчанию https://1.1.1.1/dns-query)
    --port N            порт mixed-инбаунда (по умолчанию 7890)
    --controller ADDR   external-controller (по умолчанию 127.0.0.1:9090)
    --no-tun            без TUN, только mixed-прокси на localhost
    --verify            всегда проверять TLS-сертификат
    --insecure          всегда пропускать проверку сертификата
    --nix               вывести блок services.mihomo вместо YAML
    --block-quic        резать UDP/443 (лечит зависающий YouTube)
    --dump              для vpn://: показать расшифрованный JSON и выйти
"""

import argparse
import base64
import json
import re
import sys
import zlib
from urllib.parse import urlparse, parse_qs, unquote


# ------------------------------------------------------------------ утилиты

def b64d(s: str) -> bytes:
    s = s.strip().replace("-", "+").replace("_", "/")
    s += "=" * (-len(s) % 4)
    return base64.b64decode(s)


def die(msg: str):
    print(f"ошибка: {msg}", file=sys.stderr)
    sys.exit(1)


def is_ip(s: str) -> bool:
    return bool(re.fullmatch(r"\d{1,3}(\.\d{1,3}){3}", s or ""))


# ------------------------------------------------------------ YAML-эмиттер

SAFE = re.compile(r"^[A-Za-z][A-Za-z0-9_\-]*$")
YAML_WORDS = {"true", "false", "null", "yes", "no", "on", "off", "~"}


def y_scalar(v):
    if isinstance(v, bool):
        return "true" if v else "false"
    if isinstance(v, (int, float)):
        return str(v)
    if v is None:
        return "null"
    s = str(v)
    if SAFE.match(s) and s.lower() not in YAML_WORDS:
        return s
    return "'" + s.replace("'", "''") + "'"


def to_yaml(obj, indent=0, in_list=False):
    """Минимальный эмиттер: dict / list / скаляры."""
    pad = "  " * indent
    out = []

    if isinstance(obj, dict):
        first = True
        for k, v in obj.items():
            prefix = pad
            if in_list and first:
                prefix = ""
            first = False
            if isinstance(v, (dict, list)) and v:
                out.append(f"{prefix}{k}:")
                out.append(to_yaml(v, indent + 1))
            elif isinstance(v, (dict, list)):
                out.append(f"{prefix}{k}: {'{}' if isinstance(v, dict) else '[]'}")
            else:
                out.append(f"{prefix}{k}: {y_scalar(v)}")
        return "\n".join(out)

    if isinstance(obj, list):
        for item in obj:
            if isinstance(item, dict):
                out.append(f"{pad}- " + to_yaml(item, indent + 1, in_list=True))
            elif isinstance(item, list):
                out.append(f"{pad}-")
                out.append(to_yaml(item, indent + 1))
            else:
                out.append(f"{pad}- {y_scalar(item)}")
        return "\n".join(out)

    return f"{pad}{y_scalar(obj)}"


# ----------------------------------------------------------------- парсеры

def transport(proxy, net, path, host, service_name=""):
    """Заполняет network и *-opts по правилам mihomo."""
    net = (net or "tcp").lower()
    path = unquote(path or "") or "/"
    if net in ("", "tcp", "raw"):
        proxy["network"] = "tcp"
        return
    if net == "ws":
        proxy["network"] = "ws"
        opts = {"path": path}
        if host:
            opts["headers"] = {"Host": host}
        proxy["ws-opts"] = opts
        return
    if net == "grpc":
        proxy["network"] = "grpc"
        proxy["grpc-opts"] = {"grpc-service-name": service_name or path.lstrip("/")}
        return
    if net in ("h2", "http"):
        proxy["network"] = net
        opts = {"path": path}
        if host:
            opts["host"] = [h for h in host.split(",") if h]
        proxy[f"{net}-opts"] = opts
        return
    print(f"предупреждение: транспорт '{net}' неизвестен, ставлю tcp",
          file=sys.stderr)
    proxy["network"] = "tcp"


def tls_fields(proxy, enabled, sni, server, alpn, fp, args):
    if not enabled:
        return
    proxy["tls"] = True
    sni = sni or server
    proxy["servername"] = sni
    if alpn:
        proxy["alpn"] = [a for a in unquote(alpn).split(",") if a]
    proxy["client-fingerprint"] = fp or "chrome"
    # сертификат на голый IP почти всегда самоподписанный
    if args.insecure or (is_ip(sni) and not args.verify):
        proxy["skip-cert-verify"] = True


def parse_vmess(link, args):
    try:
        cfg = json.loads(b64d(link[len("vmess://"):]))
    except Exception:
        die("не разобрал vmess-ссылку (ожидал base64 от JSON)")

    p = {
        "name": args.name or cfg.get("ps") or "proxy",
        "type": "vmess",
        "server": cfg.get("add"),
        "port": int(cfg.get("port", 443)),
        "uuid": cfg.get("id"),
        "alterId": int(cfg.get("aid", 0) or 0),
        "cipher": cfg.get("scy") or "auto",
        "udp": True,
    }
    tls_fields(p, (cfg.get("tls") or "") in ("tls", "reality"),
               cfg.get("sni") or cfg.get("host"), p["server"],
               cfg.get("alpn"), cfg.get("fp"), args)
    transport(p, cfg.get("net"), cfg.get("path"), cfg.get("host"))
    return p


def parse_vless(link, args):
    u = urlparse(link)
    q = parse_qs(u.query)
    g = lambda k, d="": q.get(k, [d])[0]

    p = {
        "name": args.name or unquote(u.fragment or "") or "proxy",
        "type": "vless",
        "server": u.hostname,
        "port": u.port or 443,
        "uuid": u.username,
        "udp": True,
    }
    sec = g("security", "none")
    tls_fields(p, sec in ("tls", "reality", "xtls"),
               g("sni") or g("host"), p["server"], g("alpn"), g("fp"), args)
    if sec == "reality":
        p["reality-opts"] = {"public-key": g("pbk")}
        if g("sid"):
            p["reality-opts"]["short-id"] = g("sid")
        p.pop("skip-cert-verify", None)   # с Reality проверка не применима
    if g("flow"):
        p["flow"] = g("flow")
    transport(p, g("type", "tcp"), g("path"), g("host"), g("serviceName"))
    return p


def parse_trojan(link, args):
    u = urlparse(link)
    q = parse_qs(u.query)
    g = lambda k, d="": q.get(k, [d])[0]
    p = {
        "name": args.name or unquote(u.fragment or "") or "proxy",
        "type": "trojan",
        "server": u.hostname,
        "port": u.port or 443,
        "password": unquote(u.username or ""),
        "udp": True,
    }
    tls_fields(p, True, g("sni") or g("peer"), p["server"],
               g("alpn"), g("fp"), args)
    p.pop("tls", None)          # у trojan TLS всегда включён, поле лишнее
    transport(p, g("type", "tcp"), g("path"), g("host"), g("serviceName"))
    return p


def parse_ss(link, args):
    body = link[len("ss://"):]
    frag = ""
    if "#" in body:
        body, frag = body.split("#", 1)
    body = body.split("?", 1)[0]
    if "@" in body:
        userinfo, hostport = body.rsplit("@", 1)
        try:
            method, password = b64d(userinfo).decode().split(":", 1)
        except Exception:
            method, password = unquote(userinfo).split(":", 1)
    else:
        userinfo, hostport = b64d(body).decode().rsplit("@", 1)
        method, password = userinfo.split(":", 1)
    host, _, port = hostport.rpartition(":")
    return {
        "name": args.name or unquote(frag) or "proxy",
        "type": "ss",
        "server": host,
        "port": int(port),
        "cipher": method,
        "password": password,
        "udp": True,
    }


PARSERS = {
    "vmess://": parse_vmess,
    "vless://": parse_vless,
    "trojan://": parse_trojan,
    "ss://": parse_ss,
    "vpn://": lambda link, args: parse_vpn(link, args),
}


# ------------------------------------------------- vpn:// (формат AmneziaVPN)

# Контейнеры Amnezia, у которых нет аналога в mihomo
UNSUPPORTED = {
    "awg": "AmneziaWG: mihomo знает обычный WireGuard, но не обфускацию "
           "Amnezia (Jc/Jmin/Jmax/S1/S2/H1-H4). Конвертация невозможна.",
    "wireguard": "WireGuard: mihomo поддерживает его как type: wireguard, но "
                 "поля тут другие — сконвертируй вручную из .conf.",
    "openvpn": "OpenVPN: mihomo его не умеет вообще.",
    "cloak": "Cloak: mihomo его не умеет.",
    "ikev2": "IKEv2: mihomo его не умеет.",
    "tor": "Tor-контейнер конвертации не подлежит.",
}


def decode_vpn(link: str) -> dict:
    """vpn:// -> dict. Payload это qCompress(JSON) в base64url, реже голый JSON."""
    raw = link[len("vpn://"):].strip()
    try:
        data = base64.urlsafe_b64decode(raw + "=" * (-len(raw) % 4))
    except Exception:
        die("тело ссылки не является корректным base64url")

    # qCompress: 4 байта размера (big-endian) + zlib
    for attempt in (lambda: zlib.decompress(data[4:]),
                    lambda: zlib.decompress(data),
                    lambda: data):
        try:
            return json.loads(attempt())
        except Exception:
            continue
    die("не удалось распаковать payload (ожидал qCompress/zlib или JSON)")


def proxy_from_xray(ob: dict, name: str, args) -> dict:
    """Аутбаунд из конфига xray-core -> прокси mihomo."""
    proto = (ob.get("protocol") or "").lower()
    st = ob.get("streamSettings") or {}
    s = ob.get("settings") or {}

    p = {"name": name, "udp": True}

    if proto in ("vmess", "vless"):
        vnext = (s.get("vnext") or [{}])[0]
        user = (vnext.get("users") or [{}])[0]
        p.update({
            "type": proto,
            "server": vnext.get("address"),
            "port": int(vnext.get("port", 443)),
            "uuid": user.get("id"),
        })
        if proto == "vmess":
            p["alterId"] = int(user.get("alterId", 0) or 0)
            p["cipher"] = user.get("security") or "auto"
        elif user.get("flow"):
            p["flow"] = user["flow"]
    elif proto == "trojan":
        srv = (s.get("servers") or [{}])[0]
        p.update({"type": "trojan", "server": srv.get("address"),
                  "port": int(srv.get("port", 443)),
                  "password": srv.get("password")})
    elif proto == "shadowsocks":
        srv = (s.get("servers") or [{}])[0]
        p.update({"type": "ss", "server": srv.get("address"),
                  "port": int(srv.get("port", 8388)),
                  "cipher": srv.get("method"), "password": srv.get("password")})
        return p
    else:
        die(f"протокол xray '{proto}' не поддерживается конвертером")

    sec = (st.get("security") or "none").lower()
    tls_cfg = st.get("tlsSettings") or {}
    rl_cfg = st.get("realitySettings") or {}
    src = rl_cfg if sec == "reality" else tls_cfg
    alpn = tls_cfg.get("alpn")

    tls_fields(p, sec in ("tls", "reality", "xtls"),
               src.get("serverName"), p["server"],
               ",".join(alpn) if isinstance(alpn, list) else alpn,
               src.get("fingerprint"), args)
    if tls_cfg.get("allowInsecure"):
        p["skip-cert-verify"] = True
    if sec == "reality":
        p["reality-opts"] = {"public-key": rl_cfg.get("publicKey")}
        if rl_cfg.get("shortId"):
            p["reality-opts"]["short-id"] = rl_cfg["shortId"]
        p.pop("skip-cert-verify", None)
    if proto == "trojan":
        p.pop("tls", None)

    net = (st.get("network") or "tcp").lower()
    ws = st.get("wsSettings") or {}
    grpc = st.get("grpcSettings") or {}
    http = st.get("httpSettings") or {}
    transport(p, net,
              ws.get("path") or http.get("path"),
              (ws.get("headers") or {}).get("Host")
              or ",".join(http.get("host") or []),
              grpc.get("serviceName"))
    return p


def parse_vpn(link, args):
    cfg = decode_vpn(link)

    if args.dump:
        print(json.dumps(cfg, indent=2, ensure_ascii=False))
        sys.exit(0)

    label = args.name or cfg.get("description") or cfg.get("hostName") or "amnezia"

    containers = cfg.get("containers") or []
    if not containers and cfg.get("last_config"):
        containers = [cfg]

    found = []
    for c in containers:
        for key, val in c.items():
            if key in ("container",) or not isinstance(val, dict):
                continue
            if key in UNSUPPORTED:
                found.append((key, None))
                continue
            inner = val.get("last_config")
            if not inner:
                continue
            try:
                xr = json.loads(inner) if isinstance(inner, str) else inner
            except Exception:
                continue
            obs = xr.get("outbounds") or []
            ob = next((o for o in obs
                       if (o.get("protocol") or "").lower()
                       not in ("freedom", "blackhole", "dns")), None)
            if ob:
                found.append((key, ob))

    usable = [(k, o) for k, o in found if o]
    if not usable:
        msgs = [UNSUPPORTED[k] for k, o in found if o is None and k in UNSUPPORTED]
        if msgs:
            die("в ссылке только неподдерживаемые контейнеры:\n  - "
                + "\n  - ".join(msgs)
                + "\n\nПосмотреть содержимое целиком: --dump")
        die("не нашёл пригодного конфига внутри vpn://. Запусти с --dump, "
            "чтобы увидеть структуру.")

    key, ob = usable[0]
    if len(usable) > 1:
        print(f"предупреждение: контейнеров несколько ({', '.join(k for k, _ in usable)}), "
              f"беру '{key}'", file=sys.stderr)
    return proxy_from_xray(ob, label, args)


# ----------------------------------------------------------------- сборка

def build_config(proxy, args):
    cfg = {
        "mixed-port": args.port,
        "mode": "rule",
        "log-level": "info",
        "ipv6": False,
        "external-controller": args.controller,
    }

    if not args.no_tun:
        cfg["tun"] = {
            "enable": True,
            "stack": args.stack,
            "device": args.device,
            "auto-route": True,
            "auto-redirect": True,
            "auto-detect-interface": True,
            "strict-route": True,
            "dns-hijack": ["any:53", "tcp://any:53"],
        }

    dns = {
        "enable": True,
        "listen": "0.0.0.0:1053",
        "ipv6": False,
        "enhanced-mode": args.dns_mode,
        "default-nameserver": ["1.1.1.1", "8.8.8.8"],
        "nameserver": [args.dns],
        "proxy-server-nameserver": ["1.1.1.1"],
        "respect-rules": False,
    }
    if args.dns_mode == "fake-ip":
        dns["fake-ip-range"] = "198.18.0.1/16"
        dns["fake-ip-filter"] = [
            "*.lan", "*.local", "*.localdomain", "+.home.arpa",
            "localhost.ptlogin2.qq.com",
        ]
    cfg["dns"] = dns

    cfg["proxies"] = [proxy]

    rules = []
    if args.block_quic:
        # YouTube и прочие уходят в HTTP/3 по UDP 443; если UDP через прокси
        # не работает, браузер залипает до таймаута вместо отката на TCP
        rules.append("AND,((NETWORK,udp),(DST-PORT,443)),REJECT")
    rules.append(f"MATCH,{proxy['name']}")
    cfg["rules"] = rules
    return cfg


NIX_TEMPLATE = """# Сгенерировано link2mihomo. Положи в configuration.nix или подключи через imports.
{{ ... }}:
{{
  services.mihomo = {{
    enable = true;
    tunMode = true;                       # только выдаёт права; сам TUN — в config.yaml
    configFile = "/etc/mihomo/config.yaml";
  }};

  # nixos-fw отбрасывает входящий трафик с tun-интерфейса, если он не доверенный
  networking.firewall.trustedInterfaces = [ "{device}" ];

  # DNS. Без этого блока запросы уходят на DNS роутера по прямому link-маршруту,
  # минуя туннель, и заблокированные домены не резолвятся.
  # Domains = [ "~." ] помечает глобальные серверы как маршрут для всех доменов,
  # чтобы они перебивали per-link серверы от DHCP.
  services.resolved = {{
    enable = true;
    settings.Resolve.Domains = [ "~." ];
  }};

  networking.nameservers = [ "1.1.1.1" "8.8.8.8" ];

  # IPv6 в туннель не заводится, а браузер по Happy Eyeballs предпочитает AAAA
  # и виснет. Раскомментируй, если сайты открываются через раз.
  # networking.enableIPv6 = false;
}}
"""


def main():
    ap = argparse.ArgumentParser(add_help=True)
    ap.add_argument("link", nargs="?", help="share-ссылка; иначе читаю stdin")
    ap.add_argument("--name")
    ap.add_argument("--device", default="mihomo0")
    ap.add_argument("--stack", default="mixed",
                    choices=["mixed", "system", "gvisor"])
    ap.add_argument("--dns-mode", default="fake-ip",
                    choices=["fake-ip", "redir-host"])
    ap.add_argument("--dns", default="https://1.1.1.1/dns-query")
    ap.add_argument("--port", type=int, default=7890)
    ap.add_argument("--controller", default="127.0.0.1:9090")
    ap.add_argument("--no-tun", action="store_true")
    ap.add_argument("--block-quic", action="store_true",
                    help="резать UDP/443, чтобы браузер не залипал на HTTP/3")
    ap.add_argument("--verify", action="store_true")
    ap.add_argument("--insecure", action="store_true")
    ap.add_argument("--nix", action="store_true")
    ap.add_argument("--dump", action="store_true",
                    help="для vpn://: показать расшифрованный JSON и выйти")
    args = ap.parse_args()

    link = (args.link or sys.stdin.read()).strip()
    if not link:
        die("пустой ввод")

    for prefix, fn in PARSERS.items():
        if link.lower().startswith(prefix):
            proxy = fn(link, args)
            break
    else:
        die(f"неизвестная схема. Умею: {', '.join(PARSERS)}")

    if not proxy.get("server") or not proxy.get("port"):
        die("в ссылке не нашлось адреса или порта сервера")
    proxy["name"] = re.sub(r"[^\w\-. ]", "", proxy["name"]).strip() or "proxy"

    if args.nix:
        print(NIX_TEMPLATE.format(device=args.device), end="")
        return

    print(f"# сгенерировано link2mihomo из {proxy['type']}-ссылки")
    print(f"# положить в /etc/mihomo/config.yaml, chmod 600")
    print(to_yaml(build_config(proxy, args)))

    notes = []
    if proxy.get("skip-cert-verify"):
        notes.append("skip-cert-verify включён: SNI — это IP, валидного "
                     "сертификата быть не может. Отключить: --verify")
    if args.no_tun:
        notes.append(f"TUN выключен: прокси доступен на 127.0.0.1:{args.port}")
    else:
        notes.append("ОБЯЗАТЕЛЬНО добавь сопутствующий блок в configuration.nix: "
                     f"python3 {sys.argv[0]} <ссылка> --nix")
        notes.append("Без services.resolved + Domains = [ \"~.\" ] запросы уйдут "
                     "на DNS роутера мимо туннеля, и заблокированные домены "
                     "не отрезолвятся (при этом обычные сайты будут работать — "
                     "выглядит как «тормозит только ютуб»).")
        notes.append(f"nixos-fw режет входящий трафик: нужен "
                     f"trustedInterfaces = [ \"{args.device}\" ]")
    if not args.block_quic:
        notes.append("Если ютуб висит, а остальное открывается — попробуй "
                     "--block-quic (UDP/443 в REJECT) или добавь в прокси "
                     "packet-encoding: xudp")
    notes.append("Проверка после применения: getent hosts www.youtube.com "
                 "должен вернуть 198.18.x.x — значит отвечает mihomo, а не провайдер")
    for n in notes:
        print(f"\n# {n}", file=sys.stderr)


if __name__ == "__main__":
    try:
        main()
    except BrokenPipeError:
        sys.stderr.close()
        sys.exit(0)
