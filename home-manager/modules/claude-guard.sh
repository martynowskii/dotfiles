# PreToolUse guard for Claude Code's Bash tool.
#
# Wrapped by pkgs.writeShellApplication in ./claude.nix, which supplies the
# shebang, the shell options and a pinned PATH (jq, git, grep, coreutils).
#
#   1. Blocks commands that reference credential material (keys, tokens, .env).
#   2. Blocks writes to Claude's own permission policy, which lives in this
#      repository and is therefore inside the area the agent may edit.
#   3. Blocks `git commit` when the staged diff looks like it carries a live
#      secret — dotfiles is pushed to a public GitHub repo, so a leak there is
#      permanent.
#
# Naming: keep this file's name clear of the deny globs in ./claude.nix. Those
# Read(...) rules are merged into sandbox.filesystem.denyRead, so a matching
# name is masked with /dev/null inside the sandbox and becomes unreadable at
# build time — the guard would block its own packaging.
#
# Contract: reads the hook payload on stdin, writes a PreToolUse decision on
# stdout, and always exits 0. A non-zero exit would surface as a hook *error*
# rather than as a deny, so failures must never propagate.

payload=$(cat)
cmd=$(printf '%s' "$payload" | jq -r '.tool_input.command // ""')
cwd=$(printf '%s' "$payload" | jq -r '.cwd // "."')

if [ -z "$cmd" ]; then
  exit 0
fi

deny() {
  jq -n --arg r "$1" '{
    hookSpecificOutput: {
      hookEventName: "PreToolUse",
      permissionDecision: "deny",
      permissionDecisionReason: $r
    }
  }'
  exit 0
}

# --- 1. paths that hold credential material -------------------------------
credential_paths=(
  '\.ssh/'
  'id_(rsa|ed25519|ecdsa|dsa)'
  '\.gnupg'
  '\.credentials\.json'
  '\.aws/credentials'
  '\.netrc|\.authinfo'
  '\.npmrc'
  '\.docker/config\.json'
  '\.config/gh/hosts'
  '(^|[[:space:]=/"'"'"'])\.env([./"'"'"'[:space:]]|$)'
  '[Ss]ecrets?\.(ya?ml|json|nix|toml|env)'
  '\.(pem|p12|pfx|jks|keystore)([[:space:]"'"'"']|$)'
  'age-key|keys\.txt'
)

for p in "${credential_paths[@]}"; do
  if printf '%s' "$cmd" | grep -Eq "$p"; then
    deny "Команда обращается к файлу с учётными данными (шаблон: ${p}). Чтение и копирование ключей, токенов и .env запрещено политикой home-manager/modules/claude.nix. Если нужен сам факт наличия файла — спроси пользователя."
  fi
done

# --- 2. environment dumps -------------------------------------------------
env_dumps=(
  '(^|[;&|`][[:space:]]*)printenv([[:space:]]|$)'
  '(^|[;&|`][[:space:]]*)env([[:space:]]*$|[[:space:]]*[|>])'
  '(^|[;&|`][[:space:]]*)export[[:space:]]+-p([[:space:]]|$)'
  '\$\{?[A-Za-z_]*(TOKEN|SECRET|PASSWORD|PASSWD|API_?KEY|CREDENTIAL)'
)

for p in "${env_dumps[@]}"; do
  if printf '%s' "$cmd" | grep -Eq "$p"; then
    deny "Команда выгружает окружение или подставляет переменную с секретом (шаблон: ${p}). Значения токенов не должны попадать в контекст модели."
  fi
done

# --- 3. self-modification of the permission policy ------------------------
# The rendered settings.json is read-only in the Nix store, but its source
# lives in this repo and the agent is allowed to edit the repo.
policy_paths='(\.claude/(settings\.json|hooks/)|modules/claude\.nix|modules/claude-guard\.sh)'
mutating='(^|[[:space:]])(sed[[:space:]]+-i|tee|truncate|install|chmod|chown|ln|cp|mv|rm|dd|patch)([[:space:]]|$)|>>?[[:space:]]*[^|&[:space:]]'

if printf '%s' "$cmd" | grep -Eq "$policy_paths" &&
  printf '%s' "$cmd" | grep -Eq "$mutating"; then
  deny "Команда пытается изменить собственную политику разрешений Claude (home-manager/modules/claude.nix, modules/claude-guard.sh или ~/.claude/). Агент не правит правила, которые его ограничивают: опиши нужное изменение пользователю словами, он применит его сам. Чтение этих файлов не запрещено."
fi

# --- 4. credentials in a staged commit -----------------------------------
if printf '%s' "$cmd" | grep -Eq '(^|[;&|`][[:space:]]*)git[[:space:]]+([^;&|]*[[:space:]])?commit([[:space:]]|$)'; then
  staged=$(git -C "$cwd" diff --cached 2>/dev/null || true)
  if [ -n "$staged" ]; then
    leak_patterns=(
      '-----BEGIN [A-Z ]*PRIVATE KEY-----'
      'gh[pousr]_[A-Za-z0-9]{30,}'
      'sk-ant-[A-Za-z0-9_-]{20,}'
      'AKIA[0-9A-Z]{16}'
      'xox[abprs]-[A-Za-z0-9-]{10,}'
      'eyJ[A-Za-z0-9_-]{15,}\.[A-Za-z0-9_-]{15,}\.'
      '(api_?key|secret|token|password)[[:space:]]*[=:][[:space:]]*"'"'"'?[A-Za-z0-9/+_-]{20,}'
    )
    for p in "${leak_patterns[@]}"; do
      if printf '%s' "$staged" | grep -Eiq "^\+.*${p}"; then
        deny "В staged-диффе найдено похожее на живой секрет (шаблон: ${p}). Коммит остановлен: dotfiles уходит на публичный GitHub, утёкший оттуда токен уже не убрать. Убери значение из индекса и вынеси его в файл вне репозитория."
      fi
    done
  fi
fi

exit 0
