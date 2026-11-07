#!/usr/bin/env bash
# Renders the cmux-flow icon and writes it into the app's asset catalog:
# AppIcon.appiconset (every size, light and dark) plus the AppIconLight /
# AppIconDark images the app applies at runtime for its appearance-following icon.
#
# The icon sits on cmux's own background, read from cmux's original artwork in
# this repository's history (the upstream commit this fork is based on).
#
# Usage: scripts/fork/apply-app-icon.sh [A|B|C]   (default A; see generate-app-icon.swift)
set -euo pipefail

DESIGN="${1:-A}"
# The cmux commit this fork branched from; its AppIconLight/Dark are the official artwork.
UPSTREAM_BASE="${CMUX_FORK_UPSTREAM_BASE:-25ef0c82e4c}"

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

git -C "$ROOT" show "$UPSTREAM_BASE:Assets.xcassets/AppIconLight.imageset/AppIconLight.png" > "$WORK/official-light.png"
git -C "$ROOT" show "$UPSTREAM_BASE:Assets.xcassets/AppIconDark.imageset/AppIconDark.png" > "$WORK/official-dark.png"
swift "$ROOT/scripts/fork/generate-app-icon.swift" "$WORK/official-light.png" "$WORK/official-dark.png" "$WORK" "$DESIGN" >/dev/null

APPICONSET="$ROOT/Assets.xcassets/AppIcon.appiconset"
for size in 16 32 128 256 512; do
  double=$((size * 2))
  sips -z "$size" "$size" "$WORK/icon-light.png" --out "$APPICONSET/${size}.png" >/dev/null
  sips -z "$double" "$double" "$WORK/icon-light.png" --out "$APPICONSET/${size}@2x.png" >/dev/null
  sips -z "$size" "$size" "$WORK/icon-dark.png" --out "$APPICONSET/${size}_dark.png" >/dev/null
  sips -z "$double" "$double" "$WORK/icon-dark.png" --out "$APPICONSET/${size}@2x_dark.png" >/dev/null
done

cp "$WORK/icon-light.png" "$ROOT/Assets.xcassets/AppIconLight.imageset/AppIconLight.png"
cp "$WORK/icon-dark.png" "$ROOT/Assets.xcassets/AppIconDark.imageset/AppIconDark.png"
echo "cmux-flow icon (design $DESIGN) applied to AppIcon, AppIconLight and AppIconDark"
