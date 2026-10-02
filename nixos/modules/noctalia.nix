# Noctalia v5 — нативный C++ шелл и отдельный пакет; v4 (noctalia-shell) живёт в components.nix.
# В nixpkgs 26.05 v5 ещё нет, поэтому берём upstream-релиз: тег и хеш лежат в noctalia-pin.json,
# обновляются через ./noctalia-pin.sh. pkgs внутрь не передаём — иначе derivation
# расходится с бинарным кешем и шелл собирается локально.
{ ... }:

let
  pin = builtins.fromJSON (builtins.readFile ./noctalia-pin.json);

  noctalia = import (fetchTarball {
    url = "https://github.com/noctalia-dev/noctalia/archive/refs/tags/${pin.tag}.tar.gz";
    inherit (pin) sha256;
  }) { };
in
{
  environment.systemPackages = [ noctalia.package ];

  nix.settings = {
    extra-substituters = [ "https://noctalia.cachix.org" ];
    extra-trusted-public-keys = [
      "noctalia.cachix.org-1:pCOR47nnMEo5thcxNDtzWpOxNFQsBRglJzxWPp3dkU4="
    ];
  };
}
