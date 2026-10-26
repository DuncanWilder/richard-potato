#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
source "$ROOT/scripts/toolchain.sh"
./scripts/format.sh
for script in scripts/*.sh; do
  case "$script" in
    scripts/test.sh|scripts/toolchain.sh) zsh -n "$script" ;;
    *) bash -n "$script" ;;
  esac
done
plutil -lint Resources/Info.plist
xcrun swift build --sdk "$SDKROOT" --configuration release
./scripts/test.sh --configuration release "$@"
