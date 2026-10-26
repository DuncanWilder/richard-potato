#!/usr/bin/env bash
# Resolves the certificate used for app packaging.
#
# Sets SIGN_IDENTITY.
# A release build must use the same certificate as a Debug build.

IDENTITY_NAME="${RICHARD_POTATO_IDENTITY:-Richard Potato Dev}"
SIGN_IDENTITY="$IDENTITY_NAME"

if security find-identity -v -p codesigning 2>/dev/null | grep -qF "$IDENTITY_NAME"; then
  echo "Signing with stable identity: $IDENTITY_NAME"
else
  echo "Code-signing identity '$IDENTITY_NAME' is missing. Run ./scripts/setup-signing.sh once." >&2
  return 1
fi
