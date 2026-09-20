{ config, lib, pkgs, ... }:

let
  dotfiles = "${config.home.homeDirectory}/Documents/dotfiles";

  nvimPkgs = import (builtins.fetchTarball {
    url = "https://github.com/NixOS/nixpkgs/archive/832efc09b4caf6b4569fbf9dc01bec3082a00611.tar.gz";
    sha256 = "1sxhlp1khk9ifh24lcg5qland4pg056l5jhyfw8xq3qmpavf390x";
  }) { system = pkgs.stdenv.hostPlatform.system; };
in
{
  xdg.configFile."nvim".source =
    config.lib.file.mkOutOfStoreSymlink "${dotfiles}/nvim";

  home.packages = with pkgs; [
    nvimPkgs.neovim

    # instead of mason
    clang-tools
    lua5_1
    lua-language-server
    luarocks
    nil
    nixpkgs-fmt
    nodejs_22
    pyright
    tree-sitter
    yaml-language-server
  ];
}
