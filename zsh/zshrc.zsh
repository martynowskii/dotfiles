# XDG base
export XDG_CONFIG_HOME="$HOME/.config"

# Oh My Zsh
export ZSH="$HOME/.oh-my-zsh"

# Theme
# ZSH_THEME="random"
ZSH_THEME="powerlevel10k/powerlevel10k"

# OMZ update policy
zstyle ':omz:update' mode auto

# Load modular config
source $XDG_CONFIG_HOME/zsh/aliases.zsh
source $XDG_CONFIG_HOME/zsh/exports.zsh
source $XDG_CONFIG_HOME/zsh/p10k.zsh
source $XDG_CONFIG_HOME/zsh/path.zsh
source $XDG_CONFIG_HOME/zsh/plugins.zsh
source $XDG_CONFIG_HOME/zsh/yandex.zsh

# Load Oh My Zsh
source $ZSH/oh-my-zsh.sh
