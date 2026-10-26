#!/bin/zsh

# Sourced by build.sh and test.sh. Prefer the app's macOS 26 SDK over beta SDKs.
# SDKROOT can select a different installed SDK explicitly.
if [[ -z "${SDKROOT:-}" ]]; then
  SDKROOT="$(xcrun --sdk macosx --show-sdk-path)"
  MACOS_26_SDK="$(dirname "$SDKROOT")/MacOSX26.sdk"
  if [[ -d "$MACOS_26_SDK" ]]; then
    SDKROOT="$MACOS_26_SDK"
  fi
fi
export SDKROOT
