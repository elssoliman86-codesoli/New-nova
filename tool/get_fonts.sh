#!/usr/bin/env bash
# Downloads the Inter font (SIL OFL 1.1) into assets/fonts/.
# Used by the GitHub Actions workflow and for local builds.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEST="$ROOT/assets/fonts"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

mkdir -p "$DEST"

curl -fsSL -o "$TMP/inter.zip" \
  "https://github.com/rsms/inter/releases/download/v4.0/Inter-4.0.zip"
unzip -q "$TMP/inter.zip" -d "$TMP/inter"

for weight in Regular Medium SemiBold Bold; do
  src="$(find "$TMP/inter" -type f -name "Inter-${weight}.ttf" | grep -vi italic | head -n 1 || true)"
  if [ -z "$src" ]; then
    echo "Could not find Inter-${weight}.ttf. Available TTF files:" >&2
    find "$TMP/inter" -type f -name '*.ttf' | head -n 60 >&2
    exit 1
  fi
  cp "$src" "$DEST/Inter-${weight}.ttf"
done

ls -la "$DEST"
