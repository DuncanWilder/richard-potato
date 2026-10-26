#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CONFIG="${1:-debug}"
case "$CONFIG" in
  debug|release) ;;
  *) echo "Usage: $0 [debug|release]" >&2; exit 1 ;;
esac
cd "$ROOT"

swift build --configuration "$CONFIG" --product RichardPotato
BIN_DIR="$(swift build --configuration "$CONFIG" --show-bin-path)"
APP="$ROOT/build/$CONFIG/RichardPotato.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/RichardPotato" "$APP/Contents/MacOS/RichardPotato"
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
