#!/usr/bin/env bash
# Обновляет noctalia-pin.json до последнего стабильного релиза Noctalia.
set -euo pipefail

cd "$(dirname "$0")"

tag=$(curl -fsSL "https://api.github.com/repos/noctalia-dev/noctalia/releases" \
  | jq -r 'map(select(.draft == false and .prerelease == false)) | .[0].tag_name')

[ -n "$tag" ] && [ "$tag" != "null" ] || { echo "не удалось получить тег релиза" >&2; exit 1; }

current=$(jq -r .tag noctalia-pin.json)
if [ "$tag" = "$current" ]; then
  echo "уже на $tag"
  exit 0
fi

sha=$(nix-prefetch-url --unpack --type sha256 \
  "https://github.com/noctalia-dev/noctalia/archive/refs/tags/$tag.tar.gz" 2>/dev/null | tail -1)

jq -n --arg tag "$tag" --arg sha256 "$sha" '{tag: $tag, sha256: $sha256}' > noctalia-pin.json
echo "$current -> $tag"
