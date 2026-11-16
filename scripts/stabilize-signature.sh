#!/usr/bin/env bash
set -euo pipefail

APP="${1:?Usage: stabilize-signature.sh /path/to/RichardPotato.app}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"

if [[ ! -d "$APP" ]]; then
  echo "App not found: $APP" >&2
  exit 1
fi

# These local build products can inherit quarantine from the source checkout.
# Remove it so macOS runs the app from this path instead of a new temporary path.
xattr -dr com.apple.quarantine "$APP" 2>/dev/null || true
if xattr -p com.apple.quarantine "$APP" >/dev/null 2>&1; then
  echo "Could not remove quarantine from local build: $APP" >&2
  exit 1
fi

# A fixed requirement keeps the app identity stable when the executable hash changes.
# This identifies the app, not its author; ad hoc signing is not notarization.
codesign --force \
  --sign - \
  --requirements "$ROOT/Resources/LocalCodeRequirement.txt" \
  --options runtime \
  --entitlements "$ROOT/RichardPotato/RichardPotato.entitlements" \
  "$APP"

codesign --verify --deep --strict --verbose=2 "$APP"
