#!/bin/zsh

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"
source "$ROOT_DIR/scripts/toolchain.sh"

# All tests use Swift Testing; the XCTest runner requires the full Xcode app.
# Some Command Line Tools releases omit this nested plugin directory from
# incremental dependency scans. Load the bundled Testing macros explicitly.
TEST_MACRO_LIBRARY="$(dirname "$(xcrun --find swiftc)")/../lib/swift/host/plugins/testing/libTestingMacros.dylib"
TEST_FLAGS=()
if [[ -f "$TEST_MACRO_LIBRARY" ]]; then
  TEST_FLAGS=(-Xswiftc -load-plugin-library -Xswiftc "$TEST_MACRO_LIBRARY")
fi
xcrun swift test --sdk "$SDKROOT" --disable-xctest "${TEST_FLAGS[@]}" "$@"
