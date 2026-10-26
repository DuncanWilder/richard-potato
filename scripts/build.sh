#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CONFIG="${1:-debug}"
case "$CONFIG" in
  debug|release) ;;
  *) echo "Usage: $0 [debug|release]" >&2; exit 1 ;;
esac
cd "$ROOT"
source "$ROOT/scripts/toolchain.sh"

xcrun swift build --sdk "$SDKROOT" --configuration "$CONFIG" --product RichardPotato
BIN_DIR="$(xcrun swift build --sdk "$SDKROOT" --configuration "$CONFIG" --show-bin-path)"
APP="$ROOT/build/$CONFIG/RichardPotato.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
# Replace the executable with a new file so macOS discards cached signature data.
STAGED_BIN="$(mktemp "$APP/Contents/MacOS/.RichardPotato.XXXXXX")"
cp -p "$BIN_DIR/RichardPotato" "$STAGED_BIN"
mv -f "$STAGED_BIN" "$APP/Contents/MacOS/RichardPotato"
cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"

# iconutil is included with macOS; an asset catalog compiler is not needed.
ICON_DIR="$(mktemp -d)/AppIcon.iconset"
mkdir -p "$ICON_DIR"
trap 'rm -rf "${ICON_DIR%/*}"' EXIT
for icon in "$ROOT"/RichardPotato/Assets.xcassets/AppIcon.appiconset/*.png; do
  name="$(basename "$icon")"
  name="${name/icon-/icon_}"
  size="${name#icon_}"
  size="${size%%[@.]*}"
  name="${name/icon_$size/icon_${size}x${size}}"
  cp "$icon" "$ICON_DIR/$name"
done
iconutil -c icns "$ICON_DIR" -o "$APP/Contents/Resources/AppIcon.icns"

# Preserve the same identity and permissions for dev and release builds.
"$ROOT/scripts/stabilize-signature.sh" "$APP"
echo "Built $APP"
