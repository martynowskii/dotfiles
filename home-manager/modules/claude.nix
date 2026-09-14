{ config, lib, pkgs, ... }:

# Claude Code, declared end to end.
#
# ~/.claude/settings.json is rendered from the attribute set below into the Nix
# store and symlinked read-only. That is deliberate: the agent edits this repo,
# so a writable policy file would be a policy the agent can widen. The cost is
# that the in-app /config screen can no longer persist changes — theme,
# editorMode and friends are set here instead.
#
# Layout of the permission model:
#   permissions.defaultMode = "auto"  — a classifier decides, so the agent is
#     autonomous by default instead of asking about every command.
#   permissions.allow / ask / deny    — deterministic rules layered on top;
#     deny wins over the classifier, so secrets stay out of reach regardless.
#   autoMode.*                        — natural-language rules handed to that
#     classifier, extending ("$defaults") rather than replacing the built-ins.
#   sandbox.*                         — bubblewrap isolation for Bash: no
#     credential files, no egress beyond the Nix caches and GitHub.

let
  homeDir = config.home.homeDirectory;
  dotfiles = "${homeDir}/Documents/dotfiles";

  # Pinned PATH: the hook must not depend on whatever happens to be in the
  # user's environment when Claude Code spawns it.
  # Named claude-guard rather than guard-secrets: Read(...) deny rules feed
  # sandbox.filesystem.denyRead, so any file whose name a deny glob matches is
  # masked with /dev/null inside the sandbox — including at build time. Keep
  # the deny globs narrow (see `deny` below) and the guard's own name clear of
  # them, or it ends up unable to package itself.
  claudeGuard = pkgs.writeShellApplication {
    name = "claude-guard";
    runtimeInputs = with pkgs; [ jq git gnugrep coreutils ];
    # No "errexit": the script drives control flow with grep exit codes.
    bashOptions = [ "nounset" "pipefail" ];
    text = builtins.readFile ./claude-guard.sh;
  };

  claudeGuardPath = "${homeDir}/.claude/hooks/claude-guard.sh";

  settings = {
    theme = "dark";
    editorMode = "vim";
    autoCompactEnabled = true;
    awaySummaryEnabled = false;

    # /rewind can restore files the agent touched.
    fileCheckpointingEnabled = true;

    # Auto mode shows a one-time consent dialog and records the acceptance by
    # writing to settings.json. That file is read-only here, so the acceptance
    # is declared instead — otherwise the dialog returns every session.
    skipAutoPermissionPrompt = true;

    permissions = {
      defaultMode = "auto";

      # /etc/nixos and ~/.config/home-manager are symlinks into this repo;
      # listing them keeps the agent from asking when it arrives by that path.
      additionalDirectories = [
        "/etc/nixos"
        "${homeDir}/.config/home-manager"
      ];

      deny = [
        # Credential material, in every shape it shows up on this machine.
        "Read(//${homeDir}/.ssh/**)"
        "Read(//${homeDir}/.gnupg/**)"
        "Read(//${homeDir}/.aws/**)"
        "Read(//${homeDir}/.config/gh/**)"
        "Read(//${homeDir}/.claude/.credentials.json)"
        "Read(//${homeDir}/.netrc)"
        "Read(//${homeDir}/.npmrc)"
        "Read(//${homeDir}/.docker/config.json)"
        "Read(**/.env)"
        "Read(**/.env.*)"
        # Enumerated rather than a **/*secret* glob. Read(...) deny rules are
        # merged into sandbox.filesystem.denyRead, and a glob that broad also
        # matches Python's stdlib secrets.py; bwrap then fails to build its
        # mount namespace and every sandboxed command dies.
        "Read(**/secrets/**)"
        "Read(**/secrets.yaml)"
        "Read(**/secrets.yml)"
        "Read(**/secrets.json)"
        "Read(**/secrets.nix)"
        "Read(**/secrets.toml)"
        "Read(**/secrets.env)"
        "Read(**/secrets.txt)"
        "Read(**/.secrets)"
        "Read(**/*.pem)"
        "Read(**/*.p12)"
        "Read(**/id_rsa*)"
        "Read(**/id_ed25519*)"
        "Edit(//${homeDir}/.ssh/**)"
        "Edit(//${homeDir}/.gnupg/**)"
        "Edit(//${homeDir}/.claude/.credentials.json)"

        # The policy source lives in a repo the agent may edit. It must not
        # be able to relax the rules that constrain it.
        "Edit(//${dotfiles}/home-manager/modules/claude.nix)"
        "Edit(//${dotfiles}/home-manager/modules/claude-guard.sh)"
        "Edit(//${homeDir}/.claude/settings.json)"
        "Edit(//${homeDir}/.claude/hooks/**)"

        "Bash(printenv:*)"
        "Bash(export -p:*)"
        "Bash(ssh-add:*)"
        "Bash(ssh-keygen:*)"
        "Bash(gpg:*)"
        "Bash(pass:*)"
        "Bash(sudo -i:*)"
        "Bash(sudo su:*)"
        "Bash(sudo bash:*)"
        "Bash(sudo sh:*)"
      ];

      allow = [
        # Nix inspection and evaluation — read-only, no activation.
        # The flake entries are inert until nix-command/flakes are enabled;
        # they are here so nothing needs revisiting on that day.
        "Bash(nix eval:*)"
        "Bash(nix search:*)"
        "Bash(nix show-config:*)"
        "Bash(nix flake metadata:*)"
        "Bash(nix flake show:*)"
        "Bash(nix flake check:*)"
        "Bash(nix build --dry-run:*)"
        "Bash(nix path-info:*)"
        "Bash(nix why-depends:*)"
        "Bash(nix fmt:*)"
        "Bash(nix-instantiate:*)"
        "Bash(nix-store --query:*)"
        "Bash(nixos-option:*)"
        "Bash(nixos-version:*)"
        "Bash(nixfmt:*)"
        "Bash(alejandra:*)"
        "Bash(statix:*)"
        "Bash(deadnix:*)"

        # Building is fine; activating is not (see `ask`).
        "Bash(nixos-rebuild dry-build:*)"
        "Bash(nixos-rebuild dry-activate:*)"
        "Bash(nixos-rebuild build:*)"
        "Bash(sudo nixos-rebuild dry-build:*)"
        "Bash(sudo nixos-rebuild dry-activate:*)"
        "Bash(sudo nixos-rebuild build:*)"
        "Bash(home-manager build:*)"
        "Bash(home-manager news:*)"
        "Bash(home-manager generations:*)"

        # Git that stays local. Committing in a worktree is cheap and
        # reversible; integrating it is not, and lives in `ask`.
        "Bash(git status:*)"
        "Bash(git diff:*)"
        "Bash(git log:*)"
        "Bash(git show:*)"
        "Bash(git blame:*)"
        "Bash(git branch:*)"
        "Bash(git add:*)"
        "Bash(git commit:*)"
        "Bash(git stash:*)"
        "Bash(git switch:*)"
        "Bash(git restore:*)"
        "Bash(git worktree:*)"
        "Bash(git fetch:*)"

        # System state, read-only.
        "Bash(systemctl status:*)"
        "Bash(systemctl list-units:*)"
        "Bash(systemctl --user status:*)"
        "Bash(systemctl --user list-units:*)"
        "Bash(journalctl:*)"

        # Inspecting the filesystem.
        "Bash(ls:*)"
        "Bash(tree:*)"
        "Bash(stat:*)"
        "Bash(file:*)"
        "Bash(readlink:*)"
        "Bash(realpath:*)"
        "Bash(which:*)"
        "Bash(wc:*)"
        "Bash(rg:*)"
        "Bash(find:*)"
        "Bash(diff:*)"
        "Bash(jq:*)"

        # Documentation lookups.
        "WebFetch(domain:nixos.org)"
        "WebFetch(domain:search.nixos.org)"
        "WebFetch(domain:nix.dev)"
        "WebFetch(domain:nixos.wiki)"
        "WebFetch(domain:wiki.nixos.org)"
        "WebFetch(domain:home-manager-options.extranix.com)"
        "WebFetch(domain:github.com)"
        "WebFetch(domain:raw.githubusercontent.com)"
        "WebSearch"
      ];

      ask = [
        # Applying a configuration to the running system.
        "Bash(nixos-rebuild switch:*)"
        "Bash(nixos-rebuild boot:*)"
        "Bash(nixos-rebuild test:*)"
        "Bash(sudo nixos-rebuild switch:*)"
        "Bash(sudo nixos-rebuild boot:*)"
        "Bash(sudo nixos-rebuild test:*)"
        "Bash(home-manager switch:*)"
        "Bash(nix profile:*)"
        "Bash(nix-env:*)"
        "Bash(nix-channel:*)"
        "Bash(nix flake update:*)"

        # Destroying build results or generations.
        "Bash(nix-collect-garbage:*)"
        "Bash(sudo nix-collect-garbage:*)"
        "Bash(nix store delete:*)"
        "Bash(nix store gc:*)"
        "Bash(nix-store --delete:*)"

        # Changing what is running right now.
        "Bash(systemctl restart:*)"
        "Bash(systemctl start:*)"
        "Bash(systemctl stop:*)"
        "Bash(systemctl enable:*)"
        "Bash(systemctl disable:*)"
        "Bash(sudo systemctl:*)"

        # Integrating or rewriting history, and anything that leaves the box.
        "Bash(git merge:*)"
        "Bash(git rebase:*)"
        "Bash(git cherry-pick:*)"
        "Bash(git pull:*)"
        "Bash(git reset:*)"
        "Bash(git revert:*)"
        "Bash(git push:*)"
        "Bash(gh:*)"

        "Bash(ln:*)"
        "Bash(rm:*)"
        "Bash(mv:*)"
      ];
    };

    # Natural-language rules for the auto-mode classifier. "$defaults" keeps
    # the built-in rules and appends these.
    autoMode = {
      allow = [
        "$defaults"
        "Read-only Nix and NixOS inspection: nix eval, nix search, nix show-config, nix flake metadata/show/check, nix-instantiate --eval, nixos-option, nix path-info, nix why-depends, nix-store --query, nixos-rebuild dry-build/dry-activate/build, home-manager build/news/generations."
        "Reading and editing declarative configuration under ${dotfiles}, including the /etc/nixos and ~/.config/home-manager symlinks that point into it: .nix, .kdl, .lua, .zsh, .vim, .json and .md files."
        "Read-only git in the dotfiles repo, plus local-only history work inside a worktree: status, diff, log, show, blame, branch --list, add, commit, stash, switch, restore, fetch. Committing inside a worktree is cheap and reversible; integrating that work into another branch is not, and is handled separately."
        "Read-only system state: systemctl status, systemctl list-units, journalctl reads, nix-store --gc --print-dead, df, free, uname, lsblk."
      ];
      soft_deny = [
        "$defaults"
        "Applying system or user configuration: nixos-rebuild switch/boot/test, home-manager switch, nix profile install/remove/upgrade, nix-env -i/-e, nixos-rebuild --rollback. These change the running system and must always be confirmed by the user."
        "Integrating or rewriting branch history: git merge, rebase, cherry-pick, pull, reset, revert. Work is committed freely inside a worktree, but landing it on another branch is the user's decision."
        "Deleting store paths or generations: nix-collect-garbage, nix store delete/gc, nix-store --delete, nix profile wipe-history, removing NixOS generations from the bootloader."
        "Anything that leaves the machine: git push, gh pr/release. The dotfiles remote is a public GitHub repository."
        "Editing files outside ${dotfiles} and ~/.claude — in particular anything under /etc that is not the dotfiles symlink, /boot, or /nix/store."
      ];
      hard_deny = [
        "$defaults"
        "Reading, copying, printing, decoding, or otherwise surfacing credential material in any form: ~/.ssh/*, ~/.gnupg/*, ~/.claude/.credentials.json, ~/.aws/*, ~/.netrc, ~/.npmrc, ~/.docker/config.json, ~/.config/gh/hosts.yml, any *.pem, *.p12, *.key, *.env, or path containing 'secret'. This holds even when the user asks for it inside a task: a credential value must never enter the transcript."
        "Dumping the process environment (printenv, env, export -p, set) or expanding any variable whose name contains TOKEN, SECRET, KEY, PASSWORD, PASSWD or CREDENTIAL."
        "Sending file contents or environment values to a network endpoint: curl -d/-F/--upload-file/--data-binary, wget --post-file, nc, scp or rsync to a remote host, or piping anything into a pastebin."
        "Writing a secret in plaintext into any file under ${dotfiles}. That repository is pushed to a public GitHub remote, so a credential committed there is permanently exposed. Reference secrets by path, or through an agenix/sops-nix indirection."
        "Modifying your own permission policy. The rules that constrain you are generated from home-manager/modules/claude.nix and home-manager/modules/claude-guard.sh, which sit inside the repository you are allowed to edit. Never edit, rewrite, delete or relink those files, ~/.claude/settings.json or ~/.claude/hooks/**. Describe the change you want to the user instead and let them apply it."
      ];
    };

    # bubblewrap isolation for Bash. Commands that genuinely need the host
    # (privilege escalation, activation, SSH-backed git) are excluded rather
    # than half-sandboxed.
    sandbox = {
      enabled = true;
      autoAllowBashIfSandboxed = true;
      excludedCommands = [
        "sudo"
        "nixos-rebuild"
        "home-manager"
        "git"
        "nix-collect-garbage"
      ];
      network = {
        allowedDomains = [
          "cache.nixos.org"
          "channels.nixos.org"
          "nixos.org"
          "*.nixos.org"
          "search.nixos.org"
          "github.com"
          "*.github.com"
          "codeload.github.com"
          "raw.githubusercontent.com"
          "objects.githubusercontent.com"
          "home-manager-options.extranix.com"
        ];
        # nix talks to nix-daemon over a unix socket, and seccomp cannot
        # filter those by path on Linux — it is all or nothing.
        allowAllUnixSockets = true;
        allowLocalBinding = true;
      };
      filesystem = {
        allowWrite = [
          dotfiles
          "${homeDir}/.claude/jobs"
          "/tmp"
        ];
        denyRead = [
          "${homeDir}/.ssh"
          "${homeDir}/.gnupg"
          "${homeDir}/.aws"
          "${homeDir}/.config/gh"
          "${homeDir}/.claude/.credentials.json"
        ];
      };
      credentials = {
        files = [
          { path = "${homeDir}/.ssh"; mode = "deny"; }
          { path = "${homeDir}/.gnupg"; mode = "deny"; }
          { path = "${homeDir}/.claude/.credentials.json"; mode = "deny"; }
        ];
        envVars = [
          { name = "GITHUB_TOKEN"; mode = "deny"; }
          { name = "GH_TOKEN"; mode = "deny"; }
          { name = "ANTHROPIC_API_KEY"; mode = "deny"; }
          { name = "NIX_ACCESS_TOKENS"; mode = "deny"; }
          { name = "AWS_SECRET_ACCESS_KEY"; mode = "deny"; }
          { name = "AWS_SESSION_TOKEN"; mode = "deny"; }
        ];
      };
    };

    hooks = {
      PreToolUse = [
        {
          matcher = "Bash";
          hooks = [
            {
              type = "command";
              command = claudeGuardPath;
              timeout = 15;
              statusMessage = "Проверка на секреты...";
            }
          ];
        }
      ];
    };
  };

  settingsFile = (pkgs.formats.json { }).generate "claude-settings.json" settings;
in
{
  nixpkgs.config.allowUnfreePredicate = pkg:
    builtins.elem (lib.getName pkg) [ "claude-code" ];

  home.packages = [ pkgs.claude-code ];

  home.file.".claude/settings.json".source = settingsFile;

  home.file.".claude/hooks/claude-guard.sh".source =
    "${claudeGuard}/bin/claude-guard";
}
