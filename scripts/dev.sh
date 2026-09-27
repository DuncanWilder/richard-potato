#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SCHEME="RichardPotato"
CONFIG="Debug"
DERIVED_DATA="$ROOT/build/DerivedData"
APP="$DERIVED_DATA/Build/Products/$CONFIG/RichardPotato.app"
BUNDLE_ID="com.local.RichardPotato"

cd "$ROOT"

quit_app() {
  if ! pgrep -x RichardPotato >/dev/null 2>&1 \
    && ! pgrep -f "$APP/Contents/MacOS/RichardPotato" >/dev/null 2>&1; then
    return 0
  fi

  echo "Stopping running Richard Potato..."
  osascript -e "tell application id \"$BUNDLE_ID\" to quit" >/dev/null 2>&1 || true
  killall RichardPotato >/dev/null 2>&1 || true

  for _ in $(seq 1 20); do
    if ! pgrep -x RichardPotato >/dev/null 2>&1; then
      return 0
    fi
    sleep 0.25
  done

  echo "Force-killing lingering RichardPotato process..."
  killall -9 RichardPotato >/dev/null 2>&1 || true
  sleep 0.25
}

quit_app

echo "Building ${SCHEME} (${CONFIG})..."
# See scripts/release.sh: -quiet mislabels warning-only tasks as failures.
xcodebuild \
  -scheme "$SCHEME" \
  -configuration "$CONFIG" \
  -derivedDataPath "$DERIVED_DATA" \
  -quiet \
  build 2>&1 | sed '/^error: the following command failed with exit code 0 but produced no further output$/d'

if [[ ! -d "$APP" ]]; then
  echo "Build succeeded but app not found at: $APP" >&2
  exit 1
fi

codesign --verify --deep --strict "$APP"

echo "Launching ${APP}"
open "$APP"

echo
echo "Richard Potato runs in the menu bar (no Dock icon)."
echo "If the shortcut is inactive, grant Accessibility access from the menu bar, then hold your shortcut to dictate."
