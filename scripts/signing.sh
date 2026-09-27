#!/usr/bin/env bash
# Resolves the certificate used by release.sh.
#
# Sets SIGN_BUILD_SETTINGS (array of xcodebuild settings) and SIGN_IDENTITY.
# A release build must use the same certificate as a Debug build.

IDENTITY_NAME="${RICHARD_POTATO_IDENTITY:-Richard Potato Dev}"
SIGN_BUILD_SETTINGS=()
SIGN_IDENTITY="$IDENTITY_NAME"

if security find-identity -v -p codesigning 2>/dev/null | grep -qF "$IDENTITY_NAME"; then
  SIGN_BUILD_SETTINGS=(
    CODE_SIGN_STYLE=Manual
    CODE_SIGN_IDENTITY="$IDENTITY_NAME"
    OTHER_CODE_SIGN_FLAGS="--timestamp=none"
  )
  echo "Signing with stable identity: $IDENTITY_NAME"
else
  echo "Code-signing identity '$IDENTITY_NAME' is missing. Run ./scripts/setup-signing.sh once." >&2
  return 1
fi
