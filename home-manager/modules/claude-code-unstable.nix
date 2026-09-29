{ ... }:

# Claude Code, взятый из rolling-канала вместо 26.05.
#
# Новые модели доезжают до CLI только релизом: Opus 5.5 (claude-opus-5-5)
# появился в 2.1.280. Ветка nixpkgs 26.05 заморожена на 2.1.223, так что
# обновление канала nixos тут ничего не даёт.
#
# Берём nixpkgs-unstable: это rolling-срез, прошедший Hydra, — не master
# (непроверенный) и не stable (замороженный). Из него нужен только рецепт
# пакета; собирается он stdenv'ом текущего канала, второй nixpkgs в систему
# не приезжает.
#
# Хеш намеренно не зафиксирован: без sha256 fetchTarball перепроверяет канал
# раз в tarball-ttl (по умолчанию час) и подтягивает свежий срез. Размен —
# свежесть вместо воспроизводимости: одна и та же ревизия этого репозитория
# со временем даёт разные версии CLI. Обновиться немедленно:
#   home-manager switch --option tarball-ttl 0
# Откатиться — обычными поколениями home-manager.
#
# Если однажды понадобится прибить версию намертво, подставь сюда
#   builtins.fetchTarball { url = ".../archive/<rev>.tar.gz"; sha256 = "..."; }
# с хешем из `nix-prefetch-url --unpack`.

let
  nixpkgsUnstable = builtins.fetchTarball
    "https://channels.nixos.org/nixpkgs-unstable/nixexprs.tar.xz";
in
{
  nixpkgs.overlays = [
    (final: _prev: {
      claude-code = final.callPackage
        "${nixpkgsUnstable}/pkgs/by-name/cl/claude-code/package.nix"
        { };
    })
  ];
}
