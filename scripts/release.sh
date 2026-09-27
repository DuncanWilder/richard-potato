#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SCHEME="RichardPotato"
CONFIG="Release"
DERIVED_DATA="$ROOT/build/DerivedData-Release"
BUILT_APP="$DERIVED_DATA/Build/Products/$CONFIG/RichardPotato.app"
DIST_DIR="$ROOT/dist"
DISPLAY_NAME="Richard Potato"
DIST_APP="$DIST_DIR/$DISPLAY_NAME.app"

cd "$ROOT"

version="$(
  sed -n 's/.*MARKETING_VERSION = \([^;]*\);/\1/p' \
    "$ROOT/RichardPotato.xcodeproj/project.pbxproj" | head -n 1 | tr -d '[:space:]'
)"
if [[ -z "${version:-}" ]]; then
  version="0.0"
fi

ARCHIVE_NAME="Richard-Potato-$version.zip"
ARCHIVE_PATH="$DIST_DIR/$ARCHIVE_NAME"

# shellcheck source=scripts/signing.sh
source "$ROOT/scripts/signing.sh"

echo "Building ${SCHEME} (${CONFIG}) v${version}..."
# Under -quiet, Xcode reports any task that emitted only warnings as
# "failed with exit code 0", once per architecture. The build actually
# succeeded, so drop that line; sed keeps xcodebuild's real exit status
# flowing through pipefail.
xcodebuild \
  -scheme "$SCHEME" \
  -configuration "$CONFIG" \
  -derivedDataPath "$DERIVED_DATA" \
  "${SIGN_BUILD_SETTINGS[@]}" \
  -quiet \
  build 2>&1 | sed '/^error: the following command failed with exit code 0 but produced no further output$/d'

if [[ ! -d "$BUILT_APP" ]]; then
  echo "Build succeeded but app not found at: $BUILT_APP" >&2
  exit 1
fi

rm -rf "$DIST_DIR"
mkdir -p "$DIST_DIR"

# Copy with a friendlier display name for sharing.
ditto "$BUILT_APP" "$DIST_APP"

# Give the distributed copy the same stable requirement as the Xcode build.
# Keep the configured certificate on the release copy when one is available.
"$ROOT/scripts/stabilize-signature.sh" "$DIST_APP" "$SIGN_IDENTITY"

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
