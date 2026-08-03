export EDITOR="nvim"
export VISUAL="nvim"

export LANG="en_US.UTF-8"

export PATH="$HOME/.local/bin:$PATH"

# Stable agent socket for tmux: ~/.ssh/rc refreshes the symlink on each ssh login
if [ -S "$HOME/.ssh/ssh_auth_sock" ]; then
    export SSH_AUTH_SOCK="$HOME/.ssh/ssh_auth_sock"
fi
