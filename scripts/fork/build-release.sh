#!/usr/bin/env bash
# Builds the distributable cmux-flow app and DMG from this fork.
#
# cmux-flow is an unofficial fork of cmux (https://github.com/manaflow-ai/cmux).
# The build gives it its own identity so it installs and runs side by side with
# an official cmux without fighting over anything:
#   - own app name, bundle id, URL scheme, sidebar extension point and icon;
#   - its own control socket (the app derives it from the non-cmux bundle id);
#   - no traffic to Manaflow's telemetry or update feed: Sentry, PostHog, remote
#     feature flags and Sparkle are all gated in code on a cmux bundle id, and
#     this script also turns Sparkle's automatic checks off;
#   - components that only work under Manaflow's signing identity, or that would
#     share an identity with an installed cmux, are left out: the Cloud network
#     extension and the Computer Use helper.
# The Cloud network extension still compiles as part of the scheme, so it is
# built against a stub WireGuard engine (CMUX_WIREGUARD_GO_REQUIRE=0) and Go is
# not needed; the extension is removed from the package afterwards.
# The result is ad-hoc signed (no Apple Developer ID), so macOS asks users to
# confirm the first launch (right-click the app, then Open).
#
# Usage: scripts/fork/build-release.sh [--universal]
#   --universal  Build arm64 + x86_64 (slower). The default is arm64 only.
# Output: dist/cmux-flow.app and dist/cmux-flow-<version>-<arch>.dmg
set -euo pipefail

APP_NAME="${CMUX_FORK_APP_NAME:-cmux-flow}"
BUNDLE_ID="${CMUX_FORK_BUNDLE_ID:-io.github.lous.cmux-flow}"
URL_SCHEME="${CMUX_FORK_URL_SCHEME:-cmux-flow}"
ARCHS="arm64"
for arg in "$@"; do
  case "$arg" in
    --universal) ARCHS="arm64 x86_64" ;;
    -h|--help) sed -n '2,23p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "unknown option: $arg" >&2; exit 1 ;;
  esac
done

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"
DERIVED_DATA="${CMUX_FORK_DERIVED_DATA:-$HOME/Library/Developer/Xcode/DerivedData/cmux-flow-release}"
DIST="$ROOT/dist"

case "$BUNDLE_ID" in
  com.cmuxterm.*)
    echo "error: $BUNDLE_ID is inside cmux's namespace; a fork needs its own bundle id" >&2
    exit 1
    ;;
esac

echo "==> Building $APP_NAME ($BUNDLE_ID, $ARCHS) — this takes a while"
xcodebuild \
  -project cmux.xcodeproj \
  -scheme cmux \
  -configuration Release \
  -destination 'generic/platform=macOS' \
  -derivedDataPath "$DERIVED_DATA" \
  ARCHS="$ARCHS" \
  ONLY_ACTIVE_ARCH=NO \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGN_ENTITLEMENTS= \
  PRODUCT_BUNDLE_IDENTIFIER="$BUNDLE_ID" \
  INFOPLIST_KEY_CFBundleName="$APP_NAME" \
  INFOPLIST_KEY_CFBundleDisplayName="$APP_NAME" \
  CMUX_AUTH_CALLBACK_SCHEME="$URL_SCHEME" \
  CMUX_SIDEBAR_EXTENSION_POINT_ID="$BUNDLE_ID.cmux.sidebar" \
  CMUX_WIREGUARD_GO_REQUIRE=0 \
  build | tail -n 5

BUILT_APP="$DERIVED_DATA/Build/Products/Release/cmux.app"
[[ -d "$BUILT_APP" ]] || { echo "error: $BUILT_APP not found" >&2; exit 1; }

echo "==> Packaging"
mkdir -p "$DIST"
APP="$DIST/$APP_NAME.app"
rm -rf "$APP"
ditto "$BUILT_APP" "$APP"
PLIST="$APP/Contents/Info.plist"
plist_set() {
  /usr/libexec/PlistBuddy -c "Set :$1 $2" "$PLIST" 2>/dev/null \
    || /usr/libexec/PlistBuddy -c "Add :$1 ${3:-string} $2" "$PLIST"
}

# Components tied to Manaflow's signing identity or to an installed cmux's identity.
rm -rf "$APP/Contents/Library/SystemExtensions/cmuxTunnel.systemextension"
rm -rf "$APP/Contents/Library/cmux Computer Use.app"
DOCK_PLUGIN_PLIST="$APP/Contents/PlugIns/CmuxDockTilePlugin.plugin/Contents/Info.plist"
if [[ -f "$DOCK_PLUGIN_PLIST" ]]; then
  /usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier $BUNDLE_ID.docktileplugin" "$DOCK_PLUGIN_PLIST"
fi

# Identity and updates. The app already refuses Manaflow's appcast for a non-cmux
# bundle id; keeping Sparkle's own automatic checks off is a second guard.
plist_set CFBundleIdentifier "$BUNDLE_ID"
plist_set CFBundleName "$APP_NAME"
plist_set CFBundleDisplayName "$APP_NAME"
plist_set SUEnableAutomaticChecks false bool
plist_set SUAutomaticallyUpdate false bool
plist_set CMUXForkOf "https://github.com/manaflow-ai/cmux"
./scripts/remove-sparkle-sandbox-xpc-services.sh "$APP" >/dev/null 2>&1 || true

echo "==> Signing (ad hoc)"
codesign --force --deep --sign - --timestamp=none "$APP"
codesign --verify --deep --strict "$APP"

VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$PLIST")"
COMMIT="$(git rev-parse --short HEAD)"
ARCH_LABEL="$( [[ "$ARCHS" == "arm64" ]] && echo arm64 || echo universal )"
DMG="$DIST/$APP_NAME-$VERSION-$COMMIT-$ARCH_LABEL.dmg"

echo "==> Creating $(basename "$DMG")"
STAGING="$(mktemp -d)"
trap 'rm -rf "$STAGING"' EXIT
ditto "$APP" "$STAGING/$APP_NAME.app"
ln -s /Applications "$STAGING/Applications"
rm -f "$DMG"
hdiutil create -quiet -volname "$APP_NAME" -srcfolder "$STAGING" -ov -format UDZO "$DMG"

echo
echo "Built $APP"
echo "      $DMG"
echo "First launch: right-click $APP_NAME.app > Open (the app is not notarized)."
