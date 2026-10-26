#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILT_APP="$ROOT/build/release/RichardPotato.app"
DIST_DIR="$ROOT/dist"
DISPLAY_NAME="Richard Potato"
DIST_APP="$DIST_DIR/$DISPLAY_NAME.app"

cd "$ROOT"

version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$ROOT/Resources/Info.plist")"

ARCHIVE_NAME="Richard-Potato-$version.zip"
ARCHIVE_PATH="$DIST_DIR/$ARCHIVE_NAME"

"$ROOT/scripts/build.sh" release

rm -rf "$DIST_DIR"
mkdir -p "$DIST_DIR"

# Copy with a friendlier display name for sharing.
ditto "$BUILT_APP" "$DIST_APP"

# Verify the signed app after copying it.
codesign --verify --deep --strict "$DIST_APP"

echo "Creating ${ARCHIVE_PATH}..."
(
  cd "$DIST_DIR"
  ditto -c -k --keepParent "$DISPLAY_NAME.app" "$ARCHIVE_NAME"
)

echo
echo "Release ready:"
echo "  App:  $DIST_APP"
echo "  Zip:  $ARCHIVE_PATH"
echo
echo "Share the zip. Recipients should unzip, then right-click the app -> Open"
echo "(needed once because this local certificate is not Apple notarized)."
echo "Dictation needs Microphone + Accessibility permission on first run."

open "$DIST_DIR"
