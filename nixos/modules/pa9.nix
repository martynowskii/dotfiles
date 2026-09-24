# ПА9 — моделирование технических систем (лабораторные по схемотехнике).
#
# Пакет и сама программа лежат отдельным репозиторием: тащить в dotfiles
# десяток чужих jar-ников ради этого не хочется. Если каталога нет,
# пересборка системы упадёт на импорте — тогда просто убрать модуль из
# configuration.nix.
{ pkgs, ... }:

let
  pa9Dir = /home/arthr/Documents/univer/pa9;
  pa9 = pkgs.callPackage (pa9Dir + "/default.nix") { };
in
{
  nixpkgs.config.allowUnfree = true;

  environment.systemPackages = [ pa9 ];
}
