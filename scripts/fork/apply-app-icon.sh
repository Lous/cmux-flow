#!/usr/bin/env bash
# Renders the cmux-flow icon and writes it into the app's asset catalog:
# AppIcon.appiconset (every size, light and dark) plus the AppIconLight /
# AppIconDark images the app applies at runtime for its appearance-following icon.
#
# Usage: scripts/fork/apply-app-icon.sh
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

swift "$ROOT/scripts/fork/generate-app-icon.swift" "$WORK" >/dev/null

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
echo "cmux-flow icon applied to AppIcon, AppIconLight and AppIconDark"
