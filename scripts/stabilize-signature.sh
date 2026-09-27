#!/usr/bin/env bash
set -euo pipefail

APP="${1:?Usage: stabilize-signature.sh /path/to/RichardPotato.app [identity]}"
IDENTITY="${2:-${RICHARD_POTATO_IDENTITY:-Richard Potato Dev}}"

if [[ ! -d "$APP" ]]; then
  echo "App not found: $APP" >&2
  exit 1
fi

if ! security find-identity -v -p codesigning | grep -qF "\"$IDENTITY\""; then
  echo "Code-signing identity '$IDENTITY' is missing. Run ./scripts/setup-signing.sh once." >&2
  exit 1
fi

# These local build products can inherit quarantine from the source checkout.
# Remove it so macOS runs the app from this path instead of a new temporary path.
xattr -dr com.apple.quarantine "$APP" 2>/dev/null || true
if xattr -p com.apple.quarantine "$APP" >/dev/null 2>&1; then
  echo "Could not remove quarantine from local build: $APP" >&2
  exit 1
fi

# Xcode has already signed nested code. Sign the outer app with one certificate
# so Debug and Release have the same designated requirement on every build.
codesign --force \
  --sign "$IDENTITY" \
  --preserve-metadata=entitlements,flags \
  "$APP"

codesign --verify --deep --strict --verbose=2 "$APP"
